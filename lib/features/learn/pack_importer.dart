/// LEARN engine — quiz-pack importer (§R4.4, S5 step B).
///
/// Treats ALL input as hostile: packs are generated outside the
/// app and may be corrupt, malicious, or simply wrong.
///
/// Pipeline:
/// - PHASE 1 validates EVERYTHING and writes NOTHING (zip caps,
///   entry hygiene, pack.json structure via pack_format.dart,
///   media presence/size/mime/magic/sha256/dimensions, and
///   per-question payload vetting via question.dart). Any
///   pack-level failure
///   rejects the whole pack with zero writes anywhere; individual
///   bad questions are skipped and reported instead. A test proves
///   the zero-writes property against the Library and the DB.
/// - Re-import semantics are decided from the packs registry
///   (engine.packByPackId) AFTER phase 1, so validation runs even
///   for a no-op re-import: same version → alreadyImported (zero
///   writes); a HIGHER stored version → reject (no downgrades);
///   a LOWER stored version → the update path.
/// - PHASE 2 writes files, only through LibraryStore.writeAtomic,
///   wrapped so a raw filesystem failure surfaces as
///   [PackException]: on a FRESH import the files this call
///   already wrote are best-effort deleted (they were created by
///   this call); on an UPDATE they are left in place — they may
///   have overwritten good files, and deleting them would lose
///   the previous version's content too.
///   The pack zip at `packs/<sanitised pack.id>.quizpack` and each
///   declared media file at the DETERMINISTIC path given by
///   [PackImporter.mediaRelPath]. Renderers resolve an
///   image_point question's media by exactly that rule: payload
///   `image` is the media id, the expected mime is the declared
///   mime of that media entry in the importing pack, and the file
///   lives at mediaRelPath(packId, mediaId, mime).
/// - PHASE 3 writes the database (source row → questions → pack
///   registry). ATOMICITY, honestly: phase-1 failures write
///   nothing at all. A phase-3 failure is compensated — question
///   rows INSERTED by this call are hard-deleted (they were
///   created seconds earlier and cannot have review history) and
///   a source row created by this call is removed — then the
///   failure rethrows as [PackException]. What compensation can
///   NOT undo: phase-2 files (they were written atomically; a
///   stale pack/media file may remain, referenced by nothing) and,
///   on the update path, payload updates and suspensions already
///   applied to pre-existing questions. Those are content edits,
///   not corruption: scheduler state is never touched by an
///   update, and a later successful re-import converges the pack.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'image_dimensions.dart';
import 'learn_engine_store.dart';
import 'learn_store.dart';
import 'library_store.dart';
import 'pack_format.dart';
import 'question.dart';

class PackException implements Exception {
  PackException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum PackImportStatus { imported, updated, alreadyImported }

class PackImportReport {
  const PackImportReport({
    required this.packId,
    required this.title,
    required this.version,
    required this.status,
    required this.importedCount,
    required this.updatedCount,
    required this.suspendedCount,
    required this.mediaCount,
    required this.skipped,
  });

  final String packId;
  final String title;
  final String version;
  final PackImportStatus status;

  /// Questions inserted by this call (all of them on a fresh
  /// import; only the newly-added ones on an update).
  final int importedCount;

  /// Pre-existing questions whose payload/difficulty this call
  /// updated (update path only).
  final int updatedCount;

  /// Pre-existing questions this call suspended because they are
  /// absent from the incoming version (update path only; already
  /// suspended questions are not counted).
  final int suspendedCount;

  /// Media files written by this call (0 for alreadyImported).
  final int mediaCount;

  /// Questions skipped in phase 1, with the reason for each.
  final List<({String questionId, String reason})> skipped;
}

/// Version compare (§R4.4 re-import): dotted segments compared
/// left to right; a segment pair compares NUMERICALLY when both
/// segments parse as integers (`1.10.0` > `1.9.0`), otherwise as
/// strings. A missing trailing segment counts as `0`, so
/// `1.0` == `1.0.0`. Returns <0, 0, >0 like [Comparable.compareTo].
int comparePackVersions(String a, String b) {
  final pa = a.split('.');
  final pb = b.split('.');
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final sa = i < pa.length ? pa[i] : '0';
    final sb = i < pb.length ? pb[i] : '0';
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    final c = (na != null && nb != null) ? na.compareTo(nb) : sa.compareTo(sb);
    if (c != 0) return c;
  }
  return 0;
}

/// Structural equality for decoded-JSON values (maps, lists,
/// scalars) — payload `target` comparison for the M2 re-verify
/// rule, where key order must not matter.
bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

class _Survivor {
  const _Survivor({
    required this.qid,
    required this.type,
    required this.payload,
    required this.difficulty,
  });
  final String qid;
  final String type;
  final Map<String, Object?> payload;
  final int difficulty;
}

class PackImporter {
  PackImporter(this._engine, this._learn, this._library);

  final LearnEngineStore _engine;
  final LearnStore _learn;
  final LibraryStore _library;

  static const int maxZipBytes = 50 * 1024 * 1024;
  static const int maxTotalUncompressedBytes = 50 * 1024 * 1024;
  static const int maxMediaBytes = 10 * 1024 * 1024;

  /// Image dimension caps (TESTING §7): a header declaring more
  /// than this would be fully decoded at play time — reject the
  /// pack in phase 1 instead.
  static const int maxImageDimension = 8192;
  static const int maxImagePixels = 50000000;

  static const Map<String, String> _extByMime = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
  };

  /// Library-relative path of the stored pack zip.
  static String packRelPath(String packId) =>
      'packs/${LibraryStore.sanitizeFileName(packId)}.quizpack';

  /// THE deterministic media path (see the library doc): both id
  /// segments pass through [LibraryStore.sanitizeFileName] (an
  /// identity transform for well-formed ids like `m1`), and the
  /// extension comes from the DECLARED mime, never the file name.
  static String mediaRelPath(String packId, String mediaId, String mime) {
    final ext = _extByMime[mime];
    if (ext == null) {
      throw PackException('Unsupported media mime: $mime');
    }
    return 'media/${LibraryStore.sanitizeFileName(packId)}/'
        '${LibraryStore.sanitizeFileName(mediaId)}.$ext';
  }

  Future<PackImportReport> importPackFile(
    File file, {
    required int topicId,
  }) async {
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      throw PackException('Pack file could not be read: ${file.path}');
    }
    return importPackBytes(bytes, topicId: topicId);
  }

  Future<PackImportReport> importPackBytes(
    List<int> bytes, {
    required int topicId,
  }) async {
    // ================= PHASE 1: validate, write nothing. ======
    if (bytes.length > maxZipBytes) {
      throw PackException('Pack is larger than 50 MB.');
    }
    final decoder = ZipDecoder();
    final Archive archive;
    try {
      archive = decoder.decodeBytes(bytes);
    } catch (_) {
      throw PackException('That file is not a readable quiz-pack zip.');
    }

    // Entry hygiene, over EVERY entry (backup_store precedent):
    // no absolute names, no `..` segment under either separator,
    // no duplicate names; and the zip-bomb guard sums DECLARED
    // uncompressed sizes before any content is read.
    //
    // This iterates the RAW central directory (decoder.directory),
    // not archive.files: ZipDecoder collapses duplicate names
    // into one ArchiveFile, so duplicates are only visible here.
    final seenNames = <String>{};
    var totalSize = 0;
    for (final header in decoder.directory.fileHeaders) {
      final name = header.filename;
      if (name.startsWith('/') ||
          name.startsWith(r'\') ||
          RegExp(r'^[a-zA-Z]:').hasMatch(name)) {
        throw PackException('Pack contains an unsafe path: $name');
      }
      if (name.split(RegExp(r'[/\\]')).any((seg) => seg == '..')) {
        throw PackException('Pack contains an unsafe path: $name');
      }
      if (!seenNames.add(name)) {
        throw PackException('Pack contains a duplicate entry: $name');
      }
      if (!name.endsWith('/')) {
        totalSize += header.uncompressedSize;
        if (totalSize > maxTotalUncompressedBytes) {
          throw PackException('Pack contents are larger than 50 MB.');
        }
      }
    }

    final entriesByName = <String, ArchiveFile>{
      for (final f in archive.files)
        if (f.isFile) f.name: f,
    };

    final packJsonFile = entriesByName['pack.json'];
    if (packJsonFile == null) {
      throw PackException('Pack is missing pack.json at its root.');
    }
    final PackDocument doc;
    try {
      final decoded = jsonDecode(utf8.decode(packJsonFile.content));
      doc = parsePackDocument(decoded);
    } on PackFormatException catch (e) {
      throw PackException('Invalid pack.json: ${e.message}');
    } catch (_) {
      throw PackException('pack.json is not readable JSON.');
    }

    // Media: presence, size, mime allow-list, magic bytes, hash.
    // ANY media failure rejects the whole pack.
    final mediaBytes = <String, List<int>>{};
    for (final m in doc.media) {
      final file = entriesByName[m.file];
      if (file == null) {
        throw PackException(
          'Declared media "${m.id}" is missing from the pack: ${m.file}',
        );
      }
      if (file.size > maxMediaBytes) {
        throw PackException('Media "${m.id}" is larger than 10 MB.');
      }
      if (!_extByMime.containsKey(m.mime)) {
        throw PackException(
          'Media "${m.id}" has an unsupported mime: ${m.mime}',
        );
      }
      final List<int> content;
      try {
        content = file.content;
      } catch (_) {
        throw PackException('Media "${m.id}" could not be read.');
      }
      if (content.length > maxMediaBytes) {
        throw PackException('Media "${m.id}" is larger than 10 MB.');
      }
      if (!_magicMatches(m.mime, content)) {
        throw PackException(
          'Media "${m.id}" content does not match its declared '
          'mime (${m.mime}).',
        );
      }
      final digest = sha256.convert(content).toString();
      if (digest != m.sha256.toLowerCase()) {
        throw PackException('Media "${m.id}" fails its sha256 check.');
      }
      // Dimensions (TESTING §7): the header must parse and stay
      // under the caps — a tiny file declaring 20000×20000 would
      // otherwise be fully decoded at play time.
      final dims = imageDimensions(m.mime, content);
      if (dims == null ||
          dims.width > maxImageDimension ||
          dims.height > maxImageDimension ||
          dims.width * dims.height > maxImagePixels) {
        throw PackException(
          'Media "${m.id}" has unparseable or oversized image '
          'dimensions.',
        );
      }
      mediaBytes[m.id] = content;
    }

    // Questions: vet one by one; bad ones are skipped+reported.
    final mediaIds = doc.media.map((m) => m.id).toSet();
    final skipped = <({String questionId, String reason})>[];
    final survivors = <_Survivor>[];
    for (final raw in doc.questions) {
      final qid = raw['id'] as String;
      final typeRaw = raw['type'];
      if (typeRaw is! String || !isKnownType(typeRaw)) {
        skipped.add((
          questionId: qid,
          reason: 'unknown question type: $typeRaw',
        ));
        continue;
      }
      final type = typeRaw;
      final payload = Map<String, Object?>.from(raw)
        ..remove('id')
        ..remove('type');
      final difficultyIssues = validateDifficulty(raw['difficulty']);
      if (difficultyIssues.isNotEmpty) {
        skipped.add((questionId: qid, reason: difficultyIssues.join('; ')));
        continue;
      }
      final issues = validatePayload(type, payload);
      if (issues.isNotEmpty) {
        skipped.add((questionId: qid, reason: issues.join('; ')));
        continue;
      }
      if (type == 'image_point') {
        final image = payload['image'];
        if (image is! String || !mediaIds.contains(image)) {
          skipped.add((
            questionId: qid,
            reason:
                'image_point image names an undeclared media id: '
                '$image',
          ));
          continue;
        }
      }
      survivors.add(
        _Survivor(
          qid: qid,
          type: type,
          payload: payload,
          difficulty: raw['difficulty'] is int ? raw['difficulty'] as int : 3,
        ),
      );
    }
    if (survivors.isEmpty) {
      throw PackException(
        'Pack has no importable questions '
        '(${skipped.length} skipped).',
      );
    }

    // The target topic must exist — knowable now, so a bad topic
    // also fails with zero writes.
    try {
      await _learn.topicById(topicId);
    } catch (_) {
      throw PackException('Topic $topicId does not exist.');
    }

    // ============ Re-import semantics (validation has run). ===
    final existing = await _engine.packByPackId(doc.pack.id);
    if (existing != null) {
      final cmp = comparePackVersions(existing.version, doc.pack.version);
      if (cmp == 0) {
        return PackImportReport(
          packId: doc.pack.id,
          title: doc.pack.title,
          version: doc.pack.version,
          status: PackImportStatus.alreadyImported,
          importedCount: 0,
          updatedCount: 0,
          suspendedCount: 0,
          mediaCount: 0,
          skipped: skipped,
        );
      }
      if (cmp > 0) {
        throw PackException(
          'Pack ${doc.pack.id} is already imported at version '
          '${existing.version}; refusing to downgrade to '
          '${doc.pack.version}.',
        );
      }
    }
    final isUpdate = existing != null;

    // ================= PHASE 2: files (writeAtomic only). =====
    final packPath = packRelPath(doc.pack.id);
    final writtenThisCall = <String>[];
    try {
      await _library.writeAtomic(packPath, bytes);
      writtenThisCall.add(packPath);
      for (final m in doc.media) {
        final rel = mediaRelPath(doc.pack.id, m.id, m.mime);
        await _library.writeAtomic(rel, mediaBytes[m.id]!);
        writtenThisCall.add(rel);
      }
    } catch (e) {
      if (!isUpdate) {
        // Fresh import: every file in writtenThisCall was created
        // by THIS call, so deleting them restores the zero-writes
        // property. Best-effort — keep unwinding on a bad delete.
        for (final rel in writtenThisCall) {
          try {
            await _library.delete(rel);
          } catch (_) {
            // Best effort, as above.
          }
        }
      }
      // On the UPDATE path the written files may have overwritten
      // good files from the previous version, so they are NOT
      // deleted here: removing them would destroy the old content
      // as well, and a later successful re-import converges them.
      if (e is PackException) rethrow;
      throw PackException('Import failed while writing files: $e');
    }

    // ================= PHASE 3: database, compensated. ========
    final insertedIds = <int>[];
    int? createdSourceId;
    var importedCount = 0;
    var updatedCount = 0;
    var suspendedCount = 0;
    try {
      final int sourceId;
      if (!isUpdate) {
        final source = await _learn.addSource(
          topicId: topicId,
          kind: SourceKind.pack,
          title: doc.pack.title,
          fileRelPath: packPath,
        );
        createdSourceId = source.id;
        sourceId = source.id;
        for (final s in survivors) {
          final q = await _insertFresh(
            s,
            topicId: topicId,
            packId: doc.pack.id,
            sourceId: sourceId,
          );
          insertedIds.add(q.id);
          importedCount++;
        }
      } else {
        // Reuse the source row the pack registry already points
        // at; only if it dangles do we mint a replacement.
        int? reused = existing.sourceId;
        if (reused != null) {
          try {
            await _learn.sourceById(reused);
          } catch (_) {
            reused = null;
          }
        }
        if (reused == null) {
          final source = await _learn.addSource(
            topicId: topicId,
            kind: SourceKind.pack,
            title: doc.pack.title,
            fileRelPath: packPath,
          );
          createdSourceId = source.id;
          reused = source.id;
        }
        sourceId = reused;

        final existingByQid = <String, LearnQuestion>{
          for (final q in await _engine.questionsForPack(doc.pack.id))
            if (q.packQid != null) q.packQid!: q,
        };
        final survivingQids = survivors.map((s) => s.qid).toSet();
        for (final s in survivors) {
          final old = existingByQid[s.qid];
          if (old == null) {
            final q = await _insertFresh(
              s,
              topicId: topicId,
              packId: doc.pack.id,
              sourceId: sourceId,
            );
            insertedIds.add(q.id);
            importedCount++;
          } else {
            var payload = s.payload;
            final gateHeld = old.payload['verifyPending'] == true;
            // M2: a VERIFIED image_point whose target or image
            // changes in the new version carries a NEW unverified
            // target — it must pass the owner's verify gate again
            // instead of rotating live with an unchecked target.
            final targetOrImageChanged =
                s.type == 'image_point' &&
                (!_deepEquals(old.payload['target'], s.payload['target']) ||
                    old.payload['image'] != s.payload['image']);
            final gated =
                s.type == 'image_point' && (gateHeld || targetOrImageChanged);
            if (gated) {
              // An unverified target stays unverified across a
              // content update until the owner verifies it.
              payload = {...payload, 'verifyPending': true};
            }
            await _engine.updateQuestionPayload(
              old.id,
              payload,
              difficulty: s.difficulty,
            );
            if (gated) {
              await _engine.suspendQuestion(old.id);
            } else if (old.suspended && !gateHeld) {
              // S2: suspended WITHOUT verifyPending means this
              // question was retired by an earlier version, not
              // gate-held. Reappearing in this version revives it
              // (the gated branch above wins when M2 fires).
              await _engine.unsuspendQuestion(old.id);
            }
            updatedCount++;
          }
        }
        // Retired by the new version: suspend, never delete
        // (review_log integrity).
        for (final old in existingByQid.values) {
          if (survivingQids.contains(old.packQid)) continue;
          if (!old.suspended) {
            await _engine.suspendQuestion(old.id);
            suspendedCount++;
          }
        }
      }
      await _engine.recordPack(
        packId: doc.pack.id,
        version: doc.pack.version,
        title: doc.pack.title,
        language: doc.pack.language,
        topicId: topicId,
        sourceId: sourceId,
        arc: doc.arc,
        questionCount: survivors.length,
      );
    } catch (e) {
      // Compensation (see the library doc for its exact limits).
      for (final id in insertedIds) {
        try {
          await _engine.deleteQuestion(id);
        } catch (_) {
          // Best effort: keep compensating the rest.
        }
      }
      if (createdSourceId != null) {
        try {
          await _learn.deleteSource(createdSourceId);
        } catch (_) {
          // Best effort, as above.
        }
      }
      if (e is PackException) rethrow;
      throw PackException('Import failed while writing: $e');
    }

    return PackImportReport(
      packId: doc.pack.id,
      title: doc.pack.title,
      version: doc.pack.version,
      status: isUpdate ? PackImportStatus.updated : PackImportStatus.imported,
      importedCount: importedCount,
      updatedCount: updatedCount,
      suspendedCount: suspendedCount,
      mediaCount: doc.media.length,
      skipped: skipped,
    );
  }

  /// Insert one fresh question; image_point questions are then
  /// suspended with `verifyPending: true` merged into the stored
  /// payload (owner must verify AI-proposed targets before the
  /// question enters rotation, §R4.1).
  Future<LearnQuestion> _insertFresh(
    _Survivor s, {
    required int topicId,
    required String packId,
    required int sourceId,
  }) async {
    final q = await _engine.insertQuestion(
      topicId: topicId,
      sourceId: sourceId,
      packId: packId,
      packQid: s.qid,
      type: s.type,
      payload: s.payload,
      difficulty: s.difficulty,
    );
    if (s.type == 'image_point') {
      await _engine.updateQuestionPayload(q.id, {
        ...s.payload,
        'verifyPending': true,
      });
      await _engine.suspendQuestion(q.id);
      return _engine.questionById(q.id);
    }
    return q;
  }

  static bool _magicMatches(String mime, List<int> b) {
    bool starts(List<int> sig) =>
        b.length >= sig.length &&
        List.generate(sig.length, (i) => b[i] == sig[i]).every((x) => x);
    bool asciiAt(int offset, String s) =>
        b.length >= offset + s.length &&
        String.fromCharCodes(b.sublist(offset, offset + s.length)) == s;
    return switch (mime) {
      'image/jpeg' => starts([0xFF, 0xD8, 0xFF]),
      'image/png' => starts([0x89, 0x50, 0x4E, 0x47]),
      'image/gif' => asciiAt(0, 'GIF8'),
      'image/webp' => asciiAt(0, 'RIFF') && asciiAt(8, 'WEBP'),
      _ => false,
    };
  }
}

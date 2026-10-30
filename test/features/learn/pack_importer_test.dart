// LEARN engine — PackImporter (S5 step B): the §R4.4 hostile
// import pipeline. Phase 1 must write NOTHING on any pack-level
// failure; bad questions skip+report; re-import obeys the
// version rules and never resets scheduler state.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/pack_importer.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/sample_pack.dart';

Future<void> wipeDb(Database db) async {
  for (final t in [
    'review_log',
    'questions',
    'learn_sessions',
    'packs',
    'marked_points',
    'sources',
    'topics',
    'day_reviews',
    'shield_events',
    'items',
    'checklist_entries',
    'projects',
    'workspaces',
    'goals',
    'day_plan_items',
    'day_plans',
    'plan_templates',
    'app_settings',
  ]) {
    await db.delete(t);
  }
}

List<int> zipOfEntries(List<MapEntry<String, List<int>>> entries) {
  final archive = Archive();
  for (final e in entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return ZipEncoder().encode(archive);
}

/// Zip a (possibly mutated) pack.json map with the sample media
/// file, unless [includeMedia] is false.
List<int> packBytesFromJson(
  Map<String, Object?> json, {
  bool includeMedia = true,
  List<int>? mediaContent,
  String mediaEntryName = sampleMediaEntryName,
}) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  return zipOfEntries([
    MapEntry('pack.json', jsonBytes),
    if (includeMedia) MapEntry(mediaEntryName, mediaContent ?? samplePngBytes),
  ]);
}

Map<String, Object?> sampleJson() =>
    (jsonDecode(buildSamplePackJson()) as Map).cast<String, Object?>();

List<Map<String, Object?>> questionsOf(Map<String, Object?> json) =>
    (json['questions'] as List)
        .map((q) => (q as Map).cast<String, Object?>())
        .toList();

/// A LibraryStore whose [failOnWrite]-th writeAtomic throws a
/// raw FileSystemException (S1: phase-2 failure simulation).
class _FailOnNthWriteLibrary extends LibraryStore {
  _FailOnNthWriteLibrary(super.root, {required this.failOnWrite});

  final int failOnWrite;
  int _writes = 0;

  @override
  Future<File> writeAtomic(String relPath, List<int> bytes) {
    _writes++;
    if (_writes == failOnWrite) {
      throw FileSystemException('simulated write failure', relPath);
    }
    return super.writeAtomic(relPath, bytes);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late LibraryStore library;
  late Database db;
  late LearnEngineStore engine;
  late LearnStore learn;
  late PackImporter importer;
  late int topicId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-pack-');
    library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    db = await AppDatabase.openInMemory();
    await wipeDb(db);
    engine = LearnEngineStore(db);
    learn = LearnStore(db);
    importer = PackImporter(engine, learn, library);
    final store = Store(db);
    final ws = await store.createWorkspace('W');
    final prj = await store.createProject(ws.id, 'P');
    topicId = (await learn.createTopic(projectId: prj.id, title: 'T')).id;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> expectNothingWritten() async {
    expect(await engine.questionsForPack('arabic-greetings-01'), isEmpty);
    expect(await engine.packByPackId('arabic-greetings-01'), isNull);
    expect(await learn.sourcesForTopic(topicId), isEmpty);
    for (final sub in ['packs', 'media']) {
      final dir = Directory('${library.rootPath}/$sub');
      final files = await dir
          .list(recursive: true)
          .where((e) => e is File)
          .length;
      expect(files, 0, reason: 'Library/$sub must stay empty');
    }
  }

  group('valid import', () {
    test('sample pack imports cleanly: counts, pack record, source, '
        'deterministic media path, image_point verifyPending', () async {
      final report = await importer.importPackBytes(
        buildSamplePackBytes(),
        topicId: topicId,
      );
      expect(report.status, PackImportStatus.imported);
      expect(report.packId, 'arabic-greetings-01');
      expect(report.title, 'Arabic Greetings');
      expect(report.version, '1.0.0');
      expect(report.importedCount, 13);
      expect(report.updatedCount, 0);
      expect(report.suspendedCount, 0);
      expect(report.mediaCount, 1);
      expect(report.skipped, isEmpty);

      final questions = await engine.questionsForPack('arabic-greetings-01');
      expect(questions.length, 13);
      final byType = <String, int>{};
      for (final q in questions) {
        byType[q.type] = (byType[q.type] ?? 0) + 1;
      }
      expect(byType, {
        'mcq': 4,
        'flashcard': 3,
        'cloze': 2,
        'mythfact': 1,
        'ordering': 1,
        'image_point': 1,
        'scenario': 1,
      });

      final pack = await engine.packByPackId('arabic-greetings-01');
      expect(pack, isNotNull);
      expect(pack!.version, '1.0.0');
      expect(pack.title, 'Arabic Greetings');
      expect(pack.language, 'ar');
      expect(pack.topicId, topicId);
      expect(pack.questionCount, 13);
      expect(pack.arc?['id'], 'arabic-city-01');
      expect(pack.arc?['title'], 'City Errands');
      expect(pack.arc?['episode'], 1);
      expect(pack.arc?['episodeTitle'], 'Greetings');
      expect(
        pack.arc?['teaser'],
        'Tomorrow: the café owner argues about the bill',
      );

      // Source row: kind=pack, pointing at the stored zip.
      expect(pack.sourceId, isNotNull);
      final source = await learn.sourceById(pack.sourceId!);
      expect(source.kind, SourceKind.pack);
      expect(source.title, 'Arabic Greetings');
      expect(source.fileRelPath, 'packs/arabic-greetings-01.quizpack');
      expect(await library.exists(source.fileRelPath!), isTrue);

      // Media at the deterministic path, byte-identical.
      const mediaPath = 'media/arabic-greetings-01/m1.png';
      expect(
        PackImporter.mediaRelPath('arabic-greetings-01', 'm1', 'image/png'),
        mediaPath,
      );
      expect(await library.readBytes(mediaPath), samplePngBytes);

      // image_point: suspended, awaiting owner verification.
      final ip = questions.singleWhere((q) => q.packQid == 'q12');
      expect(ip.type, 'image_point');
      expect(ip.suspended, isTrue);
      expect(ip.payload['verifyPending'], isTrue);
      expect(ip.payload['image'], 'm1');
      // …and everyone else is in rotation.
      expect(
        questions.where((q) => q.packQid != 'q12').every((q) => !q.suspended),
        isTrue,
      );
    });

    test('importPackFile reads the pack from disk', () async {
      final file = File('${tmp.path}/in.quizpack');
      await file.writeAsBytes(buildSamplePackBytes());
      final report = await importer.importPackFile(file, topicId: topicId);
      expect(report.status, PackImportStatus.imported);
      expect(report.importedCount, 13);
    });
  });

  group('phase 1 rejects the whole pack and writes nothing', () {
    test('malformed JSON → throws, Library + questions stay empty', () async {
      final bytes = zipOfEntries([
        MapEntry('pack.json', utf8.encode('this is { not json')),
        MapEntry(sampleMediaEntryName, samplePngBytes),
      ]);
      await expectLater(
        importer.importPackBytes(bytes, topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('wrong schema string → reject', () async {
      final json = sampleJson();
      json['schema'] = 'something.else';
      await expectLater(
        importer.importPackBytes(packBytesFromJson(json), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('wrong schemaVersion → reject', () async {
      final json = sampleJson();
      json['schemaVersion'] = 2;
      await expectLater(
        importer.importPackBytes(packBytesFromJson(json), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('duplicate question ids → reject', () async {
      final json = sampleJson();
      questionsOf(json)[1]['id'] = 'q1';
      await expectLater(
        importer.importPackBytes(packBytesFromJson(json), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('duplicate zip entry names → reject', () async {
      // Archive.add() dedupes by name, so a duplicate-entry zip
      // must be written with the streaming ZipFileEncoder.
      final out = File('${tmp.path}/dup.quizpack');
      final encoder = ZipFileEncoder();
      encoder.create(out.path);
      final jsonBytes = utf8.encode(buildSamplePackJson());
      encoder.addArchiveFile(
        ArchiveFile('pack.json', jsonBytes.length, jsonBytes),
      );
      encoder.addArchiveFile(
        ArchiveFile('pack.json', jsonBytes.length, jsonBytes),
      );
      encoder.addArchiveFile(
        ArchiveFile(
          sampleMediaEntryName,
          samplePngBytes.length,
          samplePngBytes,
        ),
      );
      await encoder.close();
      final bytes = await out.readAsBytes();
      await expectLater(
        importer.importPackBytes(bytes, topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('zip-slip entries (../ and ..\\) → reject', () async {
      for (final evil in ['../evil.txt', r'..\evil.txt']) {
        final bytes = zipOfEntries([
          MapEntry('pack.json', utf8.encode(buildSamplePackJson())),
          MapEntry(sampleMediaEntryName, samplePngBytes),
          MapEntry(evil, utf8.encode('boom')),
        ]);
        await expectLater(
          importer.importPackBytes(bytes, topicId: topicId),
          throwsA(isA<PackException>()),
          reason: evil,
        );
      }
      await expectNothingWritten();
      expect(await File('${tmp.path}/evil.txt').exists(), isFalse);
    });

    test('missing declared media → reject', () async {
      final bytes = packBytesFromJson(sampleJson(), includeMedia: false);
      await expectLater(
        importer.importPackBytes(bytes, topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('sha256 mismatch → reject', () async {
      final json = sampleJson();
      final media = (json['media'] as List)
          .map((m) => (m as Map).cast<String, Object?>())
          .toList();
      media.single['sha256'] = '0' * 64;
      await expectLater(
        importer.importPackBytes(packBytesFromJson(json), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('mime/magic mismatch (PNG bytes declared jpeg) → reject', () async {
      final json = sampleJson();
      final media = (json['media'] as List)
          .map((m) => (m as Map).cast<String, Object?>())
          .toList();
      media.single['mime'] = 'image/jpeg';
      await expectLater(
        importer.importPackBytes(packBytesFromJson(json), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('oversize media → reject, with ONLY the size guard able '
        'to fire (S8: valid PNG prefix, sha256 recomputed over '
        'the padded content)', () async {
      // Sample PNG bytes padded with trailing zeros to 10 MB + 1:
      // the PNG magic is a prefix check and still passes, the
      // declared sha256 is recomputed over the padded bytes and
      // matches, and the declared dimensions are the sample's
      // 1×1 — so if this rejects, the size guard did it.
      final total = 10 * 1024 * 1024 + 1;
      final padded = <int>[
        ...samplePngBytes,
        ...List<int>.filled(total - samplePngBytes.length, 0),
      ];
      final json = sampleJson();
      final media = (json['media'] as List)
          .map((m) => (m as Map).cast<String, Object?>())
          .toList();
      media.single['sha256'] = sha256.convert(padded).toString();
      final bytes = packBytesFromJson(json, mediaContent: padded);
      await expectLater(
        importer.importPackBytes(bytes, topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('pack id that sanitisation would change (../evil) → '
        'reject, zero writes (M1)', () async {
      final json = sampleJson();
      (json['pack'] as Map)['id'] = '../evil';
      await expectLater(
        importer.importPackBytes(packBytesFromJson(json), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      expect(await engine.packByPackId('../evil'), isNull);
      await expectNothingWritten();
    });

    test('media id that sanitisation would change (a/b) → '
        'reject, zero writes (M1)', () async {
      final json = sampleJson();
      final media = (json['media'] as List)
          .map((m) => (m as Map).cast<String, Object?>())
          .toList();
      media.single['id'] = 'a/b';
      await expectLater(
        importer.importPackBytes(packBytesFromJson(json), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('small file declaring huge PNG dimensions (correct '
        'sha256) → reject (S5 dimension cap)', () async {
      // A minimal PNG header declaring the given dimensions;
      // magic is a prefix check and passes, and the declared
      // sha256 is recomputed over exactly these bytes — only the
      // dimension guard can reject. (8000×8000 stays under each
      // per-axis cap but exceeds the 50 MP total.)
      List<int> hugePng(int w, int h) => [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0,
        0,
        0,
        13,
        ...'IHDR'.codeUnits,
        (w >> 24) & 0xFF,
        (w >> 16) & 0xFF,
        (w >> 8) & 0xFF,
        w & 0xFF,
        (h >> 24) & 0xFF,
        (h >> 16) & 0xFF,
        (h >> 8) & 0xFF,
        h & 0xFF,
        8,
        6,
        0,
        0,
        0,
      ];
      for (final (w, h) in [(20000, 20000), (8000, 8000)]) {
        final content = hugePng(w, h);
        final json = sampleJson();
        final media = (json['media'] as List)
            .map((m) => (m as Map).cast<String, Object?>())
            .toList();
        media.single['sha256'] = sha256.convert(content).toString();
        final bytes = packBytesFromJson(json, mediaContent: content);
        await expectLater(
          importer.importPackBytes(bytes, topicId: topicId),
          throwsA(isA<PackException>()),
          reason: '${w}x$h must be rejected on dimensions',
        );
      }
      await expectNothingWritten();
    });

    test('>2000 questions → reject', () async {
      final json = sampleJson();
      json['questions'] = [
        for (var i = 0; i < 2001; i++)
          {'id': 'bulk$i', 'type': 'flashcard', 'front': 'f$i', 'back': 'b$i'},
      ];
      await expectLater(
        importer.importPackBytes(packBytesFromJson(json), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('corrupt zip → PackException', () async {
      await expectLater(
        importer.importPackBytes(
          utf8.encode('PK-not-really-a-zip'),
          topicId: topicId,
        ),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });
  });

  group('bad questions are skipped and reported', () {
    test('unknown question type → skipped, others import', () async {
      final json = sampleJson();
      final qs = questionsOf(json);
      qs.add({'id': 'q99', 'type': 'telepathy', 'prompt': 'Think the answer'});
      json['questions'] = qs;
      final report = await importer.importPackBytes(
        packBytesFromJson(json),
        topicId: topicId,
      );
      expect(report.status, PackImportStatus.imported);
      expect(report.importedCount, 13);
      expect(report.skipped.length, 1);
      expect(report.skipped.single.questionId, 'q99');
      expect(report.skipped.single.reason, contains('unknown'));
    });

    test('mcq with 2 correct ids → skipped+reported', () async {
      final json = sampleJson();
      questionsOf(json)[0]['correctChoiceIds'] = ['a', 'b'];
      final report = await importer.importPackBytes(
        packBytesFromJson(json),
        topicId: topicId,
      );
      expect(report.importedCount, 12);
      expect(report.skipped.single.questionId, 'q1');
    });

    test('image_point with r=0.5 → skipped+reported', () async {
      final json = sampleJson();
      final q12 = questionsOf(json).singleWhere((q) => q['id'] == 'q12');
      (q12['target'] as Map)['r'] = 0.5;
      final report = await importer.importPackBytes(
        packBytesFromJson(json),
        topicId: topicId,
      );
      expect(report.importedCount, 12);
      expect(report.skipped.single.questionId, 'q12');
    });

    test('scenario with an endless cycle → skipped+reported', () async {
      final json = sampleJson();
      final q13 = questionsOf(json).singleWhere((q) => q['id'] == 'q13');
      q13['nodes'] = {
        'n1': {
          'text': 'Loop A',
          'choices': [
            {'text': 'go', 'next': 'n2'},
          ],
        },
        'n2': {
          'text': 'Loop B',
          'choices': [
            {'text': 'back', 'next': 'n1'},
          ],
        },
      };
      final report = await importer.importPackBytes(
        packBytesFromJson(json),
        topicId: topicId,
      );
      expect(report.importedCount, 12);
      expect(report.skipped.single.questionId, 'q13');
    });

    test('scenario whose reachable cycle cannot reach an end → '
        'skipped+reported with the reach-an-end reason (S7)', () async {
      // Start branches to BOTH a proper end node AND a reachable
      // 2-node cycle with no exit: every node is reachable and an
      // end exists, so the ONLY defect is the cycle's inability
      // to reach an end.
      final json = sampleJson();
      final q13 = questionsOf(json).singleWhere((q) => q['id'] == 'q13');
      q13['startNode'] = 's';
      q13['nodes'] = {
        's': {
          'text': 'Start',
          'choices': [
            {'text': 'finish', 'next': 'end'},
            {'text': 'wander', 'next': 'c1'},
          ],
        },
        'c1': {
          'text': 'Cycle A',
          'choices': [
            {'text': 'on', 'next': 'c2'},
          ],
        },
        'c2': {
          'text': 'Cycle B',
          'choices': [
            {'text': 'back', 'next': 'c1'},
          ],
        },
        'end': {'end': true, 'text': 'Done', 'summary': 'Finished.'},
      };
      final report = await importer.importPackBytes(
        packBytesFromJson(json),
        topicId: topicId,
      );
      expect(report.importedCount, 12);
      expect(report.skipped.single.questionId, 'q13');
      expect(
        report.skipped.single.reason,
        contains('cannot reach an end node'),
      );
    });
  });

  group('re-import semantics', () {
    test('same version → alreadyImported; count and scheduler '
        'state unchanged', () async {
      await importer.importPackBytes(buildSamplePackBytes(), topicId: topicId);
      final q5 = (await engine.questionsForPack('arabic-greetings-01'))
          .singleWhere((q) => q.packQid == 'q5');
      // Manually-applied scheduler state.
      await db.update(
        'questions',
        {'reps': 5, 'ef': 2.1, 'interval_days': 12, 'due_at': 424242},
        where: 'id = ?',
        whereArgs: [q5.id],
      );
      final report = await importer.importPackBytes(
        buildSamplePackBytes(),
        topicId: topicId,
      );
      expect(report.status, PackImportStatus.alreadyImported);
      expect(report.importedCount, 0);
      expect(report.updatedCount, 0);
      final after = await engine.questionsForPack('arabic-greetings-01');
      expect(after.length, 13);
      final q5After = after.singleWhere((q) => q.packQid == 'q5');
      expect(q5After.id, q5.id);
      expect(q5After.reps, 5);
      expect(q5After.ef, 2.1);
      expect(q5After.intervalDays, 12);
      expect(q5After.dueAt, 424242);
    });

    test('v1.1.0: changed payload updated with scheduler preserved, '
        'removed question suspended not deleted, added present, '
        'pack record at 1.1.0', () async {
      await importer.importPackBytes(buildSamplePackBytes(), topicId: topicId);
      final before = await engine.questionsForPack('arabic-greetings-01');
      final q5 = before.singleWhere((q) => q.packQid == 'q5');
      await db.update(
        'questions',
        {'reps': 4, 'ef': 2.3, 'interval_days': 9, 'due_at': 777000},
        where: 'id = ?',
        whereArgs: [q5.id],
      );

      final json = sampleJson();
      (json['pack'] as Map)['version'] = '1.1.0';
      final qs = questionsOf(json);
      // One payload changed (q5's back), one removed (q6), one
      // added (q14).
      qs.singleWhere((q) => q['id'] == 'q5')['back'] =
          'Peace be upon you — UPDATED in v1.1.';
      qs.removeWhere((q) => q['id'] == 'q6');
      qs.add({
        'id': 'q14',
        'type': 'flashcard',
        'difficulty': 1,
        'front': 'إلى اللقاء',
        'back': 'See you later / until we meet again.',
        'explanation': 'A farewell for when you expect to meet again.',
      });
      json['questions'] = qs;

      final report = await importer.importPackBytes(
        packBytesFromJson(json),
        topicId: topicId,
      );
      expect(report.status, PackImportStatus.updated);
      expect(report.version, '1.1.0');
      expect(report.importedCount, 1); // q14
      expect(report.updatedCount, 12); // q1..q5, q7..q13
      expect(report.suspendedCount, 1); // q6

      final after = await engine.questionsForPack('arabic-greetings-01');
      expect(after.length, 14); // 13 - 0 deleted + 1 added
      final q5After = after.singleWhere((q) => q.packQid == 'q5');
      expect(q5After.id, q5.id);
      expect(q5After.payload['back'], 'Peace be upon you — UPDATED in v1.1.');
      expect(q5After.reps, 4);
      expect(q5After.ef, 2.3);
      expect(q5After.intervalDays, 9);
      expect(q5After.dueAt, 777000);

      final q6After = after.singleWhere((q) => q.packQid == 'q6');
      expect(q6After.suspended, isTrue);
      expect(after.any((q) => q.packQid == 'q14'), isTrue);

      final pack = await engine.packByPackId('arabic-greetings-01');
      expect(pack!.version, '1.1.0');
    });

    test('downgrade (1.1.0 then 1.0.0) → reject', () async {
      final json = sampleJson();
      (json['pack'] as Map)['version'] = '1.1.0';
      await importer.importPackBytes(packBytesFromJson(json), topicId: topicId);
      await expectLater(
        importer.importPackBytes(buildSamplePackBytes(), topicId: topicId),
        throwsA(isA<PackException>()),
      );
      final pack = await engine.packByPackId('arabic-greetings-01');
      expect(pack!.version, '1.1.0');
      expect((await engine.questionsForPack('arabic-greetings-01')).length, 13);
    });

    test('version compare is dotted-numeric (1.10.0 > 1.9.0)', () {
      expect(comparePackVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(comparePackVersions('1.9.0', '1.10.0'), lessThan(0));
      expect(comparePackVersions('1.0', '1.0.0'), 0);
      expect(comparePackVersions('2.0.0', '1.99.99'), greaterThan(0));
      expect(comparePackVersions('1.0.0', '1.0.0'), 0);
    });
  });

  group('image_point re-verify gate (M2) and retired revival (S2)', () {
    /// Verify q12 at engine level, exactly as the verify screen
    /// saves: clear the flag, keep the target, unsuspend.
    Future<void> verifyQ12() async {
      final q12 = (await engine.questionsForPack('arabic-greetings-01'))
          .singleWhere((q) => q.packQid == 'q12');
      final payload = Map<String, Object?>.of(q12.payload)
        ..remove('verifyPending');
      await engine.updateQuestionPayload(q12.id, payload);
      await engine.unsuspendQuestion(q12.id);
    }

    Future<LearnQuestion> byQid(String qid) async =>
        (await engine.questionsForPack('arabic-greetings-01'))
            .singleWhere((q) => q.packQid == qid);

    Map<String, Object?> versioned(String version) {
      final json = sampleJson();
      (json['pack'] as Map)['version'] = version;
      return json;
    }

    test('v2 changes a VERIFIED question\'s target → gated again '
        '(suspended + verifyPending)', () async {
      await importer.importPackBytes(buildSamplePackBytes(), topicId: topicId);
      await verifyQ12();
      expect((await byQid('q12')).suspended, isFalse);

      final json = versioned('1.1.0');
      final q12 = questionsOf(json).singleWhere((q) => q['id'] == 'q12');
      (q12['target'] as Map)['cx'] = 0.7;
      final report = await importer.importPackBytes(
        packBytesFromJson(json),
        topicId: topicId,
      );
      expect(report.status, PackImportStatus.updated);

      final after = await byQid('q12');
      expect(after.suspended, isTrue);
      expect(after.payload['verifyPending'], isTrue);
      expect((after.payload['target'] as Map)['cx'], 0.7);
    });

    test('v2 changes a VERIFIED question\'s image → gated again', () async {
      await importer.importPackBytes(buildSamplePackBytes(), topicId: topicId);
      await verifyQ12();

      // A second declared media entry, so q12 can point at it.
      final json = versioned('1.1.0');
      final media = (json['media'] as List)
          .map((m) => (m as Map).cast<String, Object?>())
          .toList();
      media.add({
        'id': 'm2',
        'file': sampleMediaEntryName,
        'mime': 'image/png',
        'sha256': sha256.convert(samplePngBytes).toString(),
      });
      json['media'] = media;
      questionsOf(json).singleWhere((q) => q['id'] == 'q12')['image'] = 'm2';
      await importer.importPackBytes(packBytesFromJson(json), topicId: topicId);

      final after = await byQid('q12');
      expect(after.suspended, isTrue);
      expect(after.payload['verifyPending'], isTrue);
      expect(after.payload['image'], 'm2');
    });

    test('v2b leaves a VERIFIED question\'s target unchanged → '
        'stays live, no verifyPending', () async {
      await importer.importPackBytes(buildSamplePackBytes(), topicId: topicId);
      await verifyQ12();

      final report = await importer.importPackBytes(
        packBytesFromJson(versioned('1.1.0')),
        topicId: topicId,
      );
      expect(report.status, PackImportStatus.updated);

      final after = await byQid('q12');
      expect(after.suspended, isFalse);
      expect(after.payload.containsKey('verifyPending'), isFalse);
    });

    test('retired in v2, re-added unchanged in v3 → live again '
        '(flashcard and verified image_point alike)', () async {
      await importer.importPackBytes(buildSamplePackBytes(), topicId: topicId);
      await verifyQ12();

      // v2 retires q5 and q12.
      final v2 = versioned('1.1.0');
      v2['questions'] = questionsOf(v2)
          .where((q) => q['id'] != 'q5' && q['id'] != 'q12')
          .toList();
      final report2 = await importer.importPackBytes(
        packBytesFromJson(v2),
        topicId: topicId,
      );
      expect(report2.suspendedCount, 2);
      expect((await byQid('q5')).suspended, isTrue);
      expect((await byQid('q12')).suspended, isTrue);
      // Retirement does not stamp verifyPending on q12.
      expect(
        (await byQid('q12')).payload.containsKey('verifyPending'),
        isFalse,
      );

      // v3 re-adds both, contents unchanged.
      final report3 = await importer.importPackBytes(
        packBytesFromJson(versioned('1.2.0')),
        topicId: topicId,
      );
      expect(report3.status, PackImportStatus.updated);
      expect((await byQid('q5')).suspended, isFalse);
      final q12After = await byQid('q12');
      expect(q12After.suspended, isFalse);
      expect(q12After.payload.containsKey('verifyPending'), isFalse);
    });

    test('a gate-held question retired in v2 and re-added in v3 '
        'keeps the gate (verifyPending survives retirement)', () async {
      await importer.importPackBytes(buildSamplePackBytes(), topicId: topicId);
      // q12 is never verified: suspended WITH verifyPending.

      final v2 = versioned('1.1.0');
      v2['questions'] = questionsOf(v2).where((q) => q['id'] != 'q12').toList();
      await importer.importPackBytes(packBytesFromJson(v2), topicId: topicId);

      await importer.importPackBytes(
        packBytesFromJson(versioned('1.2.0')),
        topicId: topicId,
      );
      final after = await byQid('q12');
      expect(after.suspended, isTrue);
      expect(after.payload['verifyPending'], isTrue);
    });
  });

  group('phase 2 failure handling (S1)', () {
    test('fresh import: a raw write failure becomes PackException '
        'and files written by THIS call are removed', () async {
      // Write 1 (pack zip) succeeds, write 2 (media) explodes.
      final failing = _FailOnNthWriteLibrary(
        Directory('${tmp.path}/Library'),
        failOnWrite: 2,
      );
      final failingImporter = PackImporter(engine, learn, failing);
      await expectLater(
        failingImporter.importPackBytes(
          buildSamplePackBytes(),
          topicId: topicId,
        ),
        throwsA(isA<PackException>()),
      );
      await expectNothingWritten();
    });

    test('update: a raw write failure becomes PackException but '
        'written files are NOT deleted (they may have overwritten '
        'good files)', () async {
      await importer.importPackBytes(buildSamplePackBytes(), topicId: topicId);
      const mediaPath = 'media/arabic-greetings-01/m1.png';
      expect(await library.exists(mediaPath), isTrue);

      final failing = _FailOnNthWriteLibrary(
        Directory('${tmp.path}/Library'),
        failOnWrite: 2,
      );
      final failingImporter = PackImporter(engine, learn, failing);
      final json = sampleJson();
      (json['pack'] as Map)['version'] = '1.1.0';
      await expectLater(
        failingImporter.importPackBytes(
          packBytesFromJson(json),
          topicId: topicId,
        ),
        throwsA(isA<PackException>()),
      );
      // The pack zip (overwritten by this call) and the previous
      // media file both survive; the DB still records 1.0.0.
      expect(
        await library.exists(PackImporter.packRelPath('arabic-greetings-01')),
        isTrue,
      );
      expect(await library.readBytes(mediaPath), samplePngBytes);
      final pack = await engine.packByPackId('arabic-greetings-01');
      expect(pack!.version, '1.0.0');
      expect((await engine.questionsForPack('arabic-greetings-01')).length, 13);
    });
  });
}

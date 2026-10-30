/// LEARN engine — quiz-pack format (§R4.4): PURE structural
/// validation of a decoded `pack.json` value.
///
/// This layer knows the *container* shape only: schema markers,
/// the pack block, the media manifest, question count / id
/// uniqueness, and the optional arc block. It deliberately does
/// NOT validate per-question payloads — the importer runs those
/// through question.dart one by one so a bad question can be
/// skipped and reported without rejecting the whole pack.
///
/// API: [structuralIssues] returns every issue found (empty =
/// structurally valid) and never throws. [parsePackDocument]
/// returns a typed [PackDocument] or throws
/// [PackFormatException] carrying ALL of those issues.
library;

import '../../core/file_names.dart' as file_names;

/// Every structural problem found in one pack.json document.
class PackFormatException implements Exception {
  PackFormatException(this.issues);

  final List<String> issues;

  String get message => issues.join('; ');

  @override
  String toString() => 'PackFormatException: $message';
}

class PackMeta {
  const PackMeta({
    required this.id,
    required this.title,
    required this.version,
    this.language,
    this.author,
    this.tags,
    this.sourceRef,
  });

  final String id;
  final String title;
  final String version;
  final String? language;
  final String? author;
  final List<String>? tags;
  final String? sourceRef;
}

class PackMediaEntry {
  const PackMediaEntry({
    required this.id,
    required this.file,
    required this.mime,
    required this.sha256,
    this.alt,
  });

  final String id;

  /// Zip entry name inside the .quizpack (e.g. `media/hand.jpg`).
  final String file;
  final String mime;

  /// Declared SHA-256, 64 hex chars (case-insensitive here; the
  /// importer compares it against the lowercase computed digest).
  final String sha256;
  final String? alt;
}

/// A structurally valid pack.json, typed. [questions] are the RAW
/// question maps (id/type + payload fields, unvalidated beyond
/// id presence/uniqueness) for the importer to vet individually.
/// [arc] is the raw arc map, or null when the pack has none.
class PackDocument {
  const PackDocument({
    required this.pack,
    required this.media,
    required this.questions,
    this.arc,
  });

  final PackMeta pack;
  final List<PackMediaEntry> media;
  final List<Map<String, Object?>> questions;
  final Map<String, Object?>? arc;
}

final RegExp _sha256Re = RegExp(r'^[0-9a-fA-F]{64}$');

bool _isNonEmptyString(Object? v) => v is String && v.trim().isNotEmpty;

Map<String, Object?>? _asMap(Object? v) =>
    v is Map ? v.cast<String, Object?>() : null;

void _checkOptionalString(
  Map<String, Object?> m,
  String key,
  String what,
  List<String> issues,
) {
  final v = m[key];
  if (v != null && v is! String) issues.add('$what.$key must be a string');
}

/// Collect ALL structural issues in [decoded] (the already
/// JSON-decoded pack.json value). Empty list = valid.
List<String> structuralIssues(Object? decoded) {
  final issues = <String>[];
  final root = _asMap(decoded);
  if (root == null) {
    return ['pack.json must be a JSON object'];
  }

  if (root['schema'] != 'nimo.quizpack') {
    issues.add('schema must be "nimo.quizpack"');
  }
  final sv = root['schemaVersion'];
  if (sv is! int || sv != 1) {
    issues.add('schemaVersion must be the integer 1');
  }

  // ---- pack block
  final pack = _asMap(root['pack']);
  if (pack == null) {
    issues.add('pack must be an object {id, title, version}');
  } else {
    for (final key in ['id', 'title', 'version']) {
      if (!_isNonEmptyString(pack[key])) {
        issues.add('pack.$key must be a non-empty string');
      }
    }
    // The pack id becomes a Library path segment (via the
    // importer's sanitizeFileName-based path rule), so it must
    // survive sanitisation UNCHANGED: '../arabic-greetings-01'
    // and 'x/arabic-greetings-01' both fold to
    // 'arabic-greetings-01', and a hostile pack could otherwise
    // overwrite another pack's stored zip/media.
    final packId = pack['id'];
    if (_isNonEmptyString(packId) &&
        file_names.sanitizeFileName(packId as String) != packId) {
      issues.add(
        'pack.id must be a plain filename-safe id '
        '(it is changed by filename sanitisation)',
      );
    }
    _checkOptionalString(pack, 'language', 'pack', issues);
    _checkOptionalString(pack, 'author', 'pack', issues);
    _checkOptionalString(pack, 'sourceRef', 'pack', issues);
    final tags = pack['tags'];
    if (tags != null) {
      if (tags is! List || tags.any((t) => t is! String)) {
        issues.add('pack.tags must be a list of strings');
      }
    }
  }

  // ---- media list (absent = no media)
  final mediaRaw = root['media'];
  if (mediaRaw != null) {
    if (mediaRaw is! List) {
      issues.add('media must be a list');
    } else {
      final seen = <String>{};
      for (var i = 0; i < mediaRaw.length; i++) {
        final entry = _asMap(mediaRaw[i]);
        if (entry == null) {
          issues.add('media[$i] must be an object {id, file, mime, sha256}');
          continue;
        }
        final id = entry['id'];
        if (!_isNonEmptyString(id)) {
          issues.add('media[$i].id must be a non-empty string');
        } else if (!seen.add(id as String)) {
          issues.add('duplicate media id: $id');
        }
        // Same sanitisation-collision rule as pack.id: a media
        // id becomes a Library path segment, so it must survive
        // sanitisation unchanged or two distinct media ids could
        // fold onto the same stored file.
        if (_isNonEmptyString(id) &&
            file_names.sanitizeFileName(id as String) != id) {
          issues.add(
            'media[$i].id must be a plain filename-safe '
            'id (it is changed by filename sanitisation)',
          );
        }
        if (!_isNonEmptyString(entry['file'])) {
          issues.add('media[$i].file must be a non-empty string');
        }
        if (!_isNonEmptyString(entry['mime'])) {
          issues.add('media[$i].mime must be a non-empty string');
        }
        final sha = entry['sha256'];
        if (sha is! String || !_sha256Re.hasMatch(sha)) {
          issues.add('media[$i].sha256 must be 64 hex characters');
        }
        _checkOptionalString(entry, 'alt', 'media[$i]', issues);
      }
    }
  }

  // ---- questions list
  final questionsRaw = root['questions'];
  if (questionsRaw is! List) {
    issues.add('questions must be a list of 1–2000 entries');
  } else {
    if (questionsRaw.isEmpty || questionsRaw.length > 2000) {
      issues.add(
        'questions must contain 1–2000 entries '
        '(found ${questionsRaw.length})',
      );
    }
    final seen = <String>{};
    for (var i = 0; i < questionsRaw.length; i++) {
      final q = _asMap(questionsRaw[i]);
      if (q == null) {
        issues.add('questions[$i] must be an object');
        continue;
      }
      final id = q['id'];
      if (!_isNonEmptyString(id)) {
        issues.add('questions[$i].id must be a non-empty string');
      } else if (!seen.add(id as String)) {
        issues.add('duplicate question id: $id');
      }
    }
  }

  // ---- optional arc block
  final arcRaw = root['arc'];
  if (arcRaw != null) {
    final arc = _asMap(arcRaw);
    if (arc == null) {
      issues.add('arc must be an object {id, title, episode}');
    } else {
      if (!_isNonEmptyString(arc['id'])) {
        issues.add('arc.id must be a non-empty string');
      }
      if (!_isNonEmptyString(arc['title'])) {
        issues.add('arc.title must be a non-empty string');
      }
      final ep = arc['episode'];
      if (ep is! int || ep < 1) {
        issues.add('arc.episode must be an integer ≥ 1');
      }
      _checkOptionalString(arc, 'episodeTitle', 'arc', issues);
      _checkOptionalString(arc, 'teaser', 'arc', issues);
    }
  }

  return issues;
}

/// Parse [decoded] into a [PackDocument], or throw
/// [PackFormatException] carrying ALL structural issues.
PackDocument parsePackDocument(Object? decoded) {
  final issues = structuralIssues(decoded);
  if (issues.isNotEmpty) throw PackFormatException(issues);
  final root = (decoded as Map).cast<String, Object?>();
  final pack = (root['pack'] as Map).cast<String, Object?>();
  final mediaRaw = root['media'];
  final media = <PackMediaEntry>[
    if (mediaRaw is List)
      for (final raw in mediaRaw)
        PackMediaEntry(
          id: (raw as Map)['id'] as String,
          file: raw['file'] as String,
          mime: raw['mime'] as String,
          sha256: raw['sha256'] as String,
          alt: raw['alt'] as String?,
        ),
  ];
  final questions = <Map<String, Object?>>[
    for (final raw in root['questions'] as List)
      (raw as Map).cast<String, Object?>(),
  ];
  final arcRaw = root['arc'];
  return PackDocument(
    pack: PackMeta(
      id: pack['id'] as String,
      title: pack['title'] as String,
      version: pack['version'] as String,
      language: pack['language'] as String?,
      author: pack['author'] as String?,
      tags: (pack['tags'] as List?)?.cast<String>(),
      sourceRef: pack['sourceRef'] as String?,
    ),
    media: media,
    questions: questions,
    arc: arcRaw == null ? null : (arcRaw as Map).cast<String, Object?>(),
  );
}

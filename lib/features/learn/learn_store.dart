/// LEARN-data — topics, sources, marked points (S4, §R6.1).
///
/// A *topic* is an intention ("learn how planes fly") sparked by a
/// trigger — a reel, a link, a shared file. *Sources* are the real
/// material attached to a topic (PDF/TXT in the Library, or a link).
/// *Marked points* are the owner's own key-point captures from
/// reading cards (§R4.5): cloze-ready records (D-014) that the S5
/// Learn engine will mint `questions` rows from.
///
/// Capture never asks "which project?" first: share-intent and
/// quick captures land in a built-in **Inbox project** (seeded
/// idempotently, §R6.1); triage = moving the topic to a real
/// project later.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../core/ids.dart';
import '../store.dart';

/// Topic lifecycle (§R6.1).
abstract final class TopicStatus {
  static const String inbox = 'inbox';
  static const String sourcing = 'sourcing';
  static const String learning = 'learning';
  static const String done = 'done';
  static const String parked = 'parked';
  static const List<String> all = [inbox, sourcing, learning, done, parked];
}

/// Source kinds (§R6.1, plus 'file' for shared files that are
/// neither documents nor links — stored as-is, read externally).
abstract final class SourceKind {
  static const String pdf = 'pdf';
  static const String txt = 'txt';
  static const String link = 'link';
  static const String htmlQuiz = 'html_quiz';
  static const String pack = 'pack';
  static const String file = 'file';
}

/// Text-extraction outcome per source (§R4.5 honesty: a scanned
/// PDF is flagged, never silently imported as empty cards).
abstract final class ExtractionStatus {
  static const String ok = 'ok';
  static const String partial = 'partial';
  static const String scannedNoText = 'scanned_no_text';
  static const String failed = 'failed';

  /// Human line for the UI. Scanned PDFs say plainly that there is
  /// no readable text (OCR is out of scope, §R4.5).
  static String describe(String status) => switch (status) {
        ok => 'Text extracted',
        partial => 'Text extracted — some pages had no text',
        scannedNoText =>
          'No readable text in this PDF — it looks scanned. '
              'Read the file directly, or OCR it elsewhere.',
        failed => 'Text extraction failed for this file',
        _ => status,
      };
}

class Topic {
  const Topic({
    required this.id,
    required this.projectId,
    required this.title,
    this.triggerUrl,
    required this.status,
    this.track,
    required this.createdAt,
    required this.updatedAt,
    this.syncId,
  });

  final int id;
  final int projectId;
  final String title;
  final String? triggerUrl;
  final String status;
  final String? track;
  final int createdAt;
  final int updatedAt;
  final String? syncId;

  factory Topic.fromRow(Map<String, Object?> r) => Topic(
        id: r['id'] as int,
        projectId: r['project_id'] as int,
        title: r['title'] as String,
        triggerUrl: r['trigger_url'] as String?,
        status: r['status'] as String,
        track: r['track'] as String?,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        syncId: r['sync_id'] as String?,
      );
}

class Source {
  const Source({
    required this.id,
    required this.topicId,
    required this.kind,
    required this.title,
    this.fileRelPath,
    this.url,
    this.textRelPath,
    required this.extractionStatus,
    required this.createdAt,
    this.syncId,
  });

  final int id;
  final int topicId;
  final String kind;
  final String title;
  final String? fileRelPath;
  final String? url;

  /// Extracted-text sidecar inside the Library (PDF only; for TXT
  /// the file itself is the text, so this stays null).
  final String? textRelPath;
  final String extractionStatus;
  final int createdAt;
  final String? syncId;

  bool get hasReadableText =>
      extractionStatus == ExtractionStatus.ok ||
      extractionStatus == ExtractionStatus.partial;

  factory Source.fromRow(Map<String, Object?> r) => Source(
        id: r['id'] as int,
        topicId: r['topic_id'] as int,
        kind: r['kind'] as String,
        title: r['title'] as String,
        fileRelPath: r['file_rel_path'] as String?,
        url: r['url'] as String?,
        textRelPath: r['text_rel_path'] as String?,
        extractionStatus: r['extraction_status'] as String,
        createdAt: r['created_at'] as int,
        syncId: r['sync_id'] as String?,
      );
}

/// One marked key point (§R4.5): a full [sentence] with [spanText]
/// blanked = the cloze card S5 will build (front = sentence with
/// the span hidden, back = full sentence).
class MarkedPoint {
  const MarkedPoint({
    required this.id,
    required this.sourceId,
    required this.topicId,
    required this.sentence,
    required this.spanText,
    this.page,
    this.charOffset,
    required this.chunkIndex,
    required this.createdAt,
  });

  final int id;
  final int sourceId;
  final int topicId;
  final String sentence;
  final String spanText;

  /// 1-based PDF page, or null for TXT (whole-file text).
  final int? page;

  /// Offset of the span within the page's (PDF) or file's (TXT)
  /// extracted text.
  final int? charOffset;

  /// Which reading card (chunk) the point was marked on.
  final int chunkIndex;
  final int createdAt;

  /// The cloze preview: the sentence with the span blanked.
  String get clozeText => sentence.replaceFirst(spanText, '_____');

  factory MarkedPoint.fromRow(Map<String, Object?> r) => MarkedPoint(
        id: r['id'] as int,
        sourceId: r['source_id'] as int,
        topicId: r['topic_id'] as int,
        sentence: r['sentence'] as String,
        spanText: r['span_text'] as String,
        page: r['page'] as int?,
        charOffset: r['char_offset'] as int?,
        chunkIndex: r['chunk_index'] as int,
        createdAt: r['created_at'] as int,
      );
}

/// A mark-a-point rule violation (§R4.5). The UI shows [message]
/// verbatim; nothing is written when this is thrown.
class MarkedPointException implements Exception {
  MarkedPointException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LearnStore {
  LearnStore(this._db) : _store = Store(_db);

  final Database _db;

  /// WS/PRJ collaborator for Inbox seeding (stores may collaborate;
  /// features never reach into each other's UI).
  final Store _store;

  /// app_settings key holding the built-in Inbox project's id.
  static const String inboxProjectKey = 'inbox_project_id';

  // ------------------------------------------------------------ Inbox

  /// The built-in Inbox project, created on first use and found
  /// again afterwards (idempotent). It lives in the default
  /// workspace — the first by sort order — creating an "Inbox"
  /// workspace + project when the app has none yet. The pointer
  /// lives in `app_settings`; if it ever dangles (project deleted)
  /// it is re-seeded.
  Future<Project> ensureInboxProject() async {
    final rows = await _db.query('app_settings',
        where: 'key = ?', whereArgs: [inboxProjectKey], limit: 1);
    if (rows.isNotEmpty) {
      final id = int.tryParse(rows.first['value']! as String);
      if (id != null) {
        final found = await _db.query('projects',
            where: 'id = ?', whereArgs: [id], limit: 1);
        if (found.isNotEmpty) return Project.fromRow(found.first);
      }
    }
    final workspaces = await _store.workspaces();
    final ws = workspaces.isNotEmpty
        ? workspaces.first
        : await _store.createWorkspace('Inbox');
    final project = await _store.createProject(ws.id, 'Inbox');
    await _db.insert(
      'app_settings',
      {'key': inboxProjectKey, 'value': '${project.id}'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return project;
  }

  Future<int> inboxProjectId() async => (await ensureInboxProject()).id;

  /// How many topics sit in the Inbox — WITHOUT seeding it. For
  /// read-only surfaces (Hub Home): merely looking at the app
  /// must not create a workspace. Returns 0 when no Inbox exists
  /// yet or the pointer dangles.
  Future<int> inboxCountOrZero() async {
    final rows = await _db.query('app_settings',
        where: 'key = ?', whereArgs: [inboxProjectKey], limit: 1);
    if (rows.isEmpty) return 0;
    final id = int.tryParse(rows.first['value']! as String);
    if (id == null) return 0;
    final counts = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM topics WHERE project_id = ?', [id]);
    return counts.single['c'] as int;
  }

  // ------------------------------------------------------------ Topics

  Future<Topic> createTopic({
    required int projectId,
    required String title,
    String? triggerUrl,
    String? track,
    String status = TopicStatus.inbox,
  }) async {
    final now = AppDatabase.nowMs();
    final id = await _db.insert('topics', {
      'project_id': projectId,
      'title': title.trim(),
      'trigger_url': _blankToNull(triggerUrl),
      'status': status,
      'track': _blankToNull(track),
      'created_at': now,
      'updated_at': now,
      'sync_id': newUuid(),
      'updated_hlc': await nextHlc(_db),
    });
    return topicById(id);
  }

  Future<Topic> topicById(int id) async {
    final rows =
        await _db.query('topics', where: 'id = ?', whereArgs: [id], limit: 1);
    return Topic.fromRow(rows.single);
  }

  Future<List<Topic>> topicsForProject(int projectId) async {
    final rows = await _db.query('topics',
        where: 'project_id = ?',
        whereArgs: [projectId],
        orderBy: 'updated_at DESC, id DESC');
    return rows.map(Topic.fromRow).toList();
  }

  /// Topics sitting in the Inbox project (the triage queue).
  Future<List<Topic>> inboxTopics() async =>
      topicsForProject(await inboxProjectId());

  Future<int> inboxCount() async {
    final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM topics WHERE project_id = ?',
        [await inboxProjectId()]);
    return rows.single['c'] as int;
  }

  /// Every topic, most recently touched first (Day Close picker,
  /// Topics screen).
  Future<List<Topic>> allTopics() async {
    final rows =
        await _db.query('topics', orderBy: 'updated_at DESC, id DESC');
    return rows.map(Topic.fromRow).toList();
  }

  Future<void> updateTopic(
    int id, {
    String? title,
    String? status,
    String? track,
    bool clearTrack = false,
    int? projectId,
  }) async {
    final values = <String, Object?>{
      'updated_at': AppDatabase.nowMs(),
      'updated_hlc': await nextHlc(_db),
    };
    if (title != null) values['title'] = title.trim();
    if (status != null) values['status'] = status;
    if (clearTrack) {
      values['track'] = null;
    } else if (track != null) {
      values['track'] = _blankToNull(track);
    }
    if (projectId != null) values['project_id'] = projectId;
    await _db.update('topics', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Triage: move a topic out of (or into) a project. Leaving the
  /// Inbox with status still 'inbox' advances it to 'sourcing' —
  /// it has been picked up.
  Future<void> moveTopic(int id, int projectId) async {
    final topic = await topicById(id);
    final inboxId = await inboxProjectId();
    var status = topic.status;
    if (projectId != inboxId && status == TopicStatus.inbox) {
      status = TopicStatus.sourcing;
    }
    await updateTopic(id, projectId: projectId, status: status);
  }

  Future<void> deleteTopic(int id) async {
    await _db.delete('topics', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ Sources

  Future<Source> addSource({
    required int topicId,
    required String kind,
    required String title,
    String? fileRelPath,
    String? url,
    String? textRelPath,
    String extractionStatus = ExtractionStatus.ok,
  }) async {
    final id = await _db.insert('sources', {
      'topic_id': topicId,
      'kind': kind,
      'title': title.trim(),
      'file_rel_path': fileRelPath,
      'url': url,
      'text_rel_path': textRelPath,
      'extraction_status': extractionStatus,
      'created_at': AppDatabase.nowMs(),
      'sync_id': newUuid(),
      'updated_hlc': await nextHlc(_db),
    });
    await _touchTopic(topicId);
    return sourceById(id);
  }

  Future<Source> sourceById(int id) async {
    final rows =
        await _db.query('sources', where: 'id = ?', whereArgs: [id], limit: 1);
    return Source.fromRow(rows.single);
  }

  Future<List<Source>> sourcesForTopic(int topicId) async {
    final rows = await _db.query('sources',
        where: 'topic_id = ?', whereArgs: [topicId], orderBy: 'id ASC');
    return rows.map(Source.fromRow).toList();
  }

  Future<void> updateSourceExtraction(
    int id, {
    required String extractionStatus,
    String? textRelPath,
  }) async {
    final values = <String, Object?>{
      'extraction_status': extractionStatus,
      'updated_hlc': await nextHlc(_db),
    };
    if (textRelPath != null) values['text_rel_path'] = textRelPath;
    await _db.update('sources', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSource(int id) async {
    await _db.delete('sources', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ Marked points

  /// Mark a key point on a reading card (§R4.5 rules): the span
  /// must be part of the sentence and at most ~8 words; one mark
  /// per reading card; the same sentence cannot be marked twice
  /// from the same source. Violations throw [MarkedPointException]
  /// and write nothing.
  Future<MarkedPoint> markPoint({
    required int sourceId,
    required int topicId,
    required String sentence,
    required String spanText,
    int? page,
    int? charOffset,
    required int chunkIndex,
  }) async {
    final cleanSentence = sentence.trim();
    final cleanSpan = spanText.trim();
    if (cleanSentence.isEmpty || cleanSpan.isEmpty) {
      throw MarkedPointException('Pick a sentence and the words to blank.');
    }
    if (!cleanSentence.contains(cleanSpan)) {
      throw MarkedPointException('The blanked words must be in the sentence.');
    }
    final words = cleanSpan.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.length > 8) {
      throw MarkedPointException(
          'Keep the blanked span to about 8 words or fewer.');
    }
    final existing = await markedPointsForSource(sourceId);
    if (existing.any((m) => m.chunkIndex == chunkIndex)) {
      throw MarkedPointException(
          'This card already has a marked point — one per card.');
    }
    final normalised = _normaliseSentence(cleanSentence);
    if (existing
        .any((m) => _normaliseSentence(m.sentence) == normalised)) {
      throw MarkedPointException('That sentence is already marked.');
    }
    final id = await _db.insert('marked_points', {
      'source_id': sourceId,
      'topic_id': topicId,
      'sentence': cleanSentence,
      'span_text': cleanSpan,
      'page': page,
      'char_offset': charOffset,
      'chunk_index': chunkIndex,
      'created_at': AppDatabase.nowMs(),
      'sync_id': newUuid(),
      'updated_hlc': await nextHlc(_db),
    });
    final rows = await _db
        .query('marked_points', where: 'id = ?', whereArgs: [id], limit: 1);
    return MarkedPoint.fromRow(rows.single);
  }

  Future<List<MarkedPoint>> markedPointsForSource(int sourceId) async {
    final rows = await _db.query('marked_points',
        where: 'source_id = ?', whereArgs: [sourceId], orderBy: 'id ASC');
    return rows.map(MarkedPoint.fromRow).toList();
  }

  Future<List<MarkedPoint>> markedPointsForTopic(int topicId) async {
    final rows = await _db.query('marked_points',
        where: 'topic_id = ?', whereArgs: [topicId], orderBy: 'id ASC');
    return rows.map(MarkedPoint.fromRow).toList();
  }

  Future<void> deleteMarkedPoint(int id) async {
    await _db.delete('marked_points', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ internals

  Future<void> _touchTopic(int topicId) async {
    await _db.update(
      'topics',
      {
        'updated_at': AppDatabase.nowMs(),
        'updated_hlc': await nextHlc(_db),
      },
      where: 'id = ?',
      whereArgs: [topicId],
    );
  }

  static String _normaliseSentence(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _blankToNull(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

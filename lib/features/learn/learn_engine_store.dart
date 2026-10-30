/// LEARN engine — questions, review log, sessions, packs (S5,
/// §R4.3/§R4.4). The data layer over schema v5:
///
/// - `questions` carry their SM-2 state inline; the pure
///   scheduler in scheduler.dart computes transitions, this store
///   persists them.
/// - `review_log` is APPEND-ONLY: this class exposes inserts (via
///   [applyAnswer]) and reads, and deliberately no update/delete
///   API for it — history must survive even question deletion
///   (which is why review_log.question_id has no foreign key and
///   each row snapshots the question's sync_id as question_key).
/// - `learn_sessions` are written once at start and once at
///   finish; [finishSession] is the only update path.
/// - `packs` is the import registry for §R4.4 re-import semantics.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../core/ids.dart';
import 'question.dart';
import 'scheduler.dart';

// ------------------------------------------------------------ models

class LearnQuestion {
  const LearnQuestion({
    required this.id,
    required this.topicId,
    this.sourceId,
    this.packId,
    this.packQid,
    required this.type,
    required this.payload,
    required this.difficulty,
    required this.ef,
    required this.reps,
    required this.lapses,
    required this.intervalDays,
    required this.dueAt,
    required this.suspended,
    required this.createdAt,
    required this.updatedAt,
    this.syncId,
  });

  final int id;
  final int topicId;
  final int? sourceId;
  final String? packId;
  final String? packQid;
  final String type;

  /// Decoded JSON payload (shape per type, see question.dart).
  final Map<String, Object?> payload;
  final int difficulty;
  final double ef;
  final int reps;
  final int lapses;
  final int intervalDays;

  /// Epoch ms when this question becomes due.
  final int dueAt;
  final bool suspended;
  final int createdAt;
  final int updatedAt;
  final String? syncId;

  SchedState get schedState => SchedState(
    ef: ef,
    reps: reps,
    lapses: lapses,
    intervalDays: intervalDays,
    dueAtMs: dueAt,
  );

  factory LearnQuestion.fromRow(Map<String, Object?> r) => LearnQuestion(
    id: r['id'] as int,
    topicId: r['topic_id'] as int,
    sourceId: r['source_id'] as int?,
    packId: r['pack_id'] as String?,
    packQid: r['pack_qid'] as String?,
    type: r['type'] as String,
    payload: (jsonDecode(r['payload'] as String) as Map)
        .cast<String, Object?>(),
    difficulty: r['difficulty'] as int,
    ef: (r['ef'] as num).toDouble(),
    reps: r['reps'] as int,
    lapses: r['lapses'] as int,
    intervalDays: r['interval_days'] as int,
    dueAt: r['due_at'] as int,
    suspended: (r['suspended'] as int) == 1,
    createdAt: r['created_at'] as int,
    updatedAt: r['updated_at'] as int,
    syncId: r['sync_id'] as String?,
  );
}

/// One immutable review_log row.
class ReviewLogEntry {
  const ReviewLogEntry({
    required this.id,
    required this.questionId,
    this.questionKey,
    this.sessionId,
    required this.reviewedAt,
    required this.correct,
    this.latencyMs,
    this.syncId,
  });

  final int id;
  final int questionId;

  /// The question's sync_id, snapshotted at review time.
  final String? questionKey;
  final int? sessionId;
  final int reviewedAt;
  final bool correct;
  final int? latencyMs;
  final String? syncId;

  factory ReviewLogEntry.fromRow(Map<String, Object?> r) => ReviewLogEntry(
    id: r['id'] as int,
    questionId: r['question_id'] as int,
    questionKey: r['question_key'] as String?,
    sessionId: r['session_id'] as int?,
    reviewedAt: r['reviewed_at'] as int,
    correct: (r['correct'] as int) == 1,
    latencyMs: r['latency_ms'] as int?,
    syncId: r['sync_id'] as String?,
  );
}

class LearnSession {
  const LearnSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.finished,
    required this.kind,
    this.topicId,
    this.packId,
    required this.cardsTotal,
    required this.cardsCorrect,
    this.enjoyment,
    this.enjoymentReason,
    this.formatMix,
    this.syncId,
  });

  final int id;
  final int startedAt;
  final int? endedAt;

  /// True = reached the end screen; false = abandoned.
  final bool finished;

  /// 'episode' / 'review' / 'boss'.
  final String kind;
  final int? topicId;
  final String? packId;
  final int cardsTotal;
  final int cardsCorrect;

  /// 1–5, or null when the owner did not rate the session.
  final int? enjoyment;
  final String? enjoymentReason;

  /// Question-type → card count, decoded from JSON.
  final Map<String, int>? formatMix;
  final String? syncId;

  factory LearnSession.fromRow(Map<String, Object?> r) => LearnSession(
    id: r['id'] as int,
    startedAt: r['started_at'] as int,
    endedAt: r['ended_at'] as int?,
    finished: (r['finished'] as int) == 1,
    kind: r['kind'] as String,
    topicId: r['topic_id'] as int?,
    packId: r['pack_id'] as String?,
    cardsTotal: r['cards_total'] as int,
    cardsCorrect: r['cards_correct'] as int,
    enjoyment: r['enjoyment'] as int?,
    enjoymentReason: r['enjoyment_reason'] as String?,
    formatMix: r['format_mix'] == null
        ? null
        : (jsonDecode(r['format_mix'] as String) as Map)
              .cast<String, Object?>()
              .map((k, v) => MapEntry(k, (v as num).toInt())),
    syncId: r['sync_id'] as String?,
  );
}

class PackRecord {
  const PackRecord({
    required this.id,
    required this.packId,
    required this.version,
    required this.title,
    this.language,
    required this.topicId,
    this.sourceId,
    this.arc,
    required this.questionCount,
    required this.importedAt,
    required this.updatedAt,
    this.syncId,
  });

  final int id;
  final String packId;
  final String version;
  final String title;
  final String? language;
  final int topicId;
  final int? sourceId;

  /// Decoded arc JSON ({id,title,episode,episodeTitle,teaser}).
  final Map<String, Object?>? arc;
  final int questionCount;
  final int importedAt;
  final int updatedAt;
  final String? syncId;

  factory PackRecord.fromRow(Map<String, Object?> r) => PackRecord(
    id: r['id'] as int,
    packId: r['pack_id'] as String,
    version: r['version'] as String,
    title: r['title'] as String,
    language: r['language'] as String?,
    topicId: r['topic_id'] as int,
    sourceId: r['source_id'] as int?,
    arc: r['arc'] == null
        ? null
        : (jsonDecode(r['arc'] as String) as Map).cast<String, Object?>(),
    questionCount: r['question_count'] as int,
    importedAt: r['imported_at'] as int,
    updatedAt: r['updated_at'] as int,
    syncId: r['sync_id'] as String?,
  );
}

// ------------------------------------------------------------ store

class LearnEngineStore {
  LearnEngineStore(this._db);

  final Database _db;

  // ---------------------------------------------------------- questions

  Future<LearnQuestion> insertQuestion({
    required int topicId,
    int? sourceId,
    String? packId,
    String? packQid,
    required String type,
    required Map<String, Object?> payload,
    int difficulty = 3,
    DateTime? now,
  }) async {
    final issues = <String>[
      ...validatePayload(type, payload),
      ...validateDifficulty(difficulty),
    ];
    if (issues.isNotEmpty) {
      throw ArgumentError('Invalid question payload: ${issues.join('; ')}');
    }
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final id = await _db.insert('questions', {
      'topic_id': topicId,
      'source_id': sourceId,
      'pack_id': packId,
      'pack_qid': packQid,
      'type': type,
      'payload': jsonEncode(payload),
      'difficulty': difficulty,
      'ef': initialEf,
      'reps': 0,
      'lapses': 0,
      'interval_days': 0,
      'due_at': nowMs,
      'suspended': 0,
      'created_at': nowMs,
      'updated_at': nowMs,
      'sync_id': newUuid(),
      'updated_hlc': await nextHlc(_db),
    });
    return questionById(id);
  }

  Future<LearnQuestion> questionById(int id) async {
    final rows = await _db.query(
      'questions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return LearnQuestion.fromRow(rows.single);
  }

  Future<List<LearnQuestion>> questionsForTopic(int topicId) async {
    final rows = await _db.query(
      'questions',
      where: 'topic_id = ?',
      whereArgs: [topicId],
      orderBy: 'id ASC',
    );
    return rows.map(LearnQuestion.fromRow).toList();
  }

  Future<List<LearnQuestion>> questionsForPack(String packId) async {
    final rows = await _db.query(
      'questions',
      where: 'pack_id = ?',
      whereArgs: [packId],
      orderBy: 'id ASC',
    );
    return rows.map(LearnQuestion.fromRow).toList();
  }

  String _scopeWhere({int? topicId, String? packId, List<Object?>? args}) {
    final clauses = <String>[];
    if (topicId != null) {
      clauses.add('topic_id = ?');
      args?.add(topicId);
    }
    if (packId != null) {
      clauses.add('pack_id = ?');
      args?.add(packId);
    }
    return clauses.isEmpty ? '' : ' AND ${clauses.join(' AND ')}';
  }

  Future<List<LearnQuestion>> _listQuestions(
    String where,
    List<Object?> args, {
    required String orderBy,
    int? limit,
  }) async {
    final rows = await _db.query(
      'questions',
      where: where,
      whereArgs: args,
      orderBy: orderBy,
      limit: limit,
    );
    return rows.map(LearnQuestion.fromRow).toList();
  }

  /// Due now (or overdue), earliest due first. Suspended excluded.
  Future<List<LearnQuestion>> dueQuestions({
    int? nowMs,
    int? topicId,
    String? packId,
    int? limit,
  }) async {
    final now = nowMs ?? AppDatabase.nowMs();
    final args = <Object?>[now];
    final scope = _scopeWhere(topicId: topicId, packId: packId, args: args);
    return _listQuestions(
      'suspended = 0 AND due_at <= ?$scope',
      args,
      orderBy: 'due_at ASC, id ASC',
      limit: limit,
    );
  }

  /// Never answered (no reps, no lapses), creation order.
  Future<List<LearnQuestion>> newQuestions({
    int? topicId,
    String? packId,
    int? limit,
  }) async {
    final args = <Object?>[];
    final scope = _scopeWhere(topicId: topicId, packId: packId, args: args);
    return _listQuestions(
      'suspended = 0 AND reps = 0 AND lapses = 0$scope',
      args,
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
  }

  /// Previously missed and due again. Suspended excluded.
  Future<List<LearnQuestion>> missedQuestions({
    int? nowMs,
    int? topicId,
    String? packId,
    int? limit,
  }) async {
    final now = nowMs ?? AppDatabase.nowMs();
    final args = <Object?>[now];
    final scope = _scopeWhere(topicId: topicId, packId: packId, args: args);
    return _listQuestions(
      'suspended = 0 AND lapses > 0 AND due_at <= ?$scope',
      args,
      orderBy: 'due_at ASC, id ASC',
      limit: limit,
    );
  }

  Future<int> _count(String where, List<Object?> args) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM questions WHERE $where',
      args,
    );
    return rows.single['c'] as int;
  }

  /// Cheap due count — reads only, seeds nothing.
  Future<int> dueCount({int? nowMs, int? topicId, String? packId}) async {
    final now = nowMs ?? AppDatabase.nowMs();
    final args = <Object?>[now];
    final scope = _scopeWhere(topicId: topicId, packId: packId, args: args);
    return _count('suspended = 0 AND due_at <= ?$scope', args);
  }

  /// Cheap never-answered count — reads only, seeds nothing.
  Future<int> newCount({int? topicId, String? packId}) async {
    final args = <Object?>[];
    final scope = _scopeWhere(topicId: topicId, packId: packId, args: args);
    return _count('suspended = 0 AND reps = 0 AND lapses = 0$scope', args);
  }

  // ---------------------------------------------------------- answering

  /// Apply one answer: scheduler transition + question update +
  /// one append-only review_log row, in ONE transaction. HLCs are
  /// minted BEFORE the transaction (using the outer Database
  /// handle inside a transaction callback deadlocks in sqflite —
  /// the same pattern ReviewStore uses).
  Future<SchedState> applyAnswer(
    int questionId, {
    required bool correct,
    required int latencyMs,
    int? sessionId,
    DateTime? now,
  }) async {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final questionHlc = await nextHlc(_db);
    final logHlc = await nextHlc(_db);
    late SchedState next;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'questions',
        where: 'id = ?',
        whereArgs: [questionId],
        limit: 1,
      );
      final q = LearnQuestion.fromRow(rows.single);
      next = _schedulerApply(q.schedState, correct: correct, nowMs: nowMs);
      await txn.update(
        'questions',
        {
          'ef': next.ef,
          'reps': next.reps,
          'lapses': next.lapses,
          'interval_days': next.intervalDays,
          'due_at': next.dueAtMs,
          'updated_at': nowMs,
          'updated_hlc': questionHlc,
        },
        where: 'id = ?',
        whereArgs: [questionId],
      );
      await txn.insert('review_log', {
        'question_id': questionId,
        'question_key': q.syncId,
        'session_id': sessionId,
        'reviewed_at': nowMs,
        'correct': correct ? 1 : 0,
        'latency_ms': latencyMs,
        'sync_id': newUuid(),
        'updated_hlc': logHlc,
      });
    });
    return next;
  }

  /// Read-only review history for one question, oldest first.
  Future<List<ReviewLogEntry>> reviewLogForQuestion(int questionId) async {
    final rows = await _db.query(
      'review_log',
      where: 'question_id = ?',
      whereArgs: [questionId],
      orderBy: 'id ASC',
    );
    return rows.map(ReviewLogEntry.fromRow).toList();
  }

  /// Read-only review history for one session, oldest first.
  Future<List<ReviewLogEntry>> reviewLogForSession(int sessionId) async {
    final rows = await _db.query(
      'review_log',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(ReviewLogEntry.fromRow).toList();
  }

  // ---------------------------------------------------------- question edits

  Future<void> suspendQuestion(int id) => _setSuspended(id, true);

  Future<void> unsuspendQuestion(int id) => _setSuspended(id, false);

  Future<void> _setSuspended(int id, bool suspended) async {
    await _db.update(
      'questions',
      {
        'suspended': suspended ? 1 : 0,
        'updated_at': AppDatabase.nowMs(),
        'updated_hlc': await nextHlc(_db),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Replace a question's payload (validated against its existing
  /// type — e.g. the image-point verify step in a later step).
  /// Scheduler columns and the suspended flag are never touched.
  /// [difficulty], when given, replaces the difficulty column
  /// (validated 1–5) — the pack importer uses it on re-import so
  /// a pack update can re-level a question without touching its
  /// scheduler state.
  Future<void> updateQuestionPayload(
    int id,
    Map<String, Object?> payload, {
    int? difficulty,
  }) async {
    final q = await questionById(id);
    final issues = <String>[
      ...validatePayload(q.type, payload),
      if (difficulty != null) ...validateDifficulty(difficulty),
    ];
    if (issues.isNotEmpty) {
      throw ArgumentError('Invalid question payload: ${issues.join('; ')}');
    }
    await _db.update(
      'questions',
      {
        'payload': jsonEncode(payload),
        'difficulty': ?difficulty,
        'updated_at': AppDatabase.nowMs(),
        'updated_hlc': await nextHlc(_db),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard-delete one question row. ONLY for the pack importer's
  /// phase-3 compensation: the rows it deletes were inserted
  /// seconds earlier by the same call and cannot have review
  /// history (review_log has no FK on question_id, so even a
  /// hypothetical row would survive as history). No other caller
  /// should use this — retiring a question is [suspendQuestion].
  Future<void> deleteQuestion(int id) async {
    await _db.delete('questions', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------- cloze minting

  /// Mint one cloze question per un-minted marked point of
  /// [topicId] (front = the sentence with the span wrapped as
  /// `{{span}}`, per the §R4.5 mark-a-point records), link the
  /// point to its question, and return how many were minted.
  /// Idempotent: points already linked are skipped, so a second
  /// call mints 0.
  Future<int> mintClozeFromMarkedPoints(int topicId) async {
    final rows = await _db.query(
      'marked_points',
      where: 'topic_id = ? AND question_id IS NULL',
      whereArgs: [topicId],
      orderBy: 'id ASC',
    );
    var minted = 0;
    for (final r in rows) {
      final sentence = r['sentence'] as String;
      final span = r['span_text'] as String;
      if (!sentence.contains(span)) continue;
      final clozeText = sentence.replaceFirst(span, '{{$span}}');
      final q = await insertQuestion(
        topicId: topicId,
        sourceId: r['source_id'] as int,
        type: 'cloze',
        payload: {'text': clozeText, 'answer': span},
        difficulty: 2,
      );
      await _db.update(
        'marked_points',
        {'question_id': q.id, 'updated_hlc': await nextHlc(_db)},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
      minted++;
    }
    return minted;
  }

  // ---------------------------------------------------------- sessions

  Future<LearnSession> startSession({
    String kind = 'review',
    int? topicId,
    String? packId,
    DateTime? now,
  }) async {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final id = await _db.insert('learn_sessions', {
      'started_at': nowMs,
      'ended_at': null,
      'finished': 0,
      'kind': kind,
      'topic_id': topicId,
      'pack_id': packId,
      'cards_total': 0,
      'cards_correct': 0,
      'enjoyment': null,
      'enjoyment_reason': null,
      'format_mix': null,
      'sync_id': newUuid(),
      'updated_hlc': await nextHlc(_db),
    });
    return sessionById(id);
  }

  /// The ONLY session update path: closes the session out with
  /// its tallies and (optional) enjoyment rating.
  Future<LearnSession> finishSession(
    int id, {
    required bool finished,
    required int cardsTotal,
    required int cardsCorrect,
    Map<String, int>? formatMix,
    int? enjoyment,
    String? enjoymentReason,
    DateTime? now,
  }) async {
    if (enjoyment != null && (enjoyment < 1 || enjoyment > 5)) {
      throw ArgumentError('enjoyment must be between 1 and 5');
    }
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await _db.update(
      'learn_sessions',
      {
        'ended_at': nowMs,
        'finished': finished ? 1 : 0,
        'cards_total': cardsTotal,
        'cards_correct': cardsCorrect,
        'enjoyment': enjoyment,
        'enjoyment_reason': enjoymentReason,
        'format_mix': formatMix == null ? null : jsonEncode(formatMix),
        'updated_hlc': await nextHlc(_db),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return sessionById(id);
  }

  Future<LearnSession> sessionById(int id) async {
    final rows = await _db.query(
      'learn_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return LearnSession.fromRow(rows.single);
  }

  /// Newest sessions first, completed or not.
  Future<List<LearnSession>> recentSessions({int limit = 10}) async {
    final rows = await _db.query(
      'learn_sessions',
      orderBy: 'started_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(LearnSession.fromRow).toList();
  }

  // ---------------------------------------------------------- packs

  Future<PackRecord?> packByPackId(String packId) async {
    final rows = await _db.query(
      'packs',
      where: 'pack_id = ?',
      whereArgs: [packId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PackRecord.fromRow(rows.single);
  }

  Future<List<PackRecord>> packsForTopic(int topicId) async {
    final rows = await _db.query(
      'packs',
      where: 'topic_id = ?',
      whereArgs: [topicId],
      orderBy: 'id ASC',
    );
    return rows.map(PackRecord.fromRow).toList();
  }

  /// Every imported pack, most recently imported first (the
  /// Learn landing's Continue/Packs sections).
  Future<List<PackRecord>> allPacks() async {
    final rows = await _db.query(
      'packs',
      orderBy: 'imported_at DESC, id DESC',
    );
    return rows.map(PackRecord.fromRow).toList();
  }

  /// Image-point questions still awaiting owner verification of
  /// their target (§R4.1): suspended, with `verifyPending: true`
  /// in the payload. The LIKE pattern matches our own
  /// jsonEncode output, which writes the flag with no space.
  Future<List<LearnQuestion>> verifyPendingQuestions() async {
    final rows = await _db.query(
      'questions',
      where: "suspended = 1 AND type = 'image_point' "
          "AND payload LIKE ?",
      whereArgs: ['%"verifyPending":true%'],
      orderBy: 'id ASC',
    );
    return rows.map(LearnQuestion.fromRow).toList();
  }

  /// Marked points of [topicId] not yet minted into cloze
  /// questions (the topic screen's "Build cloze cards (N)").
  Future<int> unmintedPointCount(int topicId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM marked_points '
      'WHERE topic_id = ? AND question_id IS NULL',
      [topicId],
    );
    return rows.single['c'] as int;
  }

  /// Insert-or-update the registry row for [packId] (§R4.4
  /// re-import: the same pack_id updates in place, keeping its
  /// local id and sync_id; `imported_at` moves to the latest
  /// import time).
  Future<PackRecord> recordPack({
    required String packId,
    required String version,
    required String title,
    String? language,
    required int topicId,
    int? sourceId,
    Map<String, Object?>? arc,
    int questionCount = 0,
    DateTime? now,
  }) async {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final existing = await packByPackId(packId);
    final values = <String, Object?>{
      'pack_id': packId,
      'version': version,
      'title': title,
      'language': language,
      'topic_id': topicId,
      'source_id': sourceId,
      'arc': arc == null ? null : jsonEncode(arc),
      'question_count': questionCount,
      'imported_at': nowMs,
      'updated_at': nowMs,
      'updated_hlc': await nextHlc(_db),
    };
    if (existing == null) {
      values['sync_id'] = newUuid();
      await _db.insert('packs', values);
    } else {
      await _db.update(
        'packs',
        values,
        where: 'pack_id = ?',
        whereArgs: [packId],
      );
    }
    return (await packByPackId(packId))!;
  }
}

/// Scheduler transition (see scheduler.dart). Wrapped because
/// the store method [LearnEngineStore.applyAnswer] shadows the
/// imported top-level function of the same name inside the class.
SchedState _schedulerApply(
  SchedState state, {
  required bool correct,
  required int nowMs,
}) => applyAnswer(state, correct: correct, nowMs: nowMs);

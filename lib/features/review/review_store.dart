import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/ids.dart';
import '../today/today_store.dart';
import 'score.dart';
import 'streak.dart';

/// One closed (or closable) day: the Day Close record (REVIEW-01).
///
/// [doneScore] (the auto Done Score, formula-versioned) and
/// [selfScore] (the owner's 1–10 rating) are stored and shown
/// separately and are NEVER merged into a single number (§R5.2).
class DayReview {
  const DayReview({
    required this.id,
    required this.date,
    this.majorPoint,
    this.majorPointTopicId,
    this.selfScore,
    this.selfNote,
    this.doneScore,
    this.scoreFormulaVersion,
    this.closedAt,
    this.isCounted = false,
    this.tzOffset,
    this.syncId,
  });

  final int id;

  /// Local calendar date ('yyyy-mm-dd' key parsed back to a date).
  final DateTime date;
  final String? majorPoint;
  final int? majorPointTopicId;
  final int? selfScore;
  final String? selfNote;
  final int? doneScore;
  final int? scoreFormulaVersion;
  final DateTime? closedAt;

  /// Materialised by the streak evaluation pass only (red-team #17:
  /// the fold in streak.dart is the single derivation of "counted").
  final bool isCounted;

  /// Device UTC offset at close time, in minutes (schema stores an
  /// integer; kept for S7's cross-timezone day attribution).
  final int? tzOffset;
  final String? syncId;

  bool get isClosed => closedAt != null;

  factory DayReview.fromRow(Map<String, Object?> row) {
    return DayReview(
      id: row['id']! as int,
      date: DateTime.parse(row['date']! as String),
      majorPoint: row['major_point'] as String?,
      majorPointTopicId: row['major_point_topic_id'] as int?,
      selfScore: row['self_score'] as int?,
      selfNote: row['self_note'] as String?,
      doneScore: row['done_score'] as int?,
      scoreFormulaVersion: row['score_formula_version'] as int?,
      closedAt: row['closed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['closed_at']! as int),
      isCounted: (row['is_counted'] as int? ?? 0) == 1,
      tzOffset: row['tz_offset'] as int?,
      syncId: row['sync_id'] as String?,
    );
  }
}

/// The persisted streak summary (single row, id = 1). The
/// derivation fields are written ONLY by [ReviewStore.evaluate]
/// from the pure fold; the single exception is the
/// `shields_intro_shown` UI flag, set by
/// [ReviewStore.markShieldsIntroShown].
class StreakState {
  const StreakState({
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.totalDays = 0,
    this.shieldsHeld = 0,
    this.refillProgress = 0,
    this.lastCountedDate,
    this.evaluatedThrough,
    this.shieldsIntroShown = false,
  });

  final int currentStreak;
  final int bestStreak;
  final int totalDays;
  final int shieldsHeld;
  final int refillProgress;
  final DateTime? lastCountedDate;
  final DateTime? evaluatedThrough;
  final bool shieldsIntroShown;

  factory StreakState.fromRow(Map<String, Object?> row) {
    DateTime? parseDate(Object? v) =>
        v == null ? null : DateTime.parse(v as String);
    return StreakState(
      currentStreak: row['current_streak'] as int? ?? 0,
      bestStreak: row['best_streak'] as int? ?? 0,
      totalDays: row['total_days'] as int? ?? 0,
      shieldsHeld: row['shields_held'] as int? ?? 0,
      refillProgress: row['refill_progress'] as int? ?? 0,
      lastCountedDate: parseDate(row['last_counted_date']),
      evaluatedThrough: parseDate(row['evaluated_through']),
      shieldsIntroShown: (row['shields_intro_shown'] as int? ?? 0) == 1,
    );
  }
}

/// Which day the Day Close flow should target right now.
class CloseTarget {
  const CloseTarget(this.date, {required this.isLate});

  final DateTime date;

  /// True when [date] is yesterday being closed inside the
  /// late-close window (night-owl case, §R5.1 rule 6).
  final bool isLate;
}

/// Store for Day Close, dual scores and the streak (REVIEW-01..04).
///
/// "Counted" has exactly one derivation: the pure fold in
/// streak.dart. This store feeds it the two — and only two —
/// signals (core plan done, Day Close done; red-team finding 1),
/// persists its result, and materialises `day_reviews.is_counted`
/// and `shield_events` from it. Because evaluation re-folds from
/// scratch every time, a late Day Close automatically converts a
/// shield-covered day to counted and refunds the shield (red-team
/// #5b) — no special-case refund code exists anywhere.
class ReviewStore {
  ReviewStore(this._db, this._today);

  final Database _db;
  final TodayStore _today;

  static String _key(DateTime d) => TodayStore.dateKey(TodayStore.dayOnly(d));

  // ---- reads ------------------------------------------------------

  Future<DayReview?> reviewFor(DateTime date) async {
    final rows = await _db.query(
      'day_reviews',
      where: 'date = ?',
      whereArgs: [_key(date)],
      limit: 1,
    );
    return rows.isEmpty ? null : DayReview.fromRow(rows.first);
  }

  Future<StreakState> streakState() async {
    final rows = await _db.query('streak_state', where: 'id = 1', limit: 1);
    return rows.isEmpty
        ? const StreakState()
        : StreakState.fromRow(rows.first);
  }

  /// Done/total counts of the plan that EXISTS for [date] (never
  /// generates one) — for the Hub Home banner.
  Future<({int done, int total})> planCounts(DateTime date) async {
    final items = await _today.existingPlanItems(date);
    return (done: items.where((i) => i.done).length, total: items.length);
  }

  /// The day Day Close should target (§R5.1 rule 6): yesterday stays
  /// closable until today's plan "opens" — defined as: today not yet
  /// closed AND no item on today's (existing) plan ticked yet. Uses
  /// [TodayStore.existingPlanItems], so merely opening the app
  /// (which generates today's plan, all unticked) does not slam the
  /// window shut; the first tick of the new day does.
  Future<CloseTarget> closableDate({DateTime? now}) async {
    final today = TodayStore.dayOnly(now ?? DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final yesterdayReview = await reviewFor(yesterday);
    final todayReview = await reviewFor(today);
    if ((yesterdayReview == null || !yesterdayReview.isClosed) &&
        (todayReview == null || !todayReview.isClosed)) {
      final todaysItems = await _today.existingPlanItems(today);
      if (!todaysItems.any((i) => i.done)) {
        return CloseTarget(yesterday, isLate: true);
      }
    }
    return CloseTarget(today, isLate: false);
  }

  // ---- Day Close ----------------------------------------------------

  /// Closes [date] (or updates an already-closed review): computes
  /// the Done Score from the day's existing plan, stores the
  /// self-score and major point alongside it (never merged), then
  /// re-evaluates the streak.
  ///
  /// [learningSessionDone] feeds the score's learning block (S5).
  /// It is OR-ed with the derivation from `learn_sessions`
  /// ([_learningDoneOn]), so a day with a finished session gets
  /// the block even when the caller leaves this false.
  ///
  /// [majorPointTopicId] (S4) links the major point to a topic —
  /// the column is a real FK to `topics` since schema v4. It is
  /// only written when [majorPointTopicProvided] is true (the Day
  /// Close picker always provides its current selection, so
  /// picking "No topic" clears the link); other callers leave the
  /// flag false and any existing link is preserved.
  Future<DayReview> closeDay(
    DateTime date, {
    String? majorPoint,
    int? selfScore,
    String? selfNote,
    bool learningSessionDone = false,
    DateTime? now,
    int? majorPointTopicId,
    bool majorPointTopicProvided = false,
  }) async {
    final day = TodayStore.dayOnly(date);
    final at = now ?? DateTime.now();
    final items = await _today.existingPlanItems(day);
    final effectiveLearningDone =
        learningSessionDone || await _learningDoneOn(day);
    final doneScore = DoneScore.compute(
      itemDone: [for (final i in items) i.done],
      learningSessionDone: effectiveLearningDone,
      dayClosed: true,
    );
    final existing = await reviewFor(day);
    final hlc = await _nextHlc(at);
    // UPSERT on the date conflict: preserves the row id, the
    // original closed_at, the sync_id and — deliberately —
    // is_counted, which is owned solely by evaluate() (red-team
    // #17; review N2).
    await _db.rawInsert(
      '''
      INSERT INTO day_reviews (
        date, major_point, major_point_topic_id, self_score,
        self_note, done_score, score_formula_version, closed_at,
        tz_offset, sync_id, updated_hlc
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(date) DO UPDATE SET
        major_point = excluded.major_point,
        major_point_topic_id = excluded.major_point_topic_id,
        self_score = excluded.self_score,
        self_note = excluded.self_note,
        done_score = excluded.done_score,
        score_formula_version = excluded.score_formula_version,
        tz_offset = excluded.tz_offset,
        updated_hlc = excluded.updated_hlc
      ''',
      [
        _key(day),
        _blankToNull(majorPoint),
        majorPointTopicProvided
            ? majorPointTopicId
            : existing?.majorPointTopicId,
        selfScore,
        _blankToNull(selfNote),
        doneScore,
        DoneScore.formulaVersion,
        (existing?.closedAt ?? at).millisecondsSinceEpoch,
        at.timeZoneOffset.inMinutes,
        existing?.syncId ?? newUuid(),
        hlc,
      ],
    );
    await evaluate(now: at);
    return (await reviewFor(day))!;
  }

  /// Recomputes the Done Score of an already-closed day after its
  /// plan was edited from Hub Home (review S3: the Recap step is
  /// the last *planned* edit window, but Hub rows stay tappable —
  /// the stored score must not go stale). No-op for unclosed
  /// days. Counted-ness is untouched: the review signal holds
  /// regardless of ticks.
  Future<void> refreshDoneScoreIfClosed(DateTime date,
      {DateTime? now}) async {
    final existing = await reviewFor(date);
    if (existing == null || !existing.isClosed) return;
    final items = await _today.existingPlanItems(date);
    final score = DoneScore.compute(
      itemDone: [for (final i in items) i.done],
      learningSessionDone: await _learningDoneOn(date),
      dayClosed: true,
    );
    await _db.update(
      'day_reviews',
      {
        'done_score': score,
        'score_formula_version': DoneScore.formulaVersion,
        'updated_hlc': await _nextHlc(now ?? DateTime.now()),
      },
      where: 'date = ?',
      whereArgs: [_key(date)],
    );
  }

  // ---- streak evaluation --------------------------------------------

  /// Re-derives the streak from all signals and persists:
  /// streak_state, shield_events (regenerated wholesale), and
  /// day_reviews.is_counted. The window runs through yesterday —
  /// extended to today when today is already closed (a closed day
  /// is final). Monotonic: the evaluated-through date never
  /// regresses even if the device clock walks backwards;
  /// re-folding with changed inputs (a late close) still updates
  /// the result for the same window.
  /// The fold's full result for the current evaluation window,
  /// after refreshing the materialisations via [evaluate]. This
  /// is the ONLY window other features (PROGRESS, S6) may read
  /// counted/shield dates from — the fold stays the single
  /// derivation of counted-ness (red-team #17); consumers read
  /// its outputs, they never re-derive them from raw signals
  /// themselves.
  Future<StreakResult> currentFold({DateTime? now}) async {
    final at = now ?? DateTime.now();
    await evaluate(now: at);
    final through = await _evaluationThrough(at);
    final signals = await _signals();
    return deriveStreak(signals, through: through);
  }

  /// The date the evaluation window currently runs through:
  /// yesterday, extended to today when today is already closed,
  /// and never behind the persisted evaluated-through date
  /// (monotonic under backwards clock walks).
  Future<DateTime> _evaluationThrough(DateTime at) async {
    final stored = await streakState();
    var through = DateTime(at.year, at.month, at.day - 1);
    // A day that has been CLOSED is final, so it counts immediately
    // rather than waiting for tomorrow's evaluation.
    final todayReview = await reviewFor(DateTime(at.year, at.month, at.day));
    if (todayReview != null && todayReview.isClosed) {
      through = DateTime(at.year, at.month, at.day);
    }
    if (stored.evaluatedThrough != null &&
        stored.evaluatedThrough!.isAfter(through)) {
      through = stored.evaluatedThrough!;
    }
    return through;
  }

  Future<StreakState> evaluate({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final through = await _evaluationThrough(at);
    final signals = await _signals();
    final result = deriveStreak(signals, through: through);
    final stampMs = at.millisecondsSinceEpoch;
    // Shield keys are sorted FIRST and HLC stamps are taken in
    // that same order, before the transaction (using the outer
    // Database handle inside a transaction callback deadlocks in
    // sqflite). Stamp order must match insertion order (review N4).
    final shieldKeys = result.shieldDates.toList()..sort();
    final shieldHlcs = <String>[
      for (var i = 0; i < shieldKeys.length; i++) await _nextHlc(at),
    ];
    await _db.transaction((txn) async {
      await txn.update(
        'streak_state',
        {
          'current_streak': result.currentStreak,
          'best_streak': result.bestStreak,
          'total_days': result.totalDays,
          'shields_held': result.shieldsHeld,
          'refill_progress': result.refillProgress,
          'last_counted_date': result.lastCountedDate,
          'evaluated_through': _key(through),
          'updated_at': stampMs,
        },
        where: 'id = 1',
      );
      // Shield events are a materialisation of the fold, regenerated
      // wholesale — a refunded shield simply disappears from the list.
      await txn.delete('shield_events');
      for (var i = 0; i < shieldKeys.length; i++) {
        await txn.insert('shield_events', {
          'date': shieldKeys[i],
          'week_key': isoWeekKey(DateTime.parse(shieldKeys[i])),
          'created_at': stampMs,
          'sync_id': newUuid(),
          'updated_hlc': shieldHlcs[i],
        });
      }
      await txn.update('day_reviews', {'is_counted': 0});
      for (final d in result.countedDates) {
        await txn.update(
          'day_reviews',
          {'is_counted': 1},
          where: 'date = ?',
          whereArgs: [d],
        );
      }
    });
    return streakState();
  }

  Future<void> markShieldsIntroShown() async {
    await _db.update(
      'streak_state',
      {'shields_intro_shown': 1},
      where: 'id = 1',
    );
  }

  // ---- internals ------------------------------------------------------

  /// Whether a FINISHED learn session ended on [day] (local
  /// calendar day), derived from `learn_sessions.ended_at`.
  ///
  /// This derivation feeds the Done Score ONLY (the learning
  /// block in [closeDay] and [refreshDoneScoreIfClosed]).
  /// [_signals] / [evaluate] and counted-ness are untouched by
  /// it: a learning session is NEVER a streak signal — the day
  /// counts only via core plan done or Day Close done, exactly
  /// two signals (red-team #1).
  Future<bool> _learningDoneOn(DateTime day) async {
    final start = TodayStore.dayOnly(day);
    final end = DateTime(start.year, start.month, start.day + 1);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM learn_sessions '
      'WHERE finished = 1 AND ended_at >= ? AND ended_at < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return (rows.single['c'] as int) > 0;
  }

  /// Builds the fold's input: every date that has a plan or a
  /// review, mapped to its two signals, keyed by 'yyyy-mm-dd'.
  /// The plan signal reads the items' snapshotted core flags
  /// (review M1), so it is stable under later routine edits.
  Future<Map<String, DaySignals>> _signals() async {
    final dateRows = await _db.rawQuery(
      'SELECT date FROM day_plans UNION SELECT date FROM day_reviews',
    );
    final signals = <String, DaySignals>{};
    for (final row in dateRows) {
      final key = row['date']! as String;
      final date = DateTime.parse(key);
      final items = await _today.existingPlanItems(date);
      final review = await reviewFor(date);
      signals[key] = DaySignals(
        planCounts: items.isNotEmpty && corePlanComplete(items),
        reviewClosed: review?.isClosed ?? false,
      );
    }
    return signals;
  }

  /// Next hybrid-logical-clock stamp for this device, persisted in
  /// sync_meta so monotonicity survives restarts. Scaffold for S7.
  Future<String> _nextHlc(DateTime at) async {
    final deviceId = await AppDatabase.deviceId(_db);
    final rows = await _db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['hlc_state'],
      limit: 1,
    );
    var lastWall = -1;
    var lastCounter = -1;
    if (rows.isNotEmpty) {
      final parts = (rows.first['value']! as String).split(':');
      lastWall = int.parse(parts[0]);
      lastCounter = int.parse(parts[1]);
    }
    final wall = at.millisecondsSinceEpoch > lastWall
        ? at.millisecondsSinceEpoch
        : lastWall;
    final counter = wall == lastWall ? lastCounter + 1 : 0;
    await _db.insert('sync_meta', {
      'key': 'hlc_state',
      'value': '$wall:$counter',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return formatHlc(wall, counter, deviceId);
  }

  static String? _blankToNull(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

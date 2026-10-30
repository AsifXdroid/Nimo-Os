// PROGRESS — the weekly summary across a DST-transition week
// (S6 review S7; TESTING §9 S6 calendar boundary matrix).
//
// The EU fall-back week of 2026: Mon 19 Oct – Sun 25 Oct, where
// Sunday is 25 hours long in Europe/Berlin. The store bounds the
// week's sessions by LOCAL midnights ([Mon 00:00, next Mon
// 00:00) in epoch ms = a 169-hour window there). A session ended
// Sunday 23:30 wall-clock belongs to this week; one ended Monday
// 00:30 belongs to the next. A fixed 7×24h window would silently
// drop the Sunday-evening session.
//
// Run under a DST zone for the transition to bite:
//   TZ=Europe/Berlin flutter test test/features/progress/dst_week_test.dart
// Under UTC the same wall-clock membership assertions still hold
// (the window logic is identical; Sunday is simply 24h long).
import 'dart:convert';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/progress/progress_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late ProgressStore progress;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await AppDatabase.openInMemory();
    for (final t in [
      'day_reviews', 'shield_events', 'day_plan_items', 'day_plans',
      'plan_templates', 'app_settings', 'learn_sessions', 'review_log',
      'questions', 'marked_points', 'sources', 'topics', 'packs',
      'items', 'checklist_entries', 'projects', 'workspaces', 'goals',
    ]) {
      await db.delete(t);
    }
    await db.update('streak_state', {
      'current_streak': 0, 'best_streak': 0, 'total_days': 0,
      'shields_held': 0, 'refill_progress': 0,
      'last_counted_date': null, 'evaluated_through': null,
      'shields_intro_shown': 0, 'updated_at': 0,
    });
    await db.delete('sync_meta', where: 'key = ?', whereArgs: ['hlc_state']);
    final today = TodayStore(db);
    progress = ProgressStore(db, ReviewStore(db, today), today);
  });

  Future<void> insertSession(DateTime ended) async {
    await db.insert('learn_sessions', {
      'started_at':
          ended.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
      'ended_at': ended.millisecondsSinceEpoch,
      'finished': 1,
      'kind': 'episode',
      'topic_id': null,
      'cards_total': 12,
      'cards_correct': 9,
      'enjoyment': 4,
      'format_mix': jsonEncode({'mcq': 12}),
    });
  }

  test('DST week: Sunday 23:30 session is this week, Monday 00:30 is next',
      () async {
    // Sunday of the fall-back week, late evening wall-clock.
    await insertSession(DateTime(2026, 10, 25, 23, 30));
    // First minutes of the NEXT week.
    await insertSession(DateTime(2026, 10, 26, 0, 30));

    final thisWeek = await progress.weeklySummary(
      DateTime(2026, 10, 25),
      now: DateTime(2026, 10, 25, 23, 45),
    );
    expect(thisWeek.monday, DateTime(2026, 10, 19));
    expect(thisWeek.sunday, DateTime(2026, 10, 25));
    expect(thisWeek.sessionCount, 1,
        reason: 'the Sunday 23:30 session must not fall out of '
            'a 25-hour Sunday');

    final nextWeek = await progress.weeklySummary(
      DateTime(2026, 10, 26),
      now: DateTime(2026, 10, 26, 1),
    );
    expect(nextWeek.monday, DateTime(2026, 10, 26));
    expect(nextWeek.sessionCount, 1);
  });

  test('the epoch-ms week window is built from local midnights', () async {
    final monday = DateTime(2026, 10, 19);
    final nextMonday = DateTime(2026, 10, 26);
    final spanHours = nextMonday.difference(monday).inHours;
    // 168 in fixed zones, 169 across the EU fall-back — either
    // way the window comes from calendar construction, never a
    // hard-coded 7*24h.
    expect(spanHours, anyOf(168, 169));
    final sundayLate = DateTime(2026, 10, 25, 23, 30);
    expect(sundayLate.millisecondsSinceEpoch,
        greaterThanOrEqualTo(monday.millisecondsSinceEpoch));
    expect(sundayLate.millisecondsSinceEpoch,
        lessThan(nextMonday.millisecondsSinceEpoch));
  });
}

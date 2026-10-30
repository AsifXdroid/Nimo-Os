// REVIEW — Streak Shields fold (§R5.3 as corrected by the red
// team): named boundary cases from the TESTING.md §10.1 matrix
// (streak lengths 0/1/6/7/8, shields 0/1/2, week boundaries, gap
// walks, late-close refund) plus glados property tests (§9/S3).
import 'package:daily_life_app/features/review/streak.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' as glados;

/// Builds fold signals from a compact day spec starting at
/// [start]: 'C' = counted via plan, 'R' = counted via Day Close,
/// '.' = present but not counted (a missed day with a plan).
Map<String, DaySignals> _spec(DateTime start, String spec) {
  final out = <String, DaySignals>{};
  for (var i = 0; i < spec.length; i++) {
    final day = DateTime(start.year, start.month, start.day + i);
    out[TodayStore.dateKey(day)] = switch (spec[i]) {
      'C' => const DaySignals(planCounts: true),
      'R' => const DaySignals(reviewClosed: true),
      _ => const DaySignals(),
    };
  }
  return out;
}

DateTime _day(DateTime start, int offset) =>
    DateTime(start.year, start.month, start.day + offset);

String _key(DateTime start, int offset) =>
    TodayStore.dateKey(_day(start, offset));

void main() {
  // Monday 2026-01-05 (ISO week 2026-W02).
  final mon = DateTime(2026, 1, 5);

  group('isoWeekKey', () {
    test('Monday 2026-01-05 is 2026-W02', () {
      expect(isoWeekKey(DateTime(2026, 1, 5)), '2026-W02');
    });
    test('Sunday 2026-01-04 belongs to 2026-W01', () {
      expect(isoWeekKey(DateTime(2026, 1, 4)), '2026-W01');
    });
    test('Monday 2025-12-29 belongs to ISO year 2026, W01', () {
      expect(isoWeekKey(DateTime(2025, 12, 29)), '2026-W01');
    });
    test('2026 is a 53-week ISO year', () {
      expect(isoWeekKey(DateTime(2026, 12, 31)), '2026-W53');
    });
  });

  group('corePlanComplete', () {
    DayPlanItem item({
      required bool routine,
      bool core = false,
      required bool done,
    }) =>
        DayPlanItem(
          id: 0,
          dayPlanId: 0,
          title: 'x',
          kind: routine ? PlanItemKind.routine : PlanItemKind.oneoff,
          templateId: null,
          done: done,
          carried: false,
          position: 0,
          countsCore: core,
        );

    test('empty plan never counts', () {
      expect(corePlanComplete(const []), isFalse);
    });
    test('all core routine items done counts', () {
      expect(
        corePlanComplete([
          item(routine: true, core: true, done: true),
          item(routine: true, core: false, done: false),
        ]),
        isTrue,
      );
    });
    test('core incomplete but 80% overall counts', () {
      expect(
        corePlanComplete([
          item(routine: true, core: true, done: false),
          item(routine: false, done: true),
          item(routine: false, done: true),
          item(routine: false, done: true),
          item(routine: false, done: true),
        ]),
        isTrue,
      );
    });
    test('core incomplete and under 80% does not count', () {
      expect(
        corePlanComplete([
          item(routine: true, core: true, done: false),
          item(routine: false, done: true),
          item(routine: false, done: true),
          item(routine: false, done: false),
          item(routine: false, done: false),
        ]),
        isFalse,
      );
    });
    test('60% overall with core incomplete does not count', () {
      // Pins the 0.8 threshold from below: 3 of 5 done = 0.6 must
      // NOT satisfy the fallback path (mutation spot-check).
      expect(
        corePlanComplete([
          item(routine: true, core: true, done: false),
          item(routine: false, done: true),
          item(routine: false, done: true),
          item(routine: false, done: true),
          item(routine: false, done: false),
        ]),
        isFalse,
      );
    });
    test('non-core routine items do not block the core path', () {
      expect(
        corePlanComplete([
          item(routine: true, core: true, done: true),
          item(routine: true, core: false, done: false),
        ]),
        isTrue,
      );
    });
  });

  group('deriveStreak named walks', () {
    test('no signals = zero state', () {
      final r = deriveStreak(const {}, through: mon);
      expect(r.currentStreak, 0);
      expect(r.totalDays, 0);
      expect(r.shieldsHeld, 0);
    });

    test('3 counted days: streak 3, no shields', () {
      final r = deriveStreak(_spec(mon, 'CCC'), through: _day(mon, 2));
      expect(r.currentStreak, 3);
      expect(r.totalDays, 3);
      expect(r.bestStreak, 3);
      expect(r.shieldsHeld, 0);
      expect(r.shieldDates, isEmpty);
    });

    test('a miss before day 7 resets (no shields exist yet)', () {
      final r = deriveStreak(_spec(mon, 'CCCCCC.C'), through: _day(mon, 7));
      expect(r.bestStreak, 6);
      expect(r.currentStreak, 1);
      expect(r.totalDays, 7);
      expect(r.shieldDates, isEmpty);
    });

    test('reaching 7 grants one shield ("You have earned protection")', () {
      final r = deriveStreak(_spec(mon, 'CCCCCCC'), through: _day(mon, 6));
      expect(r.currentStreak, 7);
      expect(r.shieldsHeld, 1);
    });

    test('a miss at streak 7 spends the shield, streak survives', () {
      final r = deriveStreak(_spec(mon, 'CCCCCCC.'), through: _day(mon, 7));
      expect(r.currentStreak, 7);
      expect(r.shieldsHeld, 0);
      expect(r.shieldDates, {_key(mon, 7)});
      expect(r.totalDays, 7); // shield days are not counted days
    });

    test('two misses in a row after the grant: shield, then reset', () {
      final r = deriveStreak(_spec(mon, 'CCCCCCC..'), through: _day(mon, 8));
      expect(r.shieldDates, {_key(mon, 7)});
      expect(r.currentStreak, 0);
      expect(r.bestStreak, 7);
      expect(r.totalDays, 7);
    });

    test('multi-week walk: refill, spend, and the per-week cap holds',
        () {
      // W02: 7 counted (grant). W03 Mon miss → shield spent.
      // W03: 6 more counted + W04 Mon counted = refill +1 on the
      // 7th protected counted day. W04 Tue miss → shield spent.
      // Then counted through W05 Mon (refill +1), W05 Tue+Wed
      // misses in the same week: first spends, second — with no
      // shield left — resets.
      const spec = 'CCCCCCC' // Jan 5–11 (W02)
          '.CCCCCC' // Jan 12 miss (shield), 13–18 counted
          'C' // Jan 19 counted → refill completes (7 protected days)
          '.' // Jan 20 miss (shield, W04)
          'CCCCCCC' // Jan 21–27 counted → refill +1 on Jan 27
          '.' // Jan 28 miss (shield, W05)
          'CCCCCC' // Jan 29–Feb 3 counted
          'C' // Feb 4 counted → refill +1 (7 protected days)
          '..'; // Feb 5 spends (W06), Feb 6 resets (no shield)
      final signals = _spec(mon, spec);
      final end = _day(mon, spec.length - 1);

      // Mid-walk: after Jan 19 the shield has refilled.
      final mid = deriveStreak(signals, through: DateTime(2026, 1, 19));
      expect(mid.shieldsHeld, 1);
      expect(mid.currentStreak, 14);
      expect(mid.shieldDates, {_key(mon, 7)});

      final r = deriveStreak(signals, through: end);
      expect(
        r.shieldDates,
        {_key(mon, 7), _key(mon, 15), _key(mon, 23), _key(mon, 31)},
      );
      // Per-week derivation (red-team #5a): no ISO week exceeds 2.
      final perWeek = <String, int>{};
      for (final d in r.shieldDates) {
        final wk = isoWeekKey(DateTime.parse(d));
        perWeek[wk] = (perWeek[wk] ?? 0) + 1;
      }
      expect(perWeek.values.every((n) => n <= 2), isTrue);
      expect(r.currentStreak, 0); // Feb 6 miss, no shield left
      expect(r.bestStreak, 28);
      expect(r.totalDays, 28);
      expect(r.shieldsHeld, 0);
    });

    test('weekly cap: a third miss in one ISO week cannot spend', () {
      // Reach 7 by Sunday Jan 11 (W02). W03: Mon miss spends the
      // only shield; Tue counted refills progress… instead build a
      // direct cap case: 7 counted, then Mon+Tue misses with two
      // shields held is impossible this early — use a long run:
      // 21 counted days (held caps at 2), then 3 misses in one week.
      final start = mon;
      // 21 counted days: Jan 5–25; misses Jan 26, 27, 28 — all in
      // ISO week W05, so the third miss must NOT spend.
      final spec = 'C' * 21 + '...';
      final r = deriveStreak(_spec(start, spec), through: _day(start, 23));
      expect(r.shieldDates.length, 2); // cap: max 2 per ISO week
      expect(r.shieldDates, {_key(start, 21), _key(start, 22)});
      expect(r.currentStreak, 0); // third miss resets
    });

    test('weekly cap binds on a THIRD spend attempt in one week',
        () {
      // Enter ISO week W05 (Mon Jan 26) with streak 20, 2 shields
      // held and refill progress 6 — built from a Jan 6 start:
      // 20 counted days (grant at 7, refill to 2 held, progress 6).
      final start = DateTime(2026, 1, 6); // Tuesday
      const spec = 'CCCCCCCCCCCCCCCCCCCC' // Jan 6–25 counted
          '.' // Mon Jan 26: miss → spend #1 (held 2→1)
          'C' // Tue Jan 27: counted → refill completes (held 2)
          '.' // Wed Jan 28: miss → spend #2 (held 2→1)
          '.'; // Thu Jan 29: miss #3 — cap (2/week) must BLOCK it
      final r = deriveStreak(_spec(start, spec), through: _day(start, 23));
      expect(r.shieldDates, {_key(start, 20), _key(start, 22)});
      expect(r.currentStreak, 0); // third miss resets the streak
      expect(r.shieldsHeld, 1); // the blocked spend keeps the shield
    });

    test('refill needs the full 7 protected days, not 6', () {
      // Grant at 7, spend on the miss, then count: after exactly
      // 6 protected counted days no shield may have refilled yet;
      // the 7th completes the refill (mutation spot-check).
      const spec = 'CCCCCCC' '.' 'CCCCCC'; // through the 6th day
      final mid = deriveStreak(_spec(mon, spec), through: _day(mon, 13));
      expect(mid.shieldsHeld, 0);
      expect(mid.refillProgress, 6);
      final full =
          deriveStreak(_spec(mon, '${spec}C'), through: _day(mon, 14));
      expect(full.shieldsHeld, 1);
      expect(full.refillProgress, 0);
    });

    test('refill caps at 2 held', () {
      final r = deriveStreak(_spec(mon, 'C' * 35), through: _day(mon, 34));
      expect(r.shieldsHeld, 2);
      expect(r.currentStreak, 35);
      expect(r.totalDays, 35);
    });

    test('signals after `through` are ignored', () {
      final r = deriveStreak(_spec(mon, 'C' * 20), through: _day(mon, 5));
      expect(r.totalDays, 6);
      expect(r.currentStreak, 6);
    });

    test('late close refunds the shield (fold level, red-team #5b)',
        () {
      final spent = deriveStreak(_spec(mon, 'CCCCCCC.'), through: _day(mon, 7));
      expect(spent.shieldDates, {_key(mon, 7)});
      expect(spent.shieldsHeld, 0);
      // The same history, with the missed day now closed late:
      final refunded =
          deriveStreak(_spec(mon, 'CCCCCCCR'), through: _day(mon, 7));
      expect(refunded.shieldDates, isEmpty);
      expect(refunded.shieldsHeld, 1);
      expect(refunded.currentStreak, 8);
      expect(refunded.totalDays, 8);
    });

    test('a reset re-arms the protection grant for the next run', () {
      // 7 counted, 2 misses (shield + reset), then 7 counted again.
      final r = deriveStreak(
          _spec(mon, 'CCCCCCC..CCCCCCC'), through: _day(mon, 15));
      expect(r.currentStreak, 7);
      expect(r.shieldsHeld, 1);
      expect(r.bestStreak, 7);
      expect(r.totalDays, 14);
    });
  });

  group('deriveStreak properties (glados)', () {
    glados.Glados<List<bool>>(
            glados.any.listWithLengthInRange(0, 46, glados.any.bool))
        .test('shield caps, week caps, and totals hold on random walks',
            (outcomes) {
      final signals = <String, DaySignals>{};
      for (var i = 0; i < outcomes.length; i++) {
        signals[_key(mon, i)] =
            outcomes[i] ? const DaySignals(planCounts: true) : const DaySignals();
      }
      final through =
          outcomes.isEmpty ? mon : _day(mon, outcomes.length - 1);
      final r = deriveStreak(signals, through: through);

      // Shield balance stays within [0, 2].
      expect(r.shieldsHeld, inInclusiveRange(0, 2));
      // Totals are exactly the counted inputs; best ≥ current.
      expect(r.totalDays, outcomes.where((o) => o).length);
      expect(r.countedDates.length, r.totalDays);
      expect(r.bestStreak, greaterThanOrEqualTo(r.currentStreak));
      expect(r.currentStreak, lessThanOrEqualTo(r.totalDays));
      // ≤ 2 shield-days per ISO week (red-team #5a).
      final perWeek = <String, int>{};
      for (final d in r.shieldDates) {
        final wk = isoWeekKey(DateTime.parse(d));
        perWeek[wk] = (perWeek[wk] ?? 0) + 1;
      }
      expect(perWeek.values.every((n) => n <= 2), isTrue,
          reason: 'a week used more than 2 shields: $perWeek');
      // No shields before a run first reaches 7.
      var run = 0;
      var reached7 = false;
      for (final o in outcomes) {
        run = o ? run + 1 : 0;
        if (run >= 7) reached7 = true;
      }
      if (!reached7) {
        expect(r.shieldDates, isEmpty);
        expect(r.shieldsHeld, 0);
      }
      // Shield dates are never counted dates.
      expect(r.shieldDates.intersection(r.countedDates), isEmpty);
    });
  });
}

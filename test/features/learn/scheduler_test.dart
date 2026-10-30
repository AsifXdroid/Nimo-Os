// LEARN engine — simplified SM-2 scheduler (§R4.3): the named
// interval/EF ladder plus glados properties over arbitrary
// answer sequences.
import 'package:daily_life_app/features/learn/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' as glados;

void main() {
  const t0 = 1700000000000;

  group('initialSched', () {
    test('new card: ef 2.5, no reps/lapses, due immediately', () {
      final s = initialSched(t0);
      expect(s.ef, 2.5);
      expect(s.reps, 0);
      expect(s.lapses, 0);
      expect(s.intervalDays, 0);
      expect(s.dueAtMs, t0);
    });
  });

  group('applyAnswer correct ladder', () {
    test('1st correct → 1 day, reps 1', () {
      final s = applyAnswer(initialSched(t0), correct: true, nowMs: t0);
      expect(s.intervalDays, 1);
      expect(s.reps, 1);
      expect(s.dueAtMs, t0 + msPerDay);
    });

    test('2nd correct → 3 days, reps 2', () {
      var s = applyAnswer(initialSched(t0), correct: true, nowMs: t0);
      s = applyAnswer(s, correct: true, nowMs: s.dueAtMs);
      expect(s.intervalDays, 3);
      expect(s.reps, 2);
      expect(s.dueAtMs, t0 + msPerDay + 3 * msPerDay);
    });

    test('3rd correct → round(prev × ef) = round(3 × 2.5) = 8', () {
      var s = initialSched(t0);
      s = applyAnswer(s, correct: true, nowMs: t0);
      s = applyAnswer(s, correct: true, nowMs: s.dueAtMs);
      s = applyAnswer(s, correct: true, nowMs: s.dueAtMs);
      expect(s.intervalDays, 8); // (3 * 2.5).round() = 8 (half away from zero)
      expect(s.reps, 3);
      expect(s.ef, 2.5); // correct answers never change EF
    });

    test('interval caps at 180 days', () {
      const big = SchedState(
        ef: 2.5,
        reps: 9,
        lapses: 0,
        intervalDays: 100,
        dueAtMs: t0,
      );
      final s = applyAnswer(big, correct: true, nowMs: t0);
      expect(s.intervalDays, 180);
      expect(s.dueAtMs, t0 + 180 * msPerDay);
    });

    test('dueAt arithmetic: now + interval × 86400000', () {
      var s = initialSched(t0);
      for (var i = 0; i < 5; i++) {
        final now = t0 + i * 12345;
        s = applyAnswer(s, correct: true, nowMs: now);
        expect(s.dueAtMs, now + s.intervalDays * msPerDay);
      }
    });
  });

  group('applyAnswer miss', () {
    test('miss → 1 day, reps reset to 0, lapses + 1', () {
      var s = initialSched(t0);
      s = applyAnswer(s, correct: true, nowMs: t0);
      s = applyAnswer(s, correct: true, nowMs: s.dueAtMs);
      final m = applyAnswer(s, correct: false, nowMs: s.dueAtMs);
      expect(m.intervalDays, 1);
      expect(m.reps, 0);
      expect(m.lapses, 1);
      expect(m.dueAtMs, s.dueAtMs + msPerDay);
    });

    test('first lapse keeps EF 2.5', () {
      final m = applyAnswer(initialSched(t0), correct: false, nowMs: t0);
      expect(m.ef, 2.5);
      expect(m.lapses, 1);
    });

    test('second lapse cuts EF to 2.3', () {
      var s = applyAnswer(initialSched(t0), correct: false, nowMs: t0);
      s = applyAnswer(s, correct: false, nowMs: s.dueAtMs);
      expect(s.lapses, 2);
      expect(s.ef, closeTo(2.3, 1e-9));
    });

    test('EF floors at 1.3 after many lapses', () {
      var s = initialSched(t0);
      for (var i = 0; i < 30; i++) {
        s = applyAnswer(s, correct: false, nowMs: s.dueAtMs);
      }
      expect(s.ef, 1.3);
      expect(s.lapses, 30);
    });
  });

  group('scheduler properties (glados)', () {
    glados.Glados<List<bool>>(
      glados.any.listWithLengthInRange(0, 40, glados.any.bool),
    ).test('ef/interval bounds + dueAt arithmetic on random sequences', (
      answers,
    ) {
      var s = initialSched(t0);
      var now = t0;
      for (final correct in answers) {
        s = applyAnswer(s, correct: correct, nowMs: now);
        expect(
          s.ef,
          inInclusiveRange(1.3, 2.5),
          reason: 'ef out of range after an answer',
        );
        expect(
          s.intervalDays,
          inInclusiveRange(1, 180),
          reason: 'interval out of range after ≥1 answer',
        );
        expect(s.dueAtMs, now + s.intervalDays * msPerDay);
        now = s.dueAtMs;
      }
    });

    glados.Glados<List<bool>>(
      glados.any.listWithLengthInRange(0, 20, glados.any.bool),
    ).test('from any reached state, correct-interval ≥ miss-interval', (
      answers,
    ) {
      var s = initialSched(t0);
      for (final correct in answers) {
        final c = applyAnswer(s, correct: true, nowMs: t0);
        final m = applyAnswer(s, correct: false, nowMs: t0);
        expect(c.intervalDays, greaterThanOrEqualTo(m.intervalDays));
        s = applyAnswer(s, correct: correct, nowMs: s.dueAtMs);
      }
    });

    test('from the same state, correct-interval ≥ miss-interval', () {
      // Exhaustive over reachable states from short sequences:
      // for every prefix state, a correct answer never schedules
      // sooner than a miss from that same state (miss is always
      // 1 day, correct is always ≥ 1 day).
      var states = <SchedState>[initialSched(t0)];
      for (var depth = 0; depth < 6; depth++) {
        final next = <SchedState>[];
        for (final s in states) {
          final c = applyAnswer(s, correct: true, nowMs: t0);
          final m = applyAnswer(s, correct: false, nowMs: t0);
          expect(c.intervalDays, greaterThanOrEqualTo(m.intervalDays));
          expect(m.intervalDays, 1);
          next
            ..add(c)
            ..add(m);
        }
        states = next;
      }
    });
  });
}

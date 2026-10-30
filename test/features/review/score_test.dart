// REVIEW — Done Score formula v1 (§R5.2): named boundary cases
// plus glados property tests (TESTING.md §9/S3: score is monotonic
// in completed items, clamped to range, empty-plan rule = 60).
import 'package:daily_life_app/features/review/score.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' as glados;

void main() {
  group('DoneScore named cases', () {
    test('formula version is pinned at 1', () {
      expect(DoneScore.formulaVersion, 1);
    });

    test('empty plan + closed day = 60 (maintenance day)', () {
      // Literal 60 on purpose: asserting against the constant
      // itself would be a tautology (mutation spot-check finding).
      expect(DoneScore.compute(itemDone: const [], dayClosed: true), 60);
    });

    test('empty plan + not closed = null (nothing to score)', () {
      expect(DoneScore.compute(itemDone: const [], dayClosed: false), isNull);
    });

    test('empty plan + learning block = 100 even unclosed', () {
      expect(
        DoneScore.compute(
            itemDone: const [], learningSessionDone: true, dayClosed: false),
        100,
      );
    });

    test('half of 4 items = 50', () {
      expect(
        DoneScore.compute(
            itemDone: const [true, true, false, false], dayClosed: true),
        50,
      );
    });

    test('single item: done = 100, not done = 0', () {
      expect(DoneScore.compute(itemDone: const [true], dayClosed: true), 100);
      expect(DoneScore.compute(itemDone: const [false], dayClosed: true), 0);
    });

    test('>8-item cap: all 10 done = 100', () {
      expect(
        DoneScore.compute(
            itemDone: List.filled(10, true), dayClosed: true),
        100,
      );
    });

    test('>8-item cap: first 8 of 10 done = 89 (overflow weighs ½)', () {
      // total = 8×1 + 2×0.5 = 9; done = 8 → 88.9 → 89.
      expect(
        DoneScore.compute(
          itemDone: const [
            true, true, true, true, true, true, true, true, false, false,
          ],
          dayClosed: true,
        ),
        89,
      );
    });

    test('>8-item cap: only the two overflow items done = 11', () {
      // done = 2×0.5 = 1 of 9 → 11.1 → 11.
      expect(
        DoneScore.compute(
          itemDone: const [
            false, false, false, false, false, false, false, false,
            true, true,
          ],
          dayClosed: true,
        ),
        11,
      );
    });

    test('learning block adds weight 2 to both sides: 2/4 + block = 67', () {
      // (2 + 2) / (4 + 2) = 66.7 → 67.
      expect(
        DoneScore.compute(
          itemDone: const [true, true, false, false],
          learningSessionDone: true,
          dayClosed: true,
        ),
        67,
      );
    });
  });

  group('DoneScore properties (glados)', () {
    glados.Glados2<List<bool>, bool>(
      glados.any.listWithLengthInRange(0, 21, glados.any.bool),
      glados.any.bool,
    ).test('score is in range, monotonic, and 100 when all done',
        (items, learning) {
      final score = DoneScore.compute(
        itemDone: items,
        learningSessionDone: learning,
        dayClosed: true,
      );
      // Always scorable when the day is closed, and always in range.
      expect(score, isNotNull);
      expect(score, inInclusiveRange(0, 100));

      // Monotonicity: ticking one more item never lowers the score.
      for (var i = 0; i < items.length; i++) {
        if (items[i]) continue;
        final flipped = [...items]..[i] = true;
        final after = DoneScore.compute(
          itemDone: flipped,
          learningSessionDone: learning,
          dayClosed: true,
        )!;
        expect(after, greaterThanOrEqualTo(score!),
            reason: 'ticking item $i lowered the score');
      }

      // Everything done = 100 (when there is anything to score).
      if (items.isNotEmpty || learning) {
        expect(
          DoneScore.compute(
            itemDone: List.filled(items.length, true),
            learningSessionDone: learning,
            dayClosed: true,
          ),
          100,
        );
      }
    });
  });
}

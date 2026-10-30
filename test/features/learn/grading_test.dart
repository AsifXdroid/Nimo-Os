// LEARN engine — pure graders (S5 step C2a, §R4.1): every type's
// true/false cases, with the image-point aspect math pinned in
// both orientations (r is a fraction of the SHORTER side).
import 'package:daily_life_app/features/learn/grading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gradeMcq', () {
    const payload = <String, Object?>{
      'prompt': 'p',
      'choices': [
        {'id': 'a', 'text': 'A'},
        {'id': 'b', 'text': 'B'},
      ],
      'correctChoiceIds': ['b'],
    };

    test('correct choice grades true', () {
      expect(gradeMcq(payload, 'b'), isTrue);
    });

    test('wrong choice grades false', () {
      expect(gradeMcq(payload, 'a'), isFalse);
    });
  });

  group('gradeMythFact', () {
    const factPayload = <String, Object?>{
      'statement': 's',
      'isFact': true,
      'explanation': 'e',
    };
    const mythPayload = <String, Object?>{
      'statement': 's',
      'isFact': false,
      'explanation': 'e',
    };

    test('fact statement + FACT tap → true', () {
      expect(gradeMythFact(factPayload, true), isTrue);
    });

    test('fact statement + MYTH tap → false', () {
      expect(gradeMythFact(factPayload, false), isFalse);
    });

    test('myth statement + MYTH tap → true', () {
      expect(gradeMythFact(mythPayload, false), isTrue);
    });
  });

  group('gradeOrdering', () {
    const payload = <String, Object?>{
      'prompt': 'p',
      'items': [
        {'id': 'i1', 'text': 'one'},
        {'id': 'i2', 'text': 'two'},
        {'id': 'i3', 'text': 'three'},
      ],
      'correctOrder': ['i1', 'i2', 'i3'],
    };

    test('exact correct order → true', () {
      expect(gradeOrdering(payload, ['i1', 'i2', 'i3']), isTrue);
    });

    test('permuted order → false', () {
      expect(gradeOrdering(payload, ['i2', 'i1', 'i3']), isFalse);
    });

    test('incomplete order → false', () {
      expect(gradeOrdering(payload, ['i1', 'i2']), isFalse);
    });
  });

  group('gradeImagePoint', () {
    // Target dead centre, r = 0.2 of the shorter side.
    const payload = <String, Object?>{
      'prompt': 'tap',
      'image': 'm1',
      'target': {'cx': 0.5, 'cy': 0.5, 'r': 0.2},
    };

    test('centre hit (square image)', () {
      expect(
        gradeImagePoint(payload, tapX: 0.5, tapY: 0.5, aspect: 1.0),
        isTrue,
      );
    });

    test('edge hit at exactly r (square image)', () {
      expect(
        gradeImagePoint(payload, tapX: 0.7, tapY: 0.5, aspect: 1.0),
        isTrue,
      );
    });

    test('miss beyond r (square image)', () {
      expect(
        gradeImagePoint(payload, tapX: 0.75, tapY: 0.5, aspect: 1.0),
        isFalse,
      );
    });

    test('wide image (aspect 2.0): x offset counts double, y does not', () {
      // +0.2 in x = 0.4 shorter-side units → misses r 0.2 …
      expect(
        gradeImagePoint(payload, tapX: 0.7, tapY: 0.5, aspect: 2.0),
        isFalse,
      );
      // … while the same +0.2 offset in y is 0.2 units → hits.
      expect(
        gradeImagePoint(payload, tapX: 0.5, tapY: 0.7, aspect: 2.0),
        isTrue,
      );
    });

    test('tall image (aspect 0.5): y offset counts double, x does not', () {
      // +0.2 in y = 0.4 shorter-side units → misses r 0.2 …
      expect(
        gradeImagePoint(payload, tapX: 0.5, tapY: 0.7, aspect: 0.5),
        isFalse,
      );
      // … while the same +0.2 offset in x is 0.2 units → hits.
      expect(
        gradeImagePoint(payload, tapX: 0.7, tapY: 0.5, aspect: 0.5),
        isTrue,
      );
    });

    test('acceptable point hit (target missed, alternate accepted)', () {
      const withAlt = <String, Object?>{
        'prompt': 'tap',
        'image': 'm1',
        'target': {'cx': 0.5, 'cy': 0.5, 'r': 0.2},
        'acceptablePoints': [
          {'cx': 0.1, 'cy': 0.1},
        ],
      };
      expect(
        gradeImagePoint(withAlt, tapX: 0.12, tapY: 0.08, aspect: 1.0),
        isTrue,
      );
      // And a tap near neither point still misses.
      expect(
        gradeImagePoint(withAlt, tapX: 0.9, tapY: 0.9, aspect: 1.0),
        isFalse,
      );
    });

    test('imageTarget parses the payload target', () {
      final t = imageTarget(payload);
      expect(t.cx, 0.5);
      expect(t.cy, 0.5);
      expect(t.r, 0.2);
    });
  });

  group('scenarioPassed', () {
    test('all scored choices non-zero → true', () {
      expect(scenarioPassed([1, null, 1]), isTrue);
    });

    test('any zero score → false', () {
      expect(scenarioPassed([1, 0]), isFalse);
    });

    test('no choices scored → true (absent score is neutral)', () {
      expect(scenarioPassed([]), isTrue);
      expect(scenarioPassed([null, null]), isTrue);
    });
  });
}

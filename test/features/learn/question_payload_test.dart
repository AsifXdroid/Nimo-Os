// LEARN engine — payload validation (§R4.1/§R4.4/§R4B): one
// valid payload per type, and every stated invalid rule failing.
import 'package:daily_life_app/features/learn/question.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _mcq() => {
  'prompt': 'What is 2+2?',
  'choices': [
    {'id': 'a', 'text': '3'},
    {'id': 'b', 'text': '4'},
    {'id': 'c', 'text': '5'},
  ],
  'correctChoiceIds': ['b'],
};

Map<String, Object?> _scenario() => {
  'startNode': 'start',
  'nodes': {
    'start': {
      'text': 'You find a locked door.',
      'choices': [
        {'text': 'Knock', 'next': 'door', 'feedback': 'Someone answers.'},
        {'text': 'Walk away', 'next': 'end'},
      ],
    },
    'door': {
      'text': 'It opens.',
      'choices': [
        {'text': 'Enter', 'next': 'end', 'score': 2},
      ],
    },
    'end': {'end': true, 'text': 'Done.', 'summary': 'You finished.'},
  },
};

void main() {
  group('valid payloads (one per type)', () {
    final valid = <String, Object?>{
      'mcq': _mcq(),
      'flashcard': {'front': 'hola', 'back': 'hello'},
      'cloze': {'text': 'The capital of France is {{Paris}}.'},
      'image_point': {
        'prompt': 'Tap the heart',
        'image': 'media-1',
        'target': {'cx': 0.5, 'cy': 0.4, 'r': 0.1},
        'acceptablePoints': [
          {'cx': 0.48, 'cy': 0.42},
        ],
      },
      'ordering': {
        'prompt': 'Order the steps',
        'items': [
          {'id': '1', 'text': 'First'},
          {'id': '2', 'text': 'Second'},
          {'id': '3', 'text': 'Third'},
        ],
        'correctOrder': ['1', '2', '3'],
      },
      'scenario': _scenario(),
      'mythfact': {
        'statement': 'The sky is blue.',
        'isFact': true,
        'explanation': 'Rayleigh scattering.',
      },
    };
    for (final e in valid.entries) {
      test('${e.key} valid payload has no issues', () {
        expect(validatePayload(e.key, e.value), isEmpty);
      });
    }

    test('all declared types are known; unknown type is not', () {
      for (final t in questionTypes) {
        expect(isKnownType(t), isTrue, reason: t);
      }
      expect(isKnownType('essay'), isFalse);
      expect(validatePayload('essay', const {}), isNotEmpty);
    });

    test('non-object payloads are invalid', () {
      expect(validatePayload('mcq', null), isNotEmpty);
      expect(validatePayload('mcq', 'text'), isNotEmpty);
      expect(validatePayload('mcq', const [1, 2]), isNotEmpty);
    });

    test('scenario with an escapable cycle is valid', () {
      final p = _scenario();
      // door can loop back to start, but start can still reach end.
      (p['nodes'] as Map)['door'] = {
        'text': 'It opens.',
        'choices': [
          {'text': 'Back', 'next': 'start'},
          {'text': 'Enter', 'next': 'end'},
        ],
      };
      expect(validatePayload('scenario', p), isEmpty);
    });

    test('scenario: start branches to an end AND to a reachable '
        'exit-less cycle → the cycle nodes cannot reach an end '
        '(S7 killing test)', () {
      // Every node is reachable from start and an end node
      // exists and is reachable — the ONLY defect in this graph
      // is that c1/c2 cannot reach an end. (The older endless-
      // cycle case also trips reachability issues, so it cannot
      // kill a mutant that suppresses this specific check.)
      final p = <String, Object?>{
        'startNode': 's',
        'nodes': {
          's': {
            'text': 'Start.',
            'choices': [
              {'text': 'Finish', 'next': 'end'},
              {'text': 'Wander', 'next': 'c1'},
            ],
          },
          'c1': {
            'text': 'Cycle A.',
            'choices': [
              {'text': 'On', 'next': 'c2'},
            ],
          },
          'c2': {
            'text': 'Cycle B.',
            'choices': [
              {'text': 'Back', 'next': 'c1'},
            ],
          },
          'end': {'end': true, 'text': 'Done.', 'summary': 'Finished.'},
        },
      };
      final issues = validatePayload('scenario', p);
      expect(issues, contains('scenario node "c1" cannot reach an end node'));
      expect(issues, contains('scenario node "c2" cannot reach an end node'));
      expect(issues.length, 2, reason: 'no other defect exists: $issues');
    });

    test('scenario: node-count issue returns immediately, with '
        'no further graph-walk issues (S6)', () {
      // 6 nodes, EVERY one of them individually defective (end
      // nodes without summaries): if validation kept walking
      // after the count issue, their issues would pile up here.
      final p = <String, Object?>{
        'startNode': 'n0',
        'nodes': {
          for (var i = 0; i < 6; i++) 'n$i': {'end': true, 'text': 'x'},
        },
      };
      expect(validatePayload('scenario', p), [
        'scenario must have 2–5 nodes (capped branching)',
      ]);
    });
  });

  group('invalid payloads', () {
    // (type, payload-builder, why) — each must produce ≥1 issue.
    final cases = <(String, Map<String, Object?> Function(), String)>[
      ('mcq', () => _mcq()..['prompt'] = '  ', 'empty prompt'),
      (
        'mcq',
        () => _mcq()
          ..['choices'] = [
            _mcq()['choices'] is List ? ({'id': 'a', 'text': 'x'}) : null,
          ],
        'only 1 choice',
      ),
      (
        'mcq',
        () => _mcq()
          ..['choices'] = List.generate(6, (i) => {'id': 'c$i', 'text': 't$i'}),
        '6 choices',
      ),
      (
        'mcq',
        () => _mcq()
          ..['choices'] = [
            {'id': 'a', 'text': 'x'},
            {'id': 'a', 'text': 'y'},
          ],
        'duplicate choice ids',
      ),
      (
        'mcq',
        () => _mcq()
          ..['choices'] = [
            {'id': '', 'text': 'x'},
            {'id': 'b', 'text': 'y'},
          ],
        'empty choice id',
      ),
      (
        'mcq',
        () => _mcq()
          ..['choices'] = [
            {'id': 'a', 'text': ''},
            {'id': 'b', 'text': 'y'},
          ],
        'empty choice text',
      ),
      (
        'mcq',
        () => _mcq()..['correctChoiceIds'] = ['a', 'b'],
        'two correct ids',
      ),
      (
        'mcq',
        () => _mcq()..['correctChoiceIds'] = <String>[],
        'zero correct ids',
      ),
      (
        'mcq',
        () => _mcq()..['correctChoiceIds'] = ['zz'],
        'correct id does not exist',
      ),
      ('mcq', () => _mcq()..['shuffle'] = 'yes', 'shuffle not bool'),
      ('mcq', () => _mcq()..['explanation'] = 42, 'explanation not string'),
      ('flashcard', () => {'front': '', 'back': 'x'}, 'empty front'),
      ('flashcard', () => {'front': 'x'}, 'missing back'),
      ('cloze', () => {'text': 'No blanks here.'}, 'no span'),
      ('cloze', () => {'text': 'Blank {{}} here.'}, 'empty span'),
      ('cloze', () => {'text': 'Unclosed {{answer here.'}, 'unbalanced open'),
      ('cloze', () => {'text': 'Stray }} close.'}, 'unbalanced close'),
      (
        'image_point',
        () => {
          'prompt': '',
          'image': 'm',
          'target': {'cx': 0.5, 'cy': 0.5, 'r': 0.1},
        },
        'empty prompt',
      ),
      (
        'image_point',
        () => {
          'prompt': 'p',
          'image': '',
          'target': {'cx': 0.5, 'cy': 0.5, 'r': 0.1},
        },
        'empty image',
      ),
      (
        'image_point',
        () => {
          'prompt': 'p',
          'image': 'm',
          'target': {'cx': 1.2, 'cy': 0.5, 'r': 0.1},
        },
        'cx > 1',
      ),
      (
        'image_point',
        () => {
          'prompt': 'p',
          'image': 'm',
          'target': {'cx': 0.5, 'cy': -0.1, 'r': 0.1},
        },
        'cy < 0',
      ),
      (
        'image_point',
        () => {
          'prompt': 'p',
          'image': 'm',
          'target': {'cx': 0.5, 'cy': 0.5, 'r': 0.02},
        },
        'r too small',
      ),
      (
        'image_point',
        () => {
          'prompt': 'p',
          'image': 'm',
          'target': {'cx': 0.5, 'cy': 0.5, 'r': 0.3},
        },
        'r too large',
      ),
      (
        'image_point',
        () => {
          'prompt': 'p',
          'image': 'm',
          'target': {'cx': 0.5, 'cy': 0.5, 'r': 0.1},
          'acceptablePoints': [
            {'cx': 2.0, 'cy': 0.5},
          ],
        },
        'acceptable point out of range',
      ),
      (
        'ordering',
        () => {
          'prompt': '',
          'items': [
            {'id': '1', 'text': 'a'},
            {'id': '2', 'text': 'b'},
          ],
          'correctOrder': ['1', '2'],
        },
        'empty prompt',
      ),
      (
        'ordering',
        () => {
          'prompt': 'p',
          'items': [
            {'id': '1', 'text': 'a'},
          ],
          'correctOrder': ['1'],
        },
        'only 1 item',
      ),
      (
        'ordering',
        () => {
          'prompt': 'p',
          'items': List.generate(9, (i) => {'id': '$i', 'text': 't$i'}),
          'correctOrder': List.generate(9, (i) => '$i'),
        },
        '9 items',
      ),
      (
        'ordering',
        () => {
          'prompt': 'p',
          'items': [
            {'id': '1', 'text': 'a'},
            {'id': '1', 'text': 'b'},
          ],
          'correctOrder': ['1', '1'],
        },
        'duplicate item ids',
      ),
      (
        'ordering',
        () => {
          'prompt': 'p',
          'items': [
            {'id': '1', 'text': 'a'},
            {'id': '2', 'text': 'b'},
          ],
          'correctOrder': ['1', '3'],
        },
        'correctOrder not a permutation',
      ),
      (
        'ordering',
        () => {
          'prompt': 'p',
          'items': [
            {'id': '1', 'text': 'a'},
            {'id': '2', 'text': 'b'},
          ],
          'correctOrder': ['1'],
        },
        'correctOrder too short',
      ),
      (
        'scenario',
        () => _scenario()..['startNode'] = 'nope',
        'startNode missing',
      ),
      (
        'scenario',
        () => _scenario()
          ..['nodes'] = {
            'only': {'end': true, 'text': 'x', 'summary': 's'},
          },
        'only 1 node',
      ),
      (
        'scenario',
        () => _scenario()
          ..['nodes'] = {
            for (var i = 0; i < 6; i++)
              'n$i': {'end': true, 'text': 'x', 'summary': 's'},
          },
        '6 nodes',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          (p['nodes'] as Map)['start'] = {
            'text': '',
            'choices': [
              {'text': 'go', 'next': 'end'},
            ],
          };
          return p;
        },
        'empty node text',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          (p['nodes'] as Map)['end'] = {'end': true, 'text': 'Done.'};
          return p;
        },
        'end node without summary',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          (p['nodes'] as Map)['end'] = {
            'end': true,
            'text': 'Done.',
            'summary': 's',
            'choices': [
              {'text': 'x', 'next': 'start'},
            ],
          };
          return p;
        },
        'end node with choices',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          (p['nodes'] as Map)['start'] = {'text': 't', 'choices': <Object?>[]};
          return p;
        },
        'non-end node with 0 choices',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          (p['nodes'] as Map)['start'] = {
            'text': 't',
            'choices': List.generate(4, (_) => {'text': 'x', 'next': 'end'}),
          };
          return p;
        },
        'non-end node with 4 choices',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          (p['nodes'] as Map)['start'] = {
            'text': 't',
            'choices': [
              {'text': '', 'next': 'end'},
            ],
          };
          return p;
        },
        'empty choice text',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          (p['nodes'] as Map)['start'] = {
            'text': 't',
            'choices': [
              {'text': 'x', 'next': 'ghost'},
            ],
          };
          return p;
        },
        'choice next names no node',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          // 'door' becomes unreachable.
          (p['nodes'] as Map)['start'] = {
            'text': 't',
            'choices': [
              {'text': 'x', 'next': 'end'},
            ],
          };
          return p;
        },
        'unreachable node',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          // start <-> door cycle with no path to end from them.
          (p['nodes'] as Map)['start'] = {
            'text': 't',
            'choices': [
              {'text': 'x', 'next': 'door'},
            ],
          };
          (p['nodes'] as Map)['door'] = {
            'text': 't',
            'choices': [
              {'text': 'x', 'next': 'start'},
            ],
          };
          return p;
        },
        'endless cycle (end unreachable from a node)',
      ),
      (
        'scenario',
        () {
          final p = _scenario();
          (p['nodes'] as Map)['end'] = {
            'text': 't',
            'choices': [
              {'text': 'x', 'next': 'start'},
            ],
          };
          return p;
        },
        'no end node',
      ),
      (
        'mythfact',
        () => {'statement': '', 'isFact': true, 'explanation': 'e'},
        'empty statement',
      ),
      (
        'mythfact',
        () => {'statement': 's', 'isFact': 'yes', 'explanation': 'e'},
        'isFact not bool',
      ),
      (
        'mythfact',
        () => {'statement': 's', 'isFact': false, 'explanation': ' '},
        'empty explanation',
      ),
    ];
    for (final (type, build, why) in cases) {
      test('$type invalid: $why', () {
        expect(validatePayload(type, build()), isNotEmpty, reason: why);
      });
    }
  });

  group('validateDifficulty', () {
    test('absent (null) and 1–5 ints are valid', () {
      expect(validateDifficulty(null), isEmpty);
      for (final d in [1, 2, 3, 4, 5]) {
        expect(validateDifficulty(d), isEmpty, reason: '$d');
      }
    });
    test('out-of-range and non-int are invalid', () {
      expect(validateDifficulty(0), isNotEmpty);
      expect(validateDifficulty(6), isNotEmpty);
      expect(validateDifficulty('3'), isNotEmpty);
      expect(validateDifficulty(3.5), isNotEmpty);
    });
    test('a payload carrying a bad difficulty is invalid', () {
      final p = _mcq()..['difficulty'] = 9;
      expect(validatePayload('mcq', p), isNotEmpty);
    });
  });
}

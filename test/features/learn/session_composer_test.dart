// LEARN engine — SessionComposer (S5 step C1): quota arithmetic,
// ordering (warm-up / interleaved middle / hardest last), the
// per-type format cap, boss ordering, small/empty pools, and
// determinism under a seeded Random. Pure — questions are built
// in memory, no DB.
import 'dart:math';

import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/learn/session_composer.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseMs = 1700000000000;

LearnQuestion q({
  required int id,
  int topicId = 1,
  String type = 'mcq',
  int difficulty = 3,
  int lapses = 0,
  int reps = 0,
  int dueOffset = 0,
  int createdOffset = 0,
}) => LearnQuestion(
  id: id,
  topicId: topicId,
  type: type,
  payload: const {},
  difficulty: difficulty,
  ef: 2.5,
  reps: reps,
  lapses: lapses,
  intervalDays: 0,
  dueAt: _baseMs + dueOffset,
  suspended: false,
  createdAt: _baseMs + createdOffset,
  updatedAt: _baseMs,
);

void main() {
  group('SessionKind', () {
    test('dbValue / fromDb round-trip', () {
      for (final kind in SessionKind.values) {
        expect(SessionKind.fromDb(kind.dbValue), kind);
      }
      expect(SessionKind.episode.dbValue, 'episode');
      expect(SessionKind.review.dbValue, 'review');
      expect(SessionKind.boss.dbValue, 'boss');
    });
  });

  group('compose (episode/review)', () {
    test('quotas: 40 due (10 missed) + 20 fresh → 16 cards, '
        '≈55% regular due, missed + fresh represented, no dupes', () {
      const types = ['mcq', 'flashcard', 'cloze', 'mythfact'];
      final due = [
        for (var i = 0; i < 40; i++)
          q(
            id: i + 1,
            topicId: (i % 5) + 1,
            type: types[i % 4],
            difficulty: (i % 5) + 1,
            lapses: i < 10 ? 1 : 0,
            reps: i < 10 ? 0 : 2,
            dueOffset: i * 1000,
          ),
      ];
      final fresh = [
        for (var i = 0; i < 20; i++)
          q(
            id: 101 + i,
            topicId: (i % 5) + 1,
            type: types[i % 4],
            difficulty: (i % 5) + 1,
            createdOffset: i * 1000,
          ),
      ];
      final session = SessionComposer.compose(
        due: due,
        fresh: fresh,
        kind: SessionKind.episode,
        random: Random(7),
      );
      expect(session.length, 16);
      expect(session.map((e) => e.id).toSet().length, 16); // no dupes
      final missed = session.where((e) => e.lapses > 0).length;
      final regularDue = session
          .where((e) => e.id <= 40 && e.lapses == 0)
          .length;
      final freshPicked = session.where((e) => e.id > 100).length;
      // Implemented arithmetic for target 16: missed quota
      // round(0.20×16)=3, fresh quota round(0.25×16)=4, due quota
      // 16−3−4=9 (56% ≈ 55%).
      expect(missed, 3);
      expect(regularDue, 9);
      expect(regularDue, inInclusiveRange(8, 10)); // 55% ± 1 card
      expect(freshPicked, 4);
    });

    test('interleave: no 3 consecutive cards share a type or a topic '
        'on a mixed pool', () {
      const types = ['mcq', 'flashcard', 'cloze', 'mythfact'];
      final due = [
        for (var i = 0; i < 24; i++)
          q(
            id: i + 1,
            topicId: (i % 3) + 1,
            type: types[i % 4],
            difficulty: (i % 5) + 1,
            reps: 2,
            dueOffset: i * 1000,
          ),
      ];
      final fresh = [
        for (var i = 0; i < 12; i++)
          q(
            id: 101 + i,
            topicId: (i % 3) + 1,
            type: types[(i + 1) % 4],
            difficulty: (i % 5) + 1,
            createdOffset: i * 1000,
          ),
      ];
      final session = SessionComposer.compose(
        due: due,
        fresh: fresh,
        kind: SessionKind.review,
        random: Random(3),
      );
      expect(session.length, 16);
      for (var i = 0; i + 2 < session.length; i++) {
        final a = session[i], b = session[i + 1], c = session[i + 2];
        expect(
          a.type == b.type && b.type == c.type,
          isFalse,
          reason: 'type triple at $i: ${session.map((e) => e.type)}',
        );
        expect(
          a.topicId == b.topicId && b.topicId == c.topicId,
          isFalse,
          reason: 'topic triple at $i',
        );
      }
    });

    test('warm-up: the 2 lowest-difficulty due picks come first', () {
      // First 6 by dueAt are the ones selected (no fresh/missed);
      // difficulties in due order: 3, 1, 2, 5, 4, 3.
      const diffs = [3, 1, 2, 5, 4, 3, 3, 3, 3, 3];
      const types = [
        'mcq',
        'flashcard',
        'cloze',
        'mythfact',
        'ordering',
        'mcq',
        'mcq',
        'mcq',
        'mcq',
        'mcq',
      ];
      final due = [
        for (var i = 0; i < 10; i++)
          q(
            id: i + 1,
            topicId: i + 1,
            type: types[i],
            difficulty: diffs[i],
            reps: 1,
            dueOffset: i * 1000,
          ),
      ];
      final session = SessionComposer.compose(
        due: due,
        fresh: const [],
        kind: SessionKind.episode,
        target: 6,
        random: Random(1),
      );
      expect(session.length, 6);
      expect(session[0].id, 2); // difficulty 1
      expect(session[1].id, 3); // difficulty 2
    });

    test('the 2 hardest picks go last, hardest final', () {
      const diffs = [3, 1, 2, 5, 4, 3, 3, 3, 3, 3];
      const types = [
        'mcq',
        'flashcard',
        'cloze',
        'mythfact',
        'ordering',
        'mcq',
        'mcq',
        'mcq',
        'mcq',
        'mcq',
      ];
      final due = [
        for (var i = 0; i < 10; i++)
          q(
            id: i + 1,
            topicId: i + 1,
            type: types[i],
            difficulty: diffs[i],
            reps: 1,
            dueOffset: i * 1000,
          ),
      ];
      final session = SessionComposer.compose(
        due: due,
        fresh: const [],
        kind: SessionKind.episode,
        target: 6,
        random: Random(1),
      );
      expect(session[4].id, 5); // difficulty 4
      expect(session[5].id, 4); // difficulty 5 — final card
    });

    test('format cap: a 60%-mcq pool still yields mcq ≤ 40% + 1 '
        'when alternatives suffice', () {
      final due = <LearnQuestion>[];
      var id = 0;
      // 18 mcq first by dueAt, then 6 flashcard + 6 cloze.
      for (var i = 0; i < 18; i++) {
        due.add(
          q(
            id: ++id,
            topicId: (i % 4) + 1,
            type: 'mcq',
            difficulty: (i % 5) + 1,
            reps: 1,
            dueOffset: i * 1000,
          ),
        );
      }
      for (var i = 0; i < 6; i++) {
        due.add(
          q(
            id: ++id,
            topicId: (i % 4) + 1,
            type: 'flashcard',
            difficulty: (i % 5) + 1,
            reps: 1,
            dueOffset: (18 + i) * 1000,
          ),
        );
        due.add(
          q(
            id: ++id,
            topicId: (i % 4) + 1,
            type: 'cloze',
            difficulty: (i % 5) + 1,
            reps: 1,
            dueOffset: (24 + i) * 1000,
          ),
        );
      }
      final session = SessionComposer.compose(
        due: due,
        fresh: const [],
        kind: SessionKind.episode,
        random: Random(5),
      );
      expect(session.length, 16);
      final mcq = session.where((e) => e.type == 'mcq').length;
      expect(mcq, lessThanOrEqualTo(7)); // ceil(0.40 × 16) = 40% + 1
    });

    test('small pool: 3 questions → the whole pool, ordered', () {
      final due = [
        q(id: 1, type: 'mcq', difficulty: 2, reps: 1, dueOffset: 0),
        q(id: 2, type: 'mcq', difficulty: 4, reps: 1, dueOffset: 1000),
      ];
      final fresh = [q(id: 3, type: 'mcq', difficulty: 3)];
      final session = SessionComposer.compose(
        due: due,
        fresh: fresh,
        kind: SessionKind.episode,
        random: Random(9),
      );
      expect(session.length, 3);
      expect(session.map((e) => e.id).toSet(), {1, 2, 3});
    });

    test('empty pool → empty session', () {
      expect(
        SessionComposer.compose(
          due: const [],
          fresh: const [],
          kind: SessionKind.episode,
        ),
        isEmpty,
      );
      expect(
        SessionComposer.compose(
          due: const [],
          fresh: const [],
          kind: SessionKind.boss,
        ),
        isEmpty,
      );
    });

    test('repair pass: a [mcq, mcq] hardest tail landing after '
        'an mcq middle card emits no triple (S10)', () {
      // The reviewer's scenario, probed against the pre-fix
      // composer: warm-up = ids 1–2 (easiest due), tail = ids
      // 4–5 (hardest, both mcq), and with Random(0) the middle
      // came out [mythfact, mcq] — so the old _order emitted
      // …mythfact, mcq(6), mcq(4), mcq(5): three mcq in a row
      // across the middle→tail boundary, which the old
      // tail-swap check could not fix (both tail cards are mcq).
      // Topics are all distinct so only the type axis can triple.
      final due = [
        q(
          id: 1,
          topicId: 1,
          type: 'flashcard',
          difficulty: 1,
          reps: 1,
          dueOffset: 0,
        ),
        q(
          id: 2,
          topicId: 2,
          type: 'cloze',
          difficulty: 2,
          reps: 1,
          dueOffset: 1000,
        ),
        q(
          id: 3,
          topicId: 3,
          type: 'mythfact',
          difficulty: 3,
          reps: 1,
          dueOffset: 2000,
        ),
        q(
          id: 4,
          topicId: 4,
          type: 'mcq',
          difficulty: 5,
          reps: 1,
          dueOffset: 3000,
        ),
        q(
          id: 5,
          topicId: 5,
          type: 'mcq',
          difficulty: 5,
          reps: 1,
          dueOffset: 4000,
        ),
        q(
          id: 6,
          topicId: 6,
          type: 'mcq',
          difficulty: 4,
          reps: 1,
          dueOffset: 5000,
        ),
      ];
      final session = SessionComposer.compose(
        due: due,
        fresh: const [],
        kind: SessionKind.episode,
        target: 6,
        random: Random(0),
      );
      expect(session.length, 6);
      expect(session.map((e) => e.id).toSet(), {1, 2, 3, 4, 5, 6});
      for (var i = 0; i + 2 < session.length; i++) {
        final a = session[i], b = session[i + 1], c = session[i + 2];
        expect(
          a.type == b.type && b.type == c.type,
          isFalse,
          reason: 'type triple at $i: ${session.map((e) => e.type)}',
        );
        expect(
          a.topicId == b.topicId && b.topicId == c.topicId,
          isFalse,
          reason: 'topic triple at $i',
        );
      }
    });

    test('deterministic given a seeded Random', () {
      const types = ['mcq', 'flashcard', 'cloze', 'mythfact', 'ordering'];
      List<LearnQuestion> pool(int start, int n, {required bool isDue}) => [
        for (var i = 0; i < n; i++)
          q(
            id: start + i,
            topicId: (i % 4) + 1,
            type: types[i % 5],
            difficulty: (i % 5) + 1,
            reps: isDue ? 2 : 0,
            dueOffset: i * 1000,
            createdOffset: i * 1000,
          ),
      ];
      final a = SessionComposer.compose(
        due: pool(1, 30, isDue: true),
        fresh: pool(101, 15, isDue: false),
        kind: SessionKind.episode,
        random: Random(42),
      );
      final b = SessionComposer.compose(
        due: pool(1, 30, isDue: true),
        fresh: pool(101, 15, isDue: false),
        kind: SessionKind.episode,
        random: Random(42),
      );
      expect(a.map((e) => e.id).toList(), b.map((e) => e.id).toList());
    });
  });

  group('compose (boss)', () {
    test('pool sorted by difficulty DESC, dueAt ASC; target respected; '
        'format cap exempt', () {
      final due = [
        q(id: 1, difficulty: 2, reps: 1, dueOffset: 0),
        q(id: 2, difficulty: 5, reps: 1, dueOffset: 5000),
        q(id: 3, difficulty: 5, reps: 1, dueOffset: 2000),
        q(id: 4, difficulty: 3, reps: 1, dueOffset: 1000),
      ];
      final fresh = [
        q(id: 5, difficulty: 5, dueOffset: 3000),
        q(id: 6, difficulty: 1, dueOffset: 0),
      ];
      final session = SessionComposer.compose(
        due: due,
        fresh: fresh,
        kind: SessionKind.boss,
        target: 4,
      );
      // All mcq — boss ignores the cap. Difficulty 5 first, by
      // dueAt: id 3 (2000), id 5 (3000), id 2 (5000); then diff 3.
      expect(session.map((e) => e.id).toList(), [3, 5, 2, 4]);
    });
  });
}

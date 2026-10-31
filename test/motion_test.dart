// MOTION (D-038 Stage 6) — the spec §7 verification set:
// animated values reach their exact end state, reduced motion
// collapses animation, skeletons respect the 150ms gate, the
// goal badge celebrates a crossing (not a revisit), and key
// compositions survive 200% text scaling at 320dp width.
import 'package:daily_life_app/core/motion.dart';
import 'package:daily_life_app/core/neo_ui.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/goals/goals_screen.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {bool reduced = false}) {
  return MaterialApp(
    theme: AppTheme.neoDark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: child),
    ),
  );
}

String _countText(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text).first);
  return text.data ?? '';
}

void main() {
  group('AnimatedCount', () {
    testWidgets('tweens through intermediate values to the exact end',
        (tester) async {
      await tester.pumpWidget(_wrap(const AnimatedCount(value: 0)));
      expect(_countText(tester), '0');
      await tester.pumpWidget(_wrap(const AnimatedCount(value: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      final mid = int.parse(_countText(tester));
      expect(mid, greaterThan(0));
      expect(mid, lessThan(100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_countText(tester), '100');
    });

    testWidgets('reduced motion snaps immediately', (tester) async {
      await tester
          .pumpWidget(_wrap(const AnimatedCount(value: 0), reduced: true));
      await tester
          .pumpWidget(_wrap(const AnimatedCount(value: 42), reduced: true));
      await tester.pump();
      expect(_countText(tester), '42');
    });
  });

  testWidgets('NeoTrack reaches its exact fill and snaps when reduced',
      (tester) async {
    await tester.pumpWidget(_wrap(const NeoTrack(value: 0.25)));
    await tester.pumpWidget(_wrap(const NeoTrack(value: 0.9)));
    await tester.pump(const Duration(milliseconds: 300));
    final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox));
    expect(box.widthFactor, 0.9);

    await tester
        .pumpWidget(_wrap(const NeoTrack(value: 0.5), reduced: true));
    await tester.pump();
    final box2 = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox));
    expect(box2.widthFactor, 0.5);
  });

  testWidgets('NeoCheck settles filled after a tick', (tester) async {
    await tester.pumpWidget(_wrap(const NeoCheck(done: false)));
    await tester.pumpWidget(_wrap(const NeoCheck(done: true)));
    await tester.pump(const Duration(milliseconds: 200));
    final container =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, AppTheme.neoDark().colorScheme.primary);
  });

  testWidgets('DelayedSkeleton shows nothing before 150ms, blocks after',
      (tester) async {
    await tester.pumpWidget(_wrap(
        const DelayedSkeleton(skeleton: SkeletonList(panels: 1))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SkeletonBlock), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SkeletonBlock), findsWidgets);
  });

  testWidgets('GoalCard celebrates the crossing, then just shows the badge',
      (tester) async {
    Goal goal(int current) => Goal(
          id: 1,
          title: 'Read',
          target: 10,
          current: current,
          unit: 'books',
          position: 0,
          createdAt: 0,
        );
    await tester.pumpWidget(_wrap(GoalCard(goal: goal(9), onStep: (_) {})));
    expect(find.byType(GoalCompletionBadge), findsNothing);
    await tester.pumpWidget(_wrap(GoalCard(goal: goal(10), onStep: (_) {})));
    expect(find.byType(GoalCompletionBadge), findsOneWidget);
    expect(find.text('Goal reached — nicely done.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    // Still there after the celebration ends — it's a state now.
    expect(find.byType(GoalCompletionBadge), findsOneWidget);
  });

  testWidgets('score wells + goal card survive 200% text at 320dp',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.neoDark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(Space.page),
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: NeoScoreWell(
                        label: 'Done score · auto',
                        value: '86',
                        sub: 'Based on your core plan',
                        suffix: ' / 100',
                        fraction: 0.86,
                      ),
                    ),
                    SizedBox(width: Space.s5),
                    Expanded(
                      child: NeoScoreWell(
                        label: 'Self score · yours',
                        value: '8',
                        sub: 'Your own reflection',
                        accentValue: true,
                        fraction: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                GoalCard(
                  goal: Goal(
                    id: 2,
                    title: 'Conversational Arabic milestones',
                    target: 10,
                    current: 4,
                    unit: 'milestones',
                    position: 0,
                    createdAt: 0,
                  ),
                  onStep: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}

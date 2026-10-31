/// GOAL — goals tab (basic in S2): list, add, step progress, delete.
/// Full goal features (linking, streaks) arrive in S5.
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../shared_ui.dart';
import 'goals_store.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, required this.goalsStore});

  final GoalsStore goalsStore;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late Future<List<Goal>> _goals;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _goals = widget.goalsStore.goals();
  }

  Future<void> _add() async {
    final input = await promptGoal(context);
    if (input == null) return;
    await widget.goalsStore.addGoal(input.title, input.target, input.unit);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Goal>>(
        future: _goals,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(
                  Space.page, Gap.md, Space.page, Gap.lg),
              child: DelayedSkeleton(skeleton: SkeletonList(panels: 2)),
            );
          }
          final list = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, Gap.lg),
            children: [
              const NeoPageTitle(
                eyebrow: 'A direction, not a deadline',
                heading: 'Keep becoming.',
                sub: 'Small actions are how a goal becomes part of '
                    'your life.',
              ),
              const SizedBox(height: Gap.lg),
              NeoSectionHead(
                title: 'In motion',
                actionLabel: '+ Add goal',
                onAction: _add,
              ),
              const SizedBox(height: Space.s3),
              if (list.isEmpty)
                Text(
                  'No goals yet — give your intention a direction.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              for (var i = 0; i < list.length; i++)
                GoalCard(
                  goal: list[i],
                  // D-038 (§6.5): the first goal carries the
                  // visual weight; later goals sit quieter.
                  level: i == 0
                      ? NeoSurfaceLevel.raised
                      : NeoSurfaceLevel.flat,
                  onStep: (delta) async {
                    await widget.goalsStore.step(list[i], delta);
                    setState(_reload);
                  },
                  onDelete: () async {
                    if (!await confirmDelete(context, 'goal')) return;
                    await widget.goalsStore.deleteGoal(list[i].id);
                    setState(_reload);
                  },
                ),
              const SizedBox(height: Gap.md),
              NeoPanel(
                level: NeoSurfaceLevel.flat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const NeoGlyph(icon: Icons.eco_outlined),
                    const SizedBox(height: Space.s4),
                    Text(
                      'Progress at your own pace.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.s2),
                    Text(
                      'Your goals are a direction, not a daily '
                      'verdict. Update them when you have taken a '
                      'meaningful step.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                    ),
                    const SizedBox(height: Space.s3),
                    Text(
                      'Manual progress. Learning does not '
                      'automatically advance a goal.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One goal with progress bar and −/+ stepper. Stateful for
/// one reason (D-038 Stage 6, Tier 3): it notices the moment
/// the goal CROSSES into complete, so the completion badge can
/// celebrate exactly once — later rebuilds and revisits show
/// the badge statically.
class GoalCard extends StatefulWidget {
  const GoalCard({
    super.key,
    required this.goal,
    required this.onStep,
    this.onDelete,
    this.level = NeoSurfaceLevel.raised,
  });

  final Goal goal;
  final void Function(int delta) onStep;
  final VoidCallback? onDelete;

  /// Surface emphasis (D-038): the first goal raised, the
  /// rest flat.
  final NeoSurfaceLevel level;

  @override
  State<GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<GoalCard> {
  bool _justCompleted = false;

  @override
  void didUpdateWidget(GoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.goal.fraction < 1 && widget.goal.fraction >= 1) {
      _justCompleted = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s5),
      child: NeoRaisedSm(
        level: widget.level,
        radius: RadiusToken.card,
        padding: const EdgeInsets.all(Space.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const NeoGlyph(icon: Icons.flag_outlined),
                const SizedBox(width: Space.s4),
                Expanded(
                  child: Text(goal.title,
                      style: AppType.cardHeading(theme.textTheme)),
                ),
                Text(
                  '${(goal.fraction * 100).round()}%',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: scheme.primary),
                ),
                if (goal.fraction >= 1) ...[
                  const SizedBox(width: Space.s3),
                  GoalCompletionBadge(celebrate: _justCompleted),
                ],
                if (widget.onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete goal',
                    onPressed: widget.onDelete,
                  ),
              ],
            ),
            const SizedBox(height: Space.s5),
            NeoTrack(value: goal.fraction),
            const SizedBox(height: Space.s4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    goal.fraction >= 1
                        ? 'Goal reached — nicely done.'
                        : (goal.unit.isEmpty
                            ? 'steps completed'
                            : '${goal.unit} completed'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: goal.fraction >= 1
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                NeoStepperButton(
                  icon: Icons.remove,
                  tooltip: 'Decrease',
                  onTap: goal.current <= 0 ? null : () => widget.onStep(-1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                  child: Text(
                    '${goal.current} / ${goal.target}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                NeoStepperButton(
                  icon: Icons.add,
                  tooltip: 'Increase',
                  onTap: goal.current >= goal.target
                      ? null
                      : () => widget.onStep(1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

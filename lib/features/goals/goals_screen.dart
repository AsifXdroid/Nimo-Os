/// GOAL — goals tab (basic in S2): list, add, step progress, delete.
/// Full goal features (linking, streaks) arrive in S5.
library;

import 'package:flutter/material.dart';

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
      appBar: AppBar(title: const Text('Goals')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Goal>>(
        future: _goals,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          if (list.isEmpty) {
            return const Center(
              child: Text('No goals yet.\nTap + to add a short-term goal.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(Gap.md),
            itemCount: list.length,
            itemBuilder: (context, i) => GoalCard(
              goal: list[i],
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
          );
        },
      ),
    );
  }
}

/// One goal with progress bar and −/+ stepper.
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    required this.onStep,
    this.onDelete,
  });

  final Goal goal;
  final void Function(int delta) onStep;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = goal.unit.isEmpty ? '' : ' ${goal.unit}';
    return Card(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(goal.title, style: theme.textTheme.titleMedium),
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete goal',
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            LinearProgressIndicator(value: goal.fraction),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  tooltip: 'Decrease',
                  onPressed: () => onStep(-1),
                ),
                Expanded(
                  child: Text(
                    '${goal.current} of ${goal.target}$unit',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Increase',
                  onPressed: () => onStep(1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

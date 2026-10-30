/// TODAY — routine template editor (S2).
/// Templates regenerate as fresh unticked items in each new day's
/// plan (D-002). Changes here affect future days, never past plans.
library;

import 'package:flutter/material.dart';

import '../shared_ui.dart';
import 'today_store.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key, required this.todayStore});

  final TodayStore todayStore;

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  late Future<List<PlanTemplate>> _templates;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _templates = widget.todayStore.templates();
  }

  Future<void> _add() async {
    final title =
        await promptText(context, title: 'New routine item', label: 'Title');
    if (title == null || title.isEmpty) return;
    await widget.todayStore.addTemplate(title);
    setState(_reload);
  }

  Future<void> _rename(PlanTemplate t) async {
    final title = await promptText(context,
        title: 'Rename routine item', label: 'Title', initial: t.title);
    if (title == null || title.isEmpty) return;
    await widget.todayStore.renameTemplate(t.id, title);
    setState(_reload);
  }

  Future<void> _delete(PlanTemplate t) async {
    if (!await confirmDelete(context, 'routine item')) return;
    await widget.todayStore.deleteTemplate(t.id);
    setState(_reload);
  }

  /// Tiny-habits fields (§R5.5): the tiny version of the habit, the
  /// anchor moment it attaches to, its life-area track, and whether
  /// it counts toward the day's core (the streak's core signal).
  Future<void> _habitDetails(PlanTemplate t) async {
    final starter = TextEditingController(text: t.starterTitle ?? '');
    final anchor = TextEditingController(text: t.anchorText ?? '');
    final track = TextEditingController(text: t.track ?? '');
    var countsCore = t.countsCore;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Habit details — ${t.title}'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: starter,
                  decoration: const InputDecoration(
                    labelText: 'Tiny version',
                    hintText: 'e.g. Read one line of Arabic',
                  ),
                ),
                TextField(
                  controller: anchor,
                  decoration: const InputDecoration(
                    labelText: 'Anchor — after…',
                    hintText: 'e.g. after Fajr prayer',
                  ),
                ),
                TextField(
                  controller: track,
                  decoration: const InputDecoration(labelText: 'Track'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in HabitTracks.suggestions)
                      ChoiceChip(
                        label: Text(s),
                        selected: track.text == s,
                        onSelected: (_) =>
                            setDialogState(() => track.text = s),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Counts toward the day\'s core'),
                  subtitle: const Text(
                      'Core items done (or 80% of the plan) keep '
                      'the streak alive.'),
                  value: countsCore,
                  onChanged: (v) =>
                      setDialogState(() => countsCore = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final starterText = starter.text;
    final anchorText = anchor.text;
    final trackText = track.text;
    starter.dispose();
    anchor.dispose();
    track.dispose();
    if (saved != true) return;
    await widget.todayStore.updateTemplateHabits(
      t.id,
      starterTitle: starterText,
      anchorText: anchorText,
      track: trackText,
      countsCore: countsCore,
    );
    setState(_reload);
  }

  String? _habitSummary(PlanTemplate t) {
    final parts = <String>[
      if (t.anchorText != null) 'After ${t.anchorText}',
      if (t.starterTitle != null) 'Tiny: ${t.starterTitle}',
      if (t.track != null) t.track!,
      if (!t.countsCore) 'Not core',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Routine template')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<PlanTemplate>>(
        future: _templates,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          if (list.isEmpty) {
            return const Center(
              child: Text(
                  'No routine items yet.\nTap + to add one — it will '
                  'appear in every new day\'s plan.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i];
              return ListTile(
                title: Text(t.title),
                subtitle: _habitSummary(t) == null
                    ? null
                    : Text(_habitSummary(t)!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: t.isActive,
                      onChanged: (v) async {
                        await widget.todayStore.setTemplateActive(t.id, v);
                        setState(_reload);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.spa_outlined),
                      tooltip: 'Habit details',
                      onPressed: () => _habitDetails(t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rename',
                      onPressed: () => _rename(t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _delete(t),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

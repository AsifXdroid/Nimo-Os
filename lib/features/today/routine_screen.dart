/// TODAY — routine template editor (S2).
/// Templates regenerate as fresh unticked items in each new day's
/// plan (D-002). Changes here affect future days, never past plans.
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../shared_ui.dart';
import 'today_store.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key, required this.todayStore});

  final TodayStore todayStore;

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  late Future<({List<PlanTemplate> templates, String ifThen})> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<({List<PlanTemplate> templates, String ifThen})> _load() async {
    return (
      templates: await widget.todayStore.templates(),
      ifThen: await widget.todayStore.ifThenLine(),
    );
  }

  Future<void> _editIfThen(String current) async {
    final text = await promptText(
      context,
      title: 'Your if–then line',
      label: 'If …, then I will …',
      initial: current,
      maxLines: 2,
    );
    if (text == null) return;
    await widget.todayStore.setIfThenLine(text);
    setState(_reload);
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Routine template')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<({List<PlanTemplate> templates, String ifThen})>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final list = data.templates;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, Gap.lg),
            children: [
              const NeoPageTitle(
                eyebrow: 'Your daily template',
                heading: 'Keep the rhythm realistic.',
                sub: 'A small plan is easier to return to. '
                    'Changes apply from tomorrow.',
              ),
              const SizedBox(height: Gap.lg),
              if (list.isEmpty)
                Text(
                  'No routine items yet. Tap + to add one — it will '
                  'appear in every new day\'s plan.',
                  style: theme.textTheme.bodyMedium,
                )
              else
                NeoPanel(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.s6, vertical: Space.s2),
                  child: Column(
                    children: [
                      for (final t in list)
                        _templateRow(context, t, last: t == list.last),
                    ],
                  ),
                ),
              const SizedBox(height: Gap.lg),
              NeoPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('A tiny habit prompt',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: Gap.sm),
                    Text(
                      'Connect something new to something you '
                      'already do.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Gap.md),
                    InkWell(
                      onTap: () => _editIfThen(data.ifThen),
                      child: Row(
                        children: [
                          Icon(Icons.bolt_outlined,
                              size: 18,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: Space.s3),
                          Expanded(
                            child: Text(
                              data.ifThen.isEmpty
                                  ? 'Set your if–then line: '
                                      '"If …, then I will …"'
                                  : data.ifThen,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          const Icon(Icons.edit_outlined, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 72), // FAB clearance
            ],
          );
        },
      ),
    );
  }

  Widget _templateRow(BuildContext context, PlanTemplate t,
      {bool last = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = _habitSummary(t);
    return Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
      padding: const EdgeInsets.symmetric(vertical: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: t.isActive,
                onChanged: (v) async {
                  await widget.todayStore.setTemplateActive(t.id, v);
                  setState(_reload);
                },
              ),
            ],
          ),
          if (summary != null)
            Text(
              summary,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.spa_outlined, size: 20),
                tooltip: 'Habit details',
                onPressed: () => _habitDetails(t),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Rename',
                onPressed: () => _rename(t),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete',
                onPressed: () => _delete(t),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

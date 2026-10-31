/// TODAY — routine template editor (S2).
/// Templates regenerate as fresh unticked items in each new day's
/// plan (D-002). Changes here affect future days, never past plans.
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'plan_link.dart';
import 'today_store.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key, required this.todayStore, this.store});

  final TodayStore todayStore;

  /// D-042: enables the item picker in Schedule & link
  /// (optional — without it only URL links can be edited).
  final Store? store;

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
      if (t.weekdays != null && t.weekdays != 127)
        _weekdaySummary(t.weekdays!),
      if (t.url != null || t.itemId != null) 'Linked',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _weekdaySummary(int mask) => [
        for (var i = 0; i < 7; i++)
          if ((mask >> i) & 1 == 1) _dayNames[i],
      ].join(' · ');

  /// Schedule (weekday mask) + linked resource for a template
  /// (D-042). Applies to plans not yet generated, like every
  /// template edit — generated history is never rewritten.
  /// D-044: the explicit exception to tomorrow-by-default —
  /// add this routine to today's plan, in place, and say
  /// plainly what happened (including when scheduling says no).
  Future<void> _addToToday(PlanTemplate t) async {
    final now = DateTime.now();
    final result =
        await widget.todayStore.addRoutineToToday(t.id, now);
    if (!mounted) return;
    final message = switch (result) {
      AddRoutineResult.added => '“${t.title}” added to today\'s plan.',
      AddRoutineResult.alreadyInPlan =>
        '“${t.title}” is already in today\'s plan.',
      AddRoutineResult.notScheduledToday =>
        '“${t.title}” isn\'t scheduled for '
            '${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][now.weekday - 1]}s — '
            'it will appear on its scheduled days.',
      AddRoutineResult.inactive => 'Turn the routine on first.',
      AddRoutineResult.notFound => 'That routine no longer exists.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    setState(_reload);
  }

  Future<void> _scheduleLink(PlanTemplate t) async {
    var mask = t.weekdays ?? 127;
    var itemId = t.itemId;
    String? itemTitle;
    if (widget.store != null && t.itemId != null) {
      try {
        itemTitle = (await widget.store!.itemById(t.itemId!)).title;
      } catch (_) {
        itemTitle = 'Linked item';
      }
    }
    if (!mounted) return;
    final url = TextEditingController(text: t.url ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Schedule & link — ${t.title}'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Runs on',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i < 7; i++)
                      FilterChip(
                        label: Text(_dayNames[i]),
                        selected: (mask >> i) & 1 == 1,
                        onSelected: (v) => setDialogState(
                            () => mask = v ? mask | (1 << i) : mask & ~(1 << i)),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setDialogState(() => mask = 127),
                    child: const Text('Every day'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Linked resource',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: 'Web or video link',
                    hintText: 'https://…',
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (v) {
                    if (v.trim().isNotEmpty && itemId != null) {
                      setDialogState(() {
                        itemId = null;
                        itemTitle = null;
                      });
                    }
                  },
                ),
                if (widget.store != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          itemId == null
                              ? 'No Spaces item linked'
                              : 'Item: ${itemTitle ?? 'Linked item'}',
                          style:
                              Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await pickLinkItem(
                              context, widget.store!);
                          if (picked == null) return;
                          setDialogState(() {
                            itemId = picked.id;
                            itemTitle = picked.title;
                            url.text = '';
                          });
                        },
                        child: const Text('Choose…'),
                      ),
                      if (itemId != null)
                        TextButton(
                          onPressed: () => setDialogState(() {
                            itemId = null;
                            itemTitle = null;
                          }),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ],
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
            onPressed: () {
              if (mask == 0) {
                // Rebuild with the error: the dialog's own
                // setState is out of scope here, so pop nothing;
                // simplest correct route: refuse via snackbar.
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Pick at least one day.')));
                return;
              }
              final raw = url.text.trim();
              if (raw.isNotEmpty && !isValidWebUrl(raw)) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "That doesn't look like a valid web link.")));
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final rawUrl = url.text.trim();
    url.dispose();
    if (saved != true) return;
    await widget.todayStore.updateTemplateLink(
      t.id,
      weekdays: mask == 127 ? null : mask,
      itemId: itemId,
      url: rawUrl.isEmpty ? null : rawUrl,
    );
    setState(_reload);
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
                // D-039: template rows on the canvas (hairlines).
                Column(
                  children: [
                    for (final t in list)
                      _templateRow(context, t, last: t == list.last),
                  ],
                ),
              const SizedBox(height: Gap.lg),
              Column(
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
              if (t.isActive)
                IconButton(
                  icon: const Icon(Icons.today_outlined, size: 20),
                  tooltip: "Add to today's plan",
                  onPressed: () => _addToToday(t),
                ),
              IconButton(
                icon: const Icon(Icons.spa_outlined, size: 20),
                tooltip: 'Habit details',
                onPressed: () => _habitDetails(t),
              ),
              IconButton(
                icon: const Icon(Icons.event_outlined, size: 20),
                tooltip: 'Schedule & link',
                onPressed: () => _scheduleLink(t),
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

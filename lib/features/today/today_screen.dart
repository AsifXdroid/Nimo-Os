/// TODAY — Hub Home (S2, layout per D-009).
///
/// Sections, in order: header (date, greeting, search/settings
/// placeholders — global search is S5, settings is S6), week strip,
/// quick-add row, today's plan card (or the This-week pending view),
/// pinned spaces, recent items, goals, Customize Home. Which of the
/// optional sections show is persisted in `app_settings`.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../goals/goals_store.dart';
import '../items/item_detail_screen.dart';
import '../items/item_registry.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../learn/session_composer.dart';
import '../learn/session_screen.dart';
import '../progress/progress_store.dart';
import '../progress/weekly_summary.dart';
import '../review/day_close_screen.dart';
import '../review/review_store.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'routine_screen.dart';
import 'today_store.dart';

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday',
];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

String _formatDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]}';

String _greeting(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Everything Hub Home renders, loaded in one pass.
class _HubData {
  _HubData({
    required this.items,
    required this.weekPending,
    required this.weekCounts,
    required this.pinned,
    required this.recent,
    required this.goals,
    required this.sections,
    required this.streak,
    required this.todayReview,
    required this.closeTarget,
    required this.ifThen,
    required this.inboxCount,
    required this.dueCount,
    required this.newCount,
    this.weekSummary,
  });

  final List<DayPlanItem> items;
  final List<DayPending> weekPending;
  final List<int> weekCounts;
  final List<({Workspace workspace, int itemCount})> pinned;
  final List<RecentItem> recent;
  final List<Goal> goals;
  final Map<String, bool> sections;

  /// REVIEW (S3): streak summary, today's review (null until
  /// closed), the Day Close target (today, or yesterday inside the
  /// late-close window), and the if–then line.
  final StreakState streak;
  final DayReview? todayReview;
  final CloseTarget closeTarget;
  final String ifThen;

  /// LEARN (S4): topics waiting in the Inbox (shown on the Topics
  /// & Library card only — the count is deliberately NOT a Home
  /// badge; §R9.5 keeps the Inbox off the guilt surface).
  final int inboxCount;

  /// LEARN (S5): cheap engine counts for the Learn card (due now
  /// / never answered). COUNT queries only — loading Home never
  /// seeds or writes anything.
  final int dueCount;
  final int newCount;

  /// PROGRESS (S6): this week's summary, loaded ONLY when the
  /// Sunday-evening card is due (§R5.4: Sunday from ~18:00) and
  /// a ProgressStore is wired; null otherwise.
  final WeeklySummary? weekSummary;
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.store,
    required this.todayStore,
    required this.goalsStore,
    required this.reviewStore,
    required this.learn,
    required this.thumbnails,
    required this.onOpenTopics,
    required this.onOpenWorkspace,
    required this.onOpenLearn,
    this.progressStore,
    this.onOpenSettings,
    this.onOpenWeeklySummary,
  });

  final Store store;
  final TodayStore todayStore;
  final GoalsStore goalsStore;
  final ReviewStore reviewStore;

  /// LEARN (S4): topics/library services (Day Close topic picker).
  final LearnServices learn;

  /// LINK (S4): thumbnail cache for item detail screens opened
  /// from Home's recent items.
  final ThumbnailService thumbnails;

  /// Opens the Topics & Library screen (built by the shell, which
  /// also wires the backup section into it).
  final void Function() onOpenTopics;

  /// Called when a pinned space is tapped: the shell switches to the
  /// Spaces tab and opens the workspace.
  final void Function(Workspace workspace) onOpenWorkspace;

  /// Opens the Learn tab (the shell selects the learn destination).
  final void Function() onOpenLearn;

  /// PROGRESS (S6): progress read model for the Sunday summary
  /// card; optional so isolated tests can mount Home without it.
  final ProgressStore? progressStore;

  /// Opens the Settings surface (S6); null keeps the header icon
  /// a disabled placeholder.
  final void Function()? onOpenSettings;

  /// Opens the full weekly summary for the given Monday (S6).
  final void Function(DateTime monday)? onOpenWeeklySummary;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<_HubData> _data;
  bool _showWeek = false;
  final _addController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _reload() {
    _data = _load();
  }

  Future<_HubData> _load() async {
    final now = DateTime.now();
    // REVIEW (S3): resolve the close target BEFORE generating
    // today's plan, then refresh the streak fold through yesterday.
    final closeTarget = await widget.reviewStore.closableDate(now: now);
    await widget.reviewStore.evaluate(now: now);
    final streak = await widget.reviewStore.streakState();
    final todayReview = await widget.reviewStore.reviewFor(now);
    final ifThen = await widget.todayStore.ifThenLine();
    final items = await widget.todayStore.planItems(now);
    final weekPending = await widget.todayStore.weekPending(now);
    final weekCounts = await widget.todayStore.weekPendingCounts(now);
    final pinnedWs = await widget.store.pinnedWorkspaces();
    final pinned = <({Workspace workspace, int itemCount})>[];
    for (final ws in pinnedWs) {
      pinned.add((
        workspace: ws,
        itemCount: await widget.store.itemCountForWorkspace(ws.id),
      ));
    }
    final recent = await widget.store.recentItems(limit: 5);
    final goals = await widget.goalsStore.goals();
    final sections = await widget.todayStore.homeSectionVisibility();
    final inboxCount = await widget.learn.store.inboxCountOrZero();
    final dueCount = await widget.learn.engine.dueCount();
    final newCount = await widget.learn.engine.newCount();
    // PROGRESS (S6): the Sunday summary is computed only when its
    // card is due (Sunday ≥18:00, §R5.4) — a pure recompute over
    // stored data, never a stored artefact.
    final weekSummary = (widget.progressStore != null &&
            sundaySummaryDue(now))
        ? await widget.progressStore!.weeklySummary(now, now: now)
        : null;
    return _HubData(
      items: items,
      weekPending: weekPending,
      weekCounts: weekCounts,
      pinned: pinned,
      recent: recent,
      goals: goals,
      sections: sections,
      streak: streak,
      todayReview: todayReview,
      closeTarget: closeTarget,
      ifThen: ifThen,
      inboxCount: inboxCount,
      dueCount: dueCount,
      newCount: newCount,
      weekSummary: weekSummary,
    );
  }

  // ------------------------------------------------------------ actions

  Future<void> _addOneOff(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    await widget.todayStore.addOneOff(DateTime.now(), t);
    await _afterPlanEdit();
    _addController.clear();
    setState(_reload);
  }

  Future<void> _quickAddTask() async {
    final title =
        await promptText(context, title: 'Add task for today', label: 'Task');
    if (title != null) await _addOneOff(title);
  }

  Future<void> _quickAddGoal() async {
    final input = await promptGoal(context);
    if (input == null) return;
    await widget.goalsStore.addGoal(input.title, input.target, input.unit);
    setState(_reload);
  }

  Future<void> _quickAddItem(String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final workspaces = await widget.store.workspaces();
    if (!mounted) return;
    if (workspaces.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Create a workspace in Spaces first.')));
      return;
    }
    final ws = await _pickFrom<Workspace>(
      title: 'Choose workspace',
      values: workspaces,
      label: (w) => w.name,
    );
    if (ws == null || !mounted) return;
    final projects = await widget.store.projects(ws.id);
    if (!mounted) return;
    if (projects.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Create a project in Spaces first.')));
      return;
    }
    final prj = projects.length == 1
        ? projects.single
        : await _pickFrom<Project>(
            title: 'Choose project',
            values: projects,
            label: (p) => p.name,
          );
    if (prj == null || !mounted) return;
    final def = itemTypeDef(type);
    final title = await promptText(context,
        title: 'New ${def.label.toLowerCase()}', label: 'Title');
    if (title == null || title.isEmpty) return;
    await widget.store.createItem(prj.id, type: type, title: title);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('Added to ${prj.name}')));
    setState(_reload);
  }

  Future<T?> _pickFrom<T>({
    required String title,
    required List<T> values,
    required String Function(T) label,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(title)),
            for (final v in values)
              ListTile(
                title: Text(label(v)),
                onTap: () => Navigator.pop(context, v),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _customize(_HubData data) async {
    const labels = {
      TodayStore.sectionWeekStrip: 'Week strip',
      TodayStore.sectionDayClose: 'Day Close banner',
      TodayStore.sectionPinned: 'Pinned spaces',
      TodayStore.sectionRecent: 'Recent items',
      TodayStore.sectionGoals: 'Goals',
    };
    final result = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) {
        final values = Map<String, bool>.of(data.sections);
        return AlertDialog(
          title: const Text('Customize Home'),
          content: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in TodayStore.homeSections)
                  SwitchListTile(
                    title: Text(labels[key]!),
                    value: values[key] ?? true,
                    onChanged: (v) =>
                        setDialogState(() => values[key] = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, values),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    for (final e in result.entries) {
      await widget.todayStore.setHomeSectionVisible(e.key, e.value);
    }
    setState(_reload);
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Life')),
      body: FutureBuilder<_HubData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              _header(context, now),
              if (data.weekSummary != null) ...[
                const SizedBox(height: Gap.md),
                _sundaySummaryCard(context, data.weekSummary!),
              ],
              if (data.sections[TodayStore.sectionWeekStrip] ?? true)
                _weekStrip(context, data),
              _quickAddRow(context),
              const SizedBox(height: Gap.md),
              if (data.sections[TodayStore.sectionDayClose] ?? true) ...[
                _dayCloseCard(context, data),
                const SizedBox(height: Gap.md),
              ],
              _topicsCard(context, data),
              const SizedBox(height: Gap.md),
              _learnCard(context, data),
              const SizedBox(height: Gap.md),
              if (_showWeek)
                _weekCard(context, data)
              else
                _planCard(context, data),
              if (data.sections[TodayStore.sectionPinned] ?? true)
                _pinnedSection(context, data),
              if (data.sections[TodayStore.sectionRecent] ?? true)
                _recentSection(context, data),
              if (data.sections[TodayStore.sectionGoals] ?? true)
                _goalsSection(context, data),
              const SizedBox(height: Gap.sm),
              Center(
                child: TextButton.icon(
                  onPressed: () => _customize(data),
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text('Customize Home'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, DateTime now) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatDate(now),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              Text(_greeting(now), style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
        const IconButton(
          icon: Icon(Icons.search),
          tooltip: 'Coming soon',
          onPressed: null,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: widget.onOpenSettings == null ? 'Coming soon' : 'Settings',
          onPressed: widget.onOpenSettings,
        ),
      ],
    );
  }

  /// Sunday weekly summary card (PROGRESS, S6 — §R2.3/§R5.4):
  /// takes over the top of Today on Sunday evening; dismissing
  /// is not needed because it simply stops being due on Monday,
  /// and the full summary lives in Progress afterwards.
  Widget _sundaySummaryCard(BuildContext context, WeeklySummary summary) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: ListTile(
        leading: Icon(Icons.auto_stories_outlined,
            color: theme.colorScheme.primary),
        title: const Text('Your week, wrapped up'),
        subtitle: Text(summary.isEmpty
            ? 'A quiet week — see the summary in Progress.'
            : 'You showed up ${summary.daysCounted} of 7 days'
                '${summary.shieldDays > 0 ? ' · ${summary.shieldDays} shield day${summary.shieldDays == 1 ? '' : 's'}' : ''}'
                '${summary.majorPoints.isNotEmpty ? ' · ${summary.majorPoints.length} major point${summary.majorPoints.length == 1 ? '' : 's'} captured' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenWeeklySummary == null
            ? null
            : () => widget.onOpenWeeklySummary!(summary.monday),
      ),
    );
  }

  Widget _weekStrip(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final monday = TodayStore.mondayOf(DateTime.now());
    final today = TodayStore.dayOnly(DateTime.now());
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    Widget cell(int i) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final isToday = day == today;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _showWeek = true),
          child: Column(
            children: [
              Text(letters[i], style: theme.textTheme.labelSmall),
              const SizedBox(height: 4),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday ? theme.colorScheme.primary : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${day.day}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isToday ? theme.colorScheme.onPrimary : null,
                    fontWeight: isToday ? FontWeight.bold : null,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: data.weekCounts[i] > 0
                      ? theme.colorScheme.tertiary
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.sm),
      child: Row(children: [for (var i = 0; i < 7; i++) cell(i)]),
    );
  }

  Widget _quickAddRow(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback onTap) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(height: 2),
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
        );
    return Row(
      children: [
        button(Icons.add_task_outlined, 'Task', _quickAddTask),
        button(Icons.flag_outlined, 'Goal', _quickAddGoal),
        button(Icons.note_outlined, 'Note',
            () => _quickAddItem(ItemType.note)),
        button(Icons.checklist_outlined, 'Checklist',
            () => _quickAddItem(ItemType.checklist)),
      ],
    );
  }

  Future<void> _openDayClose(_HubData data,
      {DateTime? date, bool? isLate}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DayCloseScreen(
          todayStore: widget.todayStore,
          reviewStore: widget.reviewStore,
          date: date ?? data.closeTarget.date,
          isLate: isLate ?? data.closeTarget.isLate,
          learnStore: widget.learn.store,
        ),
      ),
    );
    setState(_reload);
  }

  /// After any edit to today's plan from Hub Home, keep a closed
  /// day's stored Done Score in step (review S3).
  Future<void> _afterPlanEdit() =>
      widget.reviewStore.refreshDoneScoreIfClosed(DateTime.now());

  Future<void> _editIfThen(_HubData data) async {
    final text = await promptText(
      context,
      title: 'Your if–then line',
      label: 'If …, then I will …',
      initial: data.ifThen,
      maxLines: 2,
    );
    if (text == null) return;
    await widget.todayStore.setIfThenLine(text);
    setState(_reload);
  }

  /// Topics & Library card (LEARN, S4): the doorway to topics,
  /// sources and backup. The Inbox count is shown as plain text
  /// ("3 waiting") — information, not a badge (§R9.5).
  Widget _topicsCard(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.library_books_outlined,
            color: theme.colorScheme.primary),
        title: const Text('Topics & Library'),
        subtitle: Text(data.inboxCount == 0
            ? 'Inbox is clear'
            : 'Inbox · ${data.inboxCount} waiting'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenTopics,
      ),
    );
  }

  /// Pushes a review session directly from Home (the ≤2-tap
  /// path to learning: this Start button is tap one, answering
  /// is tap two) and reloads the Hub on return.
  Future<void> _openLearnSession() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          learn: widget.learn,
          reviewStore: widget.reviewStore,
          store: widget.store,
          kind: SessionKind.review,
        ),
      ),
    );
    setState(_reload);
  }

  /// Learn card (LEARN engine, S5): due/new counts and the direct
  /// Start path. Tapping the card itself goes to the Learn tab.
  Widget _learnCard(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final total = data.dueCount + data.newCount;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.school_outlined,
            color: theme.colorScheme.primary),
        title: const Text('Learn'),
        subtitle: Text(total == 0
            ? 'Import a pack to start learning'
            : '${data.dueCount} due · ${data.newCount} new'),
        trailing: total > 0
            ? FilledButton(
                onPressed: _openLearnSession,
                child: const Text('Start'),
              )
            : const Icon(Icons.chevron_right),
        onTap: widget.onOpenLearn,
      ),
    );
  }

  /// Day Close banner (REVIEW, S3): streak + shields, today's dual
  /// scores once closed, otherwise the close action — targeting
  /// yesterday instead while the late-close window is open.
  Widget _dayCloseCard(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final streak = data.streak;
    final review = data.todayReview;
    final doneCount = data.items.where((i) => i.done).length;
    final closed = review != null && review.isClosed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department_outlined,
                    color: scheme.primary),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    streak.currentStreak > 0
                        ? '${streak.currentStreak}-day streak'
                        : 'No streak yet — today counts',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                for (var i = 0; i < streak.shieldsHeld; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(Icons.shield_outlined,
                        size: 18, color: scheme.tertiary),
                  ),
              ],
            ),
            if (streak.shieldsHeld > 0 && !streak.shieldsIntroShown) ...[
              const SizedBox(height: Gap.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      "You've earned protection: a shield covers a "
                      'missed day, so one bad day never ends the '
                      'streak (max 2 shield-days a week).',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Got it',
                    onPressed: () async {
                      await widget.reviewStore.markShieldsIntroShown();
                      setState(_reload);
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: Gap.sm),
            if (data.closeTarget.isLate)
              Text("Yesterday isn't closed yet — you can still close it.",
                  style: theme.textTheme.bodyMedium)
            else if (closed)
              Text(
                'Today closed · Done ${review.doneScore ?? '—'}'
                ' · Mine ${review.selfScore ?? '—'}'
                '${review.selfScore != null ? ' / 10' : ''}',
                style: theme.textTheme.bodyMedium,
              )
            else
              Text('$doneCount of ${data.items.length} done today',
                  style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                // Review S2: while the late window is open the
                // primary action closes yesterday — but today's
                // close must never be blocked behind it.
                if (data.closeTarget.isLate)
                  TextButton(
                    onPressed: () => _openDayClose(
                      data,
                      date: DateTime.now(),
                      isLate: false,
                    ),
                    child: const Text('Close today instead'),
                  ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () => _openDayClose(data),
                  child: Text(
                    data.closeTarget.isLate
                        ? 'Close yesterday'
                        : closed
                            ? 'Review today'
                            : 'Close the day',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final items = data.items;
    final done = items.where((e) => e.done).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("Today's plan",
                      style: theme.textTheme.titleMedium),
                ),
                Text('$done of ${items.length} done',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: Gap.sm),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Today')),
                  ButtonSegment(value: true, label: Text('This week')),
                ],
                selected: {_showWeek},
                onSelectionChanged: (s) =>
                    setState(() => _showWeek = s.first),
              ),
            ),
            const SizedBox(height: Gap.sm),
            LinearProgressIndicator(
                value: items.isEmpty ? 0 : done / items.length),
            const SizedBox(height: Gap.sm),
            InkWell(
              onTap: () => _editIfThen(data),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.bolt_outlined,
                        size: 18, color: theme.colorScheme.tertiary),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        data.ifThen.isEmpty
                            ? 'Set your if–then line: '
                                '"If …, then I will …"'
                            : data.ifThen,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: data.ifThen.isEmpty
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                    ),
                    const Icon(Icons.edit_outlined, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            if (items.isEmpty)
              Text('Nothing planned yet. Add a task below, or build '
                  'your routine template.',
                  style: theme.textTheme.bodyMedium),
            for (final item in items) _planRow(context, item),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: const InputDecoration(
                      hintText: 'Add a task for today…',
                      border: InputBorder.none,
                    ),
                    onSubmitted: _addOneOff,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add task',
                  onPressed: () => _addOneOff(_addController.text),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RoutineScreen(todayStore: widget.todayStore),
                    ),
                  );
                  setState(_reload);
                },
                child: const Text('Edit routine template →'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planRow(BuildContext context, DayPlanItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () async {
        await widget.todayStore.toggleItem(item);
        await _afterPlanEdit();
        setState(_reload);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.primary, width: 2),
                color: item.done ? scheme.primary : null,
              ),
              child: item.done
                  ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                  : null,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                item.title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  decoration:
                      item.done ? TextDecoration.lineThrough : null,
                  color: item.done ? scheme.onSurfaceVariant : null,
                ),
              ),
            ),
            if (item.isRoutine)
              _badge(context, 'ROUTINE', scheme.secondaryContainer,
                  scheme.onSecondaryContainer)
            else if (item.carried)
              _badge(context, 'CARRIED', scheme.tertiaryContainer,
                  scheme.onTertiaryContainer),
            if (!item.isRoutine)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Delete',
                onPressed: () async {
                  await widget.todayStore.deletePlanItem(item.id);
                  await _afterPlanEdit();
                  setState(_reload);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(
      BuildContext context, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: fg, fontWeight: FontWeight.bold)),
    );
  }

  Widget _weekCard(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      Text('This week', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Today')),
                  ButtonSegment(value: true, label: Text('This week')),
                ],
                selected: {_showWeek},
                onSelectionChanged: (s) =>
                    setState(() => _showWeek = s.first),
              ),
            ),
            const SizedBox(height: Gap.sm),
            if (data.weekPending.isEmpty)
              Text('Nothing pending this week.',
                  style: theme.textTheme.bodyMedium),
            for (final day in data.weekPending) ...[
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm, bottom: 4),
                child: Text(
                  '${_formatDate(day.date)} · ${day.items.length} pending',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final item in day.items)
                Padding(
                  padding: const EdgeInsets.only(left: Gap.md, bottom: 2),
                  child: Row(
                    children: [
                      const Text('• '),
                      Expanded(child: Text(item.title)),
                      if (item.carried)
                        _badge(
                            context,
                            'CARRIED',
                            theme.colorScheme.tertiaryContainer,
                            theme.colorScheme.onTertiaryContainer),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.sm),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _pinnedSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, 'Pinned spaces'),
        if (data.pinned.isEmpty)
          Text('Pin a workspace from the Spaces tab to see it here.',
              style: theme.textTheme.bodyMedium)
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Gap.sm,
            crossAxisSpacing: Gap.sm,
            childAspectRatio: 0.95,
            children: [
              for (final p in data.pinned)
                Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () => widget.onOpenWorkspace(p.workspace),
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            child: Text(
                              p.workspace.name.isEmpty
                                  ? '?'
                                  : p.workspace.name[0].toUpperCase(),
                              style: TextStyle(
                                  color:
                                      theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: Gap.sm),
                          Text(p.workspace.name,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          Text('${p.itemCount} items',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _recentSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, 'Recent items'),
        if (data.recent.isEmpty)
          Text('Nothing yet — items you create will show up here.',
              style: theme.textTheme.bodyMedium)
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final r in data.recent)
                  ListTile(
                    leading: Icon(itemTypeDef(r.item.type).icon),
                    title: Text(r.item.title),
                    subtitle:
                        Text('${r.workspaceName} · ${r.projectName}'),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ItemDetailScreen(
                            store: widget.store,
                            item: r.item,
                            learn: widget.learn,
                            thumbnails: widget.thumbnails,
                          ),
                        ),
                      );
                      setState(_reload);
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _goalsSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, 'Short-term goals'),
        if (data.goals.isEmpty)
          Text('No goals yet. Use Quick add → Goal to create one.',
              style: theme.textTheme.bodyMedium)
        else
          for (final goal in data.goals)
            Card(
              margin: const EdgeInsets.only(bottom: Gap.sm),
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: Gap.sm),
                    LinearProgressIndicator(value: goal.fraction),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          tooltip: 'Decrease',
                          onPressed: () async {
                            await widget.goalsStore.step(goal, -1);
                            setState(_reload);
                          },
                        ),
                        Expanded(
                          child: Text(
                            '${goal.current} of ${goal.target}'
                            '${goal.unit.isEmpty ? '' : ' ${goal.unit}'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Increase',
                          onPressed: () async {
                            await widget.goalsStore.step(goal, 1);
                            setState(_reload);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

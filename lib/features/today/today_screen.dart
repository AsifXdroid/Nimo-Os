/// TODAY — Hub Home (S2, layout per D-009).
///
/// Sections, in order: header (date, greeting, search/settings
/// placeholders — global search is S5, settings is S6), week strip,
/// quick-add row, today's plan card (or the This-week pending view),
/// pinned spaces, recent items, goals, Customize Home. Which of the
/// optional sections show is persisted in `app_settings`.
library;

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../goals/goals_store.dart';
import '../items/item_detail_screen.dart';
import '../items/item_registry.dart';
import '../items/link_card/link_card_service.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../learn/session_composer.dart';
import '../learn/session_screen.dart';
import '../progress/progress_store.dart';
import '../progress/weekly_summary.dart';
import '../quick_add/quick_add_service.dart';
import '../quick_add/quick_add_sheet.dart';
import '../review/day_close_screen.dart';
import '../review/review_store.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'routine_screen.dart';
import 'today_store.dart';
import 'plan_link.dart';

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
    this.linkedItems = const {},
    this.templates = const [],
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

  /// D-042: plan items' linked Spaces items, resolved at load
  /// (id → item) so rows can render their resource action.
  /// A missing id (deleted resource) simply has no entry —
  /// the FK already nulled it; this is belt-and-braces.
  final Map<int, Item> linkedItems;

  /// D-044: every routine template, so the plan card can
  /// explain routines that are not in today's plan (created
  /// after generation, or not scheduled for this weekday).
  final List<PlanTemplate> templates;
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
    this.onOpenProgress,
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

  /// Opens the Progress tab (D-040): the header streak chip's
  /// destination, where the full streak detail lives. Null
  /// keeps the chip a display-only indicator.
  final void Function()? onOpenProgress;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<_HubData> _data;
  bool _showWeek = false;

  /// Goal-completion tracking (D-038 Stage 6, Tier 3): the
  /// previous fraction per goal, and the goals that crossed
  /// to complete on the latest load (celebrated once).
  final Map<int, double> _prevGoalFractions = {};
  final Set<int> _justCompleted = {};
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
    for (final g in goals) {
      final prev = _prevGoalFractions[g.id];
      if (prev != null && prev < 1 && g.fraction >= 1) {
        _justCompleted.add(g.id);
      }
      _prevGoalFractions[g.id] = g.fraction;
    }
    // D-042: resolve the plan's linked resources for the rows.
    final linkedItems = <int, Item>{};
    for (final it in items) {
      final id = it.itemId;
      if (id != null && !linkedItems.containsKey(id)) {
        try {
          linkedItems[id] = await widget.store.itemById(id);
        } catch (_) {
          // Deleted between generation and load: plain task.
        }
      }
    }
    // D-044: the routine templates ride along so the plan card
    // can EXPLAIN a missing Daily To-do section (created after
    // generation, or not scheduled today) instead of hiding it.
    final templates = await widget.todayStore.templates();
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
      linkedItems: linkedItems,
      weekSummary: weekSummary,
      templates: templates,
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

  /// D-045: the shared Quick Add capture workflow — the same
  /// operations the shell's Quick Add sheet runs.
  QuickAddService get _quickAdd => QuickAddService(
        store: widget.store,
        todayStore: widget.todayStore,
        learnStore: widget.learn.store,
        linkCards: LinkCardService(
            widget.store, widget.learn.store, widget.thumbnails),
      );

  Future<void> _quickAddTask() async {
    if (await quickAddTaskFlow(context, service: _quickAdd)) {
      await _afterPlanEdit();
      setState(_reload);
    }
  }

  /// D-045: the row's Note button runs the shared quick-note
  /// capture (Inbox project, title derived from the text),
  /// like the shell sheet — not the old picker chain.
  Future<void> _quickAddNote() async {
    await quickAddNoteFlow(
      context,
      service: _quickAdd,
      onOpenItem: (item) async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ItemDetailScreen(
              store: widget.store,
              item: item,
              learn: widget.learn,
              thumbnails: widget.thumbnails,
            ),
          ),
        );
        if (mounted) setState(_reload);
      },
    );
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
    // D-040: the Header group's element switches.
    const headerLabels = [
      (TodayStore.headerDate, 'Date label'),
      (TodayStore.headerEyebrow, 'Eyebrow line'),
      (TodayStore.headerHeading, 'Greeting heading'),
      (TodayStore.headerTagline, 'Tagline'),
    ];
    final result = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) {
        final values = Map<String, bool>.of(data.sections);
        return AlertDialog(
          title: const Text('Customize Home'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              final masterOn = values[TodayStore.headerGreeting] ?? true;
              // Scrollable: the Header group makes the dialog
              // taller than small screens are.
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Header',
                        style: Theme.of(context).textTheme.labelLarge),
                    SwitchListTile(
                      title: const Text('Show editorial greeting'),
                      value: masterOn,
                      onChanged: (v) => setDialogState(
                          () => values[TodayStore.headerGreeting] = v),
                    ),
                    for (final (key, label) in headerLabels)
                      SwitchListTile(
                        title: Text(label),
                        value: values[key] ?? true,
                        // Editable only while the master greeting
                        // is on (D-040).
                        onChanged: masterOn
                            ? (v) =>
                                setDialogState(() => values[key] = v)
                            : null,
                      ),
                    const Divider(),
                    Text('Sections',
                        style: Theme.of(context).textTheme.labelLarge),
                    for (final key in TodayStore.homeSections)
                      SwitchListTile(
                        title: Text(labels[key]!),
                        value: values[key] ?? true,
                        onChanged: (v) =>
                            setDialogState(() => values[key] = v),
                      ),
                  ],
                ),
              );
            },
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
      // BRAND (D-035): the static Nimo logo lives top-left in the
      // app's home header — same mark, same place, always.
      // D-040: the header also carries the streak chip (the
      // streak's one home now) and the Settings action, which
      // moved up from the intro's date row.
      appBar: AppBar(
        title: const NimoBrand(),
        actions: [
          FutureBuilder<_HubData>(
            future: _data,
            builder: (context, snap) => snap.hasData
                ? _streakChip(context, snap.data!.streak)
                : const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip:
                widget.onOpenSettings == null ? 'Coming soon' : 'Settings',
            onPressed: widget.onOpenSettings,
          ),
        ],
      ),
      body: FutureBuilder<_HubData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            // Skeleton after 150ms (spec §6) — local reads
            // usually land first and show nothing.
            return const Padding(
              padding: EdgeInsets.fromLTRB(
                  Space.page, Gap.md, Space.page, Gap.lg),
              child: DelayedSkeleton(skeleton: SkeletonList()),
            );
          }
          final data = snapshot.data!;
          // D-040: the greeting block renders only when its
          // master switch is on AND at least one element is —
          // hidden means NO placeholder and NO leftover gap:
          // each block below carries its own trailing spacing.
          bool on(String k) => data.sections[k] ?? true;
          final showIntro = on(TodayStore.headerGreeting) &&
              (on(TodayStore.headerDate) ||
                  on(TodayStore.headerEyebrow) ||
                  on(TodayStore.headerHeading) ||
                  on(TodayStore.headerTagline));
          final showWeek = on(TodayStore.sectionWeekStrip);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, Gap.lg),
            children: [
              if (showIntro) ...[
                _intro(context, now, data),
                const SizedBox(height: Gap.lg),
              ],
              if (data.weekSummary != null) ...[
                _sundaySummaryCard(context, data.weekSummary!),
                const SizedBox(height: Gap.lg),
              ],
              if (showWeek) ...[
                _dailyProgress(context, data),
                const SizedBox(height: Gap.md),
              ],
              _quickAddRow(context),
              const SizedBox(height: Gap.lg),
              if (_showWeek)
                _weekCard(context, data)
              else
                _planCard(context, data),
              const SizedBox(height: Gap.lg),
              _learnSection(context, data),
              const SizedBox(height: Gap.lg),
              _scoresSection(context, data),
              if (data.sections[TodayStore.sectionDayClose] ?? true) ...[
                const SizedBox(height: Gap.lg),
                _dayCloseSection(context, data),
              ],
              if (data.sections[TodayStore.sectionPinned] ?? true) ...[
                const SizedBox(height: Gap.lg),
                _pinnedSection(context, data),
              ],
              if (data.sections[TodayStore.sectionRecent] ?? true) ...[
                const SizedBox(height: Gap.lg),
                _recentSection(context, data),
              ],
              if (data.sections[TodayStore.sectionGoals] ?? true) ...[
                const SizedBox(height: Gap.lg),
                _goalsSection(context, data),
              ],
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

  /// The editorial greeting block (D-037, element switches
  /// D-040): date, eyebrow, greeting heading, tagline — each
  /// rendered only when its Customize Home switch is on, with
  /// the original rhythm kept between the parts that remain.
  /// The master switch and the all-off case are handled by
  /// the caller, which omits this block (and its spacing)
  /// entirely. Settings no longer lives here — it sits in the
  /// AppBar beside the streak chip.
  Widget _intro(BuildContext context, DateTime now, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    bool on(String k) => data.sections[k] ?? true;
    final parts = <Widget>[];
    void add(Widget part, double gapBefore) {
      if (parts.isNotEmpty) parts.add(SizedBox(height: gapBefore));
      parts.add(part);
    }

    if (on(TodayStore.headerDate)) {
      add(
        Text(
          // The concept's date chip: mono, uppercase.
          _formatDate(now).toUpperCase(),
          style: AppType.eyebrow.copyWith(
            fontSize: 10,
            letterSpacing: 1.2,
            color: scheme.onSurfaceVariant,
          ),
        ),
        0,
      );
    }
    if (on(TodayStore.headerEyebrow)) {
      add(const NeoEyebrow('A little intention goes a long way'), Gap.sm);
    }
    if (on(TodayStore.headerHeading)) {
      add(
        Text(_greeting(now), style: AppType.display(theme.textTheme)),
        Space.s3,
      );
    }
    if (on(TodayStore.headerTagline)) {
      add(
        Text(
          'Make room for what matters. One small step at a time.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Space.s2,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts,
    );
  }

  /// The header streak chip (D-040): the streak's one home on
  /// Today, beside the brand in the AppBar. Fed by the SAME
  /// hub load as everything else — no second calculation.
  /// Compact by design (mono micro-label, visually secondary
  /// to the brand); on narrow screens (< 360dp) it reduces to
  /// the flame and the number. A full-height tap target, and
  /// tapping opens Direction on its Progress tab, where the
  /// streak detail lives, when the shell provides the callback.
  Widget _streakChip(BuildContext context, StreakState streak) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = streak.currentStreak;
    final label = n == 1 ? '1 day' : '$n days';
    final narrow = MediaQuery.sizeOf(context).width < 360;
    return Semantics(
      container: true,
      button: widget.onOpenProgress != null,
      label: 'Current streak: $label'
          '${widget.onOpenProgress != null ? '. Opens Progress in Direction.' : ''}',
      child: InkWell(
        onTap: widget.onOpenProgress,
        borderRadius: BorderRadius.circular(RadiusToken.round),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_outlined,
                    size: 16, color: scheme.primary),
                const SizedBox(width: Space.s1),
                ExcludeSemantics(
                  child: Text(
                    narrow ? '$n' : label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Daily progress (D-040): the week strip alone. The streak
  /// row that used to head this block moved to the brand
  /// header chip — the same information is never shown twice.
  /// Shield detail remains in the scores section below and in
  /// Progress.
  Widget _dailyProgress(BuildContext context, _HubData data) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.only(top: Space.s3),
      child: _weekCells(context, data),
    );
  }

  /// Sunday weekly summary card (PROGRESS, S6 — §R2.3/§R5.4):
  /// takes over the top of Today on Sunday evening; dismissing
  /// is not needed because it simply stops being due on Monday,
  /// and the full summary lives in Progress afterwards.
  Widget _sundaySummaryCard(BuildContext context, WeeklySummary summary) {
    return NeoPanel(
      level: NeoSurfaceLevel.flat,
      padding: const EdgeInsets.symmetric(
          horizontal: Space.s6, vertical: Space.s2),
      onTap: widget.onOpenWeeklySummary == null
          ? null
          : () => widget.onOpenWeeklySummary!(summary.monday),
      child: NeoListRow(
        icon: Icons.auto_stories_outlined,
        title: 'Your week, wrapped up',
        sub: summary.isEmpty
            ? 'A quiet week — see the summary in Progress.'
            : 'You showed up ${summary.daysCounted} of 7 days'
                '${summary.shieldDays > 0 ? ' · ${summary.shieldDays} shield day${summary.shieldDays == 1 ? '' : 's'}' : ''}'
                '${summary.majorPoints.isNotEmpty ? ' · ${summary.majorPoints.length} major point${summary.majorPoints.length == 1 ? '' : 's'} captured' : ''}',
        last: true,
      ),
    );
  }

  /// The week cells alone (inside [_dailyProgress]).
  Widget _weekCells(BuildContext context, _HubData data) {
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
                      ? theme.colorScheme.secondary
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(children: [for (var i = 0; i < 7; i++) cell(i)]);
  }

  Widget _quickAddRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String label, VoidCallback onTap) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: NeoRaisedSm(
              level: NeoSurfaceLevel.flat,
              padding: const EdgeInsets.symmetric(vertical: Space.s3),
              onTap: onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(height: 2),
                  Text(label,
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
        );
    return Row(
      children: [
        button(Icons.add_task_outlined, 'Task', _quickAddTask),
        button(Icons.flag_outlined, 'Goal', _quickAddGoal),
        button(Icons.note_outlined, 'Note', _quickAddNote),
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

  /// Learn section (D-037, Neo "A moment to learn"): the plum
  /// learning card, the quiet Inbox line, and the Topics &
  /// Library doorway row. The Inbox count stays plain text —
  /// information, not a badge (§R9.5).
  Widget _learnSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeoSectionHead(
          title: 'A moment to learn',
          actionLabel: 'Your library →',
          onAction: widget.onOpenTopics,
        ),
        const SizedBox(height: Space.s3),
        _learningCard(context, data),
        const SizedBox(height: Space.s4),
        InkWell(
          onTap: widget.onOpenTopics,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s1),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined,
                    size: 16, color: scheme.primary),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Text(
                    data.inboxCount == 0
                        ? 'Your Inbox is clear — nothing waiting for a home.'
                        : '${data.inboxCount} waiting in your Inbox. '
                            'No rush, though.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s4),
        NeoListRow(
          icon: Icons.library_books_outlined,
          title: 'Topics & Library',
          sub: 'Topics, sources and marked points',
          onTap: widget.onOpenTopics,
          last: true,
        ),
      ],
    );
  }

  /// The learning card (D-039): the PAPER feature surface —
  /// the concept's signature light card inside the dark UI
  /// (in light mode it is the lightest paper). Serif headline,
  /// mono desk label, the round outline arrow starts a session
  /// directly (the ≤2-tap path); tapping the card goes to the
  /// Learn tab. All colours come from [EditorialColors] — the
  /// ambient scheme would be wrong on paper.
  Widget _learningCard(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final ed = EditorialColors.of(context);
    final total = data.dueCount + data.newCount;
    return FeaturePanel(
      kind: FeatureSurfaceKind.paper,
      onTap: widget.onOpenLearn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ON YOUR LEARNING DESK',
                  style: AppType.eyebrow.copyWith(color: ed.paperMuted),
                ),
              ),
              Icon(Icons.menu_book_outlined,
                  size: AppIconSize.md, color: ed.paperMuted),
            ],
          ),
          const SizedBox(height: Space.s5),
          Text(
            total == 0
                ? 'Import a pack to start learning.'
                : 'Your next session is ready.',
            style: AppType.pageTitle(theme.textTheme)
                ?.copyWith(color: ed.onPaper),
          ),
          const SizedBox(height: Space.s2),
          Text(
            total == 0
                ? 'Bring a PDF, text file, link or learning pack.'
                : '${data.dueCount} cards due to revisit · '
                    '${data.newCount} new to explore.',
            style: AppType.caption(theme.textTheme)
                ?.copyWith(color: ed.paperMuted),
          ),
          const SizedBox(height: Space.s6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Measured in enjoyment, not minutes.',
                  style: AppType.caption(theme.textTheme)
                      ?.copyWith(color: ed.paperMuted),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ed.onPaper.withValues(alpha: 0.35),
                  ),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.arrow_forward,
                      size: 18, color: ed.onPaper),
                  tooltip: 'Start a session',
                  onPressed:
                      total > 0 ? _openLearnSession : widget.onOpenLearn,
                ),
              ),
            ],
          ),
        ],
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

  /// "Quiet progress" (D-037): today's two scores in their inset
  /// wells — always side by side, never merged. Before Day Close
  /// both read as a quiet dash, exactly like the prototype.
  Widget _scoresSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final review = data.todayReview;
    final closed = review != null && review.isClosed;
    final streak = data.streak;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NeoSectionHead(title: 'Quiet progress'),
        const SizedBox(height: Space.s3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: NeoScoreWell(
                label: 'Done score · auto',
                value: closed && review.doneScore != null
                    ? '${review.doneScore}'
                    : '—',
                sub: 'Based on your core plan',
                suffix: ' / 100',
                fraction: closed && review.doneScore != null
                    ? review.doneScore! / 100
                    : null,
              ),
            ),
            const SizedBox(width: Space.s5),
            Expanded(
              child: NeoScoreWell(
                label: 'Self score · yours',
                value: closed && review.selfScore != null
                    ? '${review.selfScore}'
                    : '—',
                sub: closed ? 'Your own reflection' : 'Add yours at Day Close',
                accentValue: true,
                fraction: closed && review.selfScore != null
                    ? review.selfScore! / 10
                    : null,
              ),
            ),
          ],
        ),
        if (streak.shieldsHeld > 0) ...[
          const SizedBox(height: Space.s4),
          Row(
            children: [
              Icon(Icons.shield_outlined,
                  size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Text(
                  '${streak.shieldsHeld} Streak Shield'
                  '${streak.shieldsHeld == 1 ? '' : 's'} available · '
                  'a little room for life.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        if (streak.shieldsHeld > 0 && !streak.shieldsIntroShown) ...[
          const SizedBox(height: Space.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: NeoNotice(
                  "You've earned protection: a shield covers a missed "
                  'day, so one bad day never ends the streak '
                  '(max 2 shield-days a week).',
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
      ],
    );
  }

  /// Day Close (D-039): the concept's RULED BAND — hairlines
  /// above and below, a circled mark, a serif title, and one
  /// solid action button. Targets yesterday while the
  /// late-close window is open, without ever blocking today's
  /// close behind it.
  Widget _dayCloseSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final review = data.todayReview;
    final closed = review != null && review.isClosed;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outline),
          bottom: BorderSide(color: scheme.outline),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: Space.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outline),
                ),
                child: Icon(Icons.nightlight_outlined,
                    size: 17, color: scheme.primary),
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      closed
                          ? 'A day, gently closed.'
                          : 'Leave the day a little lighter.',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: Space.s1),
                    Text(
                      data.closeTarget.isLate
                          ? "Yesterday isn't closed yet — you can "
                              'still close it.'
                          : closed
                              ? 'Your reflection is here when you need it.'
                              : 'A two-minute check-in. Just for you.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s4),
          Wrap(
            spacing: Space.s3,
            runSpacing: Space.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: () => _openDayClose(data),
                child: Text(
                  data.closeTarget.isLate
                      ? 'Close yesterday'
                      : closed
                          ? 'Revisit reflection'
                          : 'Begin Day Close',
                ),
              ),
              // While the late window is open the primary action
              // closes yesterday — but today's close must never
              // be blocked behind it.
              if (data.closeTarget.isLate)
                TextButton(
                  onPressed: () => _openDayClose(
                    data,
                    date: DateTime.now(),
                    isLate: false,
                  ),
                  child: const Text('Close today instead'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planCard(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = data.items;
    final routines = items.where((e) => e.isRoutine).toList();
    final oneoffs = items.where((e) => !e.isRoutine).toList();
    final done = items.where((e) => e.done).length;
    // D-044: routines that exist but are NOT in today's plan —
    // the explanation the old UI never gave. `missing` were
    // created (or reactivated) after today's plan was generated
    // (tomorrow-by-default); `notToday` are scheduled for other
    // weekdays.
    final now = DateTime.now();
    final inPlan = {
      for (final e in items)
        if (e.templateId != null) e.templateId!,
    };
    final active = data.templates.where((t) => t.isActive).toList();
    final missing = active
        .where((t) => t.scheduledOn(now) && !inPlan.contains(t.id))
        .toList();
    final notToday =
        active.where((t) => !t.scheduledOn(now)).toList();
    // D-039: the plan is an editorial TIMELINE on the canvas —
    // a hairline rail through node marks (see _planRow). The
    // data model carries no clock times, so the rail shows
    // order and state, never invented times (Stage 0 call).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeoSectionHead(
          title: "Today's plan",
          actionLabel: 'Edit routine →',
          onAction: _openRoutineScreen,
        ),
        const SizedBox(height: Space.s3),
        Row(
          children: [
            Expanded(
              child: NeoTrack(
                  value: items.isEmpty ? 0 : done / items.length),
            ),
            const SizedBox(width: Space.s4),
            Text('$done of ${items.length} done',
                style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: Space.s4),
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
        const SizedBox(height: Space.s2),
        if (items.isEmpty && missing.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s4),
            child: Text(
                'Nothing planned yet. Add a task below, or build '
                'your routine template.',
                style: theme.textTheme.bodyMedium),
          )
        else ...[
          // D-042: the plan is SECTIONED by kind — Daily To-do
          // (routine templates) above, Today (one-offs) below —
          // one scrolling list, no second mode switch. The
          // Today/This week control above stays the only one.
          // D-044: the Daily To-do head now renders even with no
          // routine rows, carrying the explanation + the
          // add-to-today action instead of vanishing silently.
          if (routines.isNotEmpty)
            _planGroup(context, data, 'Daily To-do', routines)
          else ...[
            _groupHead(context, 'Daily To-do'),
            _routineNote(context, missing, notToday,
                noRoutinesAtAll: active.isEmpty),
          ],
          if (oneoffs.isNotEmpty) ...[
            const SizedBox(height: Space.s4),
            _planGroup(context, data, 'Today', oneoffs),
          ],
          if (routines.isNotEmpty &&
              (missing.isNotEmpty || notToday.isNotEmpty)) ...[
            const SizedBox(height: Space.s3),
            _routineNote(context, missing, notToday,
                noRoutinesAtAll: false),
          ],
        ],
        const SizedBox(height: Space.s4),
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
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          margin: const EdgeInsets.only(top: Space.s4),
          padding: const EdgeInsets.only(top: Space.s4),
          child: InkWell(
            onTap: () => _editIfThen(data),
            child: Row(
              children: [
                Icon(Icons.bolt_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Text(
                    data.ifThen.isEmpty
                        ? 'Set your if–then line: '
                            '"If …, then I will …"'
                        : data.ifThen,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: data.ifThen.isEmpty
                          ? scheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// One plan section (D-042): a mono group label with a
  /// hairline, then the group's rows on the timeline rail.
  Future<void> _openRoutineScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutineScreen(
            todayStore: widget.todayStore, store: widget.store),
      ),
    );
    setState(_reload);
  }

  static String _weekdayName(DateTime d) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][d.weekday - 1];

  /// D-044: add every scheduled-but-missing routine to today's
  /// plan (the explicit exception to tomorrow-by-default).
  Future<void> _addMissingToToday(List<PlanTemplate> missing) async {
    var added = 0;
    for (final t in missing) {
      final r = await widget.todayStore
          .addRoutineToToday(t.id, DateTime.now());
      if (r == AddRoutineResult.added) added++;
    }
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added == 1
            ? 'Routine added to today\'s plan.'
            : '$added routines added to today\'s plan.'),
      ));
    }
    await _afterPlanEdit();
    setState(_reload);
  }

  /// D-044: why the Daily To-do section is short or empty —
  /// always an explanation, never silence. [missing] routines
  /// start tomorrow by default and can be added explicitly;
  /// [notToday] routines are scheduled for other weekdays.
  Widget _routineNote(
    BuildContext context,
    List<PlanTemplate> missing,
    List<PlanTemplate> notToday, {
    required bool noRoutinesAtAll,
  }) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;
    String quoted(List<PlanTemplate> ts) =>
        ts.map((t) => '“${t.title}”').join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (noRoutinesAtAll)
            Text('No daily routines yet.', style: style)
          else ...[
            if (missing.isNotEmpty)
              Text(
                '${quoted(missing)} '
                '${missing.length == 1 ? 'starts' : 'start'} '
                'tomorrow — routines created after today\'s plan '
                'was made join from the next day.',
                style: style,
              ),
            if (notToday.isNotEmpty)
              Text(
                '${quoted(notToday)} '
                '${notToday.length == 1 ? "isn't" : "aren't"} '
                'scheduled for ${_weekdayName(DateTime.now())}s.',
                style: style,
              ),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: Space.s2),
            TextButton.icon(
              onPressed: () => _addMissingToToday(missing),
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text("Add to today's plan"),
            ),
          ] else if (noRoutinesAtAll) ...[
            const SizedBox(height: Space.s2),
            TextButton.icon(
              onPressed: _openRoutineScreen,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Set up routines'),
            ),
          ],
        ],
      ),
    );
  }

  /// The mono group head (D-042): eyebrow label + hairline.
  Widget _groupHead(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: AppType.eyebrow.copyWith(
            fontSize: 10,
            letterSpacing: 1.2,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: Space.s3),
        Expanded(
          child: Container(height: 1, color: scheme.outlineVariant),
        ),
      ],
    );
  }

  Widget _planGroup(BuildContext context, _HubData data, String label,
      List<DayPlanItem> group) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupHead(context, label),
        Stack(
          children: [
            Positioned(
              left: 5,
              top: 10,
              bottom: 10,
              child: Container(width: 1, color: scheme.outlineVariant),
            ),
            Column(
              children: [
                for (final item in group) _planRow(context, data, item),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// One plan row on the timeline: a node mark on the rail
  /// (filled when done), the title with its quiet
  /// classification line, a CARRIED tag when the item rolled
  /// over, delete for one-offs, and the circular check at the
  /// right — the row tap toggles; the check is its affordance.
  Widget _planRow(BuildContext context, _HubData data, DayPlanItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A11y (D-038 Stage 6): the row announces as a checkbox
    // with its state, not just a tappable text block.
    return Semantics(
      container: true,
      button: true,
      checked: item.done,
      label: item.title,
      child: InkWell(
        onTap: () async {
          await widget.todayStore.toggleItem(item);
          await _afterPlanEdit();
          setState(_reload);
        },
        // D-042: management lives in the sheet (long-press is
        // the accelerator; the ⋯ button is the visible path).
        onLongPress: () => _showPlanItemSheet(context, data, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.done ? scheme.primary : scheme.surface,
                  border: Border.all(
                    color: item.done ? scheme.primary : scheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration:
                            item.done ? TextDecoration.lineThrough : null,
                        color: item.done ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.isRoutine
                          ? (item.countsCore ? 'Routine · Core' : 'Routine')
                          : 'One-off',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (item.hasResource)
                      _resourceAction(context, data, item),
                  ],
                ),
              ),
              if (item.carried) ...[
                const SizedBox(width: Space.s3),
                const NeoTag('CARRIED', tint: true),
              ],
              // D-042: no permanent × — deletion lives in the
              // management sheet, behind a confirmation.
              IconButton(
                icon: const Icon(Icons.more_horiz, size: 20),
                tooltip: 'Task options',
                onPressed: () =>
                    _showPlanItemSheet(context, data, item),
              ),
              const SizedBox(width: Space.s2),
              NeoCheck(done: item.done),
            ],
          ),
        ),
      ),
    );
  }

  /// The row's resource action (D-042): derived from the
  /// link — never stored, never toggles completion. A link
  /// whose item has vanished renders nothing.
  Widget _resourceAction(
      BuildContext context, _HubData data, DayPlanItem item) {
    final scheme = Theme.of(context).colorScheme;
    final linked =
        item.itemId == null ? null : data.linkedItems[item.itemId];
    if (item.url == null && linked == null) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () async {
          await openPlanResource(
            context,
            url: item.url,
            item: linked,
            store: widget.store,
            learn: widget.learn,
            thumbnails: widget.thumbnails,
          );
          if (mounted) setState(_reload);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                resourceActionIcon(url: item.url, item: linked),
                size: 14,
                color: scheme.primary,
              ),
              const SizedBox(width: Space.s2),
              Text(
                resourceActionLabel(url: item.url, item: linked),
                style: AppType.eyebrow.copyWith(
                  fontSize: 10,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The task-management sheet (D-042) — the × button's
  /// replacement. Everything deliberate lives here: open the
  /// resource, retitle, link, remove. Deletion always
  /// confirms; removing a completed core routine names its
  /// streak consequence first (owner decision).
  Future<void> _showPlanItemSheet(
      BuildContext context, _HubData data, DayPlanItem item) async {
    final theme = Theme.of(context);
    final linked =
        item.itemId == null ? null : data.linkedItems[item.itemId];
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
              child: Text(item.title,
                  style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                item.isRoutine
                    ? (item.countsCore
                        ? 'Daily to-do · Core'
                        : 'Daily to-do')
                    : 'Today',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (item.url != null || linked != null)
              ListTile(
                leading: Icon(
                    resourceActionIcon(url: item.url, item: linked)),
                title: Text(resourceActionLabel(
                        url: item.url, item: linked)
                    .replaceAll(' →', '')),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await openPlanResource(
                    context,
                    url: item.url,
                    item: linked,
                    store: widget.store,
                    learn: widget.learn,
                    thumbnails: widget.thumbnails,
                  );
                  if (mounted) setState(_reload);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit title'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final title = await promptText(context,
                    title: 'Edit title',
                    label: 'Title',
                    initial: item.title);
                if (title == null ||
                    title.isEmpty ||
                    title == item.title) {
                  return;
                }
                await widget.todayStore.renamePlanItem(item.id, title);
                if (mounted) setState(_reload);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(
                  item.hasResource ? 'Change link' : 'Attach a link'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _attachLink(context, item);
              },
            ),
            if (item.hasResource)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Remove link'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await widget.todayStore.setPlanItemLink(item.id);
                  if (mounted) setState(_reload);
                },
              ),
            const Divider(),
            if (item.isRoutine) ...[
              ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Edit in Routine'),
                subtitle:
                    const Text('Changes every day, from tomorrow'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RoutineScreen(
                          todayStore: widget.todayStore,
                          store: widget.store),
                    ),
                  );
                  if (mounted) setState(_reload);
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Remove from today only'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _removeFromToday(context, item);
                },
              ),
            ] else
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: theme.colorScheme.error),
                title: Text('Delete task',
                    style:
                        TextStyle(color: theme.colorScheme.error)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _deleteOneOff(context, item);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// The attach flow (D-042): paste a link, or pick an
  /// existing Spaces item. Setting one clears the other —
  /// one resource per task.
  Future<void> _attachLink(BuildContext context, DayPlanItem item) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Paste a web or video link'),
              onTap: () => Navigator.pop(c, 'url'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text(
                  'Choose a note, link or quiz from Spaces'),
              onTap: () => Navigator.pop(c, 'item'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'url') {
      final controller = TextEditingController(text: item.url ?? '');
      final saved = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Web or video link'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
                labelText: 'URL', hintText: 'https://…'),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      final raw = controller.text.trim();
      controller.dispose();
      if (saved != true || !context.mounted) return;
      if (!isValidWebUrl(raw)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("That doesn't look like a valid web link.")));
        return;
      }
      await widget.todayStore.setPlanItemLink(item.id, url: raw);
    } else {
      final picked = await pickLinkItem(context, widget.store);
      if (picked == null) return;
      await widget.todayStore.setPlanItemLink(item.id, itemId: picked.id);
    }
    if (mounted) setState(_reload);
  }

  Future<bool> _confirmAction(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _deleteOneOff(BuildContext context, DayPlanItem item) async {
    final ok = await _confirmAction(
      context,
      title: 'Delete this task?',
      body: 'It will be removed from today and will not carry '
          'over to tomorrow.',
      action: 'Delete',
    );
    if (!ok) return;
    await widget.todayStore.deletePlanItem(item.id);
    await _afterPlanEdit();
    if (mounted) setState(_reload);
  }

  Future<void> _removeFromToday(
      BuildContext context, DayPlanItem item) async {
    // Owner decision (D-042): allowed, never silent — and a
    // completed CORE row carries the explicit consequence.
    final (title, body) = switch ((item.done, item.countsCore)) {
      (true, true) => (
          'Remove a completed core task?',
          'This task is done and counts toward today\'s core. '
              'Removing it recalculates today\'s Done Score from '
              'the remaining tasks — and today may stop counting '
              'toward your streak. The task stays in your '
              'routine and returns tomorrow.'
        ),
      (true, false) => (
          'Remove this task for today?',
          'It is done, so today\'s Done Score will be '
              'recalculated from the remaining tasks. The task '
              'stays in your routine and returns tomorrow.'
        ),
      _ => (
          'Remove this task for today?',
          'The task stays in your routine and returns tomorrow.'
        ),
    };
    final ok = await _confirmAction(context,
        title: title, body: body, action: 'Remove for today');
    if (!ok) return;
    await widget.todayStore.deletePlanItem(item.id);
    await _afterPlanEdit();
    if (mounted) setState(_reload);
  }

  Widget _weekCard(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    // D-039: the week view sits on the canvas like the plan.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.s4),
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
                    if (item.carried) const NeoTag('CARRIED', tint: true),
                  ],
                ),
              ),
          ],
        ],
    );
  }

  Widget _pinnedSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NeoSectionHead(title: 'Pinned spaces'),
        const SizedBox(height: Space.s3),
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
                NeoRaisedSm(
                  level: NeoSurfaceLevel.flat,
                  padding: const EdgeInsets.all(Space.s3),
                  onTap: () => widget.onOpenWorkspace(p.workspace),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: theme.colorScheme.outline),
                          borderRadius:
                              BorderRadius.circular(RadiusToken.sm),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          p.workspace.name.isEmpty
                              ? '?'
                              : p.workspace.name[0].toUpperCase(),
                          style: TextStyle(
                            fontFamily: fontSerif,
                            fontFamilyFallback: fontSerifFallback,
                            fontSize: 15,
                            color: theme.colorScheme.primary,
                          ),
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
            ],
          ),
      ],
    );
  }

  Widget _recentSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    // D-038: Recently touched sits DIRECTLY on the canvas
    // (Level 0) — hairline-divided rows under a section head,
    // no enclosing panel.
    return NeoSection(
      title: 'Recently touched',
      child: data.recent.isEmpty
          ? Text('Nothing yet — items you create will show up here.',
              style: theme.textTheme.bodyMedium)
          : Column(
              children: [
                for (final r in data.recent)
                  NeoListRow(
                    icon: itemTypeDef(r.item.type).icon,
                    title: r.item.title,
                    sub: '${r.workspaceName} · ${r.projectName}',
                    last: r == data.recent.last,
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
    );
  }

  Widget _goalsSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_justCompleted.isNotEmpty) {
      // Celebrate once: after this build, later rebuilds show
      // the badge statically.
      final shown = Set<int>.of(_justCompleted);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _justCompleted.removeAll(shown);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NeoSectionHead(title: 'A direction, not a deadline'),
        const SizedBox(height: Space.s3),
        if (data.goals.isEmpty)
          Text('No goals yet. Use Quick add → Goal to create one.',
              style: theme.textTheme.bodyMedium)
        else
          for (final goal in data.goals)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s3),
              child: NeoRaisedSm(
                padding: const EdgeInsets.all(Space.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const NeoGlyph(
                            icon: Icons.flag_outlined,
                            size: 36,
                            iconSize: 18),
                        const SizedBox(width: Space.s4),
                        Expanded(
                          child: Text(goal.title,
                              style: theme.textTheme.titleSmall),
                        ),
                        Text(
                          '${(goal.fraction * 100).round()}%',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: scheme.primary),
                        ),
                        if (goal.fraction >= 1) ...[
                          const SizedBox(width: Space.s3),
                          GoalCompletionBadge(
                            celebrate: _justCompleted.contains(goal.id),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Space.s4),
                    NeoTrack(value: goal.fraction),
                    const SizedBox(height: Space.s3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${goal.current} of ${goal.target}'
                            '${goal.unit.isEmpty ? '' : ' ${goal.unit}'}'
                            ' explored',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                        NeoStepperButton(
                          icon: Icons.remove,
                          tooltip: 'Decrease',
                          // Disabled at the bounds, matching the
                          // Goals tab (D-037 call 6).
                          onTap: goal.current <= 0
                              ? null
                              : () async {
                                  await widget.goalsStore.step(goal, -1);
                                  setState(_reload);
                                },
                        ),
                        const SizedBox(width: Space.s3),
                        NeoStepperButton(
                          icon: Icons.add,
                          tooltip: 'Increase',
                          onTap: goal.current >= goal.target
                              ? null
                              : () async {
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

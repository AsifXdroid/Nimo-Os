/// TODAY — Hub Home (S2, layout per D-009).
///
/// Sections, in order: header (date, greeting, search/settings
/// placeholders — global search is S5, settings is S6), week strip,
/// quick-add row, today's plan card (or the This-week pending view),
/// pinned spaces, recent items, goals. Which of the
/// optional sections show is persisted in `app_settings`.
library;

import 'package:flutter/material.dart';

import '../../core/glass_ui.dart';
import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/spatial_ui.dart';
import '../../core/theme.dart';
import '../goals/goals_store.dart';
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
import 'daily_todo_screen.dart';
import 'agenda_screen.dart';
import 'dua_library_screen.dart';
import 'plan_list.dart';
import 'routine_screen.dart';
import 'today_store.dart';

/// Everything Hub Home renders, loaded in one pass.
class _HubData {
  _HubData({
    required this.items,
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
    this.manualFocus,
  });

  final List<DayPlanItem> items;
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

  /// Mission 03 Phase 3: the VALIDATED manual focus selection
  /// for today (null = automatic focus). Validation happened in
  /// _load(): a stored selection that is stale, completed,
  /// deleted or foreign never reaches this field.
  final DayPlanItem? manualFocus;
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

  /// Called when a pinned space is tapped: the shell pushes
  /// the workspace's Projects screen. The future completes
  /// when that route pops, so Home can refresh.
  final Future<void> Function(Workspace workspace) onOpenWorkspace;

  /// Opens the Learn tab (the shell selects the Library
  /// destination, whose default tab is Learn).
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

  /// Goal-completion tracking (D-038 Stage 6, Tier 3): the
  /// previous fraction per goal, and the goals that crossed
  /// to complete on the latest load (celebrated once).
  final Map<int, double> _prevGoalFractions = {};
  final Set<int> _justCompleted = {};

  /// Redesign R2: the pinned status bar appears once the
  /// compact hero zone has scrolled away.
  final ScrollController _scrollController = ScrollController();
  bool _pinnedBarVisible = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reloadPlan();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.hasClients && _scrollController.offset > 96;
    if (show != _pinnedBarVisible) {
      setState(() => _pinnedBarVisible = show);
    }
  }

  /// Reload after today's PLAN changed (complete/uncomplete,
  /// add, remove, delete, rename, attach), and on return
  /// from the Daily To-do screen (Phase 4).
  void _reloadPlan() {
    _data = _load();
  }

  /// Reload for anything else (customize, hero image, goals,
  /// notes, returning from another screen).
  void _refresh() {
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
    final weekSummary = (widget.progressStore != null && sundaySummaryDue(now))
        ? await widget.progressStore!.weeklySummary(now, now: now)
        : null;
    // Mission 03 Phase 3: validate the stored manual focus
    // selection against today's plan. Valid = stored for TODAY
    // and its sync_id names an INCOMPLETE item in today's plan.
    // Anything else (another day, completed, deleted, foreign,
    // malformed) is cleared here — storage heals itself on load —
    // and focus falls back to the first incomplete item.
    DayPlanItem? manualFocus;
    final selection = await widget.todayStore.focusSelection();
    if (selection != null) {
      if (selection.dateKey == TodayStore.dateKey(now)) {
        for (final it in items) {
          if (!it.done && it.syncId == selection.syncId) {
            manualFocus = it;
            break;
          }
        }
      }
      if (manualFocus == null) {
        await widget.todayStore.clearFocusSelection();
      }
    }
    return _HubData(
      items: items,
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
      manualFocus: manualFocus,
    );
  }

  // ------------------------------------------------------------ actions

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    // Today has NO AppBar — the brand row lives inside the
    // hero and scrolls away with it. The shell's bottom
    // capsule navigation is untouched and stays fixed.
    return Scaffold(
      body: FutureBuilder<_HubData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // B-11: a failed load is an error state with a
            // retry, never an endless skeleton.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Today could not be loaded. '
                      'Your records are unchanged.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Gap.md),
                    FilledButton(
                      onPressed: () => setState(_reloadPlan),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            // Skeleton after 150ms (spec §6) — local reads
            // usually land first and show nothing.
            return const Padding(
              padding: EdgeInsets.fromLTRB(
                Space.page,
                Gap.md,
                Space.page,
                Gap.lg,
              ),
              child: DelayedSkeleton(skeleton: SkeletonList()),
            );
          }
          final data = snapshot.data!;
          bool on(String k) => data.sections[k] ?? true;
          final showWeek = on(TodayStore.sectionWeekStrip);
          // Mission 03 Phase 3: a closed day shows no actionable
          // Focus Now panel (same isClosed signal the scores use).
          final closedToday = data.todayReview?.isClosed ?? false;
          // The hero spans the full width; everything below it
          // keeps the page margin.
          Widget pad(Widget w) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            child: w,
          );
          // Redesign R2: the photo hero is replaced by the
          // compact status zone (hero research, 2026-11-13):
          // the date promoted, the streak as a compact data
          // chip, a pre-rendered dawn tint behind them, and a
          // pinned bar that takes over on scroll carrying the
          // agenda and settings actions. No wordmark, no
          // photograph, no greeting block.
          return Stack(
            children: [
              ListView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 110.0),
                children: [
                  _statusZone(context, data),
                  if (data.streak.shieldsHeld > 0) ...[
                    const SizedBox(height: Gap.md),
                    pad(_shieldNote(context, data.streak)),
                  ],
                  const SizedBox(height: Gap.md),
                  pad(_ifThenControl(context, data)),
                  const SizedBox(height: Gap.md),
                  if (data.weekSummary != null) ...[
                    pad(_sundaySummaryCard(context, data.weekSummary!)),
                    const SizedBox(height: Gap.lg),
                  ],
                  if (showWeek) ...[
                    pad(_dailyProgress(context, data)),
                    const SizedBox(height: Gap.md),
                  ],
                  // Mission 03 Phase 3: the Focus Now panel
                  // (Phase 2 reserved this position: hero →
                  // Focus → Quick Capture → preview). Hidden
                  // when the day is closed or the plan is
                  // empty; a slim state when all is done.
                  if (!closedToday && data.items.isNotEmpty) ...[
                    pad(_focusPanel(context, data)),
                    const SizedBox(height: Gap.lg),
                  ],
                  // Quick actions are optional (Customize Home):
                  // hidden means the row AND its spacing vanish,
                  // so the plan moves up into the space.
                  // Mission 03 Phase 1: the plan card always
                  // renders — the This Week swap is removed.
                  pad(_planCard(context, data)),
                  const SizedBox(height: Gap.lg),
                  pad(_viewFullPlanEntry(context)),
                  if (data.dueCount + data.newCount > 0) ...[
                    const SizedBox(height: Gap.lg),
                    pad(_learnSection(context, data)),
                  ],
                  const SizedBox(height: Gap.lg),
                  pad(_duaEntry(context)),
                  const SizedBox(height: Gap.lg),
                  pad(_scoresSection(context, data)),
                  if (data.sections[TodayStore.sectionDayClose] ?? true) ...[
                    const SizedBox(height: Gap.lg),
                    pad(_dayCloseSection(context, data)),
                  ],
                  // Library merge (2026-11-12): Organise lives
                  // in the Library destination now. What stays
                  // on Today is the pinned-workspace shortcuts
                  // at the foot of the page — rendered only
                  // when the stored 'Pinned spaces' value is on
                  // and at least one workspace is pinned.
                  if ((data.sections[TodayStore.sectionPinned] ?? true) &&
                      data.pinned.isNotEmpty) ...[
                    const SizedBox(height: Gap.lg),
                    pad(_organiseSection(context, data)),
                  ],
                ],
              ),
              _pinnedBar(context, data),
            ],
          );
        },
      ),
    );
  }

  /// The pinned-workspace shortcuts (UX Phase 4, reshaped by
  /// the Library merge, 2026-11-12). Organise itself lives in
  /// the Library destination; what remains here is one row
  /// per pinned workspace — a one-tap deep link to its
  /// Projects, which no tab can match. The build gates this
  /// section on the stored 'Pinned spaces' value and a
  /// non-empty pinned list. A tap refreshes Home when the
  /// route pops, so item changes inside the workspace show
  /// immediately on return.
  Widget _organiseSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: planSurfaceDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 0),
            child: Text(
              'Pinned spaces',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final (i, p) in data.pinned.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: Space.s4,
                endIndent: Space.s4,
                color: scheme.outlineVariant,
              ),
            Semantics(
              key: ValueKey('pinned_workspace_${p.workspace.id}'),
              button: true,
              label:
                  'Open ${p.workspace.name}, '
                  '${p.itemCount} ${p.itemCount == 1 ? 'item' : 'items'}',
              child: ExcludeSemantics(
                child: InkWell(
                  onTap: () async {
                    await widget.onOpenWorkspace(p.workspace);
                    if (mounted) {
                      setState(() {
                        _data = _load();
                      });
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.s4,
                      vertical: Space.s3,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder, size: 20, color: scheme.primary),
                        const SizedBox(width: Space.s3),
                        Expanded(
                          child: Text(
                            p.workspace.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${p.itemCount} '
                          '${p.itemCount == 1 ? 'item' : 'items'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// D-053: Today's floating-surface decoration — translucent
  /// charcoal with the #363636 hairline and a soft lift in
  /// dark; the D-052 scheme surface in light (the charcoal
  /// system is dark-only). Used by the plan groups, the Learn
  /// strip and the Sunday card so the page reads as layered
  /// surfaces over the environment, not stacked opaque cards.
  /// Mission 03 Phase 3: pure focus resolution. A validated
  /// manual selection wins; otherwise the first incomplete item
  /// in plan order. Reads only — never reorders the plan or the
  /// preview. Null when nothing is incomplete.
  DayPlanItem? _resolveFocus(_HubData data) {
    final manual = data.manualFocus;
    if (manual != null) return manual;
    for (final it in data.items) {
      if (!it.done) return it;
    }
    return null;
  }

  /// Mission 03 Phase 3: the Focus Now panel. One task, two
  /// actions. Done reuses the plan rows' shared completion path
  /// (togglePlanItemWithUndo: toggle + _afterPlanEdit +
  /// _reloadPlan, with Undo); Change opens the picker sheet.
  /// All-done is a slim, action-free state.
  Widget _focusPanel(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final focus = _resolveFocus(data);
    return Container(
      key: const ValueKey('focus_panel'),
      decoration: _surfaceDeco(context),
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FOCUS NOW',
            style: AppType.eyebrow.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: Space.s2),
          if (focus == null)
            Text(
              'Everything is done for today.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              focus.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  focus.isRoutine
                      ? (focus.countsCore ? 'Routine · Core' : 'Routine')
                      : 'One-off',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (focus.carried) ...[
                  const SizedBox(width: Space.s2),
                  const NeoTag('CARRIED', tint: true),
                ],
              ],
            ),
            if (focus.hasResource)
              planResourceAction(
                context,
                item: focus,
                linkedItems: data.linkedItems,
                store: widget.store,
                learn: widget.learn,
                thumbnails: widget.thumbnails,
                onOpened: () {
                  if (mounted) setState(_refresh);
                },
              ),
            if (data.manualFocus != null) ...[
              const SizedBox(height: Space.s2),
              Text(
                'Chosen by you',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
            const SizedBox(height: Space.s3),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => togglePlanItemWithUndo(
                    context,
                    todayStore: widget.todayStore,
                    item: focus,
                    onChanged: () async {
                      await _afterPlanEdit();
                      if (mounted) setState(_reloadPlan);
                    },
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Done'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
                const SizedBox(width: Space.s2),
                OutlinedButton(
                  onPressed: () => _showFocusPicker(context, data),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Change'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Mission 03 Phase 3: the Change sheet — every incomplete
  /// task in plan order, "Automatic (first task)" first.
  /// Picking a task stores its sync_id for today and refreshes
  /// WITHOUT touching plan state (the Phase 2 preview keeps its
  /// expansion and its order); Automatic clears the selection.
  /// Dismissing the sheet changes nothing.
  final Object _automaticPick = Object();

  Future<void> _showFocusPicker(BuildContext context, _HubData data) async {
    final open = data.items.where((e) => !e.done).toList();
    final current = _resolveFocus(data);
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s4,
                    Space.s4,
                    Space.s4,
                    Space.s2,
                  ),
                  child: Text(
                    'Choose your focus',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  key: const ValueKey('focus_pick_automatic'),
                  leading: const Icon(Icons.auto_awesome, size: 20),
                  title: const Text('Automatic (first task)'),
                  trailing: data.manualFocus == null
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(_automaticPick),
                ),
                for (final item in open)
                  ListTile(
                    key: ValueKey('focus_pick_${item.id}'),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(item.isRoutine ? 'Routine' : 'One-off'),
                    trailing: current?.id == item.id
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(item),
                  ),
                const SizedBox(height: Space.s2),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted) return;
    if (picked == null) return; // dismissed — no change
    if (identical(picked, _automaticPick)) {
      if (data.manualFocus != null) {
        await widget.todayStore.clearFocusSelection();
        if (!context.mounted) return;
        setState(_refresh);
      }
      return;
    }
    final item = picked as DayPlanItem;
    final syncId = item.syncId;
    if (syncId == null) return;
    await widget.todayStore.setFocusSelection(DateTime.now(), syncId);
    if (!context.mounted) return;
    setState(_refresh);
  }

  BoxDecoration _surfaceDeco(
    BuildContext context, {
    double radius = RadiusToken.card,
  }) => planSurfaceDeco(context, radius: radius);

  /// Redesign R2: the compact status zone that opens Today.
  /// The hero research (2026-11-13) gives the top of a daily
  /// app four jobs: orientation (the date, promoted), a
  /// glanceable status (the streak, as compact data), one or
  /// two essential actions (they live in the pinned bar, not
  /// here), and a little tone (a pre-rendered dawn tint —
  /// gradients only, never a photograph or a live blur). The
  /// zone is the status-bar inset plus 88dp of content.
  Widget _statusZone(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      height: topInset + 112,
      padding: EdgeInsets.fromLTRB(
        Space.page,
        topInset + Space.s2,
        Space.page,
        Space.s2,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0C2314), Color(0xFF07170D), Color(0xFF000000)]
              : [
                  scheme.surfaceContainerLow,
                  scheme.surfaceContainerLow,
                  theme.scaffoldBackgroundColor,
                ],
          stops: const [0.0, 0.52, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weekdayName(now),
                        style: theme.textTheme.headlineLarge,
                      ),
                      Text(
                        '${now.day} ${monthNames[now.month - 1]}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _streakChip(context, data.streak),
              ],
            ),
          ),
          // The agenda and settings doors live here at
          // rest, in the zone's top-right corner — a short
          // day may never scroll far enough to reveal the
          // pinned bar's copies.
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Agenda',
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: _openAgenda,
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: widget.onOpenSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Redesign R2: the pinned status bar. It takes over when
  /// the status zone scrolls away: short date, the streak
  /// chip, and the two essential actions (agenda, settings)
  /// the research moved out of the hero. Hidden from
  /// semantics and touches while invisible.
  Widget _pinnedBar(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ExcludeSemantics(
        excluding: !_pinnedBarVisible,
        child: IgnorePointer(
          ignoring: !_pinnedBarVisible,
          child: AnimatedOpacity(
            opacity: _pinnedBarVisible ? 1 : 0,
            duration: motionDuration(context, Motion.micro),
            child: Container(
              height: topInset + 56,
              padding: EdgeInsets.fromLTRB(Space.page, topInset, Space.s2, 0),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${weekdayName(now).substring(0, 3)} ${now.day} '
                    '${monthNames[now.month - 1].substring(0, 3)}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(width: Space.s3),
                  _streakChip(context, data.streak),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.calendar_month_outlined),
                    tooltip: 'Agenda',
                    onPressed: _openAgenda,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: widget.onOpenSettings == null
                        ? 'Coming soon'
                        : 'Settings',
                    onPressed: widget.onOpenSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Baseline B-03: the shield, explained in words on Today.
  /// Shown only while the owner actually holds a shield.
  Widget _shieldNote(BuildContext context, StreakState streak) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = streak.shieldsHeld;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: scheme.primary),
        const SizedBox(width: Space.s3),
        Expanded(
          child: Text(
            n == 1
                ? '1 shield ready. It covers a missed day '
                      'automatically, so one missed day will not '
                      'break your streak.'
                : '$n shields ready. They cover missed days '
                      'automatically, so a missed day will not '
                      'break your streak.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _ifThenControl(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = data.ifThen.isEmpty;
    final radius = BorderRadius.circular(RadiusToken.card + 2);
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _editIfThen(data),
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            // Mission 03 Phase 2: vertical padding s3 → s2
            // as part of the ~25% hero reduction (see
            // _heroIntro); at 390dp wide this also absorbs
            // the last 2.8px of hero-column overflow the
            // shorter hero left at that width.
            vertical: Space.s2,
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Text(
                  empty
                      ? 'Set your if–then line: '
                            '"If …, then I will …"'
                      : data.ifThen,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.edit_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The header streak chip (D-040): the streak's one home on
  /// Today, in the status zone and its pinned bar. Fed by the
  /// SAME hub load as everything else — no second calculation.
  /// Compact by design (mono micro-label, visually secondary);
  /// on narrow screens (< 400dp) it reduces to the flame and
  /// the number. A full-height tap target, and tapping opens
  /// Direction on its Progress tab, where the streak detail
  /// lives, when the shell provides the callback.
  Widget _streakChip(BuildContext context, StreakState streak) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = streak.currentStreak;
    final label = n == 1 ? '1 day' : '$n days';
    final narrow = MediaQuery.sizeOf(context).width < 400;
    final body = SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_outlined,
              size: 16,
              color: scheme.primary,
            ),
            const SizedBox(width: Space.s1),
            ExcludeSemantics(
              child: Text(
                narrow ? '$n' : label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      button: widget.onOpenProgress != null,
      label:
          'Current streak: $label'
          '${widget.onOpenProgress != null ? '. Opens Journey in Progress.' : ''}',
      child: InkWell(
        onTap: widget.onOpenProgress,
        borderRadius: BorderRadius.circular(RadiusToken.round),
        child: body,
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
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
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
    // D-053: same floating charcoal surface as the plan
    // groups (was a flat NeoPanel).
    return Container(
      decoration: _surfaceDeco(context),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onOpenWeeklySummary == null
              ? null
              : () => widget.onOpenWeeklySummary!(summary.monday),
          borderRadius: BorderRadius.circular(RadiusToken.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s6,
              vertical: Space.s2,
            ),
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
          ),
        ),
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
        // Mission 03 Phase 1: display-only. The tap that
        // switched Today into the week view is removed with
        // the week view; the strip and its pending dots stay.
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
      );
    }

    return Row(children: [for (var i = 0; i < 7; i++) cell(i)]);
  }

  Future<void> _openDayClose(
    _HubData data, {
    DateTime? date,
    bool? isLate,
  }) async {
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
    setState(_refresh);
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
    setState(_refresh);
  }

  /// Compact contextual learn section: shown only when questions are due or new.
  Widget _learnSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeoSectionHead(
          title: 'Review due',
          actionLabel: 'Learn →',
          onAction: widget.onOpenLearn,
        ),
        const SizedBox(height: Space.s2),
        Container(
          decoration: _surfaceDeco(context),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            children: [
              Icon(Icons.school_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data.dueCount} cards due · ${data.newCount} new',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Spaced repetition review ready',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: _openLearnSession,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Start →'),
              ),
            ],
          ),
        ),
      ],
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
    setState(_refresh);
  }

  /// Core C2: "Your Spiritual Space" — a dedicated square tile
  /// for the Dua Library, as wide as one score well. It opens
  /// the library directly (no intermediate screen) and renders
  /// in every plan state, so the library stays reachable when
  /// the plan is empty or all done. It takes its space below
  /// the plan card; the scores keep their own section (C3).
  /// UX Phase 5: the permanent View Full Plan entry —
  /// rendered in EVERY plan state (empty, partial, all
  /// done), where the old conditional buttons vanished.
  /// Same surface language as the Organise entry below.
  Widget _viewFullPlanEntry(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: planSurfaceDeco(context),
      child: Semantics(
        key: const ValueKey('view_full_plan_entry'),
        button: true,
        label: 'View full plan',
        child: ExcludeSemantics(
          child: InkWell(
            onTap: _openDailyTodo,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s4,
                vertical: Space.s3,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.format_list_bulleted,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Text(
                      'View Full Plan',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// UX Phase 5: the Dua Library entry is a compact row
  /// now (Core C2's square tile retired — it overflowed at
  /// 360dp in C5 and cost a whole line of the page). Same
  /// library, same data, same destination; the tile's two
  /// lines become the row's title and quiet subtitle.
  Widget _duaEntry(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: planSurfaceDeco(context),
      child: Semantics(
        key: const ValueKey('dua_library_entry'),
        button: true,
        label: 'Open Dua Library',
        child: ExcludeSemantics(
          child: InkWell(
            onTap: _openDuaLibrary,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s4,
                vertical: Space.s3,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dua Library',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Your Spiritual Space',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Quiet progress" (D-037): today's two scores — always
  /// side by side, never merged into one number.
  /// Core C3 (owner-confirmed 2026-11-09): ONE shared card
  /// shows the pair normalised to a common /10 reading —
  /// first = Done (auto), second = Self (yours) — with the
  /// labels kept and NO denominator printed. This is
  /// presentation only: the stored scores, their separate
  /// calculations and the gauge fractions (Done/100,
  /// Self/10) are exactly as before. Before Day Close both
  /// read as a quiet dash, exactly like the prototype.
  Widget _scoresSection(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final review = data.todayReview;
    final closed = review != null && review.isClosed;
    final streak = data.streak;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NeoSectionHead(title: 'Quiet progress'),
        const SizedBox(height: Space.s3),
        SpatialCard(
          key: const ValueKey('quiet_progress_pair'),
          elevation: SpatialDepth.elevated,
          borderRadius: 14,
          padding: const EdgeInsets.all(Space.s3),
          enablePerspective: true,
          // D-053: charcoal in dark (was the spatial
          // kit's default surface).
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? GlassTokens.darkCharcoalSolid
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: NeoScoreWell(
                  label: 'Done score · auto',
                  value: closed && review.doneScore != null
                      ? '${(review.doneScore! / 10).round()}'
                      : '—',
                  sub: 'Based on your core plan',
                  suffix: '',
                  fraction: closed && review.doneScore != null
                      ? review.doneScore! / 100
                      : null,
                ),
              ),
              const SizedBox(width: Space.s3),
              Text(
                '/',
                style: AppType.statistic(size: 20)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: NeoScoreWell(
                  label: 'Self score · yours',
                  value: closed && review.selfScore != null
                      ? '${review.selfScore}'
                      : '—',
                  sub: closed
                      ? 'Your own reflection'
                      : 'Add yours at Day Close',
                  suffix: '',
                  accentValue: true,
                  fraction: closed && review.selfScore != null
                      ? review.selfScore! / 10
                      : null,
                ),
              ),
            ],
          ),
        ),
        if (streak.shieldsHeld > 0) ...[
          const SizedBox(height: Space.s4),
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Text(
                  '${streak.shieldsHeld} Streak Shield'
                  '${streak.shieldsHeld == 1 ? '' : 's'} available · '
                  'a little room for life.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
                  setState(_refresh);
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
    final ed = EditorialColors.of(context);
    final review = data.todayReview;
    final closed = review != null && review.isClosed;
    // D-052: the Day Close invitation is the prototype's
    // closing card — the deep-green feature panel, one bright
    // action. (Was the D-039 ruled band.)
    return Container(
      decoration: BoxDecoration(
        color: ed.deep,
        borderRadius: BorderRadius.circular(RadiusToken.card),
      ),
      padding: const EdgeInsets.all(Space.s5),
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
                  border: Border.all(color: ed.deepLine),
                ),
                child: Icon(
                  Icons.nightlight_outlined,
                  size: 17,
                  color: ed.deepAccent,
                ),
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      closed ? 'A day, gently closed.' : 'Close your day',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: ed.onDeep,
                      ),
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
                        color: ed.deepMuted,
                      ),
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
                style: FilledButton.styleFrom(
                  backgroundColor: ed.deepAccent,
                  foregroundColor: ed.onDeepAccent,
                ),
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
                  onPressed: () =>
                      _openDayClose(data, date: DateTime.now(), isLate: false),
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
    final items = data.items;
    // Mission 03 Phase 2: the card no longer splits items by
    // kind — the preview is one flat list in plan order (see
    // the Builder below). Kind counts are not needed here.
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
    final notToday = active.where((t) => !t.scheduledOn(now)).toList();
    // D-039: the plan is an editorial TIMELINE on the canvas —
    // a hairline rail through node marks (see _planRow). The
    // data model carries no clock times, so the rail shows
    // order and state, never invented times (Stage 0 call).
    return Column(
      key: const ValueKey('focus_plan_anchor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeoSectionHead(
          title: "Today's plan",
          actionLabel: 'Routines →',
          onAction: _openRoutineScreen,
        ),
        const SizedBox(height: Space.s3),
        Row(
          children: [
            Expanded(
              child: NeoTrack(value: items.isEmpty ? 0 : done / items.length),
            ),
            const SizedBox(width: Space.s4),
            Text(
              '$done of ${items.length} done',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        if (items.isEmpty && missing.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s4),
            child: Text(
              'Nothing planned yet. Use the + button to add a '
              'task, or build your routine template.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else ...[
          // Mission 03 Phase 2 (decision A): the card is now a
          // compact PREVIEW. One flat list of INCOMPLETE items
          // in plain plan order — carried-over and fresh items
          // interleaved exactly as stored (position, id) — with
          // no kind group heads. At most 4 rows show; "See all"
          // navigates to the Daily To-do screen (Phase 4).
          // Completed items
          // leave the list; the done-track above still counts
          // the whole day. The grouped full-plan rendering
          // returns with the Daily To-do screen in Phase 4.
          Builder(
            builder: (context) {
              final open = items.where((e) => !e.done).toList();
              if (open.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s4),
                  child: Text(
                    items.isEmpty
                        ? 'Nothing planned yet. Use the + button to '
                              'add a task, or build your routine '
                              'template.'
                        : 'Everything is done for today.',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              final shown = open.take(4).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlanList(
                    label: null,
                    items: shown,
                    linkedItems: data.linkedItems,
                    todayStore: widget.todayStore,
                    store: widget.store,
                    learn: widget.learn,
                    thumbnails: widget.thumbnails,
                    onMutated: () async {
                      await _afterPlanEdit();
                      if (mounted) setState(_reloadPlan);
                    },
                    onReload: () {
                      if (mounted) setState(_reloadPlan);
                    },
                    onRefresh: () {
                      if (mounted) setState(_refresh);
                    },
                  ),
                  // UX Phase 5: the conditional door buttons
                  // that used to sit here ('See all', 'Tasks',
                  // 'Agenda') are gone — View Full Plan is a
                  // permanent entry below the card, Agenda is
                  // the header calendar, and Tasks lives in
                  // the Full Plan's third tab. What remains is
                  // the honest signal that the preview is
                  // truncated: a plain count, not a button.
                  if (open.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s3),
                      child: Text(
                        '+${open.length - 4} more '
                        '${open.length - 4 == 1 ? 'task' : 'tasks'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (missing.isNotEmpty || notToday.isNotEmpty) ...[
            const SizedBox(height: Space.s3),
            routineNote(
              context,
              missing: missing,
              notToday: notToday,
              noRoutinesAtAll: active.isEmpty,
              onAddMissing: _addMissingToToday,
              onOpenRoutines: _openRoutineScreen,
            ),
          ],
        ],
      ],
    );
  }

  /// One plan section (D-042): a mono group label with a
  /// hairline, then the group's rows on the timeline rail.
  /// Mission 03 Phase 4: the preview's "See all" opens the
  /// full Daily To-do screen; the plan may have changed
  /// there, so returning reloads it.
  Future<void> _openRoutineScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RoutineScreen(todayStore: widget.todayStore, store: widget.store),
      ),
    );
    setState(_reloadPlan);
  }

  Future<void> _openDailyTodo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailyTodoScreen(
          todayStore: widget.todayStore,
          store: widget.store,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
          reviewStore: widget.reviewStore,
        ),
      ),
    );
    setState(_reloadPlan);
  }

  /// Mission 03 Phase 5 (D7, owner-confirmed): the Tasks
  /// collection opens from Today's plan card — the shell
  /// keeps its four destinations. One-offs may have been
  /// completed, renamed or deleted there, so returning
  /// reloads the plan.
  Future<void> _openAgenda() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgendaScreen(
          todayStore: widget.todayStore,
          store: widget.store,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
          reviewStore: widget.reviewStore,
        ),
      ),
    );
    setState(_reloadPlan);
  }

  /// Mission 03 Phase 7: the Dua Library entry point.
  /// Core C2: it opens from the dedicated square tile below
  /// the plan card (the shell keeps its four destinations).
  Future<void> _openDuaLibrary() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DuaLibraryScreen(
          store: widget.store,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
        ),
      ),
    );
  }

  /// UX Phase 2: the plan card's Tasks entry opens the Full
  /// Plan on its Open Tasks tab — the standalone Tasks
  /// screen retired once the tab reached parity (the Phase 2
  /// parity tests are the proof).
  /// D-044: add every scheduled-but-missing routine to today's
  /// plan (the explicit exception to tomorrow-by-default).
  Future<void> _addMissingToToday(List<PlanTemplate> missing) async {
    var added = 0;
    for (final t in missing) {
      final r = await widget.todayStore.addRoutineToToday(t.id, DateTime.now());
      if (r == AddRoutineResult.added) added++;
    }
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added == 1
                ? 'Routine added to today\'s plan.'
                : '$added routines added to today\'s plan.',
          ),
        ),
      );
    }
    await _afterPlanEdit();
    setState(_reloadPlan);
  }
}

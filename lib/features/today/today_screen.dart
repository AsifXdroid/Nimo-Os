/// TODAY — Hub Home (S2, layout per D-009).
///
/// Sections, in order: header (date, greeting, search/settings
/// placeholders — global search is S5, settings is S6), week strip,
/// quick-add row, today's plan card (or the This-week pending view),
/// pinned spaces, recent items, goals, Customize Home. Which of the
/// optional sections show is persisted in `app_settings`.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/brand.dart';
import '../../core/glass_ui.dart';
import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/spatial_ui.dart';
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
import 'daily_todo_screen.dart';
import 'agenda_screen.dart';
import 'tasks_screen.dart';
import 'plan_list.dart';
import 'routine_screen.dart';
import 'today_store.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
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
    this.heroImagePath,
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

  /// D-053: the resolved custom hero image path (null = the
  /// shipped default photograph). Resolved at load — the file
  /// must exist, or the default quietly takes over.
  final String? heroImagePath;

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

  /// Goal-completion tracking (D-038 Stage 6, Tier 3): the
  /// previous fraction per goal, and the goals that crossed
  /// to complete on the latest load (celebrated once).
  final Map<int, double> _prevGoalFractions = {};
  final Set<int> _justCompleted = {};

  @override
  void initState() {
    super.initState();
    _reloadPlan();
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
    // D-053: resolve the custom hero image (a missing file —
    // e.g. storage cleared — falls back to the default photo).
    final heroStored = await widget.todayStore.heroImagePath();
    final heroImagePath =
        (heroStored != null && await File(heroStored).exists())
        ? heroStored
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
      heroImagePath: heroImagePath,
      manualFocus: manualFocus,
    );
  }

  // ------------------------------------------------------------ actions

  /// D-045: the shared Quick Add capture workflow — the same
  /// operations the shell's Quick Add sheet runs.
  QuickAddService get _quickAdd => QuickAddService(
    store: widget.store,
    todayStore: widget.todayStore,
    learnStore: widget.learn.store,
    linkCards: LinkCardService(
      widget.store,
      widget.learn.store,
      widget.thumbnails,
    ),
    library: widget.learn.library,
  );

  Future<void> _quickAddTask() async {
    if (await quickAddTaskFlow(context, service: _quickAdd)) {
      await _afterPlanEdit();
      setState(_reloadPlan);
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
        if (mounted) setState(_refresh);
      },
    );
  }

  Future<void> _quickAddGoal() async {
    final input = await promptGoal(context);
    if (input == null) return;
    await widget.goalsStore.addGoal(input.title, input.target, input.unit);
    setState(_refresh);
  }

  Future<void> _quickAddItem(String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final def = itemTypeDef(type);
    final title = await promptText(
      context,
      title: 'New ${def.label.toLowerCase()}',
      label: 'Title',
    );
    if (title == null || title.isEmpty) return;
    final inbox = await widget.learn.store.ensureInboxProject();
    final item = await widget.store.createItem(
      inbox.id,
      type: type,
      title: title,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Added to ${inbox.name}.'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            Navigator.push(
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
          },
        ),
      ),
    );
    setState(_refresh);
  }

  Future<void> _customize(_HubData data) async {
    const labels = {
      TodayStore.sectionQuickActions: 'Show quick actions on Today',
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
        // D-053: the hero image state rides along in the
        // dialog (changed immediately, not via Save — picking
        // a file can't wait for the switch form).
        var heroCustom = data.heroImagePath != null;
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
                    Text(
                      'Header',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    SwitchListTile(
                      title: const Text('Show editorial greeting'),
                      value: masterOn,
                      onChanged: (v) => setDialogState(
                        () => values[TodayStore.headerGreeting] = v,
                      ),
                    ),
                    for (final (key, label) in headerLabels)
                      SwitchListTile(
                        title: Text(label),
                        value: values[key] ?? true,
                        // Editable only while the master greeting
                        // is on (D-040).
                        onChanged: masterOn
                            ? (v) => setDialogState(() => values[key] = v)
                            : null,
                      ),
                    const Divider(),
                    Text(
                      'Background',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('Hero image'),
                      subtitle: Text(
                        heroCustom ? 'Your photo' : 'Default photograph',
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('Change image…'),
                      onTap: () async {
                        if (await _changeHeroImage()) {
                          setDialogState(() => heroCustom = true);
                        }
                      },
                    ),
                    if (heroCustom)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.restart_alt_outlined),
                        title: const Text('Reset to default'),
                        onTap: () async {
                          if (await _resetHeroImage()) {
                            setDialogState(() => heroCustom = false);
                          }
                        },
                      ),
                    const Divider(),
                    Text(
                      'Sections',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    for (final key in TodayStore.homeSections)
                      SwitchListTile(
                        title: Text(labels[key]!),
                        subtitle: key == TodayStore.sectionQuickActions
                            ? const Text(
                                'Show or hide the Task, Goal, Note and '
                                'Checklist shortcuts on your Today screen.',
                              )
                            : null,
                        value: values[key] ?? true,
                        onChanged: (v) => setDialogState(() => values[key] = v),
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
    if (!mounted) return;
    setState(_refresh);
  }

  /// D-053: pick a replacement hero photograph. The picked
  /// file is COPIED into app storage first (a picker may hand
  /// back a cache path that later vanishes), and the store
  /// remembers where the copy lives. Returns true when the
  /// hero actually changed.
  Future<bool> _changeHeroImage() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp']),
      ],
    );
    if (picked == null || !mounted) return false;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      final dest = File('${dir.path}/nimo_hero_custom.$ext');
      await File(picked.path).copy(dest.path);
      // A previous custom image with a different extension
      // would linger beside the new one — remove siblings.
      await for (final f in dir.list()) {
        if (f is File &&
            f.path.contains('nimo_hero_custom') &&
            f.path != dest.path) {
          await f.delete();
        }
      }
      await widget.todayStore.setHeroImagePath(dest.path);
      if (!mounted) return true;
      setState(_refresh);
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not use that image: $e')));
      return false;
    }
  }

  /// D-053: back to the shipped default photograph — the
  /// custom file is deleted and the stored path cleared.
  Future<bool> _resetHeroImage() async {
    final stored = await widget.todayStore.heroImagePath();
    if (stored != null) {
      final f = File(stored);
      if (await f.exists()) await f.delete();
    }
    await widget.todayStore.setHeroImagePath(null);
    if (!mounted) return true;
    setState(_refresh);
    return true;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // D-053: Today has NO AppBar — the brand row lives inside
    // the hero and scrolls away with it (the hero is the
    // screen's environment, not a pinned bar). The shell's
    // bottom capsule navigation is untouched and stays fixed.
    return Scaffold(
      body: FutureBuilder<_HubData>(
        future: _data,
        builder: (context, snapshot) {
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
          // D-040: the greeting block renders only when its
          // master switch is on AND at least one element is —
          // hidden means NO placeholder and NO leftover gap:
          // each block below carries its own trailing spacing.
          bool on(String k) => data.sections[k] ?? true;
          final showIntro =
              on(TodayStore.headerGreeting) &&
              (on(TodayStore.headerDate) ||
                  on(TodayStore.headerEyebrow) ||
                  on(TodayStore.headerHeading) ||
                  on(TodayStore.headerTagline));
          final showWeek = on(TodayStore.sectionWeekStrip);
          final showQuick = on(TodayStore.sectionQuickActions);
          // Mission 03 Phase 3: a closed day shows no actionable
          // Focus Now panel (same isClosed signal the scores use).
          final closedToday = data.todayReview?.isClosed ?? false;
          // The hero spans the full width; everything below it
          // keeps the page margin.
          Widget pad(Widget w) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            child: w,
          );
          // Visual refinement (2026-11-05): the screen is two
          // layers — the photograph is a FIXED backdrop behind
          // the scroll view (it never moves), while the hero
          // CONTENT (brand row, greeting, if–then) stays in
          // the ListView and scrolls away over it. Both layers
          // share one hero height so the content sits exactly
          // on the photograph at rest.
          final heroHeight = _heroHeight(MediaQuery.of(context).size);
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: heroHeight,
                child: IgnorePointer(
                  child: RepaintBoundary(child: _heroBackdrop(context, data)),
                ),
              ),
              ListView(
                padding: const EdgeInsets.only(bottom: 110.0),
                children: [
                  _heroContent(
                    context,
                    now,
                    data,
                    showIntro: showIntro,
                    height: heroHeight,
                  ),
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
                  if (showQuick) ...[
                    pad(_quickAddRow(context)),
                    const SizedBox(height: Gap.lg),
                  ],
                  // Mission 03 Phase 1: the plan card always
                  // renders — the This Week swap is removed.
                  pad(_planCard(context, data)),
                  if (data.dueCount + data.newCount > 0) ...[
                    const SizedBox(height: Gap.lg),
                    pad(_learnSection(context, data)),
                  ],
                  const SizedBox(height: Gap.lg),
                  pad(_scoresSection(context, data)),
                  if (data.sections[TodayStore.sectionDayClose] ?? true) ...[
                    const SizedBox(height: Gap.lg),
                    pad(_dayCloseSection(context, data)),
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
              ),
            ],
          );
        },
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
  /// actions. Done reuses the plan row's exact completion path
  /// (toggleItem + _afterPlanEdit + _reloadPlan); Change opens
  /// the picker sheet. All-done is a slim, action-free state.
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
                  onPressed: () async {
                    await widget.todayStore.toggleItem(focus);
                    await _afterPlanEdit();
                    if (!context.mounted) return;
                    setState(_reloadPlan);
                  },
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

  /// The hero's height: ~40% of the viewport is the TARGET.
  /// The floor is the measured worst case for the content —
  /// brand row + full greeting + if–then — and grows on
  /// narrow screens, where the same text wraps taller; the
  /// content's Spacer absorbs any slack on taller heroes.
  /// Shared by the fixed backdrop and the scrolling hero
  /// content so the two layers align exactly.
  double _heroHeight(Size viewport) {
    // Mission 03 Phase 2: the hero is ~25% shorter than the
    // D-053 original (was 40% of viewport height, floor 336 /
    // 356 under 340dp wide, cap 440) so the plan enters the
    // first viewport. The floor is set by content, not by the
    // percentage: brand row + greeting + if–then + streak
    // chip must fit without clipping at 360dp wide, where a
    // two-line if–then is the tallest case (the D-053 note
    // recorded a ~3px overflow there at the old proportions).
    // The floor is an ENVELOPE, not a constant: the hero
    // column insets its content by the status-bar height
    // (media.padding.top), so the floor grows with that
    // inset — on a device with a tall status bar the old
    // fixed floor would squeeze the column and overflow
    // (page_top_test: 47dp inset, 6px overflow, measured).
    final inset = MediaQuery.paddingOf(context).top;
    final floor = (viewport.width < 340 ? 268.0 : 252.0) + inset;
    return (viewport.height * 0.30 + inset).clamp(floor, 330.0 + inset);
  }

  /// How far the hug contour's centre dips below its sides —
  /// a shallow, restrained sag scaled gently off the hero
  /// height (see [_HugClipper]).
  static double _hugDip(double heroHeight) =>
      (heroHeight * 0.035).clamp(10.0, 14.0);

  /// The FIXED hero backdrop (D-053, refined 2026-11-05):
  /// the background photograph (the owner-approved default,
  /// or the owner's own image) plus its readability scrim,
  /// ending in the hug-shaped contour (see [_HugClipper]).
  /// It lives OUTSIDE the ListView, behind it, so it stays
  /// stationary while the page scrolls over it.
  Widget _heroBackdrop(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final ImageProvider image = data.heroImagePath != null
        ? FileImage(File(data.heroImagePath!))
        : const AssetImage('assets/images/hero_default.png');
    return ClipPath(
      clipper: const _HugClipper(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            // Decode near the displayed size, never the
            // full-resolution photograph.
            image: ResizeImage(
              image,
              width: (media.size.width * media.devicePixelRatio).round(),
            ),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          // Readability scrim: shade at the top (brand row)
          // and toward the bottom (greeting + if–then),
          // easing into the page colour at the very edge so
          // the hug contour shows no seam.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.42),
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.38),
                  theme.scaffoldBackgroundColor.withValues(alpha: 0.92),
                ],
                stops: const [0.0, 0.38, 0.72, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The hero CONTENT (D-053, refined 2026-11-05): the brand
  /// row, the greeting and the if–then control, rendered
  /// transparently at the top of the ListView so they sit on
  /// the fixed photograph at rest and scroll away over it —
  /// nothing here is pinned.
  Widget _heroContent(
    BuildContext context,
    DateTime now,
    _HubData data, {
    required bool showIntro,
    required double height,
  }) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Space.page,
          media.padding.top + Space.s2,
          Space.page,
          _hugDip(height) + Space.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const NimoMark(size: 30),
                const SizedBox(width: Space.s3),
                Text(
                  'Nimo',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: GlassTokens.darkOnCharcoal,
                  ),
                ),
                const Spacer(),
                _streakChip(context, data.streak, onPhoto: true),
                IconButton(
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: GlassTokens.darkOnCharcoal,
                  ),
                  tooltip: widget.onOpenSettings == null
                      ? 'Coming soon'
                      : 'Settings',
                  onPressed: widget.onOpenSettings,
                ),
              ],
            ),
            const Spacer(),
            if (showIntro) ...[
              _heroIntro(context, now, data),
              const SizedBox(height: Space.s3),
            ],
            _ifThenControl(context, data),
          ],
        ),
      ),
    );
  }

  /// The greeting block ON the photograph (D-053): the same
  /// D-040 element switches as the old intro — date, eyebrow,
  /// greeting heading, tagline — in white-family colours for
  /// the image. The caller omits the block entirely when the
  /// master switch is off.
  Widget _heroIntro(BuildContext context, DateTime now, _HubData data) {
    final theme = Theme.of(context);
    bool on(String k) => data.sections[k] ?? true;
    final parts = <Widget>[];
    void add(Widget part, double gapBefore) {
      if (parts.isNotEmpty) parts.add(SizedBox(height: gapBefore));
      parts.add(part);
    }

    if (on(TodayStore.headerDate)) {
      add(
        Text(
          _formatDate(now).toUpperCase(),
          style: AppType.eyebrow.copyWith(
            fontSize: 10,
            letterSpacing: 1.2,
            color: GlassTokens.darkOnCharcoalSecondary,
          ),
        ),
        0,
      );
    }
    if (on(TodayStore.headerEyebrow)) {
      add(
        Text(
          'A LITTLE INTENTION GOES A LONG WAY',
          // Mission 03 Phase 2: at most one line in the
          // shorter hero — the wide-tracked eyebrow wrapped
          // to two lines at 320dp wide (measured: it plus
          // the two-line greeting and tagline overflowed the
          // 252dp hero by 57px). One line with an ellipsis;
          // at normal widths it fits whole, unchanged.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.eyebrow.copyWith(
            letterSpacing: 1.2,
            color: GlassTokens.darkOnCharcoalSecondary,
          ),
        ),
        Gap.sm,
      );
    }
    if (on(TodayStore.headerHeading)) {
      add(
        Text(
          _greeting(now),
          // Mission 03 Phase 2: one line in the shorter hero
          // (see the eyebrow note in this method).
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.display(theme.textTheme)
              ?.copyWith(color: GlassTokens.darkOnCharcoal),
        ),
        // Mission 03 Phase 2: tightened s3 → s2 as part of
        // the ~25% hero reduction (the full greeting stack no
        // longer fits the shorter hero at narrow widths
        // otherwise — 61px overflow at 320dp, test-proven).
        Space.s2,
      );
    }
    if (on(TodayStore.headerTagline)) {
      add(
        Text(
          'A little better, at your pace.',
          // Mission 03 Phase 2: one line in the shorter hero
          // (see the eyebrow note in this method).
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: GlassTokens.darkOnCharcoalSecondary,
          ),
        ),
        Space.s2,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts,
    );
  }

  /// The if–then line as the hero's translucent charcoal
  /// control (D-053): bolt in the accent green, the line in
  /// neutral white, the edit affordance at the end. Same
  /// action as always ([_editIfThen]) — only its home moved;
  /// it used to sit at the foot of the plan card.
  Widget _ifThenControl(BuildContext context, _HubData data) {
    final theme = Theme.of(context);
    final empty = data.ifThen.isEmpty;
    final radius = BorderRadius.circular(RadiusToken.card + 2);
    return Material(
      color: GlassTokens.darkCharcoal,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: GlassTokens.darkCharcoalBorder),
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
              const Icon(
                Icons.bolt_outlined,
                size: 18,
                color: Color(0xFF1ED760),
              ),
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
                    color: empty
                        ? GlassTokens.darkOnCharcoalSecondary
                        : GlassTokens.darkOnCharcoal,
                  ),
                ),
              ),
              const Icon(
                Icons.edit_outlined,
                size: 16,
                color: GlassTokens.darkOnCharcoalSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The header streak chip (D-040): the streak's one home on
  /// Today, beside the brand. Fed by the SAME hub load as
  /// everything else — no second calculation. Compact by
  /// design (mono micro-label, visually secondary to the
  /// brand); on narrow screens (< 360dp) it reduces to the
  /// flame and the number. A full-height tap target, and
  /// tapping opens Direction on its Progress tab, where the
  /// streak detail lives, when the shell provides the callback.
  /// D-053: on the hero photograph the chip sits on a
  /// translucent charcoal pill so it stays readable.
  Widget _streakChip(
    BuildContext context,
    StreakState streak, {
    bool onPhoto = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = streak.currentStreak;
    final label = n == 1 ? '1 day' : '$n days';
    final narrow = MediaQuery.sizeOf(context).width < 360;
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
                  color: onPhoto
                      ? GlassTokens.darkOnCharcoalSecondary
                      : scheme.onSurfaceVariant,
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
        child: onPhoto
            ? Container(
                decoration: BoxDecoration(
                  color: GlassTokens.darkCharcoal,
                  borderRadius: BorderRadius.circular(RadiusToken.round),
                  border: Border.all(color: GlassTokens.darkCharcoalBorder),
                ),
                child: body,
              )
            : body,
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

  Widget _quickAddRow(BuildContext context) {
    Widget button(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool primary = false,
    }) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _quickTile(context, icon, label, onTap, primary: primary),
      ),
    );
    return Row(
      children: [
        button(Icons.add_task_outlined, 'Task', _quickAddTask, primary: true),
        button(Icons.flag_outlined, 'Goal', _quickAddGoal),
        button(Icons.note_outlined, 'Note', _quickAddNote),
        button(
          Icons.checklist_outlined,
          'Checklist',
          () => _quickAddItem(ItemType.checklist),
        ),
      ],
    );
  }

  /// One quick-action tile (D-053): a floating charcoal
  /// surface — translucent fill, grey hairline, soft lift —
  /// with a NEUTRAL icon; only the primary action (Task)
  /// carries the accent green. Same layout rhythm as the
  /// spatial tile it replaces (icon over label, centred),
  /// restyled for the charcoal system. Light theme keeps a
  /// white tile on the paper page.
  Widget _quickTile(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool primary = false,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(14);
    return Material(
      color: dark ? GlassTokens.darkCharcoalRaised : Colors.white,
      elevation: dark ? 3 : 1,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: dark
              ? GlassTokens.darkCharcoalBorder
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 24,
                color: primary
                    ? theme.colorScheme.primary
                    : (dark
                          ? GlassTokens.darkOnCharcoal
                          : theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: dark
                      ? GlassTokens.darkOnCharcoal
                      : theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
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
              child: SpatialCard(
                elevation: SpatialDepth.elevated,
                borderRadius: 14,
                padding: EdgeInsets.zero,
                enablePerspective: true,
                // D-053: charcoal in dark (was the spatial
                // kit's default surface).
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? GlassTokens.darkCharcoalSolid
                    : null,
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
            ),
            const SizedBox(width: Space.s4),
            Expanded(
              child: SpatialCard(
                elevation: SpatialDepth.elevated,
                borderRadius: 14,
                padding: EdgeInsets.zero,
                enablePerspective: true,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? GlassTokens.darkCharcoalSolid
                    : null,
                child: NeoScoreWell(
                  label: 'Self score · yours',
                  value: closed && review.selfScore != null
                      ? '${review.selfScore}'
                      : '—',
                  sub: closed
                      ? 'Your own reflection'
                      : 'Add yours at Day Close',
                  accentValue: true,
                  fraction: closed && review.selfScore != null
                      ? review.selfScore! / 10
                      : null,
                ),
              ),
            ),
          ],
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
                  Row(
                    children: [
                      if (open.length > 4)
                        TextButton(
                          onPressed: _openDailyTodo,
                          child: const Text('See all'),
                        ),
                      TextButton(
                        onPressed: _openTasks,
                        child: const Text('Tasks'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _openAgenda,
                        child: const Text('Agenda'),
                      ),
                    ],
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

  Future<void> _openTasks() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TasksScreen(
          todayStore: widget.todayStore,
          store: widget.store,
          reviewStore: widget.reviewStore,
        ),
      ),
    );
    setState(_reloadPlan);
  }

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

/// The hero's hug-shaped bottom edge (D-053): both sides
/// curve gently UP while the centre reaches lowest — a
/// shallow, symmetrical embrace. Not a U, not a rounded
/// rectangle: the dip is only [dip] deep across the full
/// width. Two mirrored cubic segments keep the tangent
/// smooth through the centre point.
/// The hero's hug-shaped bottom contour (refined
/// 2026-11-05): a single broad, shallow cosine bowl — the
/// sides sit [_TodayScreenState._hugDip] higher than the
/// centre, the slope is zero at both edges and at the
/// centre, and there are no joins, inflections sharp enough
/// to read as a wave, or pointed corners. The profile is a
/// function of the actual size only, so it stays
/// proportional on any screen; 48 samples keep it smooth
/// at any width for a negligible one-off path cost (the
/// backdrop is outside the scroll view and never repaints
/// while scrolling).
class _HugClipper extends CustomClipper<Path> {
  const _HugClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final dip = _TodayScreenState._hugDip(h);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - dip);
    const steps = 48;
    for (var i = 1; i <= steps; i++) {
      final x = w - w * i / steps;
      final t = x / w;
      // Cosine bowl: h - dip at both edges, h at the centre,
      // easing through the whole width — never a local scoop.
      final y = h - dip + dip * (0.5 - 0.5 * math.cos(2 * math.pi * t));
      path.lineTo(x, y);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_HugClipper oldClipper) => false;
}

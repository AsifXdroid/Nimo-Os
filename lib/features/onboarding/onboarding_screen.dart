/// ONBOARD — "Build your Nimo" (D-044): a first-run setup that
/// prepares a personal space instead of interrogating a new
/// user. Six steps, every one skippable, none mandatory:
///
/// 1. Daily rhythm — routine templates (categories or custom),
///    with weekday selection.
/// 2. Prepare today — one-off tasks for today. (A daily
///    intention is deliberately absent: the data model has no
///    such field; Day Close's self-note is a different thing.)
/// 3. Learning desk — topics, with an optional link source.
/// 4. Spaces & projects — a space, a project, a note, a
///    checklist.
/// 5. Goals — the app's numeric goals (title, target, unit;
///    the model has no milestones or target dates).
/// 6. Review — everything created, removable, then Today.
///
/// Lifecycle (via OnboardingGate): everything is written
/// straight into the real stores as it is added — there is no
/// draft copy to replay, so an interruption cannot duplicate
/// records; the current step is persisted, and on relaunch the
/// lists below are re-read from the stores, which on a fresh
/// install contain exactly what onboarding created. The first
/// daily plan is generated only when the first one-off is
/// added (step 2, after step 1's templates exist) or when
/// Today first loads after onboarding — never before.
library;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../goals/goals_store.dart';
import '../learn/learn_services.dart';
import '../learn/learn_store.dart';
import '../store.dart';
import '../today/plan_link.dart';
import '../today/today_store.dart';
import 'onboarding_gate.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.db,
    required this.todayStore,
    required this.store,
    required this.learn,
    required this.goalsStore,
    required this.onDone,
  });

  final Database db;
  final TodayStore todayStore;
  final Store store;
  final LearnServices learn;
  final GoalsStore goalsStore;

  /// Called after the completion marker is recorded.
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepTitles = [
    ('Daily rhythm', 'The shape of a good day, on repeat.'),
    ('Prepare today', 'Just for today — nothing repeats.'),
    ('Learning desk', 'What you are curious about.'),
    ('Spaces & projects', 'Where your things live.'),
    ('Goals', 'Something to aim at.'),
    ('Review', 'Your Nimo is ready.'),
  ];
  static const _categories = [
    'Study',
    'Exercise',
    'Reading',
    'Work',
    'Personal care',
    'Meditation',
  ];
  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  int _step = 0;
  bool _loading = true;

  List<PlanTemplate> _routines = [];
  List<DayPlanItem> _oneOffs = [];
  List<Topic> _topics = [];
  List<Workspace> _spaces = [];
  List<Project> _projects = [];
  List<Item> _notes = [];
  List<Item> _checklists = [];
  List<Goal> _goals = [];

  final _customRoutine = TextEditingController();
  final _oneOff = TextEditingController();
  final _topicTitle = TextEditingController();
  final _topicUrl = TextEditingController();
  final _spaceName = TextEditingController();
  final _projectName = TextEditingController();
  final _noteTitle = TextEditingController();
  final _checklistTitle = TextEditingController();
  final _goalTitle = TextEditingController();
  final _goalTarget = TextEditingController();
  final _goalUnit = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _customRoutine, _oneOff, _topicTitle, _topicUrl, _spaceName,
      _projectName, _noteTitle, _checklistTitle, _goalTitle,
      _goalTarget, _goalUnit,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final step = await OnboardingGate.savedStep(widget.db);
    await _reloadLists();
    if (!mounted) return;
    setState(() {
      _step = step;
      _loading = false;
    });
  }

  /// Re-read every created-list from the stores. On a fresh
  /// install these hold exactly what onboarding created, which
  /// is what makes a mid-onboarding restart resumable without
  /// any draft state.
  Future<void> _reloadLists() async {
    final routines = await widget.todayStore.templates();
    final plan = await widget.todayStore
        .existingPlanItems(DateTime.now());
    final topics = await widget.learn.store.allTopics();
    final spaces = await widget.store.workspaces();
    final projects = <Project>[];
    final notes = <Item>[];
    final checklists = <Item>[];
    for (final ws in spaces) {
      final ps = await widget.store.projects(ws.id);
      projects.addAll(ps);
      for (final prj in ps) {
        final items = await widget.store.items(prj.id);
        notes.addAll(items.where((i) => i.type == ItemType.note));
        checklists
            .addAll(items.where((i) => i.type == ItemType.checklist));
      }
    }
    final goals = await widget.goalsStore.goals();
    if (!mounted) return;
    setState(() {
      _routines = routines;
      _oneOffs = plan.where((i) => !i.isRoutine).toList();
      _topics = topics;
      _spaces = spaces;
      _projects = projects;
      _notes = notes;
      _checklists = checklists;
      _goals = goals;
    });
  }

  Future<void> _go(int step) async {
    await OnboardingGate.saveStep(widget.db, step);
    if (!mounted) return;
    setState(() => _step = step);
  }

  Future<void> _finish() async {
    await OnboardingGate.markCompleted(widget.db);
    widget.onDone();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------- step 1

  Future<void> _addRoutine(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    await widget.todayStore.addTemplate(t);
    _customRoutine.clear();
    await _reloadLists();
  }

  Future<void> _toggleDay(PlanTemplate t, int dayIndex) async {
    final mask = (t.weekdays ?? 127) ^ (1 << dayIndex);
    if (mask == 0) {
      _snack('A routine needs at least one day.');
      return;
    }
    await widget.todayStore.updateTemplateLink(
      t.id,
      weekdays: mask == 127 ? null : mask,
      itemId: t.itemId,
      url: t.url,
    );
    await _reloadLists();
  }

  // ---------------------------------------------------------- step 2

  Future<void> _addOneOff() async {
    final t = _oneOff.text.trim();
    if (t.isEmpty) return;
    await widget.todayStore.addOneOff(DateTime.now(), t);
    _oneOff.clear();
    await _reloadLists();
  }

  // ---------------------------------------------------------- step 3

  Future<int> _learningProjectId() async {
    final spaces = await widget.store.workspaces();
    Workspace? ws;
    for (final w in spaces) {
      if (w.name == 'Learning') ws = w;
    }
    ws ??= await widget.store.createWorkspace('Learning');
    final projects = await widget.store.projects(ws.id);
    for (final prj in projects) {
      if (prj.name == 'Topics') return prj.id;
    }
    return (await widget.store.createProject(ws.id, 'Topics')).id;
  }

  Future<void> _addTopic() async {
    final title = _topicTitle.text.trim();
    if (title.isEmpty) return;
    final url = _topicUrl.text.trim();
    if (url.isNotEmpty && !isValidWebUrl(url)) {
      _snack('That link does not look like a web address.');
      return;
    }
    final topic = await widget.learn.store.createTopic(
      projectId: await _learningProjectId(),
      title: title,
    );
    if (url.isNotEmpty) {
      await widget.learn.store.addSource(
        topicId: topic.id,
        kind: SourceKind.link,
        title: title,
        url: url,
      );
    }
    _topicTitle.clear();
    _topicUrl.clear();
    await _reloadLists();
  }

  // ---------------------------------------------------------- step 4

  Future<void> _addSpace() async {
    final name = _spaceName.text.trim();
    if (name.isEmpty) return;
    await widget.store.createWorkspace(name);
    _spaceName.clear();
    await _reloadLists();
  }

  Future<void> _addProject() async {
    final name = _projectName.text.trim();
    if (name.isEmpty) return;
    if (_spaces.isEmpty) {
      _snack('Add a space first — projects live inside one.');
      return;
    }
    await widget.store.createProject(_spaces.last.id, name);
    _projectName.clear();
    await _reloadLists();
  }

  Future<void> _addItem(String type, TextEditingController c) async {
    final title = c.text.trim();
    if (title.isEmpty) return;
    if (_projects.isEmpty) {
      _snack('Add a project first — notes and checklists live '
          'inside one.');
      return;
    }
    await widget.store
        .createItem(_projects.last.id, type: type, title: title);
    c.clear();
    await _reloadLists();
  }

  // ---------------------------------------------------------- step 5

  Future<void> _addGoal() async {
    final title = _goalTitle.text.trim();
    final target = int.tryParse(_goalTarget.text.trim());
    if (title.isEmpty) return;
    if (target == null || target <= 0) {
      _snack('Give the goal a target number — for example 30.');
      return;
    }
    await widget.goalsStore
        .addGoal(title, target, _goalUnit.text.trim());
    _goalTitle.clear();
    _goalTarget.clear();
    _goalUnit.clear();
    await _reloadLists();
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final (title, sub) = _stepTitles[_step];
    return Scaffold(
      body: PageTop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.s5, Space.s4, Space.s5, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'BUILD YOUR NIMO · STEP ${_step + 1} OF 6',
                      style: AppType.eyebrow
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (_step < 5)
                    TextButton(
                      onPressed: _finish,
                      child: const Text('Skip setup'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.s5, Space.s3, Space.s5, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i <= _step
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    ),
                    if (i < 5) const SizedBox(width: Space.s2),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.s5, Space.s5, Space.s5, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: Gap.sm),
                  Text(sub, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    Space.s5, Space.s4, Space.s5, Space.s4),
                child: _stepBody(context),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: scheme.outlineVariant)),
              ),
              padding: const EdgeInsets.fromLTRB(
                  Space.s5, Space.s3, Space.s5, Space.s4),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => _go(_step - 1),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  if (_step < 5)
                    TextButton(
                      onPressed: () => _go(_step + 1),
                      child: const Text('Skip this step'),
                    ),
                  const SizedBox(width: Space.s2),
                  FilledButton(
                    onPressed:
                        _step == 5 ? _finish : () => _go(_step + 1),
                    child:
                        Text(_step == 5 ? 'Start today' : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    return switch (_step) {
      0 => _rhythmStep(context),
      1 => _todayStep(context),
      2 => _learningStep(context),
      3 => _spacesStep(context),
      4 => _goalsStep(context),
      _ => _reviewStep(context),
    };
  }

  Widget _addRow({
    required TextEditingController controller,
    required String hint,
    required Future<void> Function() onAdd,
    String action = 'Add',
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: Space.s2),
        TextButton(onPressed: onAdd, child: Text(action)),
      ],
    );
  }

  Widget _createdRow(String title, Future<void> Function() onRemove) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove',
            onPressed: () async {
              await onRemove();
              await _reloadLists();
            },
          ),
        ],
      ),
    );
  }

  Widget _rhythmStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tap to add the ones that sound like your days. You '
          'can change all of this later — nothing is mandatory.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            for (final c in _categories)
              FilterChip(
                label: Text(c),
                selected:
                    _routines.any((t) => t.title == c && t.isActive),
                onSelected: (on) async {
                  if (on) {
                    await _addRoutine(c);
                  } else {
                    final t = _routines.firstWhere((t) => t.title == c);
                    await widget.todayStore.deleteTemplate(t.id);
                    await _reloadLists();
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        _addRow(
          controller: _customRoutine,
          hint: 'Or write your own — e.g. Go to run',
          onAdd: () => _addRoutine(_customRoutine.text),
        ),
        for (final t in _routines) ...[
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: Text(t.title,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove',
                onPressed: () async {
                  await widget.todayStore.deleteTemplate(t.id);
                  await _reloadLists();
                },
              ),
            ],
          ),
          Row(
            children: [
              for (var d = 0; d < 7; d++) ...[
                ChoiceChip(
                  label: Text(_dayLetters[d]),
                  selected:
                      (((t.weekdays ?? 127) >> d) & 1) == 1,
                  onSelected: (_) => _toggleDay(t, d),
                ),
                const SizedBox(width: Space.s1),
              ],
              const SizedBox(width: Space.s2),
              Text(
                (t.weekdays == null || t.weekdays == 127)
                    ? 'Every day'
                    : 'Some days',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _todayStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'One-off tasks for today only. They will be waiting '
          'on your Today screen.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.md),
        _addRow(
          controller: _oneOff,
          hint: 'e.g. Submit the report',
          onAdd: _addOneOff,
        ),
        for (final i in _oneOffs)
          _createdRow(
              i.title, () => widget.todayStore.deletePlanItem(i.id)),
      ],
    );
  }

  Widget _learningStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A topic is something you are learning — a language, '
          'a subject, a skill. Add a link if you already have a '
          'source for it.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _topicTitle,
          decoration:
              const InputDecoration(hintText: 'Topic — e.g. Arabic'),
        ),
        const SizedBox(height: Gap.sm),
        _addRow(
          controller: _topicUrl,
          hint: 'Optional link (https://…)',
          onAdd: _addTopic,
          action: 'Add topic',
        ),
        for (final t in _topics)
          _createdRow(
              t.title, () => widget.learn.store.deleteTopic(t.id)),
      ],
    );
  }

  Widget _spacesStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spaces hold projects; projects hold notes, links and '
          'checklists. Add as much or as little as you like.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.md),
        _addRow(
          controller: _spaceName,
          hint: 'A space — e.g. Personal',
          onAdd: _addSpace,
          action: 'Add space',
        ),
        _addRow(
          controller: _projectName,
          hint: 'A project — e.g. Home',
          onAdd: _addProject,
          action: 'Add project',
        ),
        _addRow(
          controller: _noteTitle,
          hint: 'A note title',
          onAdd: () => _addItem(ItemType.note, _noteTitle),
          action: 'Add note',
        ),
        _addRow(
          controller: _checklistTitle,
          hint: 'A checklist title',
          onAdd: () => _addItem(ItemType.checklist, _checklistTitle),
          action: 'Add checklist',
        ),
        for (final w in _spaces)
          _createdRow('Space · ${w.name}',
              () => widget.store.deleteWorkspace(w.id)),
        for (final prj in _projects)
          _createdRow('Project · ${prj.name}',
              () => widget.store.deleteProject(prj.id)),
        for (final n in _notes)
          _createdRow(
              'Note · ${n.title}', () => widget.store.deleteItem(n.id)),
        for (final c in _checklists)
          _createdRow('Checklist · ${c.title}',
              () => widget.store.deleteItem(c.id)),
      ],
    );
  }

  Widget _goalsStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A goal in Nimo is a number you are moving toward — '
          'pages read, words learned, kilometres run.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _goalTitle,
          decoration:
              const InputDecoration(hintText: 'Goal — e.g. Read'),
        ),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _goalTarget,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Target'),
              ),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: TextField(
                controller: _goalUnit,
                decoration:
                    const InputDecoration(hintText: 'Unit — pages'),
              ),
            ),
            TextButton(onPressed: _addGoal, child: const Text('Add')),
          ],
        ),
        for (final g in _goals)
          _createdRow('${g.title} — 0 of ${g.target} ${g.unit}',
              () => widget.goalsStore.deleteGoal(g.id)),
      ],
    );
  }

  Widget _reviewStep(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <(String, List<Widget>)>[
      (
        'Daily rhythm',
        [
          for (final t in _routines)
            _createdRow(t.title,
                () => widget.todayStore.deleteTemplate(t.id)),
        ],
      ),
      (
        'Today',
        [
          for (final i in _oneOffs)
            _createdRow(i.title,
                () => widget.todayStore.deletePlanItem(i.id)),
        ],
      ),
      (
        'Learning',
        [
          for (final t in _topics)
            _createdRow(t.title,
                () => widget.learn.store.deleteTopic(t.id)),
        ],
      ),
      (
        'Spaces & projects',
        [
          for (final w in _spaces)
            _createdRow('Space · ${w.name}',
                () => widget.store.deleteWorkspace(w.id)),
          for (final prj in _projects)
            _createdRow('Project · ${prj.name}',
                () => widget.store.deleteProject(prj.id)),
          for (final n in _notes)
            _createdRow('Note · ${n.title}',
                () => widget.store.deleteItem(n.id)),
          for (final c in _checklists)
            _createdRow('Checklist · ${c.title}',
                () => widget.store.deleteItem(c.id)),
        ],
      ),
      (
        'Goals',
        [
          for (final g in _goals)
            _createdRow('${g.title} — ${g.target} ${g.unit}',
                () => widget.goalsStore.deleteGoal(g.id)),
        ],
      ),
    ];
    final empty = groups.every((g) => g.$2.isEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (empty)
          Text(
            'Nothing added yet — that is fine. You can set '
            'everything up later, inside the app, whenever it '
            'suits you.',
            style: theme.textTheme.bodyMedium,
          )
        else
          for (final (label, rows) in groups)
            if (rows.isNotEmpty) ...[
              Text(label.toUpperCase(),
                  style: AppType.eyebrow
                      .copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: Gap.sm),
              ...rows,
              const SizedBox(height: Gap.lg),
            ],
      ],
    );
  }
}

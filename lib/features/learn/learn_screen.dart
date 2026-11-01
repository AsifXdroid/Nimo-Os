/// LEARN — the session-first landing (S5 step C2b, §R2.3).
///
/// Sessions lead, content follows: the Start card (due/new
/// counts + one tap into a review session), Continue cards for
/// packs with an episode arc (episode + boss), the pack list,
/// and the image-target verification queue when it is non-empty.
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../review/review_store.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'image_verify_screen.dart';
import 'learn_engine_store.dart';
import 'learn_services.dart';
import 'learn_store.dart';
import 'pack_import_ui.dart';
import 'session_composer.dart';
import 'session_screen.dart';
import 'topic_detail_screen.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({
    super.key,
    required this.learn,
    required this.reviewStore,
    required this.store,
    this.onOpenTopics,
  });

  final LearnServices learn;
  final ReviewStore reviewStore;
  final Store store;

  /// Opens the Topics & Library screen (Neo Learn's "All
  /// topics →" action); wired by the shell, optional for tests.
  final void Function()? onOpenTopics;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  int _due = 0;
  int _new = 0;
  List<PackRecord> _packs = const [];
  List<Topic> _topics = const [];
  Map<int, String> _projectNames = const {};
  List<LearnQuestion> _verifyPending = const [];

  /// packId → DUE count alone (the boss gate: ≥ 5). Fresh
  /// questions are due at insert, so new ⊆ due and the due count
  /// already IS the union — adding newCount on top double-counts
  /// every fresh question and opens the gate early.
  Map<String, int> _packDueCounts = const {};
  bool _loaded = false;

  LearnEngineStore get _engine => widget.learn.engine;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final due = await _engine.dueCount();
    final fresh = await _engine.newCount();
    final packs = await _engine.allPacks();
    final topics = await widget.learn.store.allTopics();
    final names = <int, String>{};
    for (final ws in await widget.store.workspaces()) {
      for (final prj in await widget.store.projects(ws.id)) {
        names[prj.id] = prj.name;
      }
    }
    final pending = await _engine.verifyPendingQuestions();
    final dueCounts = <String, int>{};
    for (final pack in packs) {
      dueCounts[pack.packId] = await _engine.dueCount(packId: pack.packId);
    }
    if (!mounted) return;
    setState(() {
      _due = due;
      _new = fresh;
      _packs = packs;
      _topics = topics;
      _projectNames = names;
      _verifyPending = pending;
      _packDueCounts = dueCounts;
      _loaded = true;
    });
  }

  Future<void> _openTopic(Topic topic) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicDetailScreen(
          store: widget.store,
          learn: widget.learn,
          topic: topic,
        ),
      ),
    );
    _load();
  }

  /// Same first step as Topics & Library: a topic in the
  /// Inbox, opened straight into its detail page.
  Future<void> _newTopic() async {
    final title =
        await promptText(context, title: 'New topic', label: 'Title');
    if (title == null || title.isEmpty || !mounted) return;
    final topic = await widget.learn.store.createTopic(
      projectId: await widget.learn.store.inboxProjectId(),
      title: title,
    );
    if (!mounted) return;
    await _openTopic(topic);
  }

  Future<void> _openSession(SessionKind kind, {String? packId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          learn: widget.learn,
          reviewStore: widget.reviewStore,
          store: widget.store,
          kind: kind,
          packId: packId,
        ),
      ),
    );
    _load();
  }

  Future<void> _openVerifyList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageVerifyListScreen(learn: widget.learn),
      ),
    );
    _load();
  }

  Future<void> _importPack() async {
    await showPackImportFlow(context, learn: widget.learn);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: PageTop(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, Gap.lg),
            child: DelayedSkeleton(skeleton: SkeletonList(panels: 2)),
          ),
        ),
      );
    }
    final arcPacks = [
      for (final p in _packs)
        if (p.arc != null) p,
    ];
    return Scaffold(
      body: PageTop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Space.page, Gap.md, Space.page, Gap.lg),
          children: [
          const NeoPageTitle(
            eyebrow: 'Curiosity, kept alive',
            heading: 'Learn something that stays.',
            sub: 'Your sources. Your pace. A world of little discoveries.',
          ),
          const SizedBox(height: Gap.lg),
          _pulsePanel(context),
          if (arcPacks.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            const NeoSectionHead(title: 'Continue exploring'),
            const SizedBox(height: Space.s3),
            for (final pack in arcPacks) _continueCard(context, pack),
          ],
          const SizedBox(height: Gap.lg),
          const NeoSectionHead(title: 'Your topics'),
          const SizedBox(height: Space.s3),
          _topicsSection(context),
          const SizedBox(height: Gap.lg),
          const NeoSectionHead(title: 'Your packs'),
          const SizedBox(height: Space.s3),
          if (_packs.isEmpty)
            Text('No packs yet — import one to begin.',
                style: Theme.of(context).textTheme.bodyMedium)
          else
            // D-039: pack rows sit on the canvas (hairlines),
            // not inside a panel.
            Column(
              children: [
                for (final pack in _packs) _packRow(context, pack),
              ],
            ),
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            onPressed: _importPack,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Import a pack'),
          ),
          if (_verifyPending.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            _verifyCard(context),
          ],
        ],
        ),
      ),
    );
  }

  /// The learning pulse (D-039): the DEEP feature surface —
  /// the concept's tinted pulse panel. Three quiet numbers on
  /// deep green, then the one primary action. Enjoyment is
  /// named as the metric in the hint; the trend itself lives
  /// in Progress. All colours come from [EditorialColors].
  Widget _pulsePanel(BuildContext context) {
    final theme = Theme.of(context);
    final ed = EditorialColors.of(context);
    final total = _due + _new;
    Widget cell(int number, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedCount(
                value: number,
                style: AppType.statistic().copyWith(color: ed.onDeep),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: ed.deepMuted),
              ),
            ],
          ),
        );
    return FeaturePanel(
      kind: FeatureSurfaceKind.deep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Your learning pulse',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: ed.onDeep),
                ),
              ),
              if (widget.onOpenTopics != null)
                TextButton(
                  onPressed: widget.onOpenTopics,
                  child: Text(
                    'All topics →',
                    style: AppType.eyebrow.copyWith(
                      fontSize: 10,
                      // On deep, the accent is the pale mint in
                      // BOTH themes (EditorialColors.deepAccent).
                      color: ed.deepAccent,
                    ),
                  ),
                ),
            ],
          ),
          // The pulse shrinks to its content (D-038): with
          // nothing due and nothing new, the zero cells
          // collapse and the hint below carries the state.
          if (total > 0) ...[
            const SizedBox(height: Space.s5),
            Row(
              children: [
                cell(_due, 'due to revisit'),
                cell(_new, 'new to explore'),
                cell(_packs.length, 'packs in your library'),
              ],
            ),
          ],
          const SizedBox(height: Space.s5),
          FilledButton(
            // The pulse's action is a pale-mint fill in both
            // themes — the scheme primary (dark green in light
            // mode) would blend into the deep surface.
            style: FilledButton.styleFrom(
              backgroundColor: ed.deepAccent,
              foregroundColor: ed.onDeepAccent,
              disabledBackgroundColor:
                  ed.deepAccent.withValues(alpha: 0.35),
            ),
            onPressed:
                total == 0 ? null : () => _openSession(SessionKind.review),
            child: const Text('Begin a short session →'),
          ),
          const SizedBox(height: Space.s3),
          Text(
            'Measured in enjoyment, not minutes.',
            style: theme.textTheme.bodySmall?.copyWith(color: ed.deepMuted),
          ),
          if (total == 0) ...[
            const SizedBox(height: Space.s3),
            Text(
              _topics.isNotEmpty
                  ? 'Open a topic below to read, and mark points '
                      'while reading to create cards.'
                  : 'Import a pack or mark points while reading to '
                      'create cards.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: ed.onDeep),
            ),
          ],
        ],
      ),
    );
  }

  /// The owner's own material, on the landing itself (UX
  /// refinement, 2026-11-01): topics used to live only behind
  /// the pulse panel's "All topics →" link, so a library of
  /// topics with no imported packs read as an empty Learn.
  /// Rows mirror Topics & Library and open the same detail
  /// page; the list caps at five, with the full list one tap
  /// away through the shell's Topics route.
  Widget _topicsSection(BuildContext context) {
    if (_topics.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No topics yet. Add one to learn from your own '
            'material: a PDF, a text file, a link.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.s3),
          OutlinedButton.icon(
            onPressed: _newTopic,
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('New topic'),
          ),
        ],
      );
    }
    final shown = _topics.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in shown)
          NeoListRow(
            icon: t.triggerUrl != null
                ? Icons.link
                : Icons.lightbulb_outline,
            title: t.title,
            sub: [
              _projectNames[t.projectId] ?? '',
              t.status,
              if (t.track != null) t.track!,
            ].where((s) => s.isNotEmpty).join(' · '),
            last: t == shown.last && _topics.length <= 5,
            onTap: () => _openTopic(t),
          ),
        if (_topics.length > 5 && widget.onOpenTopics != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onOpenTopics,
              child: const Text('All topics →'),
            ),
          ),
      ],
    );
  }

  Widget _continueCard(BuildContext context, PackRecord pack) {
    final theme = Theme.of(context);
    final arc = pack.arc!;
    final episode = arc['episode'];
    final episodeTitle = arc['episodeTitle'] as String? ?? '';
    final teaser = arc['teaser'] as String?;
    final bossReady = (_packDueCounts[pack.packId] ?? 0) >= 5;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: NeoPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              arc['title'] as String? ?? pack.title,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Episode $episode — $episodeTitle',
              style: theme.textTheme.bodyLarge,
            ),
            if (teaser != null && teaser.isNotEmpty) ...[
              const SizedBox(height: Gap.sm),
              Text(
                teaser,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Gap.md),
            Row(
              children: [
                FilledButton(
                  onPressed: () =>
                      _openSession(SessionKind.episode, packId: pack.packId),
                  child: const Text('Play episode'),
                ),
                const SizedBox(width: Gap.sm),
                OutlinedButton(
                  onPressed: bossReady
                      ? () =>
                            _openSession(SessionKind.boss, packId: pack.packId)
                      : null,
                  child: const Text('Boss level'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _packRow(BuildContext context, PackRecord pack) {
    return NeoListRow(
      icon: Icons.style_outlined,
      title: pack.title,
      sub: 'v${pack.version} · ${pack.questionCount} questions',
      last: pack == _packs.last,
      trailing: pack.arc == null
          ? OutlinedButton(
              onPressed: () =>
                  _openSession(SessionKind.review, packId: pack.packId),
              child: const Text('Play'),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _verifyCard(BuildContext context) {
    return NeoListRow(
      icon: Icons.image_search_outlined,
      title: '${_verifyPending.length} image targets to check',
      onTap: _openVerifyList,
      last: true,
    );
  }
}

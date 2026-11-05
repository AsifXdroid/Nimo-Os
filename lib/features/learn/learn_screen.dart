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
import '../../core/spatial_ui.dart';
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
          reviewStore: widget.reviewStore,
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
    final total = _due + _new;
    return Scaffold(
      body: PageTop(
        // D-052: solid canvas + the prototype's Learn header —
        // eyebrow, curiosity heading, one-line promise.
        child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, 110.0),
            children: [
              Text(
                'YOUR LEARNING SPACE',
                style: AppType.eyebrow.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.s2),
              Text(
                'Follow your curiosity.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: Space.s2),
              Text(
                'Read, revisit, and make an idea your own.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (total > 0) ...[
                const SizedBox(height: Gap.md),
                _compactSessionBar(context, total),
              ],
              if (arcPacks.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                const NeoSectionHead(title: 'Continue exploring'),
                const SizedBox(height: Space.s3),
                for (final pack in arcPacks) _continueCard(context, pack),
              ],
              const SizedBox(height: Gap.lg),
              NeoSectionHead(
                title: 'Your topics',
                actionLabel: 'New topic',
                onAction: _newTopic,
              ),
              const SizedBox(height: Space.s3),
              _topicsSection(context),
              const SizedBox(height: Gap.lg),
              NeoSectionHead(
                title: 'Your packs',
                actionLabel: 'Import a pack',
                onAction: _importPack,
              ),
              const SizedBox(height: Space.s3),
              if (_packs.isEmpty)
                Text('No packs yet.',
                    style: Theme.of(context).textTheme.bodyMedium)
              else
                Column(
                  children: [
                    for (final pack in _packs) _packRow(context, pack),
                  ],
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

  /// Compact session bar: shown only when questions are due or new.
  Widget _compactSessionBar(BuildContext context, int total) {
    final theme = Theme.of(context);
    final ed = EditorialColors.of(context);
    return SpatialCard(
      elevation: SpatialDepth.elevated,
      enablePerspective: true,
      backgroundColor: ed.deep,
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: Space.s3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_due',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: ed.onDeep,
                          ),
                        ),
                        const SizedBox(width: Space.s2),
                        Text(
                          'due to revisit',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ed.deepMuted,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_new',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: ed.onDeep,
                          ),
                        ),
                        const SizedBox(width: Space.s2),
                        Text(
                          'new to explore',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ed.deepMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.onOpenTopics != null)
                TextButton(
                  onPressed: widget.onOpenTopics,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'All topics →',
                    style: TextStyle(
                      fontSize: 12,
                      color: ed.deepAccent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.s3),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ed.deepAccent,
              foregroundColor: ed.onDeepAccent,
            ),
            onPressed: () => _openSession(SessionKind.review),
            child: const Text('Begin a short session →'),
          ),
        ],
      ),
    );
  }

  Widget _topicsSection(BuildContext context) {
    if (_topics.isEmpty) {
      return Text(
        'No topics yet. Add one to learn from your own material.',
        style: Theme.of(context).textTheme.bodyMedium,
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
      child: SpatialCard(
        elevation: SpatialDepth.elevated,
        enablePerspective: true,
        padding: const EdgeInsets.all(Space.s4),
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

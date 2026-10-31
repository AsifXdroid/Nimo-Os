/// LEARN — the session-first landing (S5 step C2b, §R2.3).
///
/// Sessions lead, content follows: the Start card (due/new
/// counts + one tap into a review session), Continue cards for
/// packs with an episode arc (episode + boss), the pack list,
/// and the image-target verification queue when it is non-empty.
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../review/review_store.dart';
import '../store.dart';
import 'image_verify_screen.dart';
import 'learn_engine_store.dart';
import 'learn_services.dart';
import 'pack_import_ui.dart';
import 'session_composer.dart';
import 'session_screen.dart';

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
      _verifyPending = pending;
      _packDueCounts = dueCounts;
      _loaded = true;
    });
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final arcPacks = [
      for (final p in _packs)
        if (p.arc != null) p,
    ];
    return Scaffold(
      body: ListView(
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
          const NeoSectionHead(title: 'Your packs'),
          const SizedBox(height: Space.s3),
          if (_packs.isEmpty)
            Text('No packs yet — import one to begin.',
                style: Theme.of(context).textTheme.bodyMedium)
          else
            NeoPanel(
              level: NeoSurfaceLevel.flat,
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.s6, vertical: Space.s2),
              child: Column(
                children: [
                  for (final pack in _packs) _packRow(context, pack),
                ],
              ),
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
    );
  }

  /// The learning pulse panel (D-037, Neo Learn): three quiet
  /// numbers — due, new, packs — then the one primary action.
  /// Enjoyment is named as the metric in the hint, as the
  /// prototype does; the trend itself lives in Progress, where
  /// the session data is aggregated.
  Widget _pulsePanel(BuildContext context) {
    final theme = Theme.of(context);
    final total = _due + _new;
    Widget cell(String number, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                number,
                style: AppType.statistic(),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );
    return NeoPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeoSectionHead(
            title: 'Your learning pulse',
            actionLabel:
                widget.onOpenTopics == null ? null : 'All topics →',
            onAction: widget.onOpenTopics,
          ),
          // D-038: the pulse shrinks to its content — with
          // nothing due and nothing new, the three zero cells
          // collapse and the hint below carries the state.
          if (total > 0) ...[
            const SizedBox(height: Space.s5),
            Row(
              children: [
                cell('$_due', 'due to revisit'),
                cell('$_new', 'new to explore'),
                cell('${_packs.length}', 'packs in your library'),
              ],
            ),
          ],
          const SizedBox(height: Space.s5),
          FilledButton(
            onPressed:
                total == 0 ? null : () => _openSession(SessionKind.review),
            child: const Text('Begin a short session →'),
          ),
          const SizedBox(height: Space.s3),
          Text(
            'Measured in enjoyment, not minutes.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (total == 0) ...[
            const SizedBox(height: Space.s3),
            Text(
              'Import a pack or mark points while reading to '
              'create cards.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
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
    return NeoPanel(
      level: NeoSurfaceLevel.flat,
      padding: const EdgeInsets.symmetric(
          horizontal: Space.s6, vertical: Space.s2),
      child: NeoListRow(
        icon: Icons.image_search_outlined,
        title: '${_verifyPending.length} image targets to check',
        onTap: _openVerifyList,
        last: true,
      ),
    );
  }
}

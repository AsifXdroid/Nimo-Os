/// LEARN — the session-first landing (S5 step C2b, §R2.3).
///
/// Sessions lead, content follows: the Start card (due/new
/// counts + one tap into a review session), Continue cards for
/// packs with an episode arc (episode + boss), the pack list,
/// and the image-target verification queue when it is non-empty.
library;

import 'package:flutter/material.dart';

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
  });

  final LearnServices learn;
  final ReviewStore reviewStore;
  final Store store;

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
      appBar: AppBar(title: const Text('Learn')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Gap.md, Space.page, Gap.lg),
        children: [
          _startCard(context),
          if (arcPacks.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            Text('Continue', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Gap.sm),
            for (final pack in arcPacks) _continueCard(context, pack),
          ],
          const SizedBox(height: Gap.lg),
          Text('Packs', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          if (_packs.isEmpty)
            Text('No packs yet.', style: Theme.of(context).textTheme.bodySmall),
          for (final pack in _packs) _packRow(context, pack),
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

  Widget _startCard(BuildContext context) {
    final theme = Theme.of(context);
    final total = _due + _new;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Due for review: $_due', style: theme.textTheme.titleMedium),
            const SizedBox(height: Gap.sm),
            Text('New cards: $_new', style: theme.textTheme.bodyLarge),
            if (total == 0) ...[
              const SizedBox(height: Gap.sm),
              Text(
                'Import a pack or mark points while reading to '
                'create cards.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: Gap.md),
            FilledButton(
              onPressed: total == 0
                  ? null
                  : () => _openSession(SessionKind.review),
              child: const Text('Start session'),
            ),
          ],
        ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
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
    return Card(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: ListTile(
        title: Text(pack.title),
        subtitle: Text('v${pack.version} · ${pack.questionCount} questions'),
        trailing: pack.arc == null
            ? OutlinedButton(
                onPressed: () =>
                    _openSession(SessionKind.review, packId: pack.packId),
                child: const Text('Play'),
              )
            : null,
      ),
    );
  }

  Widget _verifyCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          Icons.image_search_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text('${_verifyPending.length} image targets to check'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openVerifyList,
      ),
    );
  }
}

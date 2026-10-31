/// LEARN — Topics & Library (S4): the Inbox triage queue, every
/// topic, the Library at a glance, document import, and the
/// backup section (SET). Learn's session landing arrives with
/// the engine in S5 — this screen is the data side (§R10.2 S4).
///
/// Inbox hygiene (§R9.5): the Inbox count lives here, not on
/// Home, and "park" is a first-class status — the Inbox is a
/// queue to triage, not a guilt museum.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'learn_services.dart';
import 'learn_store.dart';
import 'topic_detail_screen.dart';

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({
    super.key,
    required this.store,
    required this.learn,
    this.backupSection,
  });

  final Store store;
  final LearnServices learn;

  /// The SET backup UI, wired by the app shell (needs the live
  /// database + restart orchestration this screen doesn't own).
  final Widget? backupSection;

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  List<Topic> _inbox = const [];
  List<Topic> _others = const [];
  Map<int, String> _projectNames = const {};
  ({int files, int bytes}) _stats = (files: 0, bytes: 0);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inboxId = await widget.learn.store.inboxProjectId();
    final all = await widget.learn.store.allTopics();
    final names = <int, String>{};
    for (final ws in await widget.store.workspaces()) {
      for (final prj in await widget.store.projects(ws.id)) {
        names[prj.id] = prj.name;
      }
    }
    final stats = await widget.learn.library.stats();
    if (!mounted) return;
    setState(() {
      _inbox = all.where((t) => t.projectId == inboxId).toList();
      _others = all.where((t) => t.projectId != inboxId).toList();
      _projectNames = names;
      _stats = stats;
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

  Future<void> _newTopic() async {
    final title =
        await promptText(context, title: 'New topic', label: 'Title');
    if (title == null || title.isEmpty) return;
    final topic = await widget.learn.store.createTopic(
      projectId: await widget.learn.store.inboxProjectId(),
      title: title,
    );
    if (!mounted) return;
    await _openTopic(topic);
  }

  /// Import a document: pick the file, then the topic it belongs
  /// to (or a fresh Inbox topic named after the file).
  Future<void> _importDocument() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
            label: 'Documents', extensions: ['pdf', 'txt', 'md', 'html']),
        XTypeGroup(label: 'All files'),
      ],
    );
    if (picked == null || !mounted) return;
    final topics = await widget.learn.store.allTopics();
    if (!mounted) return;
    final choice = await showModalBottomSheet<({bool isNew, Topic? topic})>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Import into…')),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New topic (Inbox)'),
              onTap: () =>
                  Navigator.pop(context, (isNew: true, topic: null)),
            ),
            for (final t in topics)
              ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(t.title),
                onTap: () =>
                    Navigator.pop(context, (isNew: false, topic: t)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final topic = choice.isNew
          ? await widget.learn.store.createTopic(
              projectId: await widget.learn.store.inboxProjectId(),
              title: picked.name,
            )
          : choice.topic!;
      final source = await widget.learn.imports.importFile(
        topicId: topic.id,
        sourcePath: picked.path,
        originalName: picked.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(source.kind == SourceKind.pdf ||
                source.kind == SourceKind.txt
            ? ExtractionStatus.describe(source.extractionStatus)
            : 'Imported into “${topic.title}”.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Topics & Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTopic,
        icon: const Icon(Icons.add),
        label: const Text('Topic'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.page, Gap.md, Space.page, Gap.lg),
              children: [
                const NeoPageTitle(
                  eyebrow: 'Your knowledge map',
                  heading: 'Topics',
                  sub: 'Keep following the things that make you curious.',
                ),
                const SizedBox(height: Gap.lg),
                NeoSectionHead(title: 'Inbox (${_inbox.length})'),
                const SizedBox(height: Space.s3),
                if (_inbox.isEmpty)
                  Text(
                    'Nothing waiting. Share a reel or link into Nimo '
                    'and it lands here as a topic.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  NeoPanel(
                    level: NeoSurfaceLevel.flat,
                    padding: const EdgeInsets.symmetric(
                        horizontal: Space.s6, vertical: Space.s2),
                    child: Column(
                      children: [
                        for (final t in _inbox)
                          _topicRow(context, t, last: t == _inbox.last),
                      ],
                    ),
                  ),
                const SizedBox(height: Gap.lg),
                const NeoSectionHead(title: 'All topics'),
                const SizedBox(height: Space.s3),
                if (_others.isEmpty)
                  Text('No topics outside the Inbox yet.',
                      style: theme.textTheme.bodyMedium)
                else
                  NeoPanel(
                    level: NeoSurfaceLevel.flat,
                    padding: const EdgeInsets.symmetric(
                        horizontal: Space.s6, vertical: Space.s2),
                    child: Column(
                      children: [
                        for (final t in _others)
                          _topicRow(context, t, last: t == _others.last),
                      ],
                    ),
                  ),
                const SizedBox(height: Gap.lg),
                const NeoSectionHead(title: 'Your source library'),
                const SizedBox(height: Space.s3),
                NeoPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // D-038: the middle-dot stat join becomes
                      // two quiet facts; the path takes the
                      // technical role.
                      Row(
                        children: [
                          Text('${_stats.files}',
                              style: AppType.statistic(size: 20)),
                          const SizedBox(width: Space.s2),
                          Text('files',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(width: Space.s5),
                          Text(
                              '${(_stats.bytes / 1024).toStringAsFixed(0)} KB',
                              style: AppType.statistic(size: 20)),
                          const SizedBox(width: Space.s2),
                          Text('in your library',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: Space.s2),
                      Text(
                        widget.learn.library.rootPath,
                        style: AppType.technical,
                      ),
                      const SizedBox(height: Gap.md),
                      OutlinedButton.icon(
                        onPressed: _importDocument,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Import document'),
                      ),
                    ],
                  ),
                ),
                if (widget.backupSection != null) ...[
                  const SizedBox(height: Gap.lg),
                  const Divider(),
                  const SizedBox(height: Gap.md),
                  widget.backupSection!,
                ],
                const SizedBox(height: 72), // FAB clearance
              ],
            ),
    );
  }

  Widget _topicRow(BuildContext context, Topic t, {bool last = false}) {
    return NeoListRow(
      icon: t.triggerUrl != null ? Icons.link : Icons.lightbulb_outline,
      title: t.title,
      sub: [
        _projectNames[t.projectId] ?? '',
        t.status,
        if (t.track != null) t.track!,
      ].where((s) => s.isNotEmpty).join(' · '),
      last: last,
      onTap: () => _openTopic(t),
    );
  }
}

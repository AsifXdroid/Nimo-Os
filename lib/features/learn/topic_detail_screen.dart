/// LEARN — one topic: its status/track, its trigger, its sources
/// (the real material), and its marked points (§R6.1, §R4.5).
///
/// Sources open by kind: PDF → the pdfrx viewer; PDF/TXT with
/// readable text → reading cards (where points are marked);
/// links → the system browser. Extraction problems are stated
/// plainly on the source row (scanned PDF ≠ empty source).
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'learn_services.dart';
import 'learn_store.dart';
import 'pack_import_ui.dart';
import 'pdf_source_screen.dart';
import 'reading_screen.dart';

class TopicDetailScreen extends StatefulWidget {
  const TopicDetailScreen({
    super.key,
    required this.store,
    required this.learn,
    required this.topic,
  });

  final Store store;
  final LearnServices learn;
  final Topic topic;

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  late Topic _topic;
  List<Source> _sources = const [];
  List<MarkedPoint> _points = const [];
  int _unminted = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _topic = widget.topic;
    _load();
  }

  Future<void> _load() async {
    final topic = await widget.learn.store.topicById(_topic.id);
    final sources = await widget.learn.store.sourcesForTopic(_topic.id);
    final points = await widget.learn.store.markedPointsForTopic(_topic.id);
    final unminted = await widget.learn.engine.unmintedPointCount(_topic.id);
    if (!mounted) return;
    setState(() {
      _topic = topic;
      _sources = sources;
      _points = points;
      _unminted = unminted;
      _loaded = true;
    });
  }

  Future<void> _buildClozeCards() async {
    final minted =
        await widget.learn.engine.mintClozeFromMarkedPoints(_topic.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$minted cloze cards added')),
    );
    _load();
  }

  Future<void> _importPack() async {
    await showPackImportFlow(context,
        learn: widget.learn, fixedTopicId: _topic.id);
    _load();
  }

  // ------------------------------------------------------------ topic meta

  Future<void> _rename() async {
    final name = await promptText(context,
        title: 'Rename topic', initial: _topic.title, label: 'Title');
    if (name == null || name.isEmpty) return;
    await widget.learn.store.updateTopic(_topic.id, title: name);
    _load();
  }

  Future<void> _editTrack() async {
    final track = await promptText(context,
        title: 'Learning track',
        initial: _topic.track ?? '',
        label: 'Track (e.g. Arabic, Health, Money)');
    if (track == null) return;
    await widget.learn.store.updateTopic(_topic.id,
        track: track, clearTrack: track.isEmpty);
    _load();
  }

  Future<void> _move() async {
    final workspaces = await widget.store.workspaces();
    final projects = <Project>[];
    for (final ws in workspaces) {
      projects.addAll(await widget.store.projects(ws.id));
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Project>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Move topic to…')),
            for (final prj in projects)
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(prj.name),
                trailing: prj.id == _topic.projectId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, prj),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked.id == _topic.projectId) return;
    await widget.learn.store.moveTopic(_topic.id, picked.id);
    _load();
  }

  Future<void> _deleteTopic() async {
    if (!await confirmDelete(context, 'topic')) return;
    // Remove the sources' Library files too — deleting a topic
    // must not leave its PDFs/texts behind in the Library, in
    // stats, and in every future backup (the per-source delete
    // below has always done this; the topic path must match).
    final sources = await widget.learn.store.sourcesForTopic(_topic.id);
    await widget.learn.store.deleteTopic(_topic.id);
    for (final source in sources) {
      final rel = source.fileRelPath;
      if (rel != null) await widget.learn.library.delete(rel);
      final textRel = source.textRelPath;
      if (textRel != null) await widget.learn.library.delete(textRel);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  // ------------------------------------------------------------ sources

  Future<void> _addLink() async {
    final url = await promptText(context, title: 'Add link', label: 'URL');
    if (url == null || url.isEmpty) return;
    await widget.learn.imports
        .importLink(topicId: _topic.id, url: url);
    _load();
  }

  Future<void> _importFile() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
            label: 'Documents', extensions: ['pdf', 'txt', 'md', 'html']),
        XTypeGroup(label: 'All files'),
      ],
    );
    if (picked == null || !mounted) return;
    try {
      final source = await widget.learn.imports.importFile(
        topicId: _topic.id,
        sourcePath: picked.path,
        originalName: picked.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(source.kind == SourceKind.pdf ||
                source.kind == SourceKind.txt
            ? ExtractionStatus.describe(source.extractionStatus)
            : 'File added to the Library.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
    _load();
  }

  Future<void> _addText() async {
    final text = await promptText(context,
        title: 'Add text', label: 'Text', maxLines: 6);
    if (text == null || text.isEmpty) return;
    await widget.learn.imports.importTextContent(
      topicId: _topic.id,
      text: text,
      title: _topic.title,
    );
    _load();
  }

  Future<void> _openSource(Source source) async {
    switch (source.kind) {
      case SourceKind.pdf:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PdfSourceScreen(learn: widget.learn, source: source),
          ),
        );
      case SourceKind.txt:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ReadingScreen(learn: widget.learn, source: source),
          ),
        );
      case SourceKind.link:
        final uri = Uri.tryParse(source.url ?? '');
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      default:
        final rel = source.fileRelPath;
        if (rel != null) {
          final file = widget.learn.library.resolve(rel);
          await launchUrl(Uri.file(file.path));
        }
    }
    _load(); // marked points may have changed in the reader
  }

  Future<void> _deleteSource(Source source) async {
    if (!await confirmDelete(context, 'source')) return;
    await widget.learn.store.deleteSource(source.id);
    final rel = source.fileRelPath;
    if (rel != null) await widget.learn.library.delete(rel);
    final textRel = source.textRelPath;
    if (textRel != null) await widget.learn.library.delete(textRel);
    _load();
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Topic'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Import quiz pack',
            onPressed: _importPack,
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outline),
            tooltip: 'Move to project',
            onPressed: _move,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete topic',
            onPressed: _deleteTopic,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.page, Gap.md, Space.page, Gap.lg),
              children: [
                const NeoEyebrow('Topic'),
                const SizedBox(height: Space.s3),
                InkWell(
                  onTap: _rename,
                  child: Text(_topic.title,
                      style: theme.textTheme.headlineLarge),
                ),
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    DropdownButton<String>(
                      value: _topic.status,
                      items: [
                        for (final s in TopicStatus.all)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await widget.learn.store
                            .updateTopic(_topic.id, status: v);
                        _load();
                      },
                    ),
                    const SizedBox(width: Gap.md),
                    ActionChip(
                      avatar: const Icon(Icons.school_outlined, size: 18),
                      label: Text(_topic.track ?? 'No track'),
                      onPressed: _editTrack,
                    ),
                  ],
                ),
                if (_topic.triggerUrl != null) ...[
                  const SizedBox(height: Gap.md),
                  NeoPanel(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Space.s6, vertical: Space.s2),
                    child: NeoListRow(
                      icon: Icons.link,
                      title: 'Sparked by',
                      sub: _topic.triggerUrl!,
                      last: true,
                      onTap: () {
                        final uri = Uri.tryParse(_topic.triggerUrl!);
                        if (uri != null) launchUrl(uri);
                      },
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  const NeoNotice(
                    'A reel can spark a topic. Attach a real learning '
                    'source to explore it more deeply.',
                  ),
                ],
                const SizedBox(height: Gap.lg),
                const NeoSectionHead(title: 'Sources'),
                const SizedBox(height: Space.s3),
                if (_sources.isEmpty)
                  Text('No sources yet — import the real material.',
                      style: theme.textTheme.bodyMedium)
                else
                  NeoPanel(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Space.s6, vertical: Space.s2),
                    child: Column(
                      children: [
                        for (final s in _sources)
                          _sourceRow(context, s,
                              last: s == _sources.last),
                      ],
                    ),
                  ),
                const SizedBox(height: Gap.md),
                Wrap(
                  spacing: Gap.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _importFile,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Import file'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _addLink,
                      icon: const Icon(Icons.link),
                      label: const Text('Add link'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _addText,
                      icon: const Icon(Icons.text_snippet_outlined),
                      label: const Text('Add text'),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                NeoSectionHead(title: 'Marked points (${_points.length})'),
                const SizedBox(height: Space.s3),
                if (_points.isEmpty)
                  Text(
                    'None yet. Open a source, read a card, and mark '
                    'the sentence that matters — it becomes a cloze '
                    'card in Learn.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  NeoPanel(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Space.s6, vertical: Space.s2),
                    child: Column(
                      children: [
                        for (final pt in _points)
                          NeoListRow(
                            title: '“${pt.sentence}”',
                            sub: 'Cloze card: ${pt.clozeText}',
                            last: pt == _points.last,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await widget.learn.store
                                    .deleteMarkedPoint(pt.id);
                                _load();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_unminted > 0) ...[
                  const SizedBox(height: Gap.md),
                  FilledButton(
                    onPressed: _buildClozeCards,
                    child: Text('Build cloze cards ($_unminted)'),
                  ),
                ],
                const SizedBox(height: Gap.md),
                OutlinedButton.icon(
                  onPressed: _importPack,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Import quiz pack'),
                ),
              ],
            ),
    );
  }

  Widget _sourceRow(BuildContext context, Source s, {bool last = false}) {
    final icon = switch (s.kind) {
      SourceKind.pdf => Icons.picture_as_pdf_outlined,
      SourceKind.txt => Icons.text_snippet_outlined,
      SourceKind.link => Icons.link,
      SourceKind.htmlQuiz => Icons.quiz_outlined,
      SourceKind.pack => Icons.inventory_2_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    final subtitle = switch (s.kind) {
      SourceKind.link => s.url ?? '',
      SourceKind.pdf ||
      SourceKind.txt =>
        ExtractionStatus.describe(s.extractionStatus),
      _ => s.fileRelPath ?? '',
    };
    return NeoListRow(
      icon: icon,
      title: s.title,
      sub: subtitle,
      last: last,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _deleteSource(s),
      ),
      onTap: () => _openSource(s),
    );
  }
}

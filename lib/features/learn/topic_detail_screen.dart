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
import '../review/review_store.dart';
import '../shared_ui.dart';
import '../store.dart';
import '../today/today_store.dart';
import 'learn_services.dart';
import 'learn_store.dart';
import 'pack_import_ui.dart';
import 'pdf_source_screen.dart';
import 'reading_screen.dart';
import 'session_composer.dart';
import 'session_screen.dart';

class TopicDetailScreen extends StatefulWidget {
  const TopicDetailScreen({
    super.key,
    required this.store,
    required this.learn,
    required this.topic,
    this.reviewStore,
  });

  final Store store;
  final LearnServices learn;
  final Topic topic;
  final ReviewStore? reviewStore;

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  late Topic _topic;
  List<Source> _sources = const [];
  List<MarkedPoint> _points = const [];
  int _unminted = 0;
  int _questionCount = 0;
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
    final questions = await widget.learn.engine.questionsForTopic(_topic.id);
    if (!mounted) return;
    setState(() {
      _topic = topic;
      _sources = sources;
      _points = points;
      _unminted = unminted;
      _questionCount = questions.length;
      _loaded = true;
    });
  }

  Future<void> _practiceTopic() async {
    final reviewStore =
        widget.reviewStore ??
        ReviewStore(widget.learn.db, TodayStore(widget.learn.db));
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          learn: widget.learn,
          reviewStore: reviewStore,
          store: widget.store,
          kind: SessionKind.episode,
          topicId: _topic.id,
        ),
      ),
    );
    _load();
  }

  Future<void> _buildClozeCards() async {
    final minted = await widget.learn.engine.mintClozeFromMarkedPoints(
      _topic.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$minted cloze cards added')));
    _load();
  }

  Future<void> _importPack() async {
    await showPackImportFlow(
      context,
      learn: widget.learn,
      fixedTopicId: _topic.id,
    );
    _load();
  }

  // ------------------------------------------------------------ topic meta

  Future<void> _rename() async {
    final name = await promptText(
      context,
      title: 'Rename topic',
      initial: _topic.title,
      label: 'Title',
    );
    if (name == null || name.isEmpty) return;
    await widget.learn.store.updateTopic(_topic.id, title: name);
    _load();
  }

  Future<void> _editTrack() async {
    final track = await promptText(
      context,
      title: 'Learning track',
      initial: _topic.track ?? '',
      label: 'Track (e.g. Arabic, Health, Money)',
    );
    if (track == null) return;
    await widget.learn.store.updateTopic(
      _topic.id,
      track: track,
      clearTrack: track.isEmpty,
    );
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
    // Fetch the sources first so the confirmation can state
    // the scope (B-08): the cascade takes them, their files,
    // and the topic's packs and questions with it.
    final sources = await widget.learn.store.sourcesForTopic(_topic.id);
    if (!mounted) return;
    if (!await confirmDelete(
      context,
      'topic "${_topic.title}"',
      scope: sources.isEmpty
          ? 'It has no sources.'
          : 'This also deletes its ${sources.length} '
                'source${sources.length == 1 ? '' : 's'} (including their '
                'files), packs and questions.',
    )) {
      return;
    }
    // Remove the sources' Library files too — deleting a topic
    // must not leave its PDFs/texts behind in the Library, in
    // stats, and in every future backup (the per-source delete
    // below has always done this; the topic path must match).
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
    await widget.learn.imports.importLink(topicId: _topic.id, url: url);
    _load();
  }

  Future<void> _importFile() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Documents',
          extensions: ['pdf', 'txt', 'md', 'html'],
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source.kind == SourceKind.pdf || source.kind == SourceKind.txt
                ? ExtractionStatus.describe(source.extractionStatus)
                : 'File added to the Library.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
    _load();
  }

  Future<void> _addText() async {
    final text = await promptText(
      context,
      title: 'Add text',
      label: 'Text',
      maxLines: 6,
    );
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
            builder: (_) => ReadingScreen(learn: widget.learn, source: source),
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

  // ------------------------------------------------------------ build

  final Set<int> _selectedSourceIds = {};
  final Set<int> _selectedPointIds = {};

  bool get _isSelectingSources => _selectedSourceIds.isNotEmpty;
  bool get _isSelectingPoints => _selectedPointIds.isNotEmpty;
  bool get _isSelectionMode => _isSelectingSources || _isSelectingPoints;

  void _exitSelectionMode() {
    setState(() {
      _selectedSourceIds.clear();
      _selectedPointIds.clear();
    });
  }

  void _toggleSourceSelection(int id) {
    setState(() {
      _selectedPointIds.clear();
      if (_selectedSourceIds.contains(id)) {
        _selectedSourceIds.remove(id);
      } else {
        _selectedSourceIds.add(id);
      }
    });
  }

  void _togglePointSelection(int id) {
    setState(() {
      _selectedSourceIds.clear();
      if (_selectedPointIds.contains(id)) {
        _selectedPointIds.remove(id);
      } else {
        _selectedPointIds.add(id);
      }
    });
  }

  Future<void> _deleteSelectedSources() async {
    final count = _selectedSourceIds.length;
    if (count == 0) return;
    if (!await confirmDelete(
      context,
      '$count source${count > 1 ? 's' : ''}',
      scope: 'Their files are deleted too.',
    )) {
      return;
    }
    final toDelete = _sources
        .where((s) => _selectedSourceIds.contains(s.id))
        .toList();
    for (final s in toDelete) {
      await widget.learn.store.deleteSource(s.id);
      final rel = s.fileRelPath;
      if (rel != null) await widget.learn.library.delete(rel);
      final textRel = s.textRelPath;
      if (textRel != null) await widget.learn.library.delete(textRel);
    }
    _selectedSourceIds.clear();
    _load();
  }

  Future<void> _deleteSelectedPoints() async {
    final count = _selectedPointIds.length;
    if (count == 0) return;
    if (!await confirmDelete(
      context,
      '$count marked point${count > 1 ? 's' : ''}',
      scope: 'Cards already made from them stay.',
    )) {
      return;
    }
    for (final id in _selectedPointIds) {
      await widget.learn.store.deleteMarkedPoint(id);
    }
    _selectedPointIds.clear();
    _load();
  }

  Future<void> _mintSelectedPoints() async {
    final ids = _selectedPointIds.toList();
    if (ids.isEmpty) return;
    final minted = await widget.learn.engine.mintClozeForPointIds(ids);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$minted cloze card${minted == 1 ? '' : 's'} added'),
      ),
    );
    _exitSelectionMode();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelecting = _isSelectionMode;
    final selectionCount = _isSelectingSources
        ? _selectedSourceIds.length
        : _selectedPointIds.length;

    return PopScope(
      canPop: !isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isSelecting) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: isSelecting
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel selection',
                  onPressed: _exitSelectionMode,
                ),
                title: Text('$selectionCount selected'),
                actions: [
                  if (_isSelectingSources) ...[
                    IconButton(
                      icon: Icon(
                        _selectedSourceIds.length == _sources.length
                            ? Icons.deselect_outlined
                            : Icons.select_all_outlined,
                      ),
                      tooltip: _selectedSourceIds.length == _sources.length
                          ? 'Deselect all'
                          : 'Select all',
                      onPressed: () {
                        setState(() {
                          if (_selectedSourceIds.length == _sources.length) {
                            _selectedSourceIds.clear();
                          } else {
                            _selectedSourceIds.addAll(
                              _sources.map((s) => s.id),
                            );
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete selected sources',
                      onPressed: _deleteSelectedSources,
                    ),
                  ] else if (_isSelectingPoints) ...[
                    IconButton(
                      icon: const Icon(Icons.school_outlined),
                      tooltip: 'Mint cloze cards',
                      onPressed: _mintSelectedPoints,
                    ),
                    IconButton(
                      icon: Icon(
                        _selectedPointIds.length == _points.length
                            ? Icons.deselect_outlined
                            : Icons.select_all_outlined,
                      ),
                      tooltip: _selectedPointIds.length == _points.length
                          ? 'Deselect all'
                          : 'Select all',
                      onPressed: () {
                        setState(() {
                          if (_selectedPointIds.length == _points.length) {
                            _selectedPointIds.clear();
                          } else {
                            _selectedPointIds.addAll(_points.map((p) => p.id));
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete selected points',
                      onPressed: _deleteSelectedPoints,
                    ),
                  ],
                ],
              )
            : AppBar(
                title: const Text('Topic'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: 'Import quiz pack',
                    onPressed: _importPack,
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'More actions',
                    onSelected: (value) {
                      if (value == 'select_sources') {
                        if (_sources.isNotEmpty) {
                          setState(() {
                            _selectedSourceIds.add(_sources.first.id);
                          });
                        }
                      }
                      if (value == 'select_points') {
                        if (_points.isNotEmpty) {
                          setState(() {
                            _selectedPointIds.add(_points.first.id);
                          });
                        }
                      }
                      if (value == 'move') _move();
                      if (value == 'rename') _rename();
                      if (value == 'delete') _deleteTopic();
                    },
                    itemBuilder: (context) => [
                      if (_sources.isNotEmpty)
                        const PopupMenuItem(
                          value: 'select_sources',
                          child: Row(
                            children: [
                              Icon(Icons.checklist_outlined, size: 20),
                              SizedBox(width: 12),
                              Text('Select sources'),
                            ],
                          ),
                        ),
                      if (_points.isNotEmpty)
                        const PopupMenuItem(
                          value: 'select_points',
                          child: Row(
                            children: [
                              Icon(Icons.checklist_outlined, size: 20),
                              SizedBox(width: 12),
                              Text('Select marked points'),
                            ],
                          ),
                        ),
                      if (_sources.isNotEmpty || _points.isNotEmpty)
                        const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 12),
                            Text('Rename topic'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'move',
                        child: Row(
                          children: [
                            Icon(Icons.drive_file_move_outline, size: 20),
                            SizedBox(width: 12),
                            Text('Move to project'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Delete topic',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Gap.md,
                  Space.page,
                  Gap.lg,
                ),
                children: [
                  InkWell(
                    onTap: _rename,
                    child: Text(
                      _topic.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        // D-052: sans (serif retired).
                        fontFamily: fontSans,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Space.s1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<String>(
                        value: _topic.status,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final s in TopicStatus.all)
                            DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          await widget.learn.store.updateTopic(
                            _topic.id,
                            status: v,
                          );
                          _load();
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.school_outlined, size: 16),
                        label: Text(_topic.track ?? 'No track'),
                        visualDensity: VisualDensity.compact,
                        onPressed: _editTrack,
                      ),
                      if (_questionCount > 0)
                        FilledButton.tonalIcon(
                          onPressed: _practiceTopic,
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: Text('Practice ($_questionCount)'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                  if (_topic.triggerUrl != null) ...[
                    const SizedBox(height: Gap.md),
                    NeoListRow(
                      icon: Icons.link,
                      title: 'Sparked by',
                      sub: _topic.triggerUrl!,
                      last: true,
                      onTap: () {
                        final uri = Uri.tryParse(_topic.triggerUrl!);
                        if (uri != null) launchUrl(uri);
                      },
                    ),
                  ],
                  const SizedBox(height: Gap.lg),
                  NeoSectionHead(
                    title: 'Sources',
                    actionLabel: 'Add source',
                    onAction: _showAddSourceSheet,
                  ),
                  const SizedBox(height: Space.s2),
                  if (_sources.isEmpty)
                    Text(
                      'No sources yet — import the real material.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    Column(
                      children: [
                        for (final s in _sources)
                          _sourceRow(context, s, last: s == _sources.last),
                      ],
                    ),
                  const SizedBox(height: Gap.lg),
                  NeoSectionHead(title: 'Marked points (${_points.length})'),
                  const SizedBox(height: Space.s2),
                  if (_points.isEmpty)
                    Text(
                      'No marked points yet.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    Column(
                      children: [
                        for (final pt in _points)
                          NeoListRow(
                            leading: _isSelectingPoints
                                ? NeoCheck(
                                    done: _selectedPointIds.contains(pt.id),
                                  )
                                : null,
                            title: '“${pt.sentence}”',
                            sub: 'Cloze card: ${pt.clozeText}',
                            last: pt == _points.last,
                            onTap: () {
                              if (_isSelectingPoints) {
                                _togglePointSelection(pt.id);
                              }
                            },
                            onLongPress: () {
                              _togglePointSelection(pt.id);
                            },
                          ),
                      ],
                    ),
                  if (_unminted > 0) ...[
                    const SizedBox(height: Gap.md),
                    FilledButton.tonal(
                      onPressed: _buildClozeCards,
                      child: Text('Build cloze cards ($_unminted)'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  void _showAddSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Import file (PDF, TXT, HTML)'),
              onTap: () {
                Navigator.pop(ctx);
                _importFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Add link'),
              onTap: () {
                Navigator.pop(ctx);
                _addLink();
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Add text note'),
              onTap: () {
                Navigator.pop(ctx);
                _addText();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Import quiz pack'),
              onTap: () {
                Navigator.pop(ctx);
                _importPack();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceRow(BuildContext context, Source s, {bool last = false}) {
    final icon = switch (s.kind) {
      SourceKind.pdf => Icons.picture_as_pdf_outlined,
      SourceKind.txt => Icons.text_snippet_outlined,
      SourceKind.link => Icons.link,
      SourceKind.htmlQuiz => Icons.html_outlined,
      SourceKind.pack => Icons.inventory_2_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    final subtitle = switch (s.kind) {
      SourceKind.link => s.url ?? '',
      SourceKind.pdf ||
      SourceKind.txt => ExtractionStatus.describe(s.extractionStatus),
      _ => s.fileRelPath ?? '',
    };
    final isSelected = _selectedSourceIds.contains(s.id);

    return NeoListRow(
      leading: _isSelectingSources ? NeoCheck(done: isSelected) : null,
      icon: _isSelectingSources ? null : icon,
      title: s.title,
      sub: subtitle,
      last: last,
      onTap: () {
        if (_isSelectingSources) {
          _toggleSourceSelection(s.id);
        } else {
          _openSource(s);
        }
      },
      onLongPress: () {
        _toggleSourceSelection(s.id);
      },
    );
  }
}

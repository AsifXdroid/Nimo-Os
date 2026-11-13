/// LEARN — Topics & Sources (D-050; renamed in redesign
/// R3 per the adopted IA: one name per concept).
///
/// Tab 1: Topics — Filterable by status (All, Inbox, Active, Parked),
/// with clear tracks and quick action to create a new topic.
///
/// Tab 2: Sources — Dedicated overview of all imported materials
/// (PDFs, text notes, HTML files, links) with file stats and direct opening.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'learn_services.dart';
import 'learn_store.dart';
import 'pdf_source_screen.dart';
import 'reading_screen.dart';
import 'topic_detail_screen.dart';

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key, required this.store, required this.learn});

  final Store store;
  final LearnServices learn;

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Topic> _allTopics = const [];
  List<Source> _allSources = const [];
  Map<int, String> _projectNames = const {};
  ({int files, int bytes}) _stats = (files: 0, bytes: 0);
  int _inboxProjectId = 0;
  bool _loaded = false;
  bool _loadFailed = false;

  // Filter state for Topics tab
  String _selectedFilter = 'All'; // 'All', 'Inbox', 'active', 'parked', 'done'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final inboxId = await widget.learn.store.inboxProjectId();
      final all = await widget.learn.store.allTopics();
      final sources = await widget.learn.store.allSources();
      final names = <int, String>{};
      for (final ws in await widget.store.workspaces()) {
        for (final prj in await widget.store.projects(ws.id)) {
          names[prj.id] = prj.name;
        }
      }
      final stats = await widget.learn.library.stats();
      if (!mounted) return;
      setState(() {
        _inboxProjectId = inboxId;
        _allTopics = all;
        _allSources = sources;
        _projectNames = names;
        _stats = stats;
        _loaded = true;
        _loadFailed = false;
      });
    } catch (_) {
      // B-11: a failed load is an error state with a retry,
      // never an endless skeleton (the Progress pattern).
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
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
    final title = await promptText(context, title: 'New topic', label: 'Title');
    if (title == null || title.isEmpty) return;
    final topic = await widget.learn.store.createTopic(
      projectId: _inboxProjectId,
      title: title,
    );
    if (!mounted) return;
    await _openTopic(topic);
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
    _load();
  }

  Future<void> _importDocument() async {
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
    final topics = _allTopics;
    if (!mounted) return;
    final choice = await showModalBottomSheet<({bool isNew, Topic? topic})>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Import into topic…')),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New topic (Inbox)'),
              onTap: () => Navigator.pop(context, (isNew: true, topic: null)),
            ),
            for (final t in topics)
              ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(t.title),
                onTap: () => Navigator.pop(context, (isNew: false, topic: t)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final topic = choice.isNew
          ? await widget.learn.store.createTopic(
              projectId: _inboxProjectId,
              title: picked.name,
            )
          : choice.topic!;
      final source = await widget.learn.imports.importFile(
        topicId: topic.id,
        sourcePath: picked.path,
        originalName: picked.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source.kind == SourceKind.pdf || source.kind == SourceKind.txt
                ? ExtractionStatus.describe(source.extractionStatus)
                : 'Imported into “${topic.title}”.',
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

  List<Topic> get _filteredTopics {
    return _allTopics.where((t) {
      if (_searchQuery.isNotEmpty &&
          !t.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_selectedFilter == 'Inbox') {
        return t.projectId == _inboxProjectId;
      } else if (_selectedFilter != 'All') {
        return t.status.toLowerCase() == _selectedFilter.toLowerCase();
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inboxCount = _allTopics
        .where((t) => t.projectId == _inboxProjectId)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Topics'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: scheme.primary,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 18),
                  const SizedBox(width: 8),
                  Text('Topics (${_allTopics.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('Sources (${_allSources.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _newTopic();
          } else {
            _importDocument();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0 ? 'New Topic' : 'Add Source'),
      ),
      body: _loadFailed && !_loaded
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Topics could not be loaded. '
                      'Your records are unchanged.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Gap.md),
                    FilledButton(
                      onPressed: () {
                        setState(() => _loadFailed = false);
                        _load();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : !_loaded
          ? const Padding(
              padding: EdgeInsets.fromLTRB(
                Space.page,
                Gap.md,
                Space.page,
                Gap.lg,
              ),
              child: DelayedSkeleton(skeleton: SkeletonList(panels: 2)),
            )
          : TabBarView(
              controller: _tabController,
              children: [_topicsTab(context, inboxCount), _sourcesTab(context)],
            ),
    );
  }

  Widget _topicsTab(BuildContext context, int inboxCount) {
    final theme = Theme.of(context);
    final displayed = _filteredTopics;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.page, Gap.md, Space.page, 80),
      children: [
        // Quick search bar
        TextField(
          decoration: InputDecoration(
            hintText: 'Search topics…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (q) => setState(() => _searchQuery = q.trim()),
        ),
        const SizedBox(height: Gap.sm),
        // Filter pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('All', _allTopics.length),
              const SizedBox(width: 8),
              _filterChip('Inbox', inboxCount),
              const SizedBox(width: 8),
              _filterChip(
                'active',
                _allTopics.where((t) => t.status == 'active').length,
              ),
              const SizedBox(width: 8),
              _filterChip(
                'parked',
                _allTopics.where((t) => t.status == 'parked').length,
              ),
              const SizedBox(width: 8),
              _filterChip(
                'done',
                _allTopics.where((t) => t.status == 'done').length,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        if (displayed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No topics match "$_searchQuery".'
                        : 'No topics in this view.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              for (final t in displayed)
                _topicRow(context, t, last: t == displayed.last),
            ],
          ),
      ],
    );
  }

  Widget _filterChip(String label, int count) {
    final selected = _selectedFilter == label;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayLabel = label == 'active'
        ? 'Active'
        : label == 'parked'
        ? 'Parked'
        : label == 'done'
        ? 'Done'
        : label;

    return FilterChip(
      selected: selected,
      label: Text('$displayLabel ($count)'),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        color: selected ? scheme.onPrimary : scheme.onSurface,
      ),
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      selectedColor: scheme.primary,
      showCheckmark: false,
      onSelected: (_) => setState(() => _selectedFilter = label),
    );
  }

  Widget _sourcesTab(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.page, Gap.md, Space.page, 80),
      children: [
        // Storage banner
        NeoPanel(
          level: NeoSurfaceLevel.flat,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.source_outlined,
                  color: scheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_stats.files} files · ${(_stats.bytes / 1024).toStringAsFixed(0)} KB stored on this device',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PDFs, notes & learning assets',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Import document',
                icon: const Icon(Icons.upload_file),
                onPressed: _importDocument,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        const NeoSectionHead(title: 'All Imported Sources'),
        const SizedBox(height: Space.s2),
        if (_allSources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 48,
                    color: scheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text('No sources yet.', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _importDocument,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import a document'),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              for (final s in _allSources)
                _sourceItemRow(context, s, last: s == _allSources.last),
            ],
          ),
      ],
    );
  }

  Widget _sourceItemRow(BuildContext context, Source s, {bool last = false}) {
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

    return NeoListRow(
      icon: icon,
      title: s.title,
      sub: subtitle,
      last: last,
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _openSource(s),
    );
  }

  Widget _topicRow(BuildContext context, Topic t, {bool last = false}) {
    final isInbox = t.projectId == _inboxProjectId;
    return NeoListRow(
      icon: t.triggerUrl != null
          ? Icons.link
          : isInbox
          ? Icons.inbox_outlined
          : Icons.lightbulb_outline,
      title: t.title,
      sub: [
        if (isInbox) 'Inbox' else _projectNames[t.projectId] ?? '',
        t.status,
        if (t.track != null) t.track!,
      ].where((s) => s.isNotEmpty).join(' · '),
      last: last,
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _openTopic(t),
    );
  }
}

/// ITEM — item list inside one project (S1).
/// Rendering and creation are driven by the item-type registry.
///
/// S4 additions: the project's topics render above the items as
/// their own card type (§R2.3), and creating a `link_card` goes
/// through LinkCardService (card + topic trigger, LINK rework).
/// Both appear only when the learn services are wired in.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../learn/learn_services.dart';
import '../learn/learn_store.dart';
import '../learn/topic_detail_screen.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'item_detail_screen.dart';
import 'item_registry.dart';
import 'link_card/link_card_service.dart';
import 'link_card/thumbnail_service.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({
    super.key,
    required this.store,
    required this.project,
    this.learn,
    this.thumbnails,
  });

  final Store store;
  final Project project;

  /// S4 wiring (optional so S1-era constructions keep working).
  final LearnServices? learn;
  final ThumbnailService? thumbnails;

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

/// Type-tolerant payload read: a restored database is the one
/// route by which a mistyped payload value can enter, and it
/// must degrade to "absent", never a build-time cast crash.
String? _payloadString(Item item, String key) {
  final v = item.payload?[key];
  return v is String ? v : null;
}

class _ItemsScreenState extends State<ItemsScreen> {
  late Future<List<Item>> _items;
  List<Topic> _topics = const [];

  LinkCardService? get _linkCards {
    final learn = widget.learn;
    final thumbs = widget.thumbnails;
    if (learn == null || thumbs == null) return null;
    return LinkCardService(widget.store, learn.store, thumbs);
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = widget.store.items(widget.project.id);
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    final learn = widget.learn;
    if (learn == null) return;
    final topics = await learn.store.topicsForProject(widget.project.id);
    if (!mounted) return;
    setState(() => _topics = topics);
  }

  Future<void> _add() async {
    final def = await showModalBottomSheet<ItemTypeDef>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Add item')),
            for (final t in itemTypes)
              ListTile(
                leading: Icon(t.icon),
                title: Text(t.label),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (def == null || !mounted) return;
    if (def.key == ItemType.linkCard) {
      await _addLinkCard();
      return;
    }
    if (def.key == ItemType.htmlQuiz) {
      await _addHtmlQuiz();
      return;
    }
    final title = await promptText(context,
        title: 'New ${def.label.toLowerCase()}', label: 'Title');
    if (title == null || title.isEmpty) return;
    final item = await widget.store.createItem(
      widget.project.id,
      type: def.key,
      title: title,
    );
    setState(_reload);
    if (!mounted) return;
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
    setState(_reload);
  }

  Future<void> _addLinkCard() async {
    final url = await promptText(context,
        title: 'New link card', label: 'URL (e.g. a reel link)');
    if (url == null || url.isEmpty || !mounted) return;
    final title = await promptText(context,
        title: 'Title (optional)',
        label: 'Title — blank uses the site name');
    if (!mounted) return;
    final service = _linkCards;
    final Item item;
    if (service != null) {
      item = await service.createLinkCard(
        projectId: widget.project.id,
        url: url,
        title: (title == null || title.isEmpty) ? null : title,
      );
    } else {
      item = await widget.store.createItem(
        widget.project.id,
        type: ItemType.linkCard,
        title: LinkCardService.titleFromUrl(url),
        payload: {'url': url},
      );
    }
    setState(_reload);
    if (!mounted) return;
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
    setState(_reload);
  }

  Future<void> _addHtmlQuiz() async {
    final learn = widget.learn;
    if (learn == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library is not available.')),
      );
      return;
    }
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'HTML quizzes', extensions: ['html', 'htm']),
      ],
    );
    if (picked == null || !mounted) return;
    final String rel;
    try {
      rel = await learn.library.importFile(
        'html_quizzes',
        picked.path,
        picked.name,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import that quiz: $e')),
      );
      return;
    }
    if (!mounted) return;
    final base = p.basenameWithoutExtension(picked.name);
    final title = base.isEmpty ? picked.name : base;
    final item = await widget.store.createItem(
      widget.project.id,
      type: ItemType.htmlQuiz,
      title: title,
      payload: {'file_rel_path': rel},
    );
    setState(_reload);
    if (!mounted) return;
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
    setState(_reload);
  }

  Future<void> _addTopic() async {
    final learn = widget.learn;
    if (learn == null) return;
    final title =
        await promptText(context, title: 'New topic', label: 'Title');
    if (title == null || title.isEmpty) return;
    await learn.store.createTopic(
        projectId: widget.project.id, title: title);
    _loadTopics();
  }

  Future<void> _delete(Item item) async {
    if (!await confirmDelete(context, 'item')) return;
    await widget.store.deleteItem(item.id);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.project.name)),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Item>>(
        future: _items,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, Gap.lg),
            children: [
              if (widget.learn != null) ...[
                Row(
                  children: [
                    const Expanded(
                      child: NeoSectionHead(title: 'Topics'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'New topic',
                      onPressed: _addTopic,
                    ),
                  ],
                ),
                const SizedBox(height: Space.s3),
                if (_topics.isEmpty)
                  Text('No topics in this project yet.',
                      style: Theme.of(context).textTheme.bodyMedium)
                else
                  NeoPanel(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Space.s6, vertical: Space.s2),
                    child: Column(
                      children: [
                        for (final t in _topics)
                          NeoListRow(
                            icon: Icons.lightbulb_outline,
                            title: t.title,
                            sub: t.status,
                            last: t == _topics.last,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TopicDetailScreen(
                                    store: widget.store,
                                    learn: widget.learn!,
                                    topic: t,
                                  ),
                                ),
                              );
                              _loadTopics();
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: Gap.lg),
                const NeoSectionHead(title: 'Items'),
                const SizedBox(height: Space.s3),
              ],
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'A clear starting point.\nNo items yet — tap + '
                    'to add a note, checklist, or link card.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                NeoPanel(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.s6, vertical: Space.s2),
                  child: Column(
                    children: [
                      for (final item in list)
                        _itemRow(context, item, last: item == list.last),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _itemRow(BuildContext context, Item item, {bool last = false}) {
    final def = itemTypeDef(item.type);
    return NeoListRow(
      leading: item.type == ItemType.linkCard
          ? _linkThumb(item)
          : NeoGlyph(icon: def.icon),
      title: item.title,
      sub: item.type == ItemType.linkCard
          ? (_payloadString(item, 'url') ?? def.label)
          : def.label,
      last: last,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(item),
      ),
      onTap: () async {
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
        setState(_reload);
      },
    );
  }

  /// Square preview for a link card: the cached thumbnail when
  /// there is one, otherwise the designed fallback (D-003 layer 3)
  /// — never a broken-image glyph.
  Widget _linkThumb(Item item) {
    final theme = Theme.of(context);
    final name = _payloadString(item, LinkCardService.thumbKey);
    final file = widget.thumbnails?.fileFor(name);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: file != null
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallbackThumb(theme),
              )
            : _fallbackThumb(theme),
      ),
    );
  }

  Widget _fallbackThumb(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.link, color: theme.colorScheme.primary),
    );
  }
}

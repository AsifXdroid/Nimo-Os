/// ITEM — detail/editor for one item (S1: note + checklist).
/// The body switches on the item's registry type; new types add a
/// case here (or their own screen) when they are registered.
/// S4 adds the link_card body (preview card, D-003 layers, and the
/// jump to the card's topic).
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../learn/learn_services.dart';
import '../learn/topic_detail_screen.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'html_quiz/html_quiz_player_screen.dart';
import 'link_card/link_card_service.dart';
import 'link_card/thumbnail_service.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({
    super.key,
    required this.store,
    required this.item,
    this.learn,
    this.thumbnails,
  });

  final Store store;
  final Item item;

  /// S4 wiring for the link_card body (optional: without it the
  /// card still shows its fallback preview and URL).
  final LearnServices? learn;
  final ThumbnailService? thumbnails;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _bodyController;

  // Concurrent-edit detection for notes (Spaces amendment
  // §7, applied to the existing editor): a baseline snapshot
  // of the row as opened — title, note, payload and the sync
  // stamp. Local store writes never move updated_hlc; a
  // winning remote sync apply rewrites it together with the
  // content. A stamp change WITH a content change is a newer
  // remote version; a stamp change alone is an export echo
  // and stays silent.
  String? _baseTitle;
  String? _baseNote;
  String? _basePayloadJson;
  String? _baseHlc;
  bool _remoteNewer = false;
  Item? _remoteItem;

  @override
  void initState() {
    super.initState();
    _bodyController = TextEditingController(text: widget.item.note ?? '');
    _setBaseline(widget.item);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bodyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.item.type == ItemType.note) {
      _checkRemote();
    }
  }

  static String? _payloadJson(Item item) =>
      item.payload == null ? null : jsonEncode(item.payload);

  void _setBaseline(Item item) {
    _baseTitle = item.title;
    _baseNote = item.note;
    _basePayloadJson = _payloadJson(item);
    _baseHlc = item.updatedHlc;
  }

  /// Re-read the row and compare it with the baseline.
  /// Returns true when a newer remote version is present
  /// (and the warning should be showing).
  Future<bool> _checkRemote() async {
    if (widget.item.type != ItemType.note) return false;
    final Item fresh;
    try {
      fresh = await widget.store.itemById(widget.item.id);
    } catch (_) {
      return _remoteNewer; // row unreadable — leave state as-is
    }
    if (fresh.updatedHlc == _baseHlc) return _remoteNewer;
    final contentChanged = fresh.title != _baseTitle ||
        fresh.note != _baseNote ||
        _payloadJson(fresh) != _basePayloadJson;
    if (!contentChanged) {
      // Export echo: our own export stamped the row; the
      // content is exactly what we last saw. Absorb silently.
      _baseHlc = fresh.updatedHlc;
      return _remoteNewer;
    }
    if (!mounted) return true;
    setState(() {
      _remoteNewer = true;
      _remoteItem = fresh;
    });
    return true;
  }

  Future<void> _saveNote(Item item) async {
    if (await _checkRemote()) return; // warning is showing
    await widget.store.updateItem(item.id, note: _bodyController.text);
    // A local save moves neither the stamp nor title/payload;
    // the baseline's note follows what we wrote.
    _baseNote = _bodyController.text;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  void _reloadRemote() {
    final remote = _remoteItem;
    if (remote == null) return;
    _bodyController.text = remote.note ?? '';
    _setBaseline(remote);
    setState(() {
      _remoteNewer = false;
      _remoteItem = null;
    });
  }

  void _keepMine() {
    final remote = _remoteItem;
    if (remote != null) _setBaseline(remote);
    setState(() {
      _remoteNewer = false;
      _remoteItem = null;
    });
  }

  Widget _remoteWarning(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(RadiusToken.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This note was changed on another device. '
            'Saving will replace that version.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _reloadRemote, child: const Text('Reload')),
              TextButton(onPressed: _keepMine, child: const Text('Keep mine')),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: switch (item.type) {
        ItemType.note => _noteBody(item),
        ItemType.checklist => _ChecklistBody(store: widget.store, item: item),
        ItemType.linkCard => _LinkCardBody(
            store: widget.store,
            item: item,
            learn: widget.learn,
            thumbnails: widget.thumbnails,
          ),
        ItemType.htmlQuiz => _HtmlQuizBody(item: item, learn: widget.learn),
        _ => const Center(child: Text('Unknown item type')),
      },
    );
  }

  Widget _noteBody(Item item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Space.page, Gap.md, Space.page, Gap.md),
      child: Column(
        children: [
          if (_remoteNewer) ...[
            _remoteWarning(context),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: TextField(
              controller: _bodyController,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                hintText: 'Write your note…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _saveNote(item),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// LINK — the link-card body (S4): square preview (cached
/// thumbnail or the designed fallback — D-003), the URL, and the
/// three thumbnail actions (open, auto-fetch, attach image) plus
/// the jump to the card's topic.
class _LinkCardBody extends StatefulWidget {
  const _LinkCardBody({
    required this.store,
    required this.item,
    required this.learn,
    required this.thumbnails,
  });

  final Store store;
  final Item item;
  final LearnServices? learn;
  final ThumbnailService? thumbnails;

  @override
  State<_LinkCardBody> createState() => _LinkCardBodyState();
}

class _LinkCardBodyState extends State<_LinkCardBody> {
  late Item _item;
  bool _busy = false;

  LinkCardService? get _service {
    final learn = widget.learn;
    final thumbs = widget.thumbnails;
    if (learn == null || thumbs == null) return null;
    return LinkCardService(widget.store, learn.store, thumbs);
  }

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  Future<void> _fetch() async {
    final service = _service;
    if (service == null) return;
    setState(() => _busy = true);
    final updated = await service.tryFetchThumbnail(_item);
    if (!mounted) return;
    setState(() {
      _item = updated;
      _busy = false;
    });
    if (updated.payload?[LinkCardService.thumbKey] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No preview image found — the fallback card '
            'is shown, or attach your own image.'),
      ));
    }
  }

  Future<void> _attach() async {
    final service = _service;
    if (service == null) return;
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp']),
      ],
    );
    if (picked == null || !mounted) return;
    try {
      final updated =
          await service.attachUserImage(_item, picked.path, picked.name);
      if (!mounted) return;
      setState(() => _item = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach that image: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = _service;
    // Type-tolerant payload reads (see items_screen.dart): a
    // mistyped value from a restored DB degrades, never crashes.
    final urlRaw = _item.payload?['url'];
    final url = urlRaw is String ? urlRaw : '';
    final thumbRaw = _item.payload?[LinkCardService.thumbKey];
    final thumbName = thumbRaw is String ? thumbRaw : null;
    final thumbFile = widget.thumbnails?.fileFor(thumbName);
    final topicId = (_item.payload?['topic_id'] as num?)?.toInt();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Space.page, Gap.md, Space.page, Gap.lg),
      children: [
        // Square preview card (D-003): image when we have one,
        // designed fallback otherwise — never a broken glyph.
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(RadiusToken.card),
            child: thumbFile != null
                ? Image.file(
                    thumbFile,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _fallbackPreview(theme),
                  )
                : _fallbackPreview(theme),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(url, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () {
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open link'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || service == null ? null : _fetch,
              icon: const Icon(Icons.image_search_outlined),
              label: const Text('Fetch preview'),
            ),
            OutlinedButton.icon(
              onPressed: service == null ? null : _attach,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Attach image'),
            ),
            if (topicId != null && widget.learn != null)
              OutlinedButton.icon(
                onPressed: () async {
                  final topic =
                      await widget.learn!.store.topicById(topicId);
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TopicDetailScreen(
                        store: widget.store,
                        learn: widget.learn!,
                        topic: topic,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('Open topic'),
              ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 16),
        const NeoNotice(
          'This link is a topic trigger: the topic holds the real '
          'sources you attach for learning.',
        ),
      ],
    );
  }

  Widget _fallbackPreview(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link, size: 64, color: scheme.primary),
            const SizedBox(height: 8),
            Text(_item.title, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// HTML quiz body (S5 legacy player): the quiz file name and
/// the Play button that pushes the hardened player screen.
/// The player needs the LibraryStore, routed via [learn] the
/// same way the link-card body gets its services.
class _HtmlQuizBody extends StatelessWidget {
  const _HtmlQuizBody({required this.item, required this.learn});

  final Item item;
  final LearnServices? learn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = item.payload ?? const <String, Object?>{};
    final fileName = htmlQuizFileName(payload);
    final library = learn?.library;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Space.page, Gap.md, Space.page, Gap.lg),
      child: NeoPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const NeoGlyph(icon: Icons.quiz_outlined, size: 48, iconSize: 24),
            const SizedBox(height: 16),
            Text(item.title, style: theme.textTheme.titleMedium),
          if (fileName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(fileName, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: library == null
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HtmlQuizPlayerScreen(
                          library: library,
                          payload: payload,
                          title: item.title,
                        ),
                      ),
                    );
                  },
            child: const Text('Play quiz'),
          ),
            if (library == null) ...[
              const SizedBox(height: 12),
              Text(
                'Library is not available.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChecklistBody extends StatefulWidget {
  const _ChecklistBody({required this.store, required this.item});

  final Store store;
  final Item item;

  @override
  State<_ChecklistBody> createState() => _ChecklistBodyState();
}

class _ChecklistBodyState extends State<_ChecklistBody> {
  late Future<List<ChecklistEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _entries = widget.store.checklistEntries(widget.item.id);
  }

  Future<void> _add() async {
    final text = await promptText(context, title: 'New entry', label: 'Text');
    if (text == null || text.isEmpty) return;
    await widget.store.addChecklistEntry(widget.item.id, text);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<ChecklistEntry>>(
            future: _entries,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snapshot.data!;
              if (list.isEmpty) {
                return const Center(child: Text('No entries yet.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.page, vertical: Gap.sm),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final e = list[i];
                  final theme = Theme.of(context);
                  return InkWell(
                    onTap: () async {
                      await widget.store
                          .setChecklistEntryDone(e.id, !e.isDone);
                      setState(_reload);
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: Space.s3),
                      child: Row(
                        children: [
                          NeoCheck(done: e.isDone),
                          const SizedBox(width: Space.s4),
                          Expanded(
                            child: Text(
                              e.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                decoration: e.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: e.isDone
                                    ? theme.colorScheme.onSurfaceVariant
                                    : null,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await widget.store
                                  .deleteChecklistEntry(e.id);
                              setState(_reload);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add entry'),
          ),
        ),
      ],
    );
  }
}

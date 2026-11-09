/// TODAY — Dua Library screen (Mission 03 Phase 7, V1).
///
/// The owner's personal, owner-maintained Dua collection.
/// The app ships NO Dua content and never generates any:
/// entries exist only when the owner types them here, and
/// every field is stored and shown verbatim. Entries are
/// ordinary items of type 'dua' in the dedicated Dua Library
/// project (see Store.ensureDuaProject); tasks reference an
/// entry through the existing D-042 item link — a reference,
/// never a copy.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../items/dua_item.dart';
import '../items/dua_detail_screen.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../store.dart';
import 'plan_list.dart';

class DuaLibraryScreen extends StatefulWidget {
  const DuaLibraryScreen({
    super.key,
    required this.store,
    this.learn,
    this.thumbnails,
  });

  final Store store;

  /// Passed through to the entry detail (other item types
  /// need it; the Dua body does not).
  final LearnServices? learn;
  final ThumbnailService? thumbnails;

  @override
  State<DuaLibraryScreen> createState() => _DuaLibraryScreenState();
}

class _DuaLibraryScreenState extends State<DuaLibraryScreen> {
  late Future<List<Item>> _data;
  String _query = '';
  String? _category;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<List<Item>> _load() async {
    await widget.store.ensureDuaProject();
    return widget.store.duaEntries();
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _openEntry(Item item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DuaEntryScreen(store: widget.store, item: item),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _toggleBookmark(Item item) async {
    final p = DuaPayload(item);
    await widget.store.updateItemPayload(
      item.id,
      DuaPayload.build(
        arabic: p.arabic,
        transliteration: p.transliteration,
        translation: p.translation,
        source: p.source,
        authenticity: p.authenticity,
        category: p.category,
        bookmarked: !p.bookmarked,
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _addOrEdit([Item? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DuaEntryFormScreen(store: widget.store, existing: existing),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _delete(Item item) async {
    final refs = await widget.store.duaLinkReferenceCount(item.id);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this Dua?'),
        content: Text(
          refs > 0
              ? 'This Dua is linked to $refs '
                    '${refs == 1 ? 'task or routine' : 'tasks or routines'}. '
                    'Deleting it removes the link — the tasks stay. '
                    'This cannot be undone.'
              : 'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.deleteItem(item.id);
    if (mounted) _reload();
  }

  void _showEntrySheet(Item item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                item.title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Dua'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _addOrEdit(item);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                'Delete Dua',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _delete(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryRow(BuildContext context, Item item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = DuaPayload(item);
    return InkWell(
      onTap: () => _openEntry(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (p.has('arabic')) ...[
                    const SizedBox(height: 2),
                    Text(
                      p.arabic!,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.start,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                    ),
                  ],
                  if (p.has('translation')) ...[
                    const SizedBox(height: 2),
                    Text(
                      p.translation!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (p.has('category')) ...[
                    const SizedBox(height: 4),
                    Text(
                      p.category!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('dua_bookmark'),
              tooltip: p.bookmarked ? 'Remove bookmark' : 'Bookmark',
              icon: Icon(
                p.bookmarked ? Icons.bookmark : Icons.bookmark_border,
                size: 20,
              ),
              onPressed: () => _toggleBookmark(item),
            ),
            IconButton(
              key: const ValueKey('dua_options'),
              icon: const Icon(Icons.more_horiz, size: 18),
              tooltip: 'Dua options',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showEntrySheet(item),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dua Library')),
      body: FutureBuilder<List<Item>>(
        future: _data,
        builder: (context, snap) {
          final entries = snap.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = <String>{
            for (final e in entries)
              if (DuaPayload(e).has('category')) DuaPayload(e).category!,
          }.toList()..sort();
          final q = _query.trim().toLowerCase();
          final shown = entries.where((e) {
            final p = DuaPayload(e);
            if (_category != null && p.category != _category) return false;
            if (q.isEmpty) return true;
            return e.title.toLowerCase().contains(q) ||
                (p.arabic ?? '').toLowerCase().contains(q) ||
                (p.translation ?? '').toLowerCase().contains(q) ||
                (p.category ?? '').toLowerCase().contains(q);
          }).toList();
          return ListView(
            padding: const EdgeInsets.all(Space.s4),
            children: [
              Text(
                entries.isEmpty
                    ? 'Your personal collection of verified Duas.'
                    : '${entries.length} '
                          '${entries.length == 1 ? 'entry' : 'entries'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.s4),
              if (entries.isEmpty)
                Text(
                  'Your Dua Library is empty.\n'
                  'Add your own verified entries to build your '
                  'personal collection.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: Space.s3),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                      for (final c in categories)
                        ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (v) =>
                              setState(() => _category = v ? c : null),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.s4),
                if (shown.isEmpty)
                  Text('No entries match.', style: theme.textTheme.bodyMedium)
                else
                  Container(
                    decoration: planSurfaceDeco(context),
                    child: Column(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: Space.s4,
                              endIndent: Space.s4,
                              color: theme.colorScheme.outlineVariant,
                            ),
                          _entryRow(context, shown[i]),
                        ],
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: Space.s5),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _addOrEdit(),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add a Dua'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Add/edit form for one Dua entry. Only the title is
/// required; every other field is optional owner-entered
/// text, stored verbatim — the text fields never capitalise,
/// correct or trim the owner's religious text.
class DuaEntryFormScreen extends StatefulWidget {
  const DuaEntryFormScreen({super.key, required this.store, this.existing});

  final Store store;
  final Item? existing;

  @override
  State<DuaEntryFormScreen> createState() => _DuaEntryFormScreenState();
}

class _DuaEntryFormScreenState extends State<DuaEntryFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _arabic;
  late final TextEditingController _transliteration;
  late final TextEditingController _translation;
  late final TextEditingController _source;
  late final TextEditingController _authenticity;
  late final TextEditingController _category;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = e == null ? null : DuaPayload(e);
    _title = TextEditingController(text: e?.title ?? '');
    _arabic = TextEditingController(text: p?.arabic ?? '');
    _transliteration = TextEditingController(text: p?.transliteration ?? '');
    _translation = TextEditingController(text: p?.translation ?? '');
    _source = TextEditingController(text: p?.source ?? '');
    _authenticity = TextEditingController(text: p?.authenticity ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _arabic,
      _transliteration,
      _translation,
      _source,
      _authenticity,
      _category,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the Dua a title first.')),
      );
      return;
    }
    final bookmarked =
        widget.existing != null && DuaPayload(widget.existing!).bookmarked;
    final payload = DuaPayload.build(
      arabic: _arabic.text,
      transliteration: _transliteration.text,
      translation: _translation.text,
      source: _source.text,
      authenticity: _authenticity.text,
      category: _category.text,
      bookmarked: bookmarked,
    );
    final note = _note.text.trim().isEmpty ? null : _note.text;
    final existing = widget.existing;
    if (existing == null) {
      final project = await widget.store.ensureDuaProject();
      await widget.store.createItem(
        project.id,
        type: ItemType.dua,
        title: title,
        note: note,
        payload: payload,
      );
    } else {
      await widget.store.updateItem(existing.id, title: title, note: note);
      await widget.store.updateItemPayload(existing.id, payload);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    String? hint,
    int maxLines = 1,
    bool rtl = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s4),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        textDirection: rtl ? TextDirection.rtl : null,
        textCapitalization: TextCapitalization.none,
        autocorrect: false,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add a Dua' : 'Edit Dua'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.s4),
        children: [
          Text(
            'Entries are shown exactly as you type them — '
            'please check them against your source.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.s4),
          _field(_title, label: 'Title *'),
          _field(_arabic, label: 'Arabic', maxLines: 4, rtl: true),
          _field(_transliteration, label: 'Transliteration', maxLines: 3),
          _field(_translation, label: 'Translation', maxLines: 3),
          _field(_source, label: 'Source / reference'),
          _field(_authenticity, label: 'Authenticity note', maxLines: 2),
          _field(_category, label: 'Category'),
          _field(_note, label: 'Personal note', maxLines: 3),
          SizedBox(
            height: 48,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}

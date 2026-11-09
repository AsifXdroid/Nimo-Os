/// ITEM — detail/editor for one item (S1: note + checklist).
/// The body switches on the item's registry type; new types add a
/// case here (or their own screen) when they are registered.
/// S4 adds the link_card body (preview card, D-003 layers, and the
/// jump to the card's topic).
library;

import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/glass_ui.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../learn/learn_services.dart';
import '../learn/topic_detail_screen.dart';
import '../quick_add/quick_add_service.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'audio/audio_item.dart';
import 'dua_detail_screen.dart';
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

/// The note editor's save state, shown in its top bar. It
/// reflects real persistence: a write is in flight, the last
/// write landed, edits are waiting, or a remote version has
/// paused saving until the user decides.
enum _NoteSaveStatus { saved, unsaved, saving, conflict }

class _ItemDetailScreenState extends State<ItemDetailScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _bodyController;
  late final TextEditingController _titleController;
  // Focus node for the body field — used by the formatting toolbar
  // to know where to insert prefixes/wrappers.
  final FocusNode _bodyFocus = FocusNode();

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

  // Autosave (Spaces & Notebook brief, 2026-11-01): edits
  // debounce into a write; leaving the editor or background
  // flushes whatever is pending. A brand-new note that was
  // created empty and is still empty at exit is discarded
  // instead of saved — no empty rows.
  Timer? _debounce;
  _NoteSaveStatus _status = _NoteSaveStatus.saved;
  bool _isBrandNewEmpty = false;
  bool _suppressEdit = false;
  bool _disposed = false;
  bool _popping = false;

  bool get _isNote => widget.item.type == ItemType.note;

  @override
  void initState() {
    super.initState();
    _bodyController = TextEditingController(text: widget.item.note ?? '');
    _titleController = TextEditingController(text: widget.item.title);
    _isBrandNewEmpty =
        widget.item.title.isEmpty && (widget.item.note ?? '').isEmpty;
    _setBaseline(widget.item);
    if (_isNote) {
      _bodyController.addListener(_onEdit);
      _titleController.addListener(_onEdit);
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_isNote) {
      // Flush pending edits (or discard a still-empty new
      // note). Fire-and-forget: the store write proceeds
      // while the route finishes popping.
      unawaited(_flushPending());
      _bodyController.removeListener(_onEdit);
      _titleController.removeListener(_onEdit);
    }
    _bodyController.dispose();
    _titleController.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isNote) return;
    if (state == AppLifecycleState.resumed) {
      _checkRemote();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_flushPending());
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
    final contentChanged =
        fresh.title != _baseTitle ||
        fresh.note != _baseNote ||
        _payloadJson(fresh) != _basePayloadJson;
    if (!contentChanged) {
      // Export echo: our own export stamped the row; the
      // content is exactly what we last saw. Absorb silently.
      _baseHlc = fresh.updatedHlc;
      return _remoteNewer;
    }
    if (!mounted) {
      _remoteNewer = true;
      _remoteItem = fresh;
      _status = _NoteSaveStatus.conflict;
      return true;
    }
    setState(() {
      _remoteNewer = true;
      _remoteItem = fresh;
      _status = _NoteSaveStatus.conflict;
    });
    return true;
  }

  void _setStatus(_NoteSaveStatus status) {
    if (!_disposed && mounted) {
      setState(() => _status = status);
    } else {
      _status = status;
    }
  }

  /// The title a save would persist: what the user typed, or
  /// — while the title field is empty — the body's first
  /// line. The editor never stores an empty title.
  String get _effectiveTitle {
    final typed = _titleController.text.trim();
    if (typed.isNotEmpty) return typed;
    return QuickAddService.deriveNoteTitle(_bodyController.text);
  }

  bool get _isDirty =>
      _effectiveTitle != _baseTitle || _bodyController.text != _baseNote;

  void _onEdit() {
    if (_suppressEdit || _disposed) return;
    if (_remoteNewer) return; // paused until Reload / Keep mine
    if (_status != _NoteSaveStatus.unsaved) {
      _setStatus(_NoteSaveStatus.unsaved);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(_autosave());
    });
  }

  Future<void> _autosave() async {
    if (_disposed || !_isNote || _remoteNewer) return;
    if (!_isDirty) {
      _setStatus(_NoteSaveStatus.saved);
      return;
    }
    // The D-046 check runs before EVERY autosave write.
    if (await _checkRemote()) return; // conflict — banner shows
    await _writeNow();
  }

  Future<void> _writeNow() async {
    _setStatus(_NoteSaveStatus.saving);
    final title = _effectiveTitle;
    final body = _bodyController.text;
    try {
      await widget.store.updateItem(widget.item.id, title: title, note: body);
    } catch (_) {
      // Leave the state unsaved; the next edit or the exit
      // flush retries. Never claim a save that did not land.
      _setStatus(_NoteSaveStatus.unsaved);
      return;
    }
    // A local save moves neither the stamp nor the payload;
    // the baseline follows what we wrote.
    _baseTitle = title;
    _baseNote = body;
    _setStatus(_NoteSaveStatus.saved);
  }

  /// Flush on exit / backgrounding. A remote version is
  /// never overwritten from here: if the check finds one,
  /// the write is withheld (the warning was the user's
  /// chance to decide while the editor was open).
  Future<void> _flushPending() async {
    _debounce?.cancel();
    if (!_isNote || _remoteNewer) return;
    if (_isBrandNewEmpty &&
        _titleController.text.trim().isEmpty &&
        _bodyController.text.trim().isEmpty) {
      // Created empty, abandoned empty: leave no row.
      try {
        await widget.store.deleteItem(widget.item.id);
      } catch (_) {
        // Nothing sensible to surface while disposing.
      }
      return;
    }
    if (!_isDirty) return;
    if (await _checkRemote()) return;
    await _writeNow();
  }

  void _reloadRemote() {
    final remote = _remoteItem;
    if (remote == null) return;
    _suppressEdit = true;
    _titleController.text = remote.title;
    _bodyController.text = remote.note ?? '';
    _suppressEdit = false;
    _setBaseline(remote);
    setState(() {
      _remoteNewer = false;
      _remoteItem = null;
      _status = _NoteSaveStatus.saved;
    });
  }

  void _keepMine() {
    final remote = _remoteItem;
    if (remote != null) _setBaseline(remote);
    setState(() {
      _remoteNewer = false;
      _remoteItem = null;
      _status = _NoteSaveStatus.unsaved;
    });
    // The next write carries the local version over the
    // remote one — the accepted whole-note LWW.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(_autosave());
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
            'Your edits are paused until you choose.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onErrorContainer),
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

  String get _statusText => switch (_status) {
    _NoteSaveStatus.saved => 'Saved',
    _NoteSaveStatus.saving => 'Saving…',
    _NoteSaveStatus.unsaved => 'Unsaved changes',
    _NoteSaveStatus.conflict => 'Changed on another device',
  };

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    if (_isNote) {
      // The notebook: a compact top bar carrying the save
      // status, and the document itself below. The pop is
      // intercepted so the pending flush (or the empty-note
      // discard) COMPLETES before the screen below reloads —
      // the project list never shows a stale title.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || _popping) return;
          _popping = true;
          final navigator = Navigator.of(context);
          await _flushPending();
          if (mounted) navigator.pop(result);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _statusText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          body: _noteDocument(item),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: switch (item.type) {
        ItemType.checklist => _ChecklistBody(store: widget.store, item: item),
        ItemType.linkCard => _LinkCardBody(
          store: widget.store,
          item: item,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
        ),
        ItemType.htmlQuiz => _HtmlQuizBody(item: item, learn: widget.learn),
        ItemType.dua => DuaDetailBody(item: item),
        ItemType.audio => AudioItemBody(
          item: item,
          library: widget.learn?.library,
        ),
        _ => const Center(child: Text('Unknown item type')),
      },
    );
  }

  /// The document: a Playfair title field and a borderless,
  /// top-aligned body on the open canvas — no outlined box,
  /// no card. Reading width is capped on wide screens so
  /// lines stay comfortable.
  Widget _noteDocument(Item item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        if (_remoteNewer)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.page,
              Gap.sm,
              Space.page,
              0,
            ),
            child: _remoteWarning(context),
          ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Gap.sm,
                  Space.page,
                  Gap.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleController,
                      // D-052: the document title is sans now
                      // (was Playfair under D-048/D-039).
                      style: theme.textTheme.headlineSmall,
                      decoration: const InputDecoration(
                        hintText: 'Untitled note',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: 2,
                      minLines: 1,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: Gap.sm),
                    Container(height: 1, color: scheme.outlineVariant),
                    // Formatting toolbar — inserts Markdown-style
                    // syntax at the cursor. Plain text is preserved;
                    // the markers are just text characters.
                    _FormatBar(onFormat: _insertFormatting),
                    const SizedBox(height: Gap.sm),
                    Expanded(
                      child: TextField(
                        controller: _bodyController,
                        focusNode: _bodyFocus,
                        autofocus: _isBrandNewEmpty,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                        decoration: const InputDecoration(
                          hintText: 'Start writing your thoughts…',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Insert a Markdown-style prefix or wrapper at the current cursor
  /// position in the body field. The field is focused so the keyboard
  /// stays open after the tap.
  ///
  /// Behaviour:
  ///   • [prefix] alone (e.g. "**"): wraps the selected text or
  ///     inserts the prefix at the cursor.
  ///   • [linePrefix] alone (e.g. "- ", "1. ", "- [ ] ", "# "):
  ///     prepends to the start of the current line, regardless of
  ///     cursor position within that line.
  ///   • Both null → no-op.
  void _insertFormatting({String? prefix, String? linePrefix}) {
    final ctrl = _bodyController;
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) {
      // No valid selection — move focus to body then no-op;
      // next tap will have a valid position.
      _bodyFocus.requestFocus();
      return;
    }

    String newText;
    TextSelection newSel;

    if (linePrefix != null) {
      // Find the start of the current line.
      final base = sel.baseOffset.clamp(0, text.length);
      final lineStart = text.lastIndexOf('\n', base - 1) + 1;
      newText =
          text.substring(0, lineStart) + linePrefix + text.substring(lineStart);
      final shift = linePrefix.length;
      newSel = TextSelection(
        baseOffset: sel.baseOffset + shift,
        extentOffset: sel.extentOffset + shift,
      );
    } else if (prefix != null) {
      final start = sel.start.clamp(0, text.length);
      final end = sel.end.clamp(0, text.length);
      final selected = text.substring(start, end);
      final wrapped = '$prefix${selected.isEmpty ? '' : selected}$prefix';
      newText = text.substring(0, start) + wrapped + text.substring(end);
      final cursorOffset =
          start +
          prefix.length +
          (selected.isEmpty ? 0 : selected.length + prefix.length);
      newSel = TextSelection.collapsed(offset: cursorOffset);
    } else {
      return;
    }

    ctrl.value = ctrl.value.copyWith(text: newText, selection: newSel);
    _bodyFocus.requestFocus();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No preview image found — the fallback card '
            'is shown, or attach your own image.',
          ),
        ),
      );
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
      final updated = await service.attachUserImage(
        _item,
        picked.path,
        picked.name,
      );
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
        Space.page,
        Gap.md,
        Space.page,
        Gap.lg,
      ),
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
                    errorBuilder: (_, _, _) => _fallbackPreview(theme),
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
                  final topic = await widget.learn!.store.topicById(topicId);
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

/// HTML item body (D-049): shows the file name and an Open button
/// that pushes the hardened player screen. The player needs the
/// LibraryStore, routed via [learn] the same way the link-card
/// HTML item body (D-051): renders the HTML document directly
/// in place so it feels like a native document, not an awkward empty
/// card with an Open button.
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

    if (library == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Library is not available.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Clean compact sub-header showing the file info and external open
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
          child: Row(
            children: [
              const Icon(Icons.html_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName.isNotEmpty ? fileName : item.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
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
                icon: const Icon(Icons.fullscreen, size: 18),
                label: const Text('Fullscreen'),
              ),
            ],
          ),
        ),
        // Direct in-place viewer
        Expanded(
          child: HtmlQuizPlayerScreen(
            library: library,
            payload: payload,
            title: item.title,
            showAppBar: false,
          ),
        ),
      ],
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
  final Set<int> _selectedEntryIds = {};
  bool get _isSelecting => _selectedEntryIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _entries = widget.store.checklistEntries(widget.item.id);
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedEntryIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedEntryIds.contains(id)) {
        _selectedEntryIds.remove(id);
      } else {
        _selectedEntryIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedEntryIds.length;
    if (count == 0) return;
    if (!await confirmDelete(
      context,
      '$count entr${count > 1 ? 'ies' : 'y'}',
    )) {
      return;
    }
    for (final id in _selectedEntryIds) {
      await widget.store.deleteChecklistEntry(id);
    }
    if (!mounted) return;
    _selectedEntryIds.clear();
    setState(_reload);
  }

  Future<void> _editSelectedEntry(List<ChecklistEntry> list) async {
    if (_selectedEntryIds.length != 1) return;
    final entry = list.firstWhere((e) => e.id == _selectedEntryIds.first);
    final text = await promptText(
      context,
      title: 'Edit entry',
      initial: entry.text,
      label: 'Text',
    );
    if (text == null || text.isEmpty) return;
    await widget.store.updateChecklistEntry(entry.id, text: text);
    if (!mounted) return;
    _selectedEntryIds.clear();
    setState(_reload);
  }

  Future<void> _add() async {
    final text = await promptText(context, title: 'New entry', label: 'Text');
    if (text == null || text.isEmpty) return;
    await widget.store.addChecklistEntry(widget.item.id, text);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChecklistEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data!;
        final isSelecting = _isSelecting;

        return Column(
          children: [
            if (isSelecting)
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.page,
                  vertical: Space.s1,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel selection',
                      onPressed: _exitSelectionMode,
                    ),
                    const SizedBox(width: Space.s1),
                    Text(
                      '${_selectedEntryIds.length} selected',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (_selectedEntryIds.length == 1)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit entry',
                        onPressed: () => _editSelectedEntry(list),
                      ),
                    IconButton(
                      icon: Icon(
                        _selectedEntryIds.length == list.length
                            ? Icons.deselect_outlined
                            : Icons.select_all_outlined,
                      ),
                      tooltip: _selectedEntryIds.length == list.length
                          ? 'Deselect all'
                          : 'Select all',
                      onPressed: () {
                        setState(() {
                          if (_selectedEntryIds.length == list.length) {
                            _selectedEntryIds.clear();
                          } else {
                            _selectedEntryIds.addAll(list.map((e) => e.id));
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete selected entries',
                      onPressed: _deleteSelected,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('No entries yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.page,
                        vertical: Gap.sm,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final e = list[i];
                        final theme = Theme.of(context);
                        final isEntrySelected = _selectedEntryIds.contains(
                          e.id,
                        );

                        return InkWell(
                          onTap: () async {
                            if (isSelecting) {
                              _toggleSelection(e.id);
                            } else {
                              await widget.store.setChecklistEntryDone(
                                e.id,
                                !e.isDone,
                              );
                              if (!mounted) return;
                              setState(_reload);
                            }
                          },
                          onLongPress: () {
                            _toggleSelection(e.id);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.s3,
                            ),
                            child: Row(
                              children: [
                                if (isSelecting) ...[
                                  NeoCheck(done: isEntrySelected),
                                  const SizedBox(width: Space.s4),
                                ] else ...[
                                  NeoCheck(done: e.isDone),
                                  const SizedBox(width: Space.s4),
                                ],
                                Expanded(
                                  child: Text(
                                    e.text,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      decoration: e.isDone && !isSelecting
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: e.isDone && !isSelecting
                                          ? theme.colorScheme.onSurfaceVariant
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (!isSelecting)
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
      },
    );
  }
}

/// Formatting toolbar for the note document editor (D-049).
///
/// A single row of compact icon buttons that insert Markdown-style
/// formatting markers into the note body via [onFormat]. The toolbar
/// sits between the divider and the body TextField so it is always
/// visible without scrolling.
///
/// Markers used:
///   Bold       → wraps selection in **…**
///   Italic     → wraps selection in _…_
///   Heading    → prepends "# " to the current line
///   Bullet     → prepends "- " to the current line
///   Numbered   → prepends "1. " to the current line
///   Checkbox   → prepends "- [ ] " to the current line
///
/// These are plain text characters — the note stores plain text and
/// these make rich-text rendering possible in a future viewer pass
/// without a schema change.
class _FormatBar extends StatelessWidget {
  const _FormatBar({required this.onFormat});

  final void Function({String? prefix, String? linePrefix}) onFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: dark
            ? GlassTokens.darkGlassFloating
            : GlassTokens.lightGlassFloating,
        borderRadius: BorderRadius.circular(RadiusToken.card),
        border: Border.all(
          color: dark ? GlassTokens.darkRimHighlight : scheme.outlineVariant,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x66000000) : const Color(0x1F000000),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _FmtBtn(
              tooltip: 'Bold',
              icon: Icons.format_bold,
              onTap: () => onFormat(prefix: '**'),
            ),
            _FmtBtn(
              tooltip: 'Italic',
              icon: Icons.format_italic,
              onTap: () => onFormat(prefix: '_'),
            ),
            _divider(scheme),
            _FmtBtn(
              tooltip: 'Heading',
              icon: Icons.title,
              onTap: () => onFormat(linePrefix: '# '),
            ),
            _FmtBtn(
              tooltip: 'Bullet list',
              icon: Icons.format_list_bulleted,
              onTap: () => onFormat(linePrefix: '- '),
            ),
            _FmtBtn(
              tooltip: 'Numbered list',
              icon: Icons.format_list_numbered,
              onTap: () => onFormat(linePrefix: '1. '),
            ),
            _FmtBtn(
              tooltip: 'Checkbox',
              icon: Icons.check_box_outline_blank,
              onTap: () => onFormat(linePrefix: '- [ ] '),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    child: Container(width: 1, color: scheme.outlineVariant),
  );
}

/// Single icon button used inside [_FormatBar].
class _FmtBtn extends StatelessWidget {
  const _FmtBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RadiusToken.control),
          child: Container(
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

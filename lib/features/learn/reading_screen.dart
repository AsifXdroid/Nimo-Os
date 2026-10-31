/// LEARN — reading cards + mark-a-point (§R4.5).
///
/// Extracted text is shown as cards of ~120–200 words. On each
/// card the owner can mark ONE key point: pick a sentence, pick
/// the words to blank (≤ ~8), and the app stores a cloze-ready
/// marked point (front = sentence with the span blanked, back =
/// full sentence). The owner's tap is the quality control; S5's
/// Learn engine mints questions from these records (D-014).
///
/// When a source has no readable text, this screen says so
/// plainly (a scanned PDF is flagged, never shown as empty
/// cards — §R9.5).
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import 'learn_services.dart';
import 'learn_store.dart';
import 'text_extract.dart';

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.learn, required this.source});

  final LearnServices learn;
  final Source source;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  List<ReadingChunk> _chunks = const [];
  List<MarkedPoint> _marked = const [];
  bool _loaded = false;
  bool _loadFailed = false;
  int _index = 0;

  // Marking state for the current card.
  String? _sentence;
  final Set<int> _spanWords = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pages = await widget.learn.imports.readablePages(widget.source);
      final marked =
          await widget.learn.store.markedPointsForSource(widget.source.id);
      if (!mounted) return;
      setState(() {
        _chunks = pages == null
            ? const []
            : chunksForPages(pages,
                paged: widget.source.kind == SourceKind.pdf);
        _marked = marked;
        _loaded = true;
      });
    } catch (_) {
      // Never spin forever: a failed load is an honest state.
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loaded = true;
      });
    }
  }

  ReadingChunk get _chunk => _chunks[_index];

  MarkedPoint? get _markOnCard =>
      _marked.where((m) => m.chunkIndex == _chunk.index).firstOrNull;

  void _goto(int i) {
    setState(() {
      _index = i.clamp(0, _chunks.length - 1);
      _sentence = null;
      _spanWords.clear();
    });
  }

  Future<void> _createMark() async {
    final sentence = _sentence;
    if (sentence == null || _spanWords.isEmpty) return;
    final words = sentence.split(RegExp(r'\s+'));
    final lo = _spanWords.reduce((a, b) => a < b ? a : b);
    final hi = _spanWords.reduce((a, b) => a > b ? a : b);
    final span = words.sublist(lo, hi + 1).join(' ');
    try {
      final mark = await widget.learn.store.markPoint(
        sourceId: widget.source.id,
        topicId: widget.source.topicId,
        sentence: sentence,
        spanText: span,
        page: _chunk.page,
        charOffset: _chunk.spanOffset(sentence, span),
        chunkIndex: _chunk.index,
      );
      if (!mounted) return;
      setState(() {
        _marked = [..._marked, mark];
        _sentence = null;
        _spanWords.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key point marked — it becomes a cloze card in Learn.')),
      );
    } on MarkedPointException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteMark(MarkedPoint mark) async {
    await widget.learn.store.deleteMarkedPoint(mark.id);
    if (!mounted) return;
    setState(() => _marked = _marked.where((m) => m.id != mark.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.source.title)),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
              ? _loadError(context)
              : _chunks.isEmpty
                  ? _noText(context)
                  : _reader(context),
    );
  }

  Widget _loadError(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: Gap.md),
          Text(
            'This source could not be read.',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Its stored text may be damaged (for example by a '
            'sync conflict copy). The original file is still in '
            'the Library — re-importing it restores reading.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _noText(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.find_in_page_outlined, size: 48),
          const SizedBox(height: Gap.md),
          Text(
            ExtractionStatus.describe(widget.source.extractionStatus),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'The file itself is in your Library — open the source '
            'to view it directly.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _reader(BuildContext context) {
    final theme = Theme.of(context);
    final chunk = _chunk;
    final sentences = splitSentences(chunk.text);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, Gap.lg),
            children: [
              Text(
                'Card ${_index + 1} of ${_chunks.length}'
                '${chunk.page != null ? ' · page ${chunk.page}' : ''}',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: Gap.md),
              // The reader paper (D-039): the chunk sits on the
              // PAPER feature surface — reading on paper, in
              // both themes. No circle art behind long text.
              FeaturePanel(
                kind: FeatureSurfaceKind.paper,
                circles: false,
                child: SelectableText(
                  chunk.text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: EditorialColors.of(context).onPaper,
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              if (_markOnCard != null)
                _existingMark(context, _markOnCard!)
              else
                _markingUi(context, sentences),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _index > 0 ? () => _goto(_index - 1) : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Prev'),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _index < _chunks.length - 1
                      ? () => _goto(_index + 1)
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _existingMark(BuildContext context, MarkedPoint mark) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Marked point on this card',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: Gap.sm),
        NeoWell(
          child: SizedBox(
            width: double.infinity,
            child: Text(mark.clozeText, style: theme.textTheme.bodyMedium),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _deleteMark(mark),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
          ),
        ),
      ],
    );
  }

  Widget _markingUi(BuildContext context, List<String> sentences) {
    final theme = Theme.of(context);
    final selected = _sentence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mark a key point', style: theme.textTheme.titleSmall),
        const SizedBox(height: Gap.sm),
        Text(
          selected == null
              ? 'Tap the sentence that matters most on this card.'
              : 'Now tap the words to blank out (up to ~8).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: Gap.md),
        if (selected == null)
          for (final s in sentences)
            ListTile(
              dense: true,
              title: Text(s),
              onTap: () => setState(() {
                _sentence = s;
                _spanWords.clear();
              }),
            )
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0;
                  i < selected.split(RegExp(r'\s+')).length;
                  i++)
                FilterChip(
                  label: Text(selected.split(RegExp(r'\s+'))[i]),
                  selected: _spanWords.isNotEmpty &&
                      i >= _spanWords.reduce((a, b) => a < b ? a : b) &&
                      i <= _spanWords.reduce((a, b) => a > b ? a : b),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _spanWords.add(i);
                    } else {
                      _spanWords.remove(i);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _sentence = null;
                  _spanWords.clear();
                }),
                child: const Text('Back'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _spanWords.isEmpty ? null : _createMark,
                child: const Text('Mark point'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

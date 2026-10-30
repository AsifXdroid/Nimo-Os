/// LEARN engine — one card widget per question type (S5 step
/// C2a, §R4.1/§R4B).
///
/// Shared contract: every card takes the [LearnQuestion] and an
/// [onResult] callback, decodes the payload itself, and calls
/// onResult EXACTLY ONCE, when the answer is locked in. The
/// session screen then shows [QuestionResult.feedback] and its
/// own Continue button — cards do not show explanations
/// themselves (the scenario card is the exception: its debrief
/// IS part of the traversal, and its summary is also passed as
/// the result feedback).
///
/// Cards use theme tokens only (PLAN rule 4) and plain Text
/// widgets, so Arabic/RTL payload strings render through the
/// framework's bidi handling with no special casing.
library;

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'grading.dart';
import 'image_geometry.dart';
import 'learn_engine_store.dart';

/// The locked-in outcome of one card.
class QuestionResult {
  const QuestionResult({required this.correct, this.feedback});

  final bool correct;

  /// Shown by the session screen after the answer locks in
  /// (usually the payload's explanation). Null when the type has
  /// nothing to add (flashcard/cloze self-grades).
  final String? feedback;
}

typedef QuestionResultCallback = void Function(QuestionResult result);

String? _explanation(Map<String, Object?> payload) {
  final e = payload['explanation'];
  return e is String && e.isNotEmpty ? e : null;
}

Map<String, Object?> _asMap(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const <String, Object?>{};

/// Prompt heading shared by the types that carry one.
class _Prompt extends StatelessWidget {
  const _Prompt(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleLarge,
      );
}

// ------------------------------------------------------------ MCQ

class McqCard extends StatefulWidget {
  const McqCard({super.key, required this.question, required this.onResult});

  final LearnQuestion question;
  final QuestionResultCallback onResult;

  @override
  State<McqCard> createState() => _McqCardState();
}

class _McqCardState extends State<McqCard> {
  late final List<({String id, String text})> _choices;
  String? _chosenId;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.question.payload['choices'];
    _choices = [
      if (raw is List)
        for (final c in raw)
          if (c is Map)
            (
              id: c['id']?.toString() ?? '',
              text: c['text'] as String? ?? '',
            ),
    ];
    if (widget.question.payload['shuffle'] != false) {
      _choices.shuffle(Random());
    }
  }

  void _choose(String id) {
    if (_answered) return;
    final correct = gradeMcq(widget.question.payload, id);
    setState(() {
      _chosenId = id;
      _answered = true;
    });
    widget.onResult(
      QuestionResult(
        correct: correct,
        feedback: _explanation(widget.question.payload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final payload = widget.question.payload;
    final correctId = () {
      final ids = payload['correctChoiceIds'];
      return ids is List && ids.isNotEmpty ? ids.first.toString() : null;
    }();
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Prompt(payload['prompt'] as String? ?? ''),
          const SizedBox(height: Gap.md),
          for (final choice in _choices) ...[
            _ChoiceTile(
              text: choice.text,
              state: !_answered
                  ? _TileState.idle
                  : choice.id == correctId
                      ? _TileState.correct
                      : choice.id == _chosenId
                          ? _TileState.wrong
                          : _TileState.idle,
              onTap: _answered ? null : () => _choose(choice.id),
              scheme: scheme,
            ),
            const SizedBox(height: Gap.sm),
          ],
        ],
      ),
    );
  }
}

enum _TileState { idle, correct, wrong }

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.text,
    required this.state,
    required this.onTap,
    required this.scheme,
  });

  final String text;
  final _TileState state;
  final VoidCallback? onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (state) {
      _TileState.idle => (scheme.surfaceContainerHighest, scheme.onSurface,
          null),
      _TileState.correct => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check,
        ),
      _TileState.wrong => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.close,
        ),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: fg),
                ),
              ),
              if (icon != null) Icon(icon, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ myth/fact

class MythFactCard extends StatefulWidget {
  const MythFactCard({
    super.key,
    required this.question,
    required this.onResult,
  });

  final LearnQuestion question;
  final QuestionResultCallback onResult;

  @override
  State<MythFactCard> createState() => _MythFactCardState();
}

class _MythFactCardState extends State<MythFactCard> {
  bool _answered = false;

  void _answer(bool saidFact) {
    if (_answered) return;
    final correct = gradeMythFact(widget.question.payload, saidFact);
    setState(() => _answered = true);
    widget.onResult(
      QuestionResult(
        correct: correct,
        feedback: _explanation(widget.question.payload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.question.payload;
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            payload['statement'] as String? ?? '',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _answered ? null : () => _answer(false),
                  child: const Text('MYTH'),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: FilledButton(
                  onPressed: _answered ? null : () => _answer(true),
                  child: const Text('FACT'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ flashcard

class FlashcardCard extends StatefulWidget {
  const FlashcardCard({
    super.key,
    required this.question,
    required this.onResult,
  });

  final LearnQuestion question;
  final QuestionResultCallback onResult;

  @override
  State<FlashcardCard> createState() => _FlashcardCardState();
}

class _FlashcardCardState extends State<FlashcardCard> {
  bool _revealed = false;
  bool _answered = false;

  void _grade(bool gotIt) {
    if (_answered) return;
    setState(() => _answered = true);
    widget.onResult(QuestionResult(correct: gotIt));
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.question.payload;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            payload['front'] as String? ?? '',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: Gap.md),
          if (!_revealed)
            FilledButton(
              onPressed: () => setState(() => _revealed = true),
              child: const Text('Show answer'),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                payload['back'] as String? ?? '',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: Gap.md),
            _SelfGradeRow(
              answered: _answered,
              onGrade: _grade,
            ),
          ],
        ],
      ),
    );
  }
}

/// Got it / Missed it — the honest self-grade shared by the
/// reveal-and-self-grade types (flashcard, cloze).
class _SelfGradeRow extends StatelessWidget {
  const _SelfGradeRow({required this.answered, required this.onGrade});

  final bool answered;
  final void Function(bool gotIt) onGrade;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: answered ? null : () => onGrade(false),
            child: const Text('Missed it'),
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: FilledButton(
            onPressed: answered ? null : () => onGrade(true),
            child: const Text('Got it'),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ cloze

class ClozeCard extends StatefulWidget {
  const ClozeCard({super.key, required this.question, required this.onResult});

  final LearnQuestion question;
  final QuestionResultCallback onResult;

  @override
  State<ClozeCard> createState() => _ClozeCardState();
}

class _ClozeCardState extends State<ClozeCard> {
  static final _spanPattern = RegExp(r'\{\{(.+?)\}\}');

  bool _revealed = false;
  bool _answered = false;

  void _grade(bool gotIt) {
    if (_answered) return;
    setState(() => _answered = true);
    widget.onResult(QuestionResult(correct: gotIt));
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.question.payload;
    final text = payload['text'] as String? ?? '';
    final shown = _revealed
        ? text.replaceAllMapped(_spanPattern, (m) => m.group(1)!)
        : text.replaceAll(_spanPattern, '_____');
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(shown, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Gap.md),
          if (!_revealed)
            FilledButton(
              onPressed: () => setState(() => _revealed = true),
              child: const Text('Show answer'),
            )
          else
            _SelfGradeRow(answered: _answered, onGrade: _grade),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ ordering

class OrderingCard extends StatefulWidget {
  const OrderingCard({
    super.key,
    required this.question,
    required this.onResult,
  });

  final LearnQuestion question;
  final QuestionResultCallback onResult;

  @override
  State<OrderingCard> createState() => _OrderingCardState();
}

class _OrderingCardState extends State<OrderingCard> {
  late final List<({String id, String text})> _tray;
  final List<({String id, String text})> _answer = [];
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.question.payload['items'];
    _tray = [
      if (raw is List)
        for (final item in raw)
          if (item is Map)
            (
              id: item['id']?.toString() ?? '',
              text: item['text'] as String? ?? '',
            ),
    ]..shuffle(Random());
  }

  int get _total => _tray.length + _answer.length;

  void _check() {
    if (_answered || _answer.length != _total) return;
    final correct = gradeOrdering(
      widget.question.payload,
      [for (final item in _answer) item.id],
    );
    setState(() => _answered = true);
    widget.onResult(
      QuestionResult(
        correct: correct,
        feedback: _explanation(widget.question.payload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.question.payload;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Prompt(payload['prompt'] as String? ?? ''),
          const SizedBox(height: Gap.md),
          Text('Your order', style: theme.textTheme.labelLarge),
          const SizedBox(height: Gap.sm),
          if (_answer.isEmpty)
            Text(
              'Tap items below to build the order.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final item in _answer)
                  ActionChip(
                    label: Text(item.text),
                    onPressed: _answered
                        ? null
                        : () => setState(() {
                              _answer.remove(item);
                              _tray.add(item);
                            }),
                  ),
              ],
            ),
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final item in _tray)
                ActionChip(
                  label: Text(item.text),
                  onPressed: _answered
                      ? null
                      : () => setState(() {
                            _tray.remove(item);
                            _answer.add(item);
                          }),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          FilledButton(
            onPressed: !_answered && _answer.length == _total && _total > 0
                ? _check
                : null,
            child: const Text('Check order'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ image point

class ImagePointCard extends StatefulWidget {
  const ImagePointCard({
    super.key,
    required this.question,
    required this.onResult,
    required this.imageFile,
  });

  final LearnQuestion question;
  final QuestionResultCallback onResult;

  /// The resolved image file (C2b supplies resolveQuestionImage
  /// from pack_media.dart). Resolving to null means the media is
  /// missing from the Library — the card offers a miss instead
  /// of a dead end.
  final Future<File?> imageFile;

  @override
  State<ImagePointCard> createState() => _ImagePointCardState();
}

class _ImagePointCardState extends State<ImagePointCard> {
  bool _answered = false;

  void _missMissing() {
    if (_answered) return;
    setState(() => _answered = true);
    widget.onResult(
      const QuestionResult(
        correct: false,
        feedback: 'The image file is missing from the Library.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.question.payload;
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Prompt(payload['prompt'] as String? ?? ''),
          const SizedBox(height: Gap.md),
          Expanded(
            child: FutureBuilder<File?>(
              future: widget.imageFile,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final file = snapshot.data;
                if (file == null) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Image missing for this question.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: Gap.md),
                      FilledButton(
                        onPressed: _answered ? null : _missMissing,
                        child: const Text('Mark as missed'),
                      ),
                    ],
                  );
                }
                return _ImagePointBody(
                  file: file,
                  payload: payload,
                  answered: _answered,
                  onTap: (correct) {
                    if (_answered) return;
                    setState(() => _answered = true);
                    widget.onResult(
                      QuestionResult(
                        correct: correct,
                        feedback: _explanation(payload),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads the image's real aspect (grading needs it, §R4.1) and
/// hosts the letterbox-safe surface.
class _ImagePointBody extends StatefulWidget {
  const _ImagePointBody({
    required this.file,
    required this.payload,
    required this.answered,
    required this.onTap,
  });

  final File file;
  final Map<String, Object?> payload;
  final bool answered;
  final void Function(bool correct) onTap;

  @override
  State<_ImagePointBody> createState() => _ImagePointBodyState();
}

class _ImagePointBodyState extends State<_ImagePointBody> {
  double? _aspect;
  Offset? _tap;
  bool? _correct;

  @override
  void initState() {
    super.initState();
    _loadAspect();
  }

  Future<void> _loadAspect() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() => _aspect = width / height);
    } catch (_) {
      // The surface shows its own error placeholder; grading
      // simply never arms without an aspect.
    }
  }

  void _handleTap(Offset normalised) {
    final aspect = _aspect;
    if (aspect == null || widget.answered || _tap != null) return;
    final correct = gradeImagePoint(
      widget.payload,
      tapX: normalised.dx,
      tapY: normalised.dy,
      aspect: aspect,
    );
    setState(() {
      _tap = normalised;
      _correct = correct;
    });
    widget.onTap(correct);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = imageTarget(widget.payload);
    return ImagePointSurface(
      file: widget.file,
      interactive: !widget.answered && _tap == null,
      marker: _tap,
      markerRadius: _tap == null ? null : target.r,
      markerColor: _correct == null
          ? null
          : _correct!
              ? scheme.primary
              : scheme.error,
      onTapNormalised: _handleTap,
    );
  }
}

// ------------------------------------------------------------ scenario

class _Bubble {
  const _Bubble.incoming(this.text, {this.caption})
      : outgoing = false,
        muted = false;
  const _Bubble.outgoing(this.text)
      : outgoing = true,
        muted = false,
        caption = null;
  const _Bubble.muted(this.text)
      : outgoing = false,
        muted = true,
        caption = null;
  const _Bubble.debrief(this.text)
      : outgoing = false,
        muted = false,
        caption = 'Debrief';

  final String text;
  final bool outgoing;
  final bool muted;
  final String? caption;
}

class ScenarioCard extends StatefulWidget {
  const ScenarioCard({
    super.key,
    required this.question,
    required this.onResult,
  });

  final LearnQuestion question;
  final QuestionResultCallback onResult;

  @override
  State<ScenarioCard> createState() => _ScenarioCardState();
}

class _ScenarioCardState extends State<ScenarioCard> {
  final ScrollController _scroll = ScrollController();
  final List<_Bubble> _bubbles = [];
  final List<int?> _scores = [];
  String? _currentNodeId;
  String? _summary;
  bool _answered = false;

  Map<String, Object?> get _nodes =>
      _asMap(widget.question.payload['nodes']);

  Map<String, Object?> _node(String id) => _asMap(_nodes[id]);

  @override
  void initState() {
    super.initState();
    final start = widget.question.payload['startNode'];
    if (start is String && _nodes.containsKey(start)) {
      _enterNode(start);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _enterNode(String id) {
    _currentNodeId = id;
    final node = _node(id);
    final text = node['text'];
    if (text is String && text.isNotEmpty) {
      final speaker = node['speaker'];
      _bubbles.add(
        _Bubble.incoming(
          text,
          caption: speaker is String && speaker.isNotEmpty ? speaker : null,
        ),
      );
    }
    if (node['end'] == true) {
      final summary = node['summary'];
      _summary = summary is String ? summary : null;
      if (_summary != null && _summary!.isNotEmpty) {
        _bubbles.add(_Bubble.debrief(_summary!));
      }
    }
    _scrollToBottom();
  }

  void _choose(Map<String, Object?> choice) {
    if (_answered || _summary != null) return;
    final text = choice['text'];
    if (text is String && text.isNotEmpty) {
      _bubbles.add(_Bubble.outgoing(text));
    }
    final feedback = choice['feedback'];
    if (feedback is String && feedback.isNotEmpty) {
      _bubbles.add(_Bubble.muted(feedback));
    }
    final score = choice['score'];
    _scores.add(score is num ? score.toInt() : null);
    final next = choice['next'];
    setState(() {
      if (next is String && _nodes.containsKey(next)) {
        _enterNode(next);
      }
    });
    _scrollToBottom();
  }

  void _seeResult() {
    if (_answered) return;
    setState(() => _answered = true);
    widget.onResult(
      QuestionResult(correct: scenarioPassed(_scores), feedback: _summary),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atEnd = _summary != null;
    final node =
        _currentNodeId == null ? const <String, Object?>{} : _node(_currentNodeId!);
    final rawChoices = node['choices'];
    final choices = <Map<String, Object?>>[
      if (!atEnd && rawChoices is List)
        for (final c in rawChoices) if (c is Map) c.cast<String, Object?>(),
    ];
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: _bubbles.length,
              itemBuilder: (context, i) => _bubbleWidget(_bubbles[i], theme),
            ),
          ),
          const SizedBox(height: Gap.md),
          if (atEnd)
            FilledButton(
              onPressed: _answered ? null : _seeResult,
              child: const Text('See result'),
            )
          else if (choices.length == 1)
            FilledButton(
              onPressed: () => _choose(choices.single),
              child: Text(choices.single['text'] as String? ?? ''),
            )
          else
            for (final choice in choices) ...[
              OutlinedButton(
                onPressed: () => _choose(choice),
                child: Text(choice['text'] as String? ?? ''),
              ),
              const SizedBox(height: Gap.sm),
            ],
        ],
      ),
    );
  }

  Widget _bubbleWidget(_Bubble bubble, ThemeData theme) {
    final scheme = theme.colorScheme;
    if (bubble.muted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Text(
          bubble.text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final bg = bubble.outgoing
        ? scheme.primaryContainer
        : bubble.caption == 'Debrief'
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest;
    final fg = bubble.outgoing
        ? scheme.onPrimaryContainer
        : bubble.caption == 'Debrief'
            ? scheme.onSecondaryContainer
            : scheme.onSurface;
    return Align(
      alignment:
          bubble.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: Gap.sm / 2),
        padding: const EdgeInsets.all(Gap.md),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bubble.caption != null) ...[
              Text(
                bubble.caption!,
                style: theme.textTheme.labelSmall?.copyWith(color: fg),
              ),
              const SizedBox(height: Gap.sm / 2),
            ],
            Text(
              bubble.text,
              style: theme.textTheme.bodyLarge?.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

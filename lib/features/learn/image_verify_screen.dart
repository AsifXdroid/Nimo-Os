/// LEARN engine — owner verification of AI-proposed image-point
/// targets (S5 step C2b, §R4.1). Imported image_point questions
/// start suspended with `verifyPending: true`; here the owner
/// taps the image to place the target where it belongs, and
/// saving stores the corrected target, clears the flag, and
/// unsuspends the question so it enters rotation.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import 'grading.dart';
import 'image_geometry.dart';
import 'learn_engine_store.dart';
import 'learn_services.dart';
import 'pack_media.dart';

class ImageVerifyListScreen extends StatefulWidget {
  const ImageVerifyListScreen({super.key, required this.learn});

  final LearnServices learn;

  @override
  State<ImageVerifyListScreen> createState() => _ImageVerifyListScreenState();
}

class _ImageVerifyListScreenState extends State<ImageVerifyListScreen> {
  List<LearnQuestion> _pending = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pending = await widget.learn.engine.verifyPendingQuestions();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _loaded = true;
    });
  }

  Future<void> _open(LearnQuestion question) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ImageVerifyScreen(learn: widget.learn, question: question),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check image targets')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _pending.isEmpty
              ? Center(
                  child: Text(
                    'Nothing to check.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      Space.page, Gap.md, Space.page, Gap.lg),
                  children: [
                    // D-039: rows on the canvas (hairlines).
                    Column(
                      children: [
                        for (final q in _pending)
                          NeoListRow(
                            icon: Icons.image_search_outlined,
                            title: q.payload['prompt'] as String? ?? '',
                            sub: q.packId ?? '',
                            last: q == _pending.last,
                            onTap: () => _open(q),
                          ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class ImageVerifyScreen extends StatefulWidget {
  const ImageVerifyScreen({
    super.key,
    required this.learn,
    required this.question,
  });

  final LearnServices learn;
  final LearnQuestion question;

  @override
  State<ImageVerifyScreen> createState() => _ImageVerifyScreenState();
}

class _ImageVerifyScreenState extends State<ImageVerifyScreen> {
  late final Future<File?> _imageFuture;
  late Offset _marker;
  late double _radius;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _imageFuture = resolveQuestionImage(widget.learn.library, widget.question);
    final target = imageTarget(widget.question.payload);
    _marker = Offset(target.cx, target.cy);
    _radius = target.r;
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final payload = Map<String, Object?>.of(widget.question.payload);
    payload['target'] = <String, Object?>{
      'cx': _marker.dx,
      'cy': _marker.dy,
      'r': _radius, // radius unchanged — only the centre is verified
    };
    payload.remove('verifyPending');
    await widget.learn.engine.updateQuestionPayload(widget.question.id, payload);
    await widget.learn.engine.unsuspendQuestion(widget.question.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Verify target')),
      body: FutureBuilder<File?>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final file = snapshot.data;
          if (file == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Image file missing — this question stays suspended.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Gap.md),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Text(
                  widget.question.payload['prompt'] as String? ?? '',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Gap.md),
                child: Text('Tap the image to place the target.'),
              ),
              const SizedBox(height: Gap.sm),
              Expanded(
                child: ImagePointSurface(
                  file: file,
                  marker: _marker,
                  markerRadius: _radius,
                  onTapNormalised: (point) =>
                      setState(() => _marker = point),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save target'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

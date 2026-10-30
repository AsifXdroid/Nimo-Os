/// LEARN — the share-capture confirm sheet (§R9.5): ONE field,
/// pre-filled with the guessed title; Save = 1 tap. Capture must
/// stay under ~10 seconds or the Inbox dies, so nothing else is
/// asked here — organising happens later, in triage.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'capture_service.dart';

/// Shows the sheet for [capture]; returns the confirmed title, or
/// null when the owner dismissed it (capture dropped).
Future<String?> showShareConfirmSheet(
  BuildContext context,
  SharedCapture capture,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ShareConfirmSheet(capture: capture),
  );
}

class _ShareConfirmSheet extends StatefulWidget {
  const _ShareConfirmSheet({required this.capture});

  final SharedCapture capture;

  @override
  State<_ShareConfirmSheet> createState() => _ShareConfirmSheetState();
}

class _ShareConfirmSheetState extends State<_ShareConfirmSheet> {
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.capture.suggestedTitle);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _what {
    final c = widget.capture;
    return switch (c.kind) {
      CaptureKind.link => 'Link → new topic in your Inbox',
      CaptureKind.text => 'Shared text → new topic in your Inbox',
      CaptureKind.file =>
        'File “${c.fileName ?? 'shared'}” → new topic in your Inbox',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.md,
        Gap.md,
        Gap.md,
        Gap.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Save to Nimo', style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          Text(_what, style: theme.textTheme.bodySmall),
          if (widget.capture.kind == CaptureKind.link &&
              widget.capture.text != null) ...[
            const SizedBox(height: Gap.sm),
            Text(widget.capture.text!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: Gap.md),
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Topic title',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Discard'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _title.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

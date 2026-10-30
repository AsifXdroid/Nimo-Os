/// LEARN engine — the quiz-pack import flow (S5 step C2b):
/// pick a .quizpack/.zip file → pick the topic it belongs to
/// (unless [fixedTopicId] is given) → import via
/// [LearnServices.packImporter] → report dialog. All validation
/// and hostile-input handling lives in the importer; this file
/// is only the conversation around it.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'learn_services.dart';
import 'pack_importer.dart';

Future<void> showPackImportFlow(
  BuildContext context, {
  required LearnServices learn,
  int? fixedTopicId,
}) async {
  final picked = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Quiz pack', extensions: ['quizpack', 'zip']),
    ],
  );
  if (picked == null || !context.mounted) return; // cancelled: silent

  final topicId = fixedTopicId ?? await _pickTopic(context, learn);
  if (topicId == null || !context.mounted) return; // cancelled: silent

  final PackImportReport report;
  try {
    report = await learn.packImporter.importPackFile(
      File(picked.path),
      topicId: topicId,
    );
  } on PackException catch (e) {
    if (!context.mounted) return;
    await _errorDialog(context, e.message);
    return;
  } catch (e) {
    if (!context.mounted) return;
    await _errorDialog(context, 'Import failed: $e');
    return;
  }
  if (!context.mounted) return;
  await _reportDialog(context, report);
}

/// Bottom sheet: existing topics, plus a "New topic" field that
/// creates the topic in the Inbox project. Returns the topic id,
/// or null when dismissed.
Future<int?> _pickTopic(BuildContext context, LearnServices learn) async {
  final topics = await learn.store.allTopics();
  if (!context.mounted) return null;
  final controller = TextEditingController();
  try {
    return await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: Gap.md,
              right: Gap.md,
              top: Gap.md,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + Gap.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Import into…',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: Gap.sm),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final topic in topics)
                        ListTile(
                          leading: const Icon(Icons.lightbulb_outline),
                          title: Text(topic.title),
                          onTap: () =>
                              Navigator.pop(sheetContext, topic.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'New topic',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    FilledButton(
                      onPressed: controller.text.trim().isEmpty
                          ? null
                          : () async {
                              final title = controller.text.trim();
                              final projectId =
                                  await learn.store.inboxProjectId();
                              final topic = await learn.store.createTopic(
                                projectId: projectId,
                                title: title,
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, topic.id);
                              }
                            },
                      child: const Text('New topic'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<void> _reportDialog(
  BuildContext context,
  PackImportReport report,
) {
  final title = switch (report.status) {
    PackImportStatus.imported => 'Pack imported',
    PackImportStatus.updated => 'Pack updated',
    PackImportStatus.alreadyImported => 'Already imported',
  };
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Questions added: ${report.importedCount} · '
              'updated: ${report.updatedCount} · '
              'suspended: ${report.suspendedCount} · '
              'media: ${report.mediaCount}',
            ),
            if (report.skipped.isNotEmpty) ...[
              const SizedBox(height: Gap.md),
              const Text('Skipped:'),
              const SizedBox(height: Gap.sm),
              for (final s in report.skipped)
                Text('• ${s.questionId} — ${s.reason}'),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> _errorDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import failed'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

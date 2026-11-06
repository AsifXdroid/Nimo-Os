/// QUICK ADD (D-045) — the shared capture sheet and prompts.
///
/// One sheet, three captures (see quick_add_service.dart).
/// Used by the shell's Quick Add action; Today's quick-add row
/// calls the same service operations through the same prompt
/// helpers, so wording and behaviour match on both surfaces.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/spatial_ui.dart';
import '../items/audio/audio_item.dart';
import '../shared_ui.dart';
import '../store.dart';
import '../today/plan_link.dart' show isValidWebUrl, pickLinkItem;
import 'quick_add_service.dart';

/// Prompt for a task title and add it to today's plan.
Future<bool> quickAddTaskFlow(
  BuildContext context, {
  required QuickAddService service,
}) async {
  final title = await promptText(
    context,
    title: 'Add task for today',
    label: 'Task',
  );
  if (title == null || title.isEmpty || !context.mounted) return false;
  final item = await service.addTask(title);
  if (!context.mounted) return true;
  // D-054: attaching a resource is part of creating the task —
  // offered here, in the open, not only inside the task's
  // management sheet. Dismissing this sheet (or "Just the
  // task") leaves a plain task, exactly as before.
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.check),
            title: const Text('Just the task'),
            onTap: () => Navigator.pop(c, 'none'),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Attach a web or video link'),
            onTap: () => Navigator.pop(c, 'url'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Attach a note, quiz or audio from Spaces'),
            onTap: () => Navigator.pop(c, 'item'),
          ),
          if (service.library != null)
            ListTile(
              leading: const Icon(Icons.headphones_outlined),
              title: const Text('Attach an audio file'),
              subtitle: const Text('For a listening task'),
              onTap: () => Navigator.pop(c, 'audio'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted) return true;
  var attached = false;
  switch (choice) {
    case 'url':
      final url = await promptText(
        context,
        title: 'Web or video link',
        label: 'URL (https://…)',
      );
      if (url != null && url.isNotEmpty) {
        if (isValidWebUrl(url.trim())) {
          await service.todayStore.setPlanItemLink(item.id, url: url.trim());
          attached = true;
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "That doesn't look like a valid web link — "
                'the task was saved without it.',
              ),
            ),
          );
        }
      }
    case 'item':
      final picked = await pickLinkItem(context, service.store);
      if (picked != null) {
        await service.todayStore.setPlanItemLink(item.id, itemId: picked.id);
        attached = true;
      }
    case 'audio':
      final picked = await openFile(acceptedTypeGroups: const [audioFileGroup]);
      if (picked != null) {
        try {
          final audio = await service.importAudioToInbox(
            picked.path,
            picked.name,
          );
          if (audio != null) {
            await service.todayStore.setPlanItemLink(item.id, itemId: audio.id);
            attached = true;
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not import that audio file: $e')),
            );
          }
        }
      }
  }
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        attached ? 'Added to today with its resource.' : 'Added to today.',
      ),
    ),
  );
  return true;
}

/// Create an instant note in the Inbox project and immediately
/// open the editor for writing.
Future<bool> quickAddNoteFlow(
  BuildContext context, {
  required QuickAddService service,
  required void Function(Item item) onOpenItem,
}) async {
  final item = await service.createInstantNote();
  if (!context.mounted) return true;
  onOpenItem(item);
  return true;
}

/// Prompt for a URL and save it as a link card in the Inbox
/// project.
Future<bool> quickAddResourceFlow(
  BuildContext context, {
  required QuickAddService service,
}) async {
  final url = await promptText(context, title: 'Save resource', label: 'URL');
  if (url == null || url.isEmpty || !context.mounted) return false;
  if (!isValidWebUrl(url.trim())) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("That doesn't look like a valid web link.")),
    );
    return false;
  }
  await service.addResource(url);
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Saved to your Inbox.')));
  return true;
}

/// The Quick Add sheet: exactly the three captures, presented
/// in a spatial frosted action sheet with specular rim and elevation.
Future<void> showQuickAddSheet(
  BuildContext context, {
  required QuickAddService service,
  required void Function(Item item) onOpenItem,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (sheetContext) {
      Widget row(
        IconData icon,
        String label,
        String sub,
        Future<bool> Function() run,
      ) {
        return ListTile(
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(sub),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onTap: () async {
            Navigator.of(sheetContext).pop();
            await run();
          },
        );
      }

      return SpatialActionSheet(
        // D-052: the prototype's capture header + promise.
        title: 'Catch it now. Sort it later.',
        subtitle: 'A safe landing place for your ideas.',
        children: [
          row(
            Icons.add_task_outlined,
            'Task',
            'Add to today’s plan',
            () => quickAddTaskFlow(context, service: service),
          ),
          row(
            Icons.note_outlined,
            'Quick note',
            'File it in your Inbox',
            () => quickAddNoteFlow(
              context,
              service: service,
              onOpenItem: onOpenItem,
            ),
          ),
          row(
            Icons.link_outlined,
            'Save resource',
            'A link card in your Inbox',
            () => quickAddResourceFlow(context, service: service),
          ),
        ],
      );
    },
  );
}

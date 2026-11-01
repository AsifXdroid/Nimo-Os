/// QUICK ADD (D-045) — the shared capture sheet and prompts.
///
/// One sheet, three captures (see quick_add_service.dart).
/// Used by the shell's Quick Add action; Today's quick-add row
/// calls the same service operations through the same prompt
/// helpers, so wording and behaviour match on both surfaces.
library;

import 'package:flutter/material.dart';

import '../shared_ui.dart';
import '../store.dart';
import '../today/plan_link.dart' show isValidWebUrl;
import 'quick_add_service.dart';

/// Prompt for a task title and add it to today's plan.
Future<bool> quickAddTaskFlow(
  BuildContext context, {
  required QuickAddService service,
}) async {
  final title =
      await promptText(context, title: 'Add task for today', label: 'Task');
  if (title == null || title.isEmpty || !context.mounted) return false;
  await service.addTask(title);
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Added to today.')));
  return true;
}

/// Prompt for note text and file it in the Inbox project. The
/// confirmation offers Open, which calls [onOpenItem] with the
/// created note.
Future<bool> quickAddNoteFlow(
  BuildContext context, {
  required QuickAddService service,
  required void Function(Item item) onOpenItem,
}) async {
  final text = await promptText(context,
      title: 'Quick note', label: 'Note', maxLines: 5);
  if (text == null || text.isEmpty || !context.mounted) return false;
  final item = await service.addQuickNote(text);
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: const Text('Saved to your Inbox.'),
    action: SnackBarAction(
      label: 'Open',
      onPressed: () => onOpenItem(item),
    ),
  ));
  return true;
}

/// Prompt for a URL and save it as a link card in the Inbox
/// project.
Future<bool> quickAddResourceFlow(
  BuildContext context, {
  required QuickAddService service,
}) async {
  final url =
      await promptText(context, title: 'Save resource', label: 'URL');
  if (url == null || url.isEmpty || !context.mounted) return false;
  if (!isValidWebUrl(url.trim())) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("That doesn't look like a valid web link.")));
    return false;
  }
  await service.addResource(url);
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Saved to your Inbox.')));
  return true;
}

/// The Quick Add sheet: exactly the three captures, nothing
/// else. [onOpenItem] is invoked when the user taps Open on the
/// quick-note confirmation.
Future<void> showQuickAddSheet(
  BuildContext context, {
  required QuickAddService service,
  required void Function(Item item) onOpenItem,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      Widget row(IconData icon, String label, String sub,
          Future<bool> Function() run) {
        return ListTile(
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(sub),
          onTap: () async {
            Navigator.of(sheetContext).pop();
            await run();
          },
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Quick add')),
            row(Icons.add_task_outlined, 'Task', 'Add to today’s plan',
                () => quickAddTaskFlow(context, service: service)),
            row(Icons.note_outlined, 'Quick note', 'File it in your Inbox',
                () => quickAddNoteFlow(context,
                    service: service, onOpenItem: onOpenItem)),
            row(Icons.link_outlined, 'Save resource',
                'A link card in your Inbox',
                () => quickAddResourceFlow(context, service: service)),
          ],
        ),
      );
    },
  );
}

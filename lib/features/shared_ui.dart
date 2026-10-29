/// Shared UI helpers used by the S1 screens (name prompt, confirm).
library;

import 'package:flutter/material.dart';

/// Ask for a name/title. Returns the trimmed text, or null if cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Name',
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Values from the add-goal dialog (GOAL, S2).
typedef GoalInput = ({String title, int target, String unit});

/// Ask for a goal: title, numeric target, and an optional unit
/// (e.g. title "Learn Arabic words", target 100, unit "words").
/// Returns null if cancelled or the input is unusable.
Future<GoalInput?> promptGoal(BuildContext context) {
  final title = TextEditingController();
  final target = TextEditingController();
  final unit = TextEditingController();
  return showDialog<GoalInput>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('New goal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Goal'),
          ),
          TextField(
            controller: target,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Target'),
          ),
          TextField(
            controller: unit,
            decoration:
                const InputDecoration(labelText: 'Unit (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final t = title.text.trim();
            final n = int.tryParse(target.text.trim());
            if (t.isEmpty || n == null || n <= 0) {
              Navigator.pop(context);
              return;
            }
            Navigator.pop(
              context,
              (title: t, target: n, unit: unit.text.trim()),
            );
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $what?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Popup menu actions shared by list rows.
enum RowAction { rename, delete }

Future<RowAction?> showRowMenu(BuildContext context) {
  return showModalBottomSheet<RowAction>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(context, RowAction.rename),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            onTap: () => Navigator.pop(context, RowAction.delete),
          ),
        ],
      ),
    ),
  );
}

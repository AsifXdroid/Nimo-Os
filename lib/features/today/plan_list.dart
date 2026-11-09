/// TODAY — shared plan-list UI (Mission 03 Phase 4 extraction).
///
/// The plan group panel, its rows, the linked-resource action
/// and the D-042 task-management sheet, moved out of
/// today_screen.dart unchanged so Today and the Daily To-do
/// screen render and manage the SAME day_plan_items through
/// the same code. Hosts supply three callbacks: [onMutated]
/// after a completion or removal (the host refreshes derived
/// state, e.g. a closed day's Done Score, then reloads),
/// [onReload] after an in-place edit (rename, link), and
/// [onRefresh] after a non-mutating return (resource open,
/// routine editor).
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/glass_ui.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../items/audio/audio_item.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'dua_library_screen.dart';
import 'plan_link.dart';
import 'routine_screen.dart';
import 'today_store.dart';

/// The charcoal surface shared by Today panels (D-052/D-053):
/// fill, hairline border, one soft drop. Moved verbatim from
/// TodayScreen so both screens sit on the same surface.
BoxDecoration planSurfaceDeco(
  BuildContext context, {
  double radius = RadiusToken.card,
}) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: dark ? GlassTokens.darkCharcoal : theme.colorScheme.surfaceContainer,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: dark
          ? GlassTokens.darkCharcoalBorder
          : theme.colorScheme.outlineVariant,
    ),
    boxShadow: dark
        ? const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ]
        : null,
  );
}

/// The row's resource action (D-042): derived from the
/// link — never stored, never toggles completion. A link
/// whose item has vanished renders nothing.
Widget planResourceAction(
  BuildContext context, {
  required DayPlanItem item,
  required Map<int, Item> linkedItems,
  required Store store,
  required LearnServices learn,
  required ThumbnailService thumbnails,
  required VoidCallback onOpened,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final linked = item.itemId == null ? null : linkedItems[item.itemId];
  if (item.url == null && linked == null) {
    return const SizedBox.shrink();
  }
  // D-054: the action is a real button now — a filled pill
  // the owner can SEE and hit — not the 10px eyebrow text
  // D-042 shipped, which was effectively invisible.
  return Padding(
    padding: const EdgeInsets.only(top: Space.s2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: scheme.primary.withValues(alpha: 0.12),
        shape: StadiumBorder(
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await openPlanResource(
              context,
              url: item.url,
              item: linked,
              store: store,
              learn: learn,
              thumbnails: thumbnails,
            );
            onOpened();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  resourceActionIcon(url: item.url, item: linked),
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: Space.s2),
                Text(
                  resourceActionLabel(url: item.url, item: linked),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// One labelled (or label-less) group of plan rows.
class PlanList extends StatelessWidget {
  const PlanList({
    super.key,
    required this.label,
    required this.items,
    required this.linkedItems,
    required this.todayStore,
    required this.store,
    required this.learn,
    required this.thumbnails,
    required this.onMutated,
    required this.onReload,
    required this.onRefresh,
  });

  final String? label;
  final List<DayPlanItem> items;
  final Map<int, Item> linkedItems;
  final TodayStore todayStore;
  final Store store;
  final LearnServices learn;
  final ThumbnailService thumbnails;
  final Future<void> Function() onMutated;
  final VoidCallback onReload;
  final VoidCallback onRefresh;

  /// The mono group head (D-042): eyebrow label + hairline.
  Widget _head(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: AppType.eyebrow.copyWith(
            fontSize: 10,
            letterSpacing: 1.2,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: Space.s3),
        Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
      ],
    );
  }

  /// One plan section (D-042): an optional group label with
  /// a hairline, then the group's rows in a surface panel.
  /// Mission 03 Phase 2: [label] is null for the compact
  /// preview's single flat list (no head rendered).
  @override
  Widget build(BuildContext context) {
    final group = items;
    final scheme = Theme.of(context).colorScheme;
    // D-052: the plan group is a PANEL (the prototype's task
    // card) — rows on the panel surface, hairline-divided.
    // The D-039 timeline rail is retired; the data model still
    // carries no clock times, so nothing about times changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          _head(context, label!),
          const SizedBox(height: Space.s2),
        ],
        Container(
          decoration: planSurfaceDeco(context),
          child: Column(
            children: [
              for (var i = 0; i < group.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: Space.s4,
                    endIndent: Space.s4,
                    color: scheme.outlineVariant,
                  ),
                _row(context, group[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// One plan row on the timeline: a node mark on the rail
  /// (filled when done), the title with its quiet
  /// classification line, a CARRIED tag when the item rolled
  /// over, delete for one-offs, and the circular check at the
  /// right — the row tap toggles; the check is its affordance.
  Widget _row(BuildContext context, DayPlanItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A11y (D-038 Stage 6): the row announces as a checkbox
    // with its state, not just a tappable text block.
    return Semantics(
      container: true,
      button: true,
      checked: item.done,
      label: item.title,
      child: InkWell(
        onTap: () async {
          await todayStore.toggleItem(item);
          await onMutated();
        },
        // D-042: management lives in the sheet (long-press is
        // the accelerator; the ⋯ button is the visible path).
        onLongPress: () => _showSheet(context, item),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: item.done ? 0.62 : 1.0,
          child: Padding(
            // D-052: the prototype's row — the circular check
            // leads, title + quiet classification under it, the
            // ⋯ options at the right.
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: Space.s3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NeoCheck(done: item.done, size: 26),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.done ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.isRoutine
                            ? (item.countsCore ? 'Routine · Core' : 'Routine')
                            : 'One-off',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (item.hasResource) _resource(context, item),
                    ],
                  ),
                ),
                if (item.carried) ...[
                  const SizedBox(width: Space.s2),
                  const NeoTag('CARRIED', tint: true),
                ],
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 18),
                  tooltip: 'Task options',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showSheet(context, item),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The row's resource action (D-042): derived from the
  /// link — never stored, never toggles completion. A link
  /// whose item has vanished renders nothing.
  Widget _resource(BuildContext context, DayPlanItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final linked = item.itemId == null ? null : linkedItems[item.itemId];
    if (item.url == null && linked == null) {
      return const SizedBox.shrink();
    }
    // D-054: the action is a real button now — a filled pill
    // the owner can SEE and hit — not the 10px eyebrow text
    // D-042 shipped, which was effectively invisible.
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: scheme.primary.withValues(alpha: 0.12),
          shape: StadiumBorder(
            side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              await openPlanResource(
                context,
                url: item.url,
                item: linked,
                store: store,
                learn: learn,
                thumbnails: thumbnails,
              );
              onRefresh();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s3,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    resourceActionIcon(url: item.url, item: linked),
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: Space.s2),
                  Text(
                    resourceActionLabel(url: item.url, item: linked),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The task-management sheet (D-042) — the × button's
  /// replacement. Everything deliberate lives here: open the
  /// resource, retitle, link, remove. Deletion always
  /// confirms; removing a completed core routine names its
  /// streak consequence first (owner decision).
  Future<void> _showSheet(BuildContext context, DayPlanItem item) async {
    final theme = Theme.of(context);
    final linked = item.itemId == null ? null : linkedItems[item.itemId];
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
              child: Text(item.title, style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                item.isRoutine
                    ? (item.countsCore ? 'Daily to-do · Core' : 'Daily to-do')
                    : 'Today',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (item.url != null || linked != null)
              ListTile(
                leading: Icon(resourceActionIcon(url: item.url, item: linked)),
                title: Text(
                  resourceActionLabel(
                    url: item.url,
                    item: linked,
                  ).replaceAll(' →', ''),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await openPlanResource(
                    context,
                    url: item.url,
                    item: linked,
                    store: store,
                    learn: learn,
                    thumbnails: thumbnails,
                  );
                  onRefresh();
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit title'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final title = await promptText(
                  context,
                  title: 'Edit title',
                  label: 'Title',
                  initial: item.title,
                );
                if (title == null || title.isEmpty || title == item.title) {
                  return;
                }
                await todayStore.renamePlanItem(item.id, title);
                onReload();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(
                item.hasResource ? 'Change resource' : 'Attach a resource',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _attach(context, item);
              },
            ),
            if (item.hasResource)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Remove resource'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await todayStore.setPlanItemLink(item.id);
                  onReload();
                },
              ),
            const Divider(),
            if (item.isRoutine) ...[
              ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Edit in Routine'),
                subtitle: const Text('Changes every day, from tomorrow'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RoutineScreen(todayStore: todayStore, store: store),
                    ),
                  );
                  onRefresh();
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Remove from today only'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _removeToday(context, item);
                },
              ),
            ] else
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Delete task',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _deleteOneOff(context, item);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// The attach flow (D-042): paste a link, or pick an
  /// existing Spaces item. Setting one clears the other —
  /// one resource per task.
  Future<void> _attach(BuildContext context, DayPlanItem item) async {
    // Phase 8 (D-4 parity): when a resource is already
    // linked, the chooser NAMES it — for every source, not
    // only the Dua picker. One slot, said out loud.
    final currentLabel = item.url ??
        (item.itemId == null ? null : linkedItems[item.itemId]?.title);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Currently linked: $currentLabel — choosing '
                    'another replaces it.',
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Paste a web or video link'),
              onTap: () => Navigator.pop(c, 'url'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text(
                'Choose a note, link, quiz or audio from Spaces',
              ),
              onTap: () => Navigator.pop(c, 'item'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Dua from library'),
              subtitle: const Text('Link a Dua you added'),
              onTap: () => Navigator.pop(c, 'dua'),
            ),
            ListTile(
              leading: const Icon(Icons.headphones_outlined),
              title: const Text('Pick an audio file'),
              subtitle: const Text('For a listening task'),
              onTap: () => Navigator.pop(c, 'audio'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'audio') {
      final picked = await openFile(acceptedTypeGroups: const [audioFileGroup]);
      if (picked == null || !context.mounted) return;
      try {
        final inbox = await learn.store.ensureInboxProject();
        final audio = await importAudioItem(
          store: store,
          library: learn.library,
          projectId: inbox.id,
          sourcePath: picked.path,
          sourceName: picked.name,
        );
        await todayStore.setPlanItemLink(item.id, itemId: audio.id);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import that audio file: $e')),
        );
        return;
      }
      onReload();
      return;
    }
    if (choice == 'url') {
      final controller = TextEditingController(text: item.url ?? '');
      final saved = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Web or video link'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://…',
            ),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      final raw = controller.text.trim();
      controller.dispose();
      if (saved != true || !context.mounted) return;
      if (!isValidWebUrl(raw)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("That doesn't look like a valid web link."),
          ),
        );
        return;
      }
      await todayStore.setPlanItemLink(item.id, url: raw);
      onReload();
      return;
    }
    if (choice == 'dua') {
      final current = item.itemId == null ? null : linkedItems[item.itemId];
      // The lint's async-gap note does not apply: the picker
      // checks mounted itself before building and its result
      // is guarded immediately after the await.
      final picked = await pickDuaItem(
        // ignore: use_build_context_synchronously
        context,
        store,
        currentResourceLabel: item.url ?? current?.title,
        onAddDua: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DuaLibraryScreen(
                store: store,
                learn: learn,
                thumbnails: thumbnails,
              ),
            ),
          );
        },
      );
      if (picked == null || !context.mounted) return;
      await todayStore.setPlanItemLink(item.id, itemId: picked.id);
      onReload();
      return;
    }
    // choice == 'item'
    final picked = await pickLinkItem(context, store);
    if (picked == null || !context.mounted) return;
    await todayStore.setPlanItemLink(item.id, itemId: picked.id);
    onReload();
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _deleteOneOff(BuildContext context, DayPlanItem item) async {
    final ok = await _confirm(
      context,
      title: 'Delete this task?',
      body:
          'It will be removed from today and will not carry '
          'over to tomorrow.',
      action: 'Delete',
    );
    if (!ok) return;
    await todayStore.deletePlanItem(item.id);
    await onMutated();
  }

  Future<void> _removeToday(BuildContext context, DayPlanItem item) async {
    // Owner decision (D-042): allowed, never silent — and a
    // completed CORE row carries the explicit consequence.
    final (title, body) = switch ((item.done, item.countsCore)) {
      (true, true) => (
        'Remove a completed core task?',
        'This task is done and counts toward today\'s core. '
            'Removing it recalculates today\'s Done Score from '
            'the remaining tasks — and today may stop counting '
            'toward your streak. The task stays in your '
            'routine and returns tomorrow.',
      ),
      (true, false) => (
        'Remove this task for today?',
        'It is done, so today\'s Done Score will be '
            'recalculated from the remaining tasks. The task '
            'stays in your routine and returns tomorrow.',
      ),
      _ => (
        'Remove this task for today?',
        'The task stays in your routine and returns tomorrow.',
      ),
    };
    final ok = await _confirm(
      context,
      title: title,
      body: body,
      action: 'Remove for today',
    );
    if (!ok) return;
    await todayStore.deletePlanItem(item.id);
    await onMutated();
  }
}

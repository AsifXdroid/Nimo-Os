/// The Dua reading body (Mission 03 Phase 7): the owner's
/// entry, verbatim. Arabic renders RTL at a comfortable line
/// height; transliteration is collapsed by default (Mission
/// 02 §B.7); the authenticity note appears ONLY when the
/// owner supplied one — never as an app claim, never as an
/// empty label. Rendered inside ItemDetailScreen for type
/// 'dua', and (with an edit action) as the Dua Library's own
/// entry screen — one reading experience from both paths.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../store.dart';
import '../today/dua_library_screen.dart';
import 'dua_item.dart';

class DuaDetailBody extends StatelessWidget {
  const DuaDetailBody({super.key, required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = DuaPayload(item);
    Widget section(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppType.eyebrow.copyWith(
              fontSize: 10,
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.s2),
          child,
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(Space.s4),
      children: [
        if (p.has('arabic'))
          section(
            'Arabic',
            Text(
              p.arabic!,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.start,
              style: theme.textTheme.titleMedium?.copyWith(height: 1.9),
            ),
          ),
        if (p.has('translation'))
          section(
            'Translation',
            Text(p.translation!, style: theme.textTheme.bodyLarge),
          ),
        if (p.has('transliteration'))
          ExpansionTile(
            title: const Text('Transliteration'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: Space.s4),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  p.transliteration!,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        if (p.has('source'))
          section('Source', Text(p.source!, style: theme.textTheme.bodyMedium)),
        if (p.has('authenticity'))
          section(
            'Authenticity note',
            Text(p.authenticity!, style: theme.textTheme.bodyMedium),
          ),
        if (item.note != null && item.note!.trim().isNotEmpty)
          section(
            'Personal note',
            Text(item.note!, style: theme.textTheme.bodyMedium),
          ),
        if (!p.has('arabic') &&
            !p.has('translation') &&
            !p.has('transliteration') &&
            !p.has('source') &&
            !p.has('authenticity') &&
            (item.note == null || item.note!.trim().isEmpty))
          Text(
            'This entry has a title only. Edit it in the Dua '
            'Library to add its text.',
            style: theme.textTheme.bodyMedium,
          ),
      ],
    );
  }
}

/// The Dua Library's entry screen: the same reading body
/// inside a Scaffold whose app bar carries the Edit action
/// (the library owns editing; ItemDetailScreen stays a pure
/// reader for plan-pill opens). After a successful edit the
/// screen closes so the library reloads the fresh entry.
class DuaEntryScreen extends StatelessWidget {
  const DuaEntryScreen({super.key, required this.store, required this.item});

  final Store store;
  final Item item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Dua',
            onPressed: () async {
              final saved = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DuaEntryFormScreen(store: store, existing: item),
                ),
              );
              if (saved == true && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: DuaDetailBody(item: item),
    );
  }
}

/// The Dua picker sheet's content (Mission 03 Phase 7): the
/// library ONLY — Duas never appear in the generic Spaces
/// picker and Spaces items never appear here. An empty
/// library says so honestly and offers the route to add the
/// first entry. [currentResourceLabel] names the task's
/// existing link so replacing it is never a surprise: a task
/// has ONE linked resource.
class DuaPickerSheet extends StatelessWidget {
  const DuaPickerSheet({
    super.key,
    required this.entries,
    this.currentResourceLabel,
    this.onAddDua,
  });

  final List<Item> entries;
  final String? currentResourceLabel;
  final VoidCallback? onAddDua;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Choose a Dua',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              currentResourceLabel != null
                  ? 'Currently linked: $currentResourceLabel. '
                        'Choosing a Dua replaces it — a task has '
                        'one linked resource.'
                  : 'A task has one linked resource.',
            ),
          ),
          if (entries.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'Your Dua Library is empty. Add a verified '
                'entry first, then link it here.',
              ),
            ),
            if (onAddDua != null)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add a Dua'),
                onTap: () {
                  Navigator.pop(context);
                  onAddDua!();
                },
              ),
            const SizedBox(height: 8),
          ] else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in entries)
                    ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(e.title),
                      subtitle: DuaPayload(e).has('translation')
                          ? Text(
                              DuaPayload(e).translation!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, e),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

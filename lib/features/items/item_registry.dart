/// ITEM — the item-type registry (PLAN.md architecture rule 2).
///
/// Every item type registers ONE entry here: its key, display label,
/// and icon. Adding a type = one folder + one line in [itemTypes].
/// Screens render and create items generically from this registry.
library;

import 'package:flutter/material.dart';

import '../store.dart';

class ItemTypeDef {
  const ItemTypeDef({
    required this.key,
    required this.label,
    required this.icon,
    this.offerInAddSheet = true,
  });

  final String key;
  final String label;
  final IconData icon;

  /// Whether the generic project "Add item" sheet offers
  /// this type. Types with a dedicated home (Dua, Phase 7)
  /// are recognised by the registry — so their items render
  /// with the right label and icon everywhere — but are
  /// created only inside their own flow.
  final bool offerInAddSheet;
}

const List<ItemTypeDef> itemTypes = [
  ItemTypeDef(key: ItemType.note, label: 'Note', icon: Icons.note_outlined),
  ItemTypeDef(
    key: ItemType.checklist,
    label: 'Checklist',
    icon: Icons.checklist_outlined,
  ),
  ItemTypeDef(
    key: ItemType.linkCard,
    label: 'Link card',
    icon: Icons.grid_view_outlined,
  ),
  // D-049: renamed from 'HTML quiz' → 'HTML' so any HTML file is accepted,
  // not just quiz packs. The DB key (html_quiz) is intentionally unchanged.
  ItemTypeDef(key: ItemType.htmlQuiz, label: 'HTML', icon: Icons.html_outlined),
  // D-054: an audio file in the Library, played in place —
  // the resource behind "listen" tasks.
  ItemTypeDef(
    key: ItemType.audio,
    label: 'Audio',
    icon: Icons.headphones_outlined,
  ),
  // Mission 03 Phase 7: an owner-entered Dua entry. The app
  // ships no Dua content; entries exist only when the owner
  // adds them in the Dua Library.
  ItemTypeDef(
    key: ItemType.dua,
    label: 'Dua',
    icon: Icons.menu_book_outlined,
    offerInAddSheet: false,
  ),
];

ItemTypeDef itemTypeDef(String key) => itemTypes.firstWhere(
  (t) => t.key == key,
  orElse: () => const ItemTypeDef(
    key: 'unknown',
    label: 'Item',
    icon: Icons.help_outline,
  ),
);

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
  });

  final String key;
  final String label;
  final IconData icon;
}

const List<ItemTypeDef> itemTypes = [
  ItemTypeDef(key: ItemType.note, label: 'Note', icon: Icons.note_outlined),
  ItemTypeDef(
      key: ItemType.checklist,
      label: 'Checklist',
      icon: Icons.checklist_outlined),
  // S3: link_card — ItemTypeDef(key: 'link_card', label: 'Link card', icon: Icons.grid_view_outlined)
  // S4: html_quiz — ItemTypeDef(key: 'html_quiz', label: 'HTML quiz', icon: Icons.quiz_outlined)
];

ItemTypeDef itemTypeDef(String key) => itemTypes.firstWhere(
      (t) => t.key == key,
      orElse: () => const ItemTypeDef(
          key: 'unknown', label: 'Item', icon: Icons.help_outline),
    );

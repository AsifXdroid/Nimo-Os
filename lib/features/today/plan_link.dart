/// TODAY (D-042) — linked resources for plan tasks.
///
/// One resource per task: either a bare external URL or a
/// reference to an existing Spaces item (never a copy). The
/// row's action is DERIVED from whichever is set:
///   url             → "Go →" (opened externally)
///   note item       → "Open note →" (the item itself)
///   link_card item  → "Go →" (the item detail opens its URL)
///   html_quiz item  → "Play →" (the item detail hosts play)
/// Opening a resource never completes the task.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../items/item_detail_screen.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../store.dart';

/// Item types the picker offers (owner decision: notes, link
/// cards, HTML quizzes — checklists are task CONTENT, not a
/// resource a task points at).
const Set<String> linkableItemTypes = {
  ItemType.note,
  ItemType.linkCard,
  ItemType.htmlQuiz,
};

/// A usable web link: absolute http/https with a host.
/// Anything else is rejected at attach time, so a stored URL
/// can always be opened.
bool isValidWebUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// The action label for a task's resource. [item] is the
/// resolved linked item (null when only a URL is set, or the
/// item could not be loaded).
String resourceActionLabel({String? url, Item? item}) {
  if (url != null) return 'Go →';
  return switch (item?.type) {
    ItemType.note => 'Open note →',
    ItemType.htmlQuiz => 'Play →',
    _ => 'Go →',
  };
}

/// Icon paired with [resourceActionLabel].
IconData resourceActionIcon({String? url, Item? item}) {
  if (url != null) return Icons.open_in_new;
  return switch (item?.type) {
    ItemType.note => Icons.description_outlined,
    ItemType.htmlQuiz => Icons.play_circle_outline,
    _ => Icons.open_in_new,
  };
}

/// Perform the resource action: external browser for a bare
/// URL, the existing item detail for a linked item.
Future<void> openPlanResource(
  BuildContext context, {
  String? url,
  Item? item,
  required Store store,
  LearnServices? learn,
  ThumbnailService? thumbnails,
}) async {
  if (url != null) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }
  if (item != null) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(
          store: store,
          item: item,
          learn: learn,
          thumbnails: thumbnails,
        ),
      ),
    );
  }
}

/// Bottom-sheet picker over existing Spaces items of the
/// linkable types, grouped by project. Returns the chosen
/// item, or null when dismissed.
Future<Item?> pickLinkItem(BuildContext context, Store store) async {
  final entries = await _linkableItems(store);
  if (!context.mounted) return null;
  return showModalBottomSheet<Item>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Choose from Spaces',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                  'No notes, link cards or quizzes in Spaces yet.'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in entries)
                    ListTile(
                      leading: Icon(switch (e.item.type) {
                        ItemType.note => Icons.description_outlined,
                        ItemType.htmlQuiz => Icons.quiz_outlined,
                        _ => Icons.link,
                      }),
                      title: Text(e.item.title),
                      subtitle: Text(e.where),
                      onTap: () => Navigator.pop(context, e.item),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

Future<List<({Item item, String where})>> _linkableItems(Store store) async {
  final out = <({Item item, String where})>[];
  for (final ws in await store.workspaces()) {
    for (final prj in await store.projects(ws.id)) {
      for (final item in await store.items(prj.id)) {
        if (linkableItemTypes.contains(item.type)) {
          out.add((item: item, where: '${ws.name} · ${prj.name}'));
        }
      }
    }
  }
  return out;
}

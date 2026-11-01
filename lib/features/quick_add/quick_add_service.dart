/// QUICK ADD (D-045) — the one capture workflow, shared by the
/// shell's Quick Add action and Today's quick-add row so both
/// surfaces behave identically.
///
/// Three captures, each with a single home:
/// - Task → today's plan (a one-off).
/// - Quick note → the Inbox project (the app's capture home —
///   Android shares land there as topics, too).
/// - Save resource → a link card in the Inbox project (which
///   also creates its topic, like every link card).
///
/// Operations only: prompting and presentation live in
/// quick_add_sheet.dart and the calling screens.
library;

import '../items/link_card/link_card_service.dart';
import '../learn/learn_store.dart';
import '../store.dart';
import '../today/plan_link.dart' show isValidWebUrl;
import '../today/today_store.dart';

class QuickAddService {
  QuickAddService({
    required this.store,
    required this.todayStore,
    required this.learnStore,
    required this.linkCards,
  });

  final Store store;
  final TodayStore todayStore;
  final LearnStore learnStore;
  final LinkCardService linkCards;

  /// Add a one-off task to today's plan.
  Future<void> addTask(String title) =>
      todayStore.addOneOff(DateTime.now(), title.trim());

  /// File a quick note in the Inbox project. The title is
  /// derived from the first line of the text; the full text is
  /// the note body. Returns the created item.
  Future<Item> addQuickNote(String text) async {
    final inbox = await learnStore.ensureInboxProject();
    final body = text.trim();
    return store.createItem(
      inbox.id,
      type: ItemType.note,
      title: deriveNoteTitle(body),
      note: body,
    );
  }

  /// Save a web resource as a link card in the Inbox project.
  /// Returns null when [url] is not a valid web URL.
  Future<Item?> addResource(String url) async {
    final clean = url.trim();
    if (!isValidWebUrl(clean)) return null;
    final inbox = await learnStore.ensureInboxProject();
    return linkCards.createLinkCard(projectId: inbox.id, url: clean);
  }

  /// A note's title from its text: the first non-empty line,
  /// capped so list rows stay readable.
  static String deriveNoteTitle(String text) {
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      return t.length <= 60 ? t : '${t.substring(0, 57)}…';
    }
    return 'Untitled note';
  }
}

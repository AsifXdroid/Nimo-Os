/// LINK — link-card creation/rework (S4, D-010): a saved link is
/// a *topic trigger*. Creating a link card therefore creates the
/// card AND its topic (in the same project, trigger = the URL,
/// with the URL attached as the topic's first link source);
/// the card's payload records `topic_id` (§R6.2), so the card and
/// the topic stay linked both ways.
///
/// Payload shape (DATA_MODEL): {"url": ..., "topic_id": ...,
/// "thumbnail_name": ...|absent, "thumbnail_source":
/// "user"|"auto"|absent} — thumbnail_name is a file name in the
/// thumbnail cache (see thumbnail_service.dart, D-019), and
/// thumbnail_source records which D-003 layer produced it so the
/// auto-fetch layer can never demote a user-attached image.
library;

import '../../learn/learn_store.dart';
import '../../store.dart';
import 'thumbnail_service.dart';

class LinkCardService {
  LinkCardService(this._store, this._learn, this._thumbnails);

  final Store _store;
  final LearnStore _learn;
  final ThumbnailService _thumbnails;

  /// Payload key for the thumbnail cache file name.
  static const String thumbKey = 'thumbnail_name';

  /// Payload key for which D-003 layer produced the thumbnail:
  /// 'user' (attached by the owner — always wins) or 'auto'
  /// (fetched). Absent = no thumbnail yet.
  static const String thumbSourceKey = 'thumbnail_source';

  /// Create a link card in [projectId] plus its topic. A manual
  /// [title] always wins; otherwise the title is derived from the
  /// URL's host.
  Future<Item> createLinkCard({
    required int projectId,
    required String url,
    String? title,
  }) async {
    final cleanUrl = url.trim();
    final cardTitle = (title == null || title.trim().isEmpty)
        ? titleFromUrl(cleanUrl)
        : title.trim();
    final topic = await _learn.createTopic(
      projectId: projectId,
      title: cardTitle,
      triggerUrl: cleanUrl,
    );
    await _learn.addSource(
      topicId: topic.id,
      kind: SourceKind.link,
      title: cardTitle,
      url: cleanUrl,
    );
    return _store.createItem(
      projectId,
      type: ItemType.linkCard,
      title: cardTitle,
      payload: {'url': cleanUrl, 'topic_id': topic.id},
    );
  }

  /// Best title we can offer for a URL without fetching anything.
  static String titleFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return url.trim();
    return uri.host;
  }

  /// Try the auto-fetch layer (D-003 layer 2) for [item]; stores
  /// the thumbnail name in the payload on success. Returns the
  /// updated item, or the item unchanged when fetch found nothing.
  Future<Item> tryFetchThumbnail(Item item) async {
    // D-003 layering: a user-attached image ALWAYS wins — the
    // auto-fetch layer never replaces it.
    if (thumbnailSourceOf(item) == 'user') return item;
    final url = urlOf(item);
    if (url == null) return item;
    final name = await _thumbnails.fetchForUrl(url);
    if (name == null) return item;
    final payload = {
      ...?item.payload,
      thumbKey: name,
      thumbSourceKey: 'auto',
    };
    await _store.updateItemPayload(item.id, payload);
    return _store.itemById(item.id);
  }

  /// Attach a user-picked image (D-003 layer 1 — always wins).
  Future<Item> attachUserImage(
      Item item, String sourcePath, String originalName) async {
    final name = await _thumbnails.attachUserImage(sourcePath, originalName);
    final payload = {
      ...?item.payload,
      thumbKey: name,
      thumbSourceKey: 'user',
    };
    await _store.updateItemPayload(item.id, payload);
    return _store.itemById(item.id);
  }

  // Accessors are deliberately type-tolerant: payloads are
  // app-written today, but a restored database is the one route
  // by which a foreign payload enters, and a mistyped value must
  // degrade to "absent" (fallback card), never a build crash.

  /// The topic a card triggers, if the payload carries one.
  int? topicIdOf(Item item) =>
      (item.payload?['topic_id'] as num?)?.toInt();

  String? urlOf(Item item) {
    final v = item.payload?['url'];
    return v is String ? v : null;
  }

  String? thumbnailNameOf(Item item) {
    final v = item.payload?[thumbKey];
    return v is String ? v : null;
  }

  String? thumbnailSourceOf(Item item) {
    final v = item.payload?[thumbSourceKey];
    return v is String ? v : null;
  }
}

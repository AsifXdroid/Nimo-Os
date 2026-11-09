/// Mission 03, Phase 7 — the Dua entry payload.
///
/// A Dua entry is an ordinary items row of type 'dua'; its
/// content lives in the JSON payload, exactly like the other
/// item types. Every field here is OWNER-ENTERED text: the
/// app never generates, corrects or completes any of it, and
/// the authenticity note is the owner's own free text —
/// shown verbatim when present, never displayed as an app
/// claim, and never rendered as an empty label when absent.
library;

import '../store.dart';

/// Payload access for a Dua [Item]. All text getters return
/// the stored value VERBATIM (no trimming, no case changes);
/// emptiness is decided by callers via [has].
class DuaPayload {
  DuaPayload(this.item);

  final Item item;

  Map<String, Object?> get _p => item.payload ?? const {};

  String? _text(String key) {
    final v = _p[key];
    return v is String ? v : null;
  }

  bool has(String key) {
    final v = _text(key);
    return v != null && v.trim().isNotEmpty;
  }

  String? get arabic => _text('arabic');
  String? get transliteration => _text('transliteration');
  String? get translation => _text('translation');
  String? get source => _text('source');
  String? get authenticity => _text('authenticity');
  String? get category => _text('category');
  bool get bookmarked => (_p['bookmarked'] as bool?) ?? false;

  /// Build the payload map for create/update. Empty optional
  /// fields are stored as ABSENT (never as empty strings), so
  /// "not supplied" stays distinguishable and no empty labels
  /// can render. Values are stored verbatim.
  static Map<String, Object?> build({
    String? arabic,
    String? transliteration,
    String? translation,
    String? source,
    String? authenticity,
    String? category,
    bool bookmarked = false,
  }) {
    final p = <String, Object?>{};
    void put(String key, String? value) {
      if (value != null && value.trim().isNotEmpty) p[key] = value;
    }

    put('arabic', arabic);
    put('transliteration', transliteration);
    put('translation', translation);
    put('source', source);
    put('authenticity', authenticity);
    put('category', category);
    if (bookmarked) p['bookmarked'] = true;
    return p;
  }
}

/// LINK — link-card thumbnails, the layered strategy of D-003:
///
/// 1. **User-attached image** — always wins; copied into the
///    thumbnail cache by [attachUserImage].
/// 2. **Auto-fetch** — best-effort `og:image` download by
///    [fetchForUrl]. Link metadata fetching is unreliable by
///    nature (§R4.5), so every failure simply returns null.
/// 3. **Designed fallback card** — rendered by the UI whenever the
///    payload has no thumbnail (or the file is gone). A card must
///    never render broken.
///
/// Thumbnails live in app-private CACHE storage (a plain
/// directory handed in by main), not the Library: they are
/// regenerable, and §R6.4 keeps caches out of the synced tree.
/// The item payload stores only the file NAME inside that cache.
/// All writes are temp-then-rename (red-team #8's rule, applied
/// to cache writes too — a torn thumbnail is a broken card).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/file_names.dart';
import '../../../core/ids.dart';

/// One HTTP GET, capped. Injectable so tests never touch a network.
typedef BytesFetcher = Future<({int status, String? contentType, List<int> bytes})>
    Function(Uri uri, {required int maxBytes});

Future<({int status, String? contentType, List<int> bytes})> httpGetBytes(
  Uri uri, {
  required int maxBytes,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'NimoOS/1.0 (link preview)';
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final builder = <int>[];
    await for (final chunk in response) {
      builder.addAll(chunk);
      if (builder.length > maxBytes) {
        throw const HttpException('response too large');
      }
    }
    return (
      status: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      bytes: builder,
    );
  } finally {
    client.close(force: true);
  }
}

class ThumbnailService {
  ThumbnailService(this.dir, {this.fetcher = httpGetBytes});

  /// The thumbnail cache directory (created on demand).
  final Directory dir;
  final BytesFetcher fetcher;

  static const int _maxHtmlBytes = 512 * 1024;
  static const int _maxImageBytes = 2 * 1024 * 1024;

  /// The cached file for a payload thumbnail name, or null when
  /// there is none (→ the UI draws the fallback card).
  File? fileFor(String? name) {
    if (name == null || name.isEmpty) return null;
    // The name comes from an item payload — data a restored
    // backup could have crafted. Apply the Library's containment
    // discipline: reduce to a plain sanitised file name, then
    // verify the joined path stays inside the cache directory.
    final f = File(p.join(dir.path, sanitizeFileName(name)));
    if (!p.isWithin(p.normalize(dir.path), p.normalize(f.path))) {
      return null;
    }
    return f;
  }

  static const int _maxUserImageBytes = 10 * 1024 * 1024;

  /// Layer 1: copy a user-picked image into the cache. Returns
  /// the stored file name. Refuses images over 10 MB rather than
  /// reading them into memory unbounded.
  Future<String> attachUserImage(String sourcePath, String originalName) async {
    final source = File(sourcePath);
    if (await source.length() > _maxUserImageBytes) {
      throw const FileSystemException(
          'That image is larger than 10 MB.');
    }
    final bytes = await source.readAsBytes();
    final name = sanitizeFileName(originalName);
    return _writeUnique(name, bytes);
  }

  /// Layer 2: fetch the page's `og:image`. Returns the stored
  /// file name, or null on ANY failure (network, no og:image,
  /// wrong type, too big) — the fallback card is the answer.
  Future<String?> fetchForUrl(String pageUrl) async {
    try {
      final pageUri = Uri.parse(pageUrl);
      if (pageUri.scheme != 'http' && pageUri.scheme != 'https') {
        return null;
      }
      final page = await fetcher(pageUri, maxBytes: _maxHtmlBytes);
      if (page.status != 200) return null;
      final html = String.fromCharCodes(page.bytes);
      final og = _extractOgImage(html);
      if (og == null) return null;
      final imageUri = pageUri.resolve(og);
      if (imageUri.scheme != 'http' && imageUri.scheme != 'https') {
        return null;
      }
      final image = await fetcher(imageUri, maxBytes: _maxImageBytes);
      if (image.status != 200) return null;
      final ext = _extensionFor(image.contentType, imageUri);
      if (ext == null) return null;
      final name = 'og-${_urlHash(pageUrl)}$ext';
      return await _writeUnique(name, image.bytes, overwrite: true);
    } catch (_) {
      return null;
    }
  }

  Future<String> _writeUnique(String name, List<int> bytes,
      {bool overwrite = false}) async {
    await dir.create(recursive: true);
    var candidate = name;
    if (!overwrite) {
      var n = 2;
      while (await File(p.join(dir.path, candidate)).exists()) {
        final ext = p.extension(name);
        candidate =
            '${p.basenameWithoutExtension(name)}-$n$ext';
        n++;
      }
    }
    final target = File(p.join(dir.path, candidate));
    final tmp = File('${target.path}.tmp-${newUuid().substring(0, 8)}');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    return candidate;
  }

  static String? _extractOgImage(String html) {
    // property/content in either order; single or double quotes.
    final patterns = [
      RegExp(
          r'''<meta[^>]+property\s*=\s*["']og:image["'][^>]+content\s*=\s*["']([^"']+)["']''',
          caseSensitive: false),
      RegExp(
          r'''<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']og:image["']''',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String? _extensionFor(String? contentType, Uri uri) {
    switch (contentType) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/gif':
        return '.gif';
    }
    final ext = p.extension(uri.path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.gif'].contains(ext)
        ? ext
        : null;
  }

  static String _urlHash(String url) {
    var hash = 0x811c9dc5;
    for (final b in url.codeUnits) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

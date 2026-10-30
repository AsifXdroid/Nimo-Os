/// LEARN engine — image dimension sniffing (S5, TESTING §7).
/// PURE: reads the pixel dimensions out of an image's header
/// bytes WITHOUT decoding the image, so the pack importer can
/// reject absurd declarations (a tiny file claiming 20000×20000
/// would otherwise be fully decoded at play time and OOM).
///
/// [imageDimensions] returns the (width, height) for the formats
/// the importer accepts, or null when the bytes do not parse as
/// the declared [mime] (truncated, wrong signature, missing the
/// relevant header chunk, or a zero dimension).
library;

/// Pixel dimensions declared in [bytes]' header for [mime], or
/// null when unparseable. Never throws, never decodes pixels.
({int width, int height})? imageDimensions(String mime, List<int> bytes) {
  final result = switch (mime) {
    'image/png' => _png(bytes),
    'image/jpeg' => _jpeg(bytes),
    'image/gif' => _gif(bytes),
    'image/webp' => _webp(bytes),
    _ => null,
  };
  if (result == null || result.width <= 0 || result.height <= 0) {
    return null;
  }
  return result;
}

int _u16be(List<int> b, int off) => (b[off] << 8) | b[off + 1];
int _u16le(List<int> b, int off) => b[off] | (b[off + 1] << 8);
int _u24le(List<int> b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16);
int _u32be(List<int> b, int off) =>
    (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

bool _asciiAt(List<int> b, int off, String s) =>
    b.length >= off + s.length &&
    String.fromCharCodes(b.sublist(off, off + s.length)) == s;

// ------------------------------------------------------------ PNG

({int width, int height})? _png(List<int> b) {
  // 8-byte signature, then the IHDR chunk: length(4) 'IHDR'
  // width(4, BE) height(4, BE).
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (b.length < 24) return null;
  for (var i = 0; i < sig.length; i++) {
    if (b[i] != sig[i]) return null;
  }
  if (!_asciiAt(b, 12, 'IHDR')) return null;
  return (width: _u32be(b, 16), height: _u32be(b, 20));
}

// ------------------------------------------------------------ JPEG

({int width, int height})? _jpeg(List<int> b) {
  if (b.length < 2 || b[0] != 0xFF || b[1] != 0xD8) return null;
  // Walk markers: FF <marker> [<length:2> <payload…>]. Standalone
  // markers (SOI/EOI/TEM/RSTn) carry no length. SOF0 (C0) and
  // SOF2 (C2) carry: precision(1) height(2, BE) width(2, BE).
  var off = 2;
  while (off + 1 < b.length) {
    if (b[off] != 0xFF) return null;
    var marker = b[off + 1];
    // Skip padding FF bytes (the marker follows the last one).
    while (marker == 0xFF && off + 2 < b.length) {
      off++;
      marker = b[off + 1];
    }
    if (marker == 0xC0 || marker == 0xC2) {
      if (off + 9 > b.length) return null;
      return (width: _u16be(b, off + 7), height: _u16be(b, off + 5));
    }
    final standalone =
        marker == 0xD8 ||
        marker == 0xD9 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7);
    if (standalone) {
      off += 2;
      continue;
    }
    // SOS (DA): entropy data runs to EOF with no reliable SOF
    // after it — a header-only sniff gives up here.
    if (marker == 0xDA) return null;
    if (off + 4 > b.length) return null;
    final length = _u16be(b, off + 2); // includes its own 2 bytes
    if (length < 2) return null;
    off += 2 + length;
  }
  return null;
}

// ------------------------------------------------------------ GIF

({int width, int height})? _gif(List<int> b) {
  // Header(6) then the logical screen descriptor: width(2, LE)
  // height(2, LE).
  if (b.length < 10) return null;
  if (!_asciiAt(b, 0, 'GIF87a') && !_asciiAt(b, 0, 'GIF89a')) {
    return null;
  }
  return (width: _u16le(b, 6), height: _u16le(b, 8));
}

// ------------------------------------------------------------ WebP

({int width, int height})? _webp(List<int> b) {
  // 'RIFF' size(4) 'WEBP' then the first chunk: type(4) size(4)
  // data…
  if (b.length < 20) return null;
  if (!_asciiAt(b, 0, 'RIFF') || !_asciiAt(b, 8, 'WEBP')) return null;
  final chunk = String.fromCharCodes(b.sublist(12, 16));
  final data = 20; // first byte of the chunk payload
  return switch (chunk) {
    // Extended: flags(1) reserved(3) (width-1)(3, LE) (height-1)(3, LE).
    'VP8X' =>
      b.length < data + 10
          ? null
          : (width: _u24le(b, data + 4) + 1, height: _u24le(b, data + 7) + 1),
    // Lossy: frame tag(3) magic(3: 9D 01 2A) width(2, 14 bits)
    // height(2, 14 bits).
    'VP8 ' =>
      (b.length < data + 10 ||
              b[data + 3] != 0x9D ||
              b[data + 4] != 0x01 ||
              b[data + 5] != 0x2A)
          ? null
          : (
              width: _u16le(b, data + 6) & 0x3FFF,
              height: _u16le(b, data + 8) & 0x3FFF,
            ),
    // Lossless: signature(1: 0x2F) then (width-1) and (height-1)
    // packed as 14-bit fields across the next 4 bytes.
    'VP8L' =>
      (b.length < data + 5 || b[data] != 0x2F)
          ? null
          : (
              width: 1 + (((b[data + 2] & 0x3F) << 8) | b[data + 1]),
              height:
                  1 +
                  (((b[data + 4] & 0x0F) << 10) |
                      (b[data + 3] << 2) |
                      ((b[data + 2] & 0xC0) >> 6)),
            ),
    _ => null,
  };
}

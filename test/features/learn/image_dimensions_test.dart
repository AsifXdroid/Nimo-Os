// LEARN engine — imageDimensions header sniffing (S5, TESTING
// §7): one crafted header per accepted format/variant, plus the
// unparseable cases. Pure — headers are built byte by byte so
// the expected dimensions are known exactly.
import 'package:daily_life_app/features/learn/image_dimensions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/sample_pack.dart';

List<int> pngHeader(int width, int height) => [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0, 0, 0, 13, // IHDR length
  ...'IHDR'.codeUnits,
  (width >> 24) & 0xFF, (width >> 16) & 0xFF,
  (width >> 8) & 0xFF, width & 0xFF,
  (height >> 24) & 0xFF, (height >> 16) & 0xFF,
  (height >> 8) & 0xFF, height & 0xFF,
  8, 6, 0, 0, 0, // bit depth, colour type, …
];

List<int> jpegHeader(int width, int height, {int sof = 0xC0}) => [
  0xFF, 0xD8, // SOI
  0xFF, 0xE0, 0, 16, // APP0, length 16 (incl. length bytes)
  ...List.filled(14, 0),
  0xFF, sof, 0, 17, 8, // SOF, length, precision
  (height >> 8) & 0xFF, height & 0xFF,
  (width >> 8) & 0xFF, width & 0xFF,
  3, 0, 0, 0, 0, 0, 0, // components
];

List<int> gifHeader(int width, int height) => [
  ...'GIF89a'.codeUnits,
  width & 0xFF,
  (width >> 8) & 0xFF,
  height & 0xFF,
  (height >> 8) & 0xFF,
  0,
  0,
  0,
];

List<int> webpContainer(String chunk, List<int> chunkData) => [
  ...'RIFF'.codeUnits,
  0,
  0,
  0,
  0,
  ...'WEBP'.codeUnits,
  ...chunk.codeUnits,
  chunkData.length,
  0,
  0,
  0,
  ...chunkData,
];

void main() {
  group('imageDimensions parses each accepted format', () {
    test('PNG: the sample fixture PNG is 1×1', () {
      expect(imageDimensions('image/png', samplePngBytes), (
        width: 1,
        height: 1,
      ));
    });

    test('PNG: crafted IHDR 8000×6000', () {
      expect(imageDimensions('image/png', pngHeader(8000, 6000)), (
        width: 8000,
        height: 6000,
      ));
    });

    test('PNG: a huge declaration parses (the cap is the '
        'importer\'s job, not the parser\'s)', () {
      expect(imageDimensions('image/png', pngHeader(20000, 20000)), (
        width: 20000,
        height: 20000,
      ));
    });

    test('JPEG: SOF0 after an APP0 segment', () {
      expect(imageDimensions('image/jpeg', jpegHeader(640, 480)), (
        width: 640,
        height: 480,
      ));
    });

    test('JPEG: SOF2 (progressive)', () {
      expect(imageDimensions('image/jpeg', jpegHeader(1920, 1080, sof: 0xC2)), (
        width: 1920,
        height: 1080,
      ));
    });

    test('GIF: logical screen descriptor, little-endian', () {
      expect(imageDimensions('image/gif', gifHeader(320, 200)), (
        width: 320,
        height: 200,
      ));
    });

    test('WebP VP8X: canvas size is stored minus one', () {
      // 1024×768 → stored 1023 / 767 as 24-bit LE.
      final data = [
        0, 0, 0, 0, // flags + reserved
        1023 & 0xFF, (1023 >> 8) & 0xFF, (1023 >> 16) & 0xFF,
        767 & 0xFF, (767 >> 8) & 0xFF, (767 >> 16) & 0xFF,
      ];
      expect(imageDimensions('image/webp', webpContainer('VP8X', data)), (
        width: 1024,
        height: 768,
      ));
    });

    test('WebP VP8 (lossy): 14-bit dimensions after the magic', () {
      final data = [
        0, 0, 0, // frame tag
        0x9D, 0x01, 0x2A, // start code
        800 & 0xFF, (800 >> 8) & 0xFF,
        600 & 0xFF, (600 >> 8) & 0xFF,
      ];
      expect(imageDimensions('image/webp', webpContainer('VP8 ', data)), (
        width: 800,
        height: 600,
      ));
    });

    test('WebP VP8L (lossless): packed 14-bit fields, minus one', () {
      // 300×200 → w-1 = 299, h-1 = 199 packed per the VP8L spec.
      final data = [0x2F, 43, 0xC1, 49, 0];
      expect(imageDimensions('image/webp', webpContainer('VP8L', data)), (
        width: 300,
        height: 200,
      ));
    });
  });

  group('imageDimensions returns null when unparseable', () {
    test('wrong signature for the declared mime', () {
      expect(imageDimensions('image/png', gifHeader(10, 10)), isNull);
      expect(imageDimensions('image/gif', pngHeader(10, 10)), isNull);
      expect(imageDimensions('image/jpeg', pngHeader(10, 10)), isNull);
      expect(imageDimensions('image/webp', pngHeader(10, 10)), isNull);
    });

    test('truncated headers', () {
      expect(
        imageDimensions('image/png', pngHeader(10, 10).sublist(0, 12)),
        isNull,
      );
      expect(
        imageDimensions('image/gif', gifHeader(10, 10).sublist(0, 8)),
        isNull,
      );
      expect(imageDimensions('image/jpeg', const [0xFF, 0xD8]), isNull);
      expect(
        imageDimensions('image/webp', webpContainer('VP8X', const [0, 0])),
        isNull,
      );
    });

    test('JPEG with no SOF before SOS', () {
      final bytes = [
        0xFF, 0xD8,
        0xFF, 0xDA, 0, 8, 1, 1, 0, 0, 63, 0, // SOS segment
      ];
      expect(imageDimensions('image/jpeg', bytes), isNull);
    });

    test('zero dimensions are unparseable', () {
      expect(imageDimensions('image/png', pngHeader(0, 10)), isNull);
      expect(imageDimensions('image/gif', gifHeader(10, 0)), isNull);
    });

    test('unknown mime', () {
      expect(imageDimensions('image/bmp', pngHeader(10, 10)), isNull);
      expect(imageDimensions('text/plain', pngHeader(10, 10)), isNull);
    });
  });
}

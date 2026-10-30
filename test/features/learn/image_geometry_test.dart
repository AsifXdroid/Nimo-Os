// LEARN engine — image geometry (S5 step C2a, §R8.5): the
// contain rect for wide/tall/square images in wide/tall boxes,
// and tap→normalised conversion including the letterbox bands.
import 'package:daily_life_app/features/learn/image_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('containRect', () {
    test('wide image in a square box: full width, centred vertically', () {
      // 200×100 into 100×100 → scale 0.5 → 100×50, top = 25.
      expect(
        containRect(const Size(100, 100), const Size(200, 100)),
        const Rect.fromLTWH(0, 25, 100, 50),
      );
    });

    test('tall image in a square box: full height, centred horizontally',
        () {
      // 100×200 into 100×100 → scale 0.5 → 50×100, left = 25.
      expect(
        containRect(const Size(100, 100), const Size(100, 200)),
        const Rect.fromLTWH(25, 0, 50, 100),
      );
    });

    test('square image in a wide box: full height, centred horizontally',
        () {
      // 100×100 into 200×100 → scale 1 → 100×100, left = 50.
      expect(
        containRect(const Size(200, 100), const Size(100, 100)),
        const Rect.fromLTWH(50, 0, 100, 100),
      );
    });

    test('wide image in a tall box: full width, centred vertically', () {
      // 200×100 into 100×200 → scale 0.5 → 100×50, top = 75.
      expect(
        containRect(const Size(100, 200), const Size(200, 100)),
        const Rect.fromLTWH(0, 75, 100, 50),
      );
    });
  });

  group('toNormalised', () {
    // A 200×100 image contained in a 100×100 box.
    const displayed = Rect.fromLTWH(0, 25, 100, 50);

    test('centre of the displayed image → (0.5, 0.5)', () {
      expect(
        toNormalised(const Offset(50, 50), displayed),
        const Offset(0.5, 0.5),
      );
    });

    test('corners → (0, 0) and (1, 1)', () {
      expect(
        toNormalised(const Offset(0, 25), displayed),
        const Offset(0, 0),
      );
      expect(
        toNormalised(const Offset(100, 75), displayed),
        const Offset(1, 1),
      );
    });

    test('tap in the letterbox band above/below → null', () {
      expect(toNormalised(const Offset(50, 10), displayed), isNull);
      expect(toNormalised(const Offset(50, 90), displayed), isNull);
    });

    test('tap in the letterbox band at the sides → null', () {
      // A 100×200 image contained in a 100×100 box.
      const sideDisplayed = Rect.fromLTWH(25, 0, 50, 100);
      expect(toNormalised(const Offset(10, 50), sideDisplayed), isNull);
      expect(toNormalised(const Offset(90, 50), sideDisplayed), isNull);
      expect(
        toNormalised(const Offset(50, 50), sideDisplayed),
        const Offset(0.5, 0.5),
      );
    });
  });
}

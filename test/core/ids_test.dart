// CORE — sync identity helpers (S3, review S4): the HLC is S7's
// load-bearing ordering primitive, so its fixed-width padding
// and lexicographic ordering are pinned directly — including the
// counter-9→10 boundary where unpadded counters break (§R6.3).
import 'package:daily_life_app/core/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatHlc', () {
    test('fields are zero-padded to fixed widths', () {
      expect(formatHlc(42, 3, 'dev'), '0000000000042-000003-dev');
      expect(formatHlc(0, 0, 'dev'), '0000000000000-000000-dev');
    });

    test('lexicographic order matches HLC order across the 9→10 counter step',
        () {
      final nine = formatHlc(1000, 9, 'dev');
      final ten = formatHlc(1000, 10, 'dev');
      expect(ten.compareTo(nine), greaterThan(0));
    });

    test('wall clock dominates the counter', () {
      final later = formatHlc(1001, 0, 'dev');
      final earlier = formatHlc(1000, 999999, 'dev');
      expect(later.compareTo(earlier), greaterThan(0));
    });

    test('device id breaks ties last', () {
      expect(formatHlc(5, 5, 'bbb').compareTo(formatHlc(5, 5, 'aaa')),
          greaterThan(0));
    });
  });

  group('newUuid', () {
    test('is a well-formed UUIDv4', () {
      final id = newUuid();
      expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });

    test('500 draws are all distinct', () {
      final ids = {for (var i = 0; i < 500; i++) newUuid()};
      expect(ids.length, 500);
    });
  });
}

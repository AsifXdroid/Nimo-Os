/// Font integration guard (D-039): the three Editorial
/// families must be declared in pubspec AND resolvable from
/// the built asset bundle — this is what "the real font
/// binaries are integrated" means in testable form. If a
/// declared file goes missing, the bundle build (and this
/// test) fails rather than silently falling back.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FontManifest lists the Editorial families and files', () async {
    final raw = await rootBundle.loadString('FontManifest.json');
    final entries = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final byFamily = <String, List<String>>{
      for (final e in entries)
        e['family'] as String: [
          for (final f in (e['fonts'] as List).cast<Map<String, dynamic>>())
            f['asset'] as String,
        ],
    };
    expect(byFamily['Playfair Display'], [
      'assets/fonts/PlayfairDisplay-Medium.ttf',
      'assets/fonts/PlayfairDisplay-SemiBold.ttf',
      'assets/fonts/PlayfairDisplay-MediumItalic.ttf',
    ]);
    expect(byFamily['DM Sans'], [
      'assets/fonts/DMSans-Regular.ttf',
      'assets/fonts/DMSans-Medium.ttf',
      'assets/fonts/DMSans-Bold.ttf',
    ]);
    expect(byFamily['DM Mono'], [
      'assets/fonts/DMMono-Regular.ttf',
      'assets/fonts/DMMono-Medium.ttf',
    ]);
    // And the bytes are really there (a TrueType header
    // starts with 00 01 00 00). Only the Editorial families
    // are checked — the manifest also carries MaterialIcons,
    // an OTF with a different header.
    for (final family in ['Playfair Display', 'DM Sans', 'DM Mono']) {
      for (final asset in byFamily[family]!) {
        final data = await rootBundle.load(asset);
        expect(data.lengthInBytes, greaterThan(10000), reason: asset);
        expect(data.getUint32(0), 0x00010000, reason: asset);
      }
    }
  });
}

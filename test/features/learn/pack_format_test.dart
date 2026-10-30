// LEARN engine — pack_format structural validation (S5 fix
// M1): ids that filename sanitisation would CHANGE are
// structural errors, because the importer builds Library paths
// from sanitised ids and two distinct raw ids ('../x', 'a/x')
// fold onto the same stored file.
import 'dart:convert';

import 'package:daily_life_app/features/learn/pack_format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/sample_pack.dart';

Map<String, Object?> _sample() =>
    (jsonDecode(buildSamplePackJson()) as Map).cast<String, Object?>();

void main() {
  group('structuralIssues — id sanitisation (M1)', () {
    test('the sample pack is structurally valid', () {
      expect(structuralIssues(_sample()), isEmpty);
    });

    test('a pack id with a traversal prefix is an issue', () {
      final json = _sample();
      (json['pack'] as Map)['id'] = '../evil';
      final issues = structuralIssues(json);
      expect(issues, isNotEmpty);
      expect(issues.join('; '), contains('pack.id'));
      expect(
        () => parsePackDocument(json),
        throwsA(isA<PackFormatException>()),
      );
    });

    test('a pack id with a path segment is an issue '
        '(it folds onto the plain id)', () {
      final json = _sample();
      (json['pack'] as Map)['id'] = 'x/arabic-greetings-01';
      expect(structuralIssues(json), isNotEmpty);
    });

    test('a media id with a path segment is an issue', () {
      final json = _sample();
      final media = (json['media'] as List)
          .map((m) => (m as Map).cast<String, Object?>())
          .toList();
      media.single['id'] = 'a/b';
      final issues = structuralIssues(json);
      expect(issues, isNotEmpty);
      expect(issues.join('; '), contains('media[0].id'));
    });

    test('plain filename-safe ids pass unchanged', () {
      final json = _sample();
      (json['pack'] as Map)['id'] = 'my-pack_02.v2';
      final media = (json['media'] as List)
          .map((m) => (m as Map).cast<String, Object?>())
          .toList();
      media.single['id'] = 'img-1_a';
      expect(structuralIssues(json), isEmpty);
    });
  });
}

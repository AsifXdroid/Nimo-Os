/// Smoke tests for the design-plate previews (D-008): every prototype
/// body must render under every plate theme without errors.
library;

import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/design_preview/design_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final plate in AppPlate.values) {
    testWidgets('preview bodies render in ${plate.label}', (tester) async {
      Future<void> pump(Widget body) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.forPlate(plate), home: Scaffold(body: body)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      await pump(const TodayPreviewBody());
      expect(find.text("Today's plan"), findsOneWidget);
      expect(find.text('Learn 100 Arabic words'), findsOneWidget);

      await pump(const ReelsPreviewBody());
      expect(find.text('Watch Later'), findsOneWidget);
      expect(find.text('No preview yet'), findsOneWidget);

      await pump(const WorkspacesPreviewBody());
      expect(find.text('Study'), findsOneWidget);
    });
  }
}

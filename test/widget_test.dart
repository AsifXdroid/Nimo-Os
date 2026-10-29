// CORE smoke test: the app boots to the Workspaces screen (S1).
//
// Note: sqflite_common_ffi completes futures on the real event loop,
// while widget tests run in a fake-async zone — so the initial pump
// happens inside runAsync with a real delay, not pumpAndSettle
// (which deadlocks on the loading spinner). Verified 2026-10-29.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('app boots and shows empty Workspaces screen', (tester) async {
    // Everything runs inside runAsync: even opening the FFI database
    // deadlocks if awaited in the test body's fake-async zone.
    await tester.runAsync(() async {
      final store = Store(await AppDatabase.openInMemory());
      await tester.pumpWidget(DailyLifeApp(store: store));
      // Poll in real time until the workspaces future lands.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find
            .textContaining('No workspaces yet')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(find.text('Workspaces'), findsOneWidget);
      expect(find.textContaining('No workspaces yet'), findsOneWidget);
    });
  });
}

// Integration smoke test (TESTING.md §9/S4: the harness exists
// from S4 on). Runs the REAL app widget on a device/emulator:
//
//   flutter test integration_test/app_smoke_test.dart -d <device>
//
// It cannot run in the build VM (no emulator), so device runs are
// the owner's (see PROGRESS_LOG). Keep it shallow on purpose:
// boot → Hub Home visible → Topics & Library opens → back.
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/goals/goals_store.dart';
import 'package:daily_life_app/features/items/link_card/thumbnail_service.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/review/review_store.dart';
import 'package:daily_life_app/features/settings/backup_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:daily_life_app/features/today/today_store.dart';
import 'package:daily_life_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots; Topics & Library opens', (tester) async {
    final db = await AppDatabase.openInMemory();
    final todayStore = TodayStore(db);
    final tmp = await Directory.systemTemp.createTemp('nimo-it-');
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();

    await tester.pumpWidget(DailyLifeApp(
      db: db,
      store: Store(db),
      todayStore: todayStore,
      goalsStore: GoalsStore(db),
      reviewStore: ReviewStore(db, todayStore),
      learn: LearnServices(LearnStore(db), library, db: db),
      thumbnails: ThumbnailService(Directory('${tmp.path}/thumbs')),
      backup: BackupStore(),
      onRestoreBackup: (_, {required replaceConfirmed}) async {},
    ));
    await tester.pumpAndSettle();

    expect(find.text("Today's plan"), findsOneWidget);
    await tester.tap(find.text('Topics & Library'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox (0)'), findsOneWidget);
    expect(find.text('Export backup'), findsOneWidget);
  });
}

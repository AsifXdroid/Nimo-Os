/// Daily Life App — entry point (CORE).
/// S1 scope: Workspaces → Projects → Items (note + checklist).
/// Home-as-Today dashboard arrives in S2.
library;

import 'package:flutter/material.dart';

import 'core/db/app_database.dart';
import 'core/theme.dart';
import 'features/store.dart';
import 'features/workspaces/workspaces_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  runApp(DailyLifeApp(store: Store(db)));
}

class DailyLifeApp extends StatelessWidget {
  const DailyLifeApp({super.key, required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Life',
      theme: AppTheme.light(),
      home: WorkspacesScreen(store: store),
    );
  }
}

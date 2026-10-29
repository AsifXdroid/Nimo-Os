/// Daily Life App — entry point (CORE).
/// S1: Workspaces → Projects → Items (note + checklist).
/// S2: app shell with bottom navigation — Today (Hub Home, D-009),
/// Spaces (the S1 workspaces), Goals (basic).
library;

import 'package:flutter/material.dart';

import 'core/db/app_database.dart';
import 'core/theme.dart';
import 'features/goals/goals_screen.dart';
import 'features/goals/goals_store.dart';
import 'features/projects/projects_screen.dart';
import 'features/store.dart';
import 'features/today/today_screen.dart';
import 'features/today/today_store.dart';
import 'features/workspaces/workspaces_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  runApp(DailyLifeApp(
    store: Store(db),
    todayStore: TodayStore(db),
    goalsStore: GoalsStore(db),
  ));
}

class DailyLifeApp extends StatelessWidget {
  const DailyLifeApp({
    super.key,
    required this.store,
    required this.todayStore,
    required this.goalsStore,
  });

  final Store store;
  final TodayStore todayStore;
  final GoalsStore goalsStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Life',
      theme: AppTheme.forPlate(AppPlate.midnight), // D-008: Plate B
      home: AppShell(
        store: store,
        todayStore: todayStore,
        goalsStore: goalsStore,
      ),
    );
  }
}

/// Bottom-navigation shell: Today · Spaces · Goals.
/// Switching tabs rebuilds the tab body, so each screen reloads its
/// data when it becomes visible (the S1 FutureBuilder pattern).
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.store,
    required this.todayStore,
    required this.goalsStore,
  });

  final Store store;
  final TodayStore todayStore;
  final GoalsStore goalsStore;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _openWorkspace(Workspace ws) {
    setState(() => _index = 1);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectsScreen(store: widget.store, workspace: ws),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_index) {
        0 => TodayScreen(
            store: widget.store,
            todayStore: widget.todayStore,
            goalsStore: widget.goalsStore,
            onOpenWorkspace: _openWorkspace,
          ),
        1 => WorkspacesScreen(store: widget.store),
        _ => GoalsScreen(goalsStore: widget.goalsStore),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Spaces',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Goals',
          ),
        ],
      ),
    );
  }
}

/// Daily Life App — entry point (CORE).
/// S1: Workspaces → Projects → Items (note + checklist).
/// S2: app shell with bottom navigation — Today (Hub Home, D-009),
/// Spaces (the S1 workspaces), Goals (basic).
/// S3: Day Close + dual scores + Streak Shields on Hub Home.
/// S4: Topics & Library (LEARN-data), share-intent capture into
/// the Inbox, link cards as topic triggers, PDF/TXT reading with
/// mark-a-point, and backup export/import (SET) with the D-011
/// restore guard.
/// S5: Learn engine + the 4th nav destination (D-021).
/// S6: Progress destination (Journey Path, dual-score charts,
/// calendar, Sunday weekly summary) completes the D-021 layout;
/// Settings surface with opt-in inexact reminders.
/// S7: Linux desktop target (FFI database factory, share-intent
/// absent, HTML quizzes via the system browser) and Sync Stage A
/// ("Sync now" packages + Repair) in Settings.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'core/db/app_database.dart';
import 'core/platform_init.dart';
import 'core/theme.dart';
import 'features/goals/goals_screen.dart';
import 'features/goals/goals_store.dart';
import 'features/items/link_card/thumbnail_service.dart';
import 'features/learn/capture_service.dart';
import 'features/learn/learn_screen.dart';
import 'features/learn/learn_services.dart';
import 'features/learn/learn_store.dart';
import 'features/learn/library_store.dart';
import 'features/learn/share_confirm_sheet.dart';
import 'features/learn/topics_screen.dart';
import 'features/progress/progress_screen.dart';
import 'features/progress/progress_store.dart';
import 'features/progress/weekly_summary_screen.dart';
import 'features/projects/projects_screen.dart';
import 'features/review/day_close_screen.dart';
import 'features/review/review_store.dart';
import 'features/settings/backup_section.dart';
import 'features/settings/backup_store.dart';
import 'features/settings/external_backup.dart';
import 'features/settings/external_backup_section.dart';
import 'features/settings/reminder_gateway.dart';
import 'features/settings/reminders.dart';
import 'features/settings/settings_screen.dart';
import 'features/store.dart';
import 'features/sync/sync_section.dart';
import 'features/sync/sync_store.dart';
import 'features/today/today_screen.dart';
import 'features/today/today_store.dart';
import 'features/workspaces/workspaces_screen.dart';

Future<void> main() async {
  await bootstrap();
}

/// Opens the database, resolves the Library root, builds every
/// store, and (re)installs the widget tree. Backup restore calls
/// this again after swapping the database file, so the whole app
/// restarts on the restored data with fresh store objects.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // S7 (§R8.6): desktop platforms open SQLite through the FFI
  // factory; Android keeps the native one. Must precede open().
  initDatabaseFactory();
  final db = await AppDatabase.open();
  final todayStore = TodayStore(db);

  final docsDir = await getApplicationDocumentsDirectory();
  final libraryRoot = await _libraryRoot(db, docsDir);
  var library = LibraryStore(libraryRoot);
  try {
    await library.ensureLayout();
  } catch (_) {
    // A persisted Library folder that has become unwritable
    // (folder removed, permissions changed) must not brick
    // launch: fall back to the default root for this session;
    // the setting itself is left for the owner to change.
    library = LibraryStore(Directory(p.join(docsDir.path, 'NimoLibrary')));
    await library.ensureLayout();
  }
  final learn = LearnServices(LearnStore(db), library, db: db);

  final cacheDir = await getApplicationCacheDirectory();
  final thumbnails = ThumbnailService(
    Directory(p.join(cacheDir.path, 'thumbs')),
  );
  final backup = BackupStore();

  final reviewStore = ReviewStore(db, todayStore);
  final progressStore = ProgressStore(db, reviewStore, todayStore);
  final themeChoice = await _themeChoice(db);

  // SET (S6): reminders — plugin gateway + tap router. App start
  // records the open (the §R5.6 self-watch) and re-applies the
  // persisted schedule; both are fire-and-forget and can never
  // block or break boot (reminders are garnish, §R9.7).
  final reminderRouter = ReminderTapRouter();
  final reminders = ReminderController(
    db,
    PluginReminderGateway(reminderRouter),
  );
  unawaited(reminders.recordAppOpen().catchError((_) {}));
  unawaited(reminders.applyAll().catchError((_) {}));

  runApp(
    DailyLifeApp(
      db: db,
      store: Store(db),
      todayStore: todayStore,
      goalsStore: GoalsStore(db),
      reviewStore: reviewStore,
      progressStore: progressStore,
      reminders: reminders,
      reminderRouter: reminderRouter,
      initialThemeChoice: themeChoice,
      learn: learn,
      thumbnails: thumbnails,
      backup: backup,
      // Share-intent capture is Android-only: the plugin has no
      // desktop implementation, and desktop has no inbound share
      // sheet to capture from (§R8.7). The shell null-guards it;
      // on Linux the capture entry points simply never fire, and
      // file import via the picker remains the capture route.
      shareService: Platform.isAndroid ? AppShareIntentService() : null,
      // D-043 (P0): the external (SAF) backup is Android-only —
      // the grant model is Android's; on desktop the Library
      // already lives in user-controlled storage.
      externalBackup: Platform.isAndroid
          ? ExternalBackupStore(db, backup, MethodChannelSafBackup())
          : null,
      onRestoreBackup: (zip, {required replaceConfirmed}) async {
        // D-011 restore: close → swap files under the guard → the
        // whole app re-bootstraps onto the restored database. The
        // re-bootstrap is in a finally on purpose: a REFUSED or
        // failed restore (corrupt zip, guard, IO) must bring the app
        // back up on its untouched old database, never leave the
        // mounted widget tree bound to a closed one. The failure
        // itself still propagates to the caller for display.
        final dbPath = await AppDatabase.databaseFilePath();
        await AppDatabase.close();
        try {
          await backup.restoreBackup(
            zip: zip,
            dbPath: dbPath,
            libraryRoot: libraryRoot,
            replaceConfirmed: replaceConfirmed,
          );
          // S7 review S2: a restored database carries the SOURCE
          // device's sync identity and bookkeeping — reset it
          // before the app reopens on the file, so this device
          // doesn't impersonate the source. Best-effort on purpose:
          // the restore itself (the safety-critical part, D-011)
          // has already succeeded; a failure here leaves the prior
          // behaviour, never a half-restored app.
          try {
            final restored = await AppDatabase.openFile(dbPath);
            await SyncStore(restored).adoptRestoredDatabase();
            await restored.close();
          } catch (_) {
            // Bookkeeping reset failed; the restored data is intact.
          }
        } finally {
          await bootstrap();
        }
      },
    ),
  );
}

/// The persisted theme choice (D-036): `app_settings.theme_mode`
/// ('dark' | 'light'), defaulting to dark — a read failure must
/// never stop the app booting.
Future<AppThemeChoice> _themeChoice(Database db) async {
  try {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [themeModeSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) return AppThemeChoice.dark;
    return AppThemeChoice.fromStored(rows.first['value'] as String?);
  } catch (_) {
    return AppThemeChoice.dark;
  }
}

/// The Library root: `app_settings.library_root` when the owner
/// set one (a plain path — laptop-style, §R6.4), otherwise
/// `<app documents>/Library`. All DB references stay relative to
/// it, so moving the folder never breaks a source.
Future<Directory> _libraryRoot(Database db, Directory docsDir) async {
  try {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['library_root'],
      limit: 1,
    );
    final override = rows.isEmpty ? null : rows.first['value'] as String;
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override.trim());
    }
  } catch (_) {
    // app_settings exists since v2; a failure here must not stop
    // the app booting — fall through to the default root.
  }
  return Directory(p.join(docsDir.path, 'Library'));
}

class DailyLifeApp extends StatefulWidget {
  const DailyLifeApp({
    super.key,
    required this.db,
    required this.store,
    required this.todayStore,
    required this.goalsStore,
    required this.reviewStore,
    required this.learn,
    required this.thumbnails,
    required this.backup,
    required this.onRestoreBackup,
    this.shareService,
    this.externalBackup,
    this.progressStore,
    this.reminders,
    this.reminderRouter,
    this.initialThemeChoice = AppThemeChoice.dark,
  });

  /// NEO (D-036): the theme choice read from app_settings at
  /// bootstrap; the Settings switch updates + persists it.
  final AppThemeChoice initialThemeChoice;

  final Database db;
  final Store store;
  final TodayStore todayStore;
  final GoalsStore goalsStore;
  final ReviewStore reviewStore;
  final LearnServices learn;
  final ThumbnailService thumbnails;
  final BackupStore backup;

  /// PROGRESS (S6): optional so tests can mount the app without
  /// wiring it — the shell derives one from [db] when absent.
  final ProgressStore? progressStore;

  /// SET (S6): reminder controller + tap router (bootstrap wires
  /// the plugin gateway; tests fall back to a no-op gateway).
  final ReminderController? reminders;
  final ReminderTapRouter? reminderRouter;

  /// Share-intent boundary; null in tests (no platform plugin).
  final ShareIntentService? shareService;

  /// D-043 (P0): external backup store; null off Android (and in
  /// tests that do not wire it) — the section is then omitted.
  final ExternalBackupStore? externalBackup;

  /// Runs a guarded backup restore and restarts the app on the
  /// restored data (wired in bootstrap()).
  final Future<void> Function(File zip, {required bool replaceConfirmed})
  onRestoreBackup;

  @override
  State<DailyLifeApp> createState() => _DailyLifeAppState();
}

class _DailyLifeAppState extends State<DailyLifeApp> {
  late AppThemeChoice _themeChoice = widget.initialThemeChoice;

  /// NEO (D-036): switch the Neo theme and persist the choice in
  /// app_settings (same store as library_root). Persistence is
  /// best-effort — a failed write must not break the switch for
  /// this session.
  Future<void> _setThemeChoice(AppThemeChoice choice) async {
    setState(() => _themeChoice = choice);
    try {
      await widget.db.insert('app_settings', {
        'key': themeModeSettingKey,
        'value': choice.stored,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Session-only switch; the next boot falls back to the
      // last persisted (or default dark) choice.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nimo',
      // NEO (D-036): both Neo themes ship; dark is the default.
      theme: AppTheme.neoLight(),
      darkTheme: AppTheme.neoDark(),
      themeMode: _themeChoice.themeMode,
      home: AppShell(
        db: widget.db,
        store: widget.store,
        todayStore: widget.todayStore,
        goalsStore: widget.goalsStore,
        reviewStore: widget.reviewStore,
        progressStore: widget.progressStore,
        reminders: widget.reminders,
        reminderRouter: widget.reminderRouter,
        learn: widget.learn,
        thumbnails: widget.thumbnails,
        backup: widget.backup,
        shareService: widget.shareService,
        externalBackup: widget.externalBackup,
        onRestoreBackup: widget.onRestoreBackup,
        themeChoice: _themeChoice,
        onThemeChanged: _setThemeChoice,
      ),
    );
  }
}

/// One bottom-navigation destination, keyed by a stable [id].
/// Bodies switch on the ID, never on positional meaning, so
/// inserting a destination cannot silently rewire a tab.
class _Destination {
  const _Destination(this.id, this.label, this.icon, this.selectedIcon);

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Bottom-navigation shell. D-021: the final destination order is
/// Today · Learn · Progress · Spaces · Goals — S6 inserted
/// 'progress' at index 2, completing the layout with no
/// restructure (bodies switch on destination ID).
/// Switching tabs rebuilds the tab body, so each screen reloads its
/// data when it becomes visible (the S1 FutureBuilder pattern).
/// The shell also owns share-intent handling: cold-start shares
/// are checked once after the first frame, warm shares arrive on
/// a stream; each becomes the one-field confirm sheet (§R9.5).
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.db,
    required this.store,
    required this.todayStore,
    required this.goalsStore,
    required this.reviewStore,
    required this.learn,
    required this.thumbnails,
    required this.backup,
    required this.onRestoreBackup,
    this.shareService,
    this.externalBackup,
    this.progressStore,
    this.reminders,
    this.reminderRouter,
    this.themeChoice,
    this.onThemeChanged,
  });

  final Database db;
  final Store store;
  final TodayStore todayStore;
  final GoalsStore goalsStore;
  final ReviewStore reviewStore;
  final LearnServices learn;
  final ThumbnailService thumbnails;
  final BackupStore backup;
  final ShareIntentService? shareService;

  /// D-043 (P0): forwarded from the app widget; see there.
  final ExternalBackupStore? externalBackup;
  final ProgressStore? progressStore;
  final ReminderController? reminders;
  final ReminderTapRouter? reminderRouter;

  /// NEO (D-036): theme switch wiring for Settings (optional so
  /// tests can mount the shell without it).
  final AppThemeChoice? themeChoice;
  final ValueChanged<AppThemeChoice>? onThemeChanged;
  final Future<void> Function(File zip, {required bool replaceConfirmed})
  onRestoreBackup;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<_Destination> _destinations = [
    _Destination('today', 'Today', Icons.today_outlined, Icons.today),
    _Destination('learn', 'Learn', Icons.school_outlined, Icons.school),
    _Destination('progress', 'Progress', Icons.route_outlined, Icons.route),
    _Destination('spaces', 'Spaces', Icons.folder_outlined, Icons.folder),
    _Destination('goals', 'Goals', Icons.flag_outlined, Icons.flag),
  ];

  String _destId = 'today';

  /// Effective PROGRESS store: the wired one, or a plain wrapper
  /// over the same db (stores are stateless) for tests.
  ProgressStore get _progress =>
      widget.progressStore ??
      ProgressStore(widget.db, widget.reviewStore, widget.todayStore);

  /// Effective SET reminder controller (no-op gateway fallback).
  ReminderController get _reminders =>
      widget.reminders ??
      ReminderController(widget.db, const NoopReminderGateway());

  int get _index => _destinations.indexWhere((d) => d.id == _destId);

  void _select(String id) => setState(() => _destId = id);

  StreamSubscription<SharedCapture>? _shareSub;
  final List<SharedCapture> _pendingShares = [];
  bool _sheetOpen = false;

  CaptureService get _capture =>
      CaptureService(widget.learn.store, widget.learn.imports);

  @override
  void initState() {
    super.initState();
    // SET (S6): notification taps route here — morning → Today,
    // evening → Today with Day Close opened on its target day.
    widget.reminderRouter?.register((payload) {
      if (!mounted) return;
      _select('today');
      if (payload == ReminderPayloads.eveningClose) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final target = await widget.reviewStore.closableDate();
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DayCloseScreen(
                todayStore: widget.todayStore,
                reviewStore: widget.reviewStore,
                date: target.date,
                isLate: target.isLate,
                learnStore: widget.learn.store,
              ),
            ),
          );
        });
      }
    });
    final shares = widget.shareService;
    if (shares != null) {
      _shareSub = shares.captures.listen(_enqueueShare);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final initial = await shares.initialCaptures();
        for (final capture in initial) {
          _enqueueShare(capture);
        }
        if (initial.isNotEmpty) await shares.markConsumed();
      });
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  void _enqueueShare(SharedCapture capture) {
    // The same intent can be delivered twice on some Android
    // cold-start routes (initial read + stream). An identical
    // capture already waiting is a duplicate — drop it.
    final duplicate = _pendingShares.any(
      (c) =>
          c.kind == capture.kind &&
          c.text == capture.text &&
          c.filePath == capture.filePath,
    );
    if (duplicate) return;
    _pendingShares.add(capture);
    _drainShares();
  }

  /// Show confirm sheets one at a time, in arrival order. A
  /// failing capture is reported and skipped — it must never kill
  /// the queue, jam the sheet flag, or claim a save that did not
  /// happen (§R9.5: capture must not lose things silently).
  Future<void> _drainShares() async {
    if (_sheetOpen || !mounted) return;
    _sheetOpen = true;
    try {
      while (_pendingShares.isNotEmpty && mounted) {
        final capture = _pendingShares.removeAt(0);
        String? title;
        try {
          title = await showShareConfirmSheet(context, capture);
        } catch (_) {
          title = null; // a broken sheet drops only this capture
        }
        if (!mounted) break;
        if (title == null) continue; // discarded by the owner
        var saved = true;
        try {
          await _capture.saveCapture(capture, title: title);
        } catch (e) {
          saved = false;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not save that share: $e')),
            );
          }
        }
        await widget.shareService?.markConsumed();
        if (!mounted) break;
        if (saved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved to your Inbox topics.')),
          );
          setState(() {}); // refresh the Hub (Inbox count)
        }
      }
    } finally {
      _sheetOpen = false;
    }
  }

  void _openWorkspace(Workspace ws) {
    _select('spaces');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectsScreen(
          store: widget.store,
          workspace: ws,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
        ),
      ),
    );
  }

  Widget _backupSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackupSection(
            onExport: () => widget.backup.exportBackup(
              db: widget.db,
              libraryRoot: widget.learn.library.root,
            ),
            onInspect: (zip) => widget.backup.inspectBackup(zip),
            onTargetHasData: () async => widget.backup
                .databaseHasUserData(await AppDatabase.databaseFilePath()),
            onRestore: widget.onRestoreBackup,
          ),
          // D-043 (P0): the uninstall-surviving copy, Android only.
          if (widget.externalBackup != null) ...[
            const SizedBox(height: Gap.lg),
            ExternalBackupSection(
              store: widget.externalBackup!,
              libraryRoot: widget.learn.library.root,
              onInspect: (zip) => widget.backup.inspectBackup(zip),
              onTargetHasData: () async => widget.backup
                  .databaseHasUserData(
                      await AppDatabase.databaseFilePath()),
              onRestore: widget.onRestoreBackup,
            ),
          ],
        ],
      );

  void _openTopics() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TopicsScreen(
              store: widget.store,
              learn: widget.learn,
              backupSection: _backupSection(),
            ),
          ),
        )
        .then((_) {
          if (mounted) setState(() {}); // Inbox count may have changed
        });
  }

  /// SYNC (S7): the Stage A sync section for Settings — its
  /// Repair path reuses the same D-011-guarded restore wiring as
  /// the Backup section.
  SyncSection _syncSection() => SyncSection(
    store: SyncStore(widget.db),
    libraryRoot: widget.learn.library.root,
    onSetLibraryRoot: (path) async {
      await widget.db.insert('app_settings', {
        'key': 'library_root',
        'value': path,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    },
    onResetLibraryRoot: () async {
      await widget.db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['library_root'],
      );
    },
    onInspectBackup: (zip) => widget.backup.inspectBackup(zip),
    onTargetHasData: () async =>
        widget.backup.databaseHasUserData(await AppDatabase.databaseFilePath()),
    onRestoreBackup: widget.onRestoreBackup,
  );

  /// SET (S6): the Settings surface — reminders + backup.
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          reminders: _reminders,
          backupSection: _backupSection(),
          syncSection: _syncSection(),
          themeChoice: widget.themeChoice,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  /// PROGRESS (S6): the full weekly summary for [monday].
  void _openWeeklySummary(DateTime monday) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WeeklySummaryScreen(store: _progress, monday: monday),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_destId) {
        'learn' => LearnScreen(
          learn: widget.learn,
          reviewStore: widget.reviewStore,
          store: widget.store,
          onOpenTopics: _openTopics,
        ),
        'progress' => ProgressScreen(
          progressStore: _progress,
          todayStore: widget.todayStore,
          reviewStore: widget.reviewStore,
        ),
        'spaces' => WorkspacesScreen(
          store: widget.store,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
        ),
        'goals' => GoalsScreen(goalsStore: widget.goalsStore),
        _ => TodayScreen(
          store: widget.store,
          todayStore: widget.todayStore,
          goalsStore: widget.goalsStore,
          reviewStore: widget.reviewStore,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
          onOpenTopics: _openTopics,
          onOpenWorkspace: _openWorkspace,
          onOpenLearn: () => _select('learn'),
          progressStore: _progress,
          onOpenSettings: _openSettings,
          onOpenWeeklySummary: _openWeeklySummary,
          onOpenProgress: () => _select('progress'),
        ),
      },
      bottomNavigationBar: Container(
        // D-039: the shell's one hairline — the concept's ruled
        // nav edge.
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => _select(_destinations[i].id),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
        ),
      ),
    );
  }
}

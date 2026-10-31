/// SET — backup export/import (S4; format §R6.5, extends D-005).
///
/// One `.zip`: `backup.json` (manifest), `database.sqlite`
/// produced via `VACUUM INTO` (a consistent snapshot — never a
/// raw copy of the live files), and `library/…` (the §R6.4 tree,
/// minus the backups folder itself).
///
/// D-043 (P0): the manifest carries an OPTIONAL `db_sha256` —
/// the SHA-256 of the snapshot file — verified at inspect time
/// when present. Optional on purpose: backups written before
/// D-043 have no digest and still inspect/restore (the staged
/// snapshot's integrity_check remains the floor); readers older
/// than D-043 ignore the unknown key, so format_version stays 1.
///
/// **Restore guard (D-011, implemented here in S4):**
/// 1. An automatic pre-restore backup of the current state is
///    ALWAYS taken before anything is replaced.
/// 2. Restoring over a non-empty database requires the caller to
///    pass `replaceConfirmed: true` — the UI obtains it from an
///    explicit "this replaces everything on this device"
///    confirmation. Without it, restore refuses BEFORE touching
///    anything. Restoring into an empty database is the fast path.
///
/// Restore mechanics: manifest verified → zip entries checked
/// for path traversal → snapshot staged and integrity-checked →
/// DB files swapped → Library content rewritten file-by-file
/// through the Library's temp-then-rename rule.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import '../learn/library_store.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when a restore would overwrite a non-empty database
/// without the D-011 confirmation. Nothing has been touched.
class RestoreConfirmationRequired extends BackupException {
  RestoreConfirmationRequired()
      : super('Restoring over existing data needs the '
            '"replaces everything on this device" confirmation.');
}

class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.exportedAt,
    required this.deviceId,
    this.dbSha256,
  });

  final int formatVersion;
  final int schemaVersion;
  final int exportedAt;
  final String deviceId;

  /// SHA-256 (hex) of the `database.sqlite` snapshot file, or
  /// null for backups written before D-043.
  final String? dbSha256;

  Map<String, Object?> toJson() => {
        'kind': 'nimo-backup',
        'format_version': formatVersion,
        'schema_version': schemaVersion,
        'exported_at': exportedAt,
        'device_id': deviceId,
        if (dbSha256 != null) 'db_sha256': dbSha256,
      };

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    if (json['kind'] != 'nimo-backup') {
      throw BackupException('That file is not a Nimo backup.');
    }
    return BackupManifest(
      formatVersion: json['format_version']! as int,
      schemaVersion: json['schema_version']! as int,
      exportedAt: json['exported_at']! as int,
      deviceId: json['device_id']! as String,
      dbSha256: json['db_sha256'] as String?,
    );
  }
}

class RestoreReport {
  const RestoreReport({
    required this.preRestoreBackupPath,
    required this.restoredSchemaVersion,
  });

  /// Where the automatic pre-restore backup landed (null only
  /// when there was no database file at all to preserve).
  final String? preRestoreBackupPath;
  final int restoredSchemaVersion;
}

class BackupStore {
  static const int formatVersion = 1;

  /// Tables whose contents make a database "non-empty" for the
  /// D-011 guard. (Derived/device-local tables don't count.)
  static const List<String> _contentTables = [
    'workspaces',
    'projects',
    'items',
    'topics',
    'day_reviews',
    'goals',
    'plan_templates',
    // Root of the plan chain: a plan-only user (one-off tasks, no
    // templates, no Day Close) still has data worth protecting.
    'day_plans',
  ];

  /// Zip-bomb / runaway-size defences for restore: the zip itself,
  /// any single entry's declared uncompressed size, and the total.
  static const int maxZipBytes = 1073741824; // 1 GiB
  static const int maxEntryBytes = 536870912; // 512 MiB
  static const int maxTotalEntryBytes = 2147483648; // 2 GiB

  /// Library subfolders NEVER cleared on restore: `backups/`
  /// (wiping it would destroy the pre-restore backup we just
  /// took) and `.nimo/` (device-local library identity).
  ///
  /// D-043: the cleared set is DERIVED — every content subfolder
  /// the app knows ([LibraryStore.subdirs]) plus every top-level
  /// folder the backup itself carries — instead of the previous
  /// hand-maintained list. The old list silently broke the day a
  /// new content folder was added: its files would be exported
  /// but never restored (the 2026-11-01 audit's latent trap).
  static const Set<String> _neverClearedSubdirs = {'backups', '.nimo'};

  // ------------------------------------------------------------ export

  /// Export the current database (via [db], an open connection)
  /// and Library tree into `Library/backups/`. The zip itself is
  /// written temp-then-rename (red-team #8 applies to it too).
  Future<File> exportBackup({
    required Database db,
    required Directory libraryRoot,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final library = LibraryStore(libraryRoot);
    await library.ensureLayout();

    final staging =
        await Directory.systemTemp.createTemp('nimo-backup-');
    try {
      final snapshotPath = p.join(staging.path, 'database.sqlite');
      // VACUUM INTO writes a consistent snapshot of the live DB.
      await db.execute(
          "VACUUM INTO '${snapshotPath.replaceAll("'", "''")}'");
      final manifest = BackupManifest(
        formatVersion: formatVersion,
        schemaVersion: AppDatabase.schemaVersion,
        exportedAt: stamp.millisecondsSinceEpoch,
        deviceId: await _deviceId(db),
        // D-043: digest of the snapshot exactly as it will be
        // zipped, so a damaged or tampered copy is caught at
        // inspect time — before any restore begins.
        dbSha256:
            sha256.convert(await File(snapshotPath).readAsBytes()).toString(),
      );
      final manifestFile = File(p.join(staging.path, 'backup.json'));
      await manifestFile
          .writeAsString(jsonEncode(manifest.toJson()), flush: true);

      final name = 'nimo-backup-${_fileStamp(stamp)}.zip';
      final tmpZip = File(p.join(
          libraryRoot.path, 'backups', '$name.tmp-${stamp.microsecondsSinceEpoch % 100000}'));
      final encoder = ZipFileEncoder();
      encoder.create(tmpZip.path);
      try {
        await encoder.addFile(manifestFile, 'backup.json');
        await encoder.addFile(File(snapshotPath), 'database.sqlite');
        if (await libraryRoot.exists()) {
          await for (final entity
              in libraryRoot.list(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final rel = p.relative(entity.path, from: libraryRoot.path);
            if (rel.startsWith('backups${p.separator}')) continue;
            await encoder.addFile(
                entity, 'library/${rel.split(p.separator).join('/')}');
          }
        }
      } finally {
        await encoder.close();
      }
      final target = File(p.join(libraryRoot.path, 'backups', name));
      if (await target.exists()) await target.delete();
      return await tmpZip.rename(target.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  // ------------------------------------------------------------ inspect

  /// Read + validate a backup zip's manifest (also validates that
  /// no entry path escapes). Throws [BackupException] on anything
  /// unusable, including a backup from a NEWER app version.
  Future<BackupManifest> inspectBackup(File zip) async {
    final archive = await _decode(zip);
    final manifestFile = archive.findFile('backup.json');
    if (manifestFile == null) {
      throw BackupException('Backup is missing its manifest.');
    }
    final BackupManifest manifest;
    try {
      // Entry content decompresses lazily — a corrupt entry
      // throws here, not inside _decode.
      manifest = BackupManifest.fromJson(
          (jsonDecode(utf8.decode(manifestFile.content)) as Map)
              .cast<String, Object?>());
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException('Backup manifest is unreadable.');
    }
    if (manifest.formatVersion > formatVersion) {
      throw BackupException(
          'This backup uses a newer backup format '
          '(format ${manifest.formatVersion}, this app understands '
          '$formatVersion). Update the app first.');
    }
    if (manifest.schemaVersion > AppDatabase.schemaVersion) {
      throw BackupException(
          'This backup was made by a newer version of the app '
          '(data format ${manifest.schemaVersion}, this app '
          'understands ${AppDatabase.schemaVersion}). Update the '
          'app first.');
    }
    final snapshot = archive.findFile('database.sqlite');
    if (snapshot == null) {
      throw BackupException('Backup is missing its database.');
    }
    // D-043: when the manifest carries a digest, the snapshot
    // must match it. Content decompresses lazily — a corrupt
    // entry throws here and is reported as an integrity failure.
    if (manifest.dbSha256 != null) {
      final String actual;
      try {
        actual = sha256.convert(snapshot.content).toString();
      } catch (_) {
        throw BackupException(
            'Backup failed its integrity check (unreadable '
            'database).');
      }
      if (actual != manifest.dbSha256) {
        throw BackupException(
            'Backup failed its integrity check — the database '
            'does not match the manifest digest. The file may '
            'be damaged; try another backup.');
      }
    }
    return manifest;
  }

  /// True when the database file at [dbPath] holds any user
  /// content. A missing file is empty; an unreadable/foreign file
  /// counts as NON-empty (never silently replace the unknown).
  Future<bool> databaseHasUserData(String dbPath) async {
    if (!await File(dbPath).exists()) return false;
    Database? db;
    try {
      db = await databaseFactory.openDatabase(dbPath,
          options: OpenDatabaseOptions(readOnly: true));
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      final present = tables.map((r) => r['name'] as String).toSet();
      for (final table in _contentTables) {
        if (!present.contains(table)) continue;
        final rows =
            await db.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
        if ((rows.single['c'] as int) > 0) return true;
      }
      return false;
    } catch (_) {
      return true;
    } finally {
      await db?.close();
    }
  }

  // ------------------------------------------------------------ restore

  /// Restore [zip] over the database file at [dbPath] and the
  /// Library at [libraryRoot], under the D-011 guard. The caller
  /// must have CLOSED any open connection to [dbPath] first (the
  /// app does this via AppDatabase.close(), then reopens after).
  Future<RestoreReport> restoreBackup({
    required File zip,
    required String dbPath,
    required Directory libraryRoot,
    required bool replaceConfirmed,
    DateTime? now,
  }) async {
    final manifest = await inspectBackup(zip);
    final archive = await _decode(zip);

    // Guard 2 (checked BEFORE anything is written anywhere).
    final hasData = await databaseHasUserData(dbPath);
    if (hasData && !replaceConfirmed) {
      throw RestoreConfirmationRequired();
    }

    final library = LibraryStore(libraryRoot);
    await library.ensureLayout();

    // Guard 1: automatic pre-restore backup, always (when there
    // is a database file to preserve).
    String? preRestorePath;
    if (await File(dbPath).exists()) {
      final conn = await databaseFactory.openDatabase(dbPath);
      try {
        final pre = await exportBackup(
            db: conn, libraryRoot: libraryRoot, now: now);
        preRestorePath = pre.path;
      } finally {
        await conn.close();
      }
    }

    // Stage the snapshot and prove it is a sound database before
    // it goes anywhere near the live path.
    final staging =
        await Directory.systemTemp.createTemp('nimo-restore-');
    try {
      final stagedDb = File(p.join(staging.path, 'database.sqlite'));
      await stagedDb.writeAsBytes(
          archive.findFile('database.sqlite')!.content,
          flush: true);
      await _verifySnapshot(stagedDb.path);

      // Prove every library entry decompresses BEFORE the swap,
      // so a corrupt entry cannot strand a half-restored library.
      try {
        for (final entry in archive.files) {
          if (entry.isFile && entry.name.startsWith('library/')) {
            entry.content.length; // force the inflate
          }
        }
      } catch (_) {
        throw BackupException(
            'Backup contains an unreadable file entry.');
      }

      // Swap the database files (same directory = same volume, so
      // rename is atomic). The caller has closed the database and
      // the pre-restore export above opened/closed it (which
      // checkpoints the WAL), so the old WAL/SHM sidecars are
      // deleted WITH the swap — never left beside the new file.
      //
      // The old database file is kept until the Library rewrite
      // has also succeeded: any failure from here on rolls the
      // database back to the pre-restore file and rethrows. (The
      // Library itself may be partially rewritten at that point;
      // the pre-restore zip in Library/backups/ is the full
      // recovery, and the failure is reported, never hidden.)
      final live = File(dbPath);
      final old = File('$dbPath.pre-restore-old');
      if (await old.exists()) await old.delete();
      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      final hadLive = await live.exists();
      var renamed = false;
      var copied = false;
      try {
        if (hadLive) {
          await live.rename(old.path);
          renamed = true;
        }
        await stagedDb.copy(live.path);
        copied = true;

        // Rewrite the Library content: clear the derived set of
        // content subdirs (see _neverClearedSubdirs), then write
        // each backup entry through temp-then-rename.
        final clearDirs = <String>{
          ...LibraryStore.subdirs,
          for (final entry in archive.files)
            if (entry.name.startsWith('library/'))
              entry.name.substring('library/'.length).split('/').first,
        }..removeAll(_neverClearedSubdirs);
        for (final sub in clearDirs) {
          if (sub.isEmpty) continue;
          final dir = Directory(p.join(libraryRoot.path, sub));
          if (await dir.exists()) {
            await for (final entity in dir.list()) {
              await entity.delete(recursive: true);
            }
          }
        }
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          final name = entry.name;
          if (!name.startsWith('library/')) continue;
          final rel = name.substring('library/'.length);
          if (rel.isEmpty || rel.startsWith('backups/')) continue;
          await library.writeAtomic(rel, entry.content);
        }
      } catch (_) {
        if (renamed) {
          if (await live.exists()) await live.delete();
          if (await old.exists()) await old.rename(live.path);
        } else if (copied) {
          // No old database existed; drop the restored copy so a
          // failed fresh restore leaves no half-state behind.
          if (await live.exists()) await live.delete();
        }
        rethrow;
      }
      if (await old.exists()) await old.delete();
    } finally {
      await staging.delete(recursive: true);
    }

    return RestoreReport(
      preRestoreBackupPath: preRestorePath,
      restoredSchemaVersion: manifest.schemaVersion,
    );
  }

  // ------------------------------------------------------------ internals

  Future<Archive> _decode(File zip) async {
    if (!await zip.exists()) {
      throw BackupException('Backup file not found.');
    }
    if (await zip.length() > maxZipBytes) {
      throw BackupException('Backup file is unreasonably large.');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    } catch (_) {
      throw BackupException('That file is not a readable backup zip.');
    }
    var totalEntryBytes = 0;
    for (final entry in archive.files) {
      _checkEntryName(entry.name);
      if (entry.isFile) {
        totalEntryBytes += entry.size;
        if (entry.size > maxEntryBytes ||
            totalEntryBytes > maxTotalEntryBytes) {
          throw BackupException(
              'Backup contents are unreasonably large.');
        }
      }
    }
    return archive;
  }

  /// Zip-slip defence: no absolute paths, no `..` segments, no
  /// backslash tricks — in ANY entry, even ones we would ignore.
  static void _checkEntryName(String name) {
    final bad = name.startsWith('/') ||
        name.contains('\\') ||
        name.split('/').any((seg) => seg == '..' || seg == '.');
    if (bad) {
      throw BackupException('Backup contains an unsafe path: $name');
    }
  }

  Future<void> _verifySnapshot(String path) async {
    Database? db;
    try {
      db = await databaseFactory.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true));
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first['integrity_check'] != 'ok') {
        throw BackupException('The backup database is damaged.');
      }
      final version = await db.rawQuery('PRAGMA user_version');
      final v = version.first['user_version'] as int;
      if (v > AppDatabase.schemaVersion) {
        throw BackupException(
            'This backup was made by a newer version of the app.');
      }
      // integrity_check does not catch dangling references.
      final fk = await db.rawQuery('PRAGMA foreign_key_check');
      if (fk.isNotEmpty) {
        throw BackupException(
            'The backup database has broken references.');
      }
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException('The backup database is damaged.');
    } finally {
      await db?.close();
    }
  }

  Future<String> _deviceId(Database db) async {
    try {
      return await AppDatabase.deviceId(db);
    } catch (_) {
      return 'unknown';
    }
  }

  static String _fileStamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}

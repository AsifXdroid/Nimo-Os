/// SET — external backup (D-043, P0): a second destination for
/// the existing backup zip, in user-accessible storage that
/// survives uninstall.
///
/// The zip itself is unchanged (BackupStore produces it, D-011
/// guards restore it). What this layer adds:
///
/// - a folder the user grants once through Android's Storage
///   Access Framework (the system picker — copy in the UI guides
///   them to Documents/Nimo/Backups). The grant is revoked by
///   Android on uninstall; the FILES survive, and a fresh
///   install simply asks for the same folder again.
/// - a write path that can never damage the last known-good
///   backup: the native side streams into a `.partial` document,
///   verifies the size, and only then renames it to the final
///   name. Nothing is ever opened for overwriting, and P0
///   deletes nothing in the folder, ever.
/// - restore sourcing: copy the chosen backup out to a temp
///   file, then hand it to the exact inspect → confirm →
///   restore flow the internal backup already uses.
///
/// The platform side is an in-house channel (D-034 precedent)
/// behind [SafBackupChannel], so the whole lifecycle is
/// testable with a fake. Android-only; on desktop the Library
/// already lives in user-controlled storage.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'backup_store.dart';

class ExternalBackupException implements Exception {
  ExternalBackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One file in the granted backup folder, as reported by SAF.
class ExternalBackupEntry {
  const ExternalBackupEntry({
    required this.documentId,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.isDirectory,
  });

  final String documentId;
  final String name;

  /// -1 when the provider does not report a size.
  final int sizeBytes;

  /// Epoch millis; 0 when the provider does not report it.
  final int modifiedAt;
  final bool isDirectory;

  /// A finished Nimo backup (partials and unrelated files the
  /// user keeps in the same folder are not backups).
  bool get isBackupFile =>
      !isDirectory &&
      name.startsWith('nimo-backup-') &&
      name.endsWith('.zip');
}

/// The SAF operations the native side provides. Faked in tests.
abstract class SafBackupChannel {
  /// Open the system tree picker. Returns the granted folder,
  /// or null when the user cancelled.
  Future<({String treeUri, String label})?> pickFolder();

  /// Whether the persisted grant for [treeUri] is still held.
  Future<bool> folderAccess(String treeUri);

  /// Every child of the granted folder (files and directories).
  Future<List<ExternalBackupEntry>> listBackups(String treeUri);

  /// Stream [sourcePath] into the folder as a new backup named
  /// [fileName] (written as `.partial`, verified, renamed).
  /// [fileName] must not already exist in the folder.
  Future<({String name, int sizeBytes})> writeBackup({
    required String treeUri,
    required String sourcePath,
    required String fileName,
  });

  /// Stream the document [documentId] out to [destPath];
  /// returns the number of bytes written.
  Future<int> copyBackupOut({
    required String treeUri,
    required String documentId,
    required String destPath,
  });
}

class MethodChannelSafBackup implements SafBackupChannel {
  static const MethodChannel _channel =
      MethodChannel('app.dailylife/saf_backup');

  ExternalBackupException _wrap(PlatformException e) =>
      ExternalBackupException(e.message ??
          'The storage operation failed. Please try again.');

  @override
  Future<({String treeUri, String label})?> pickFolder() async {
    try {
      final res = await _channel
          .invokeMapMethod<String, Object?>('pickFolder');
      if (res == null) return null;
      return (
        treeUri: res['treeUri']! as String,
        label: res['label']! as String,
      );
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<bool> folderAccess(String treeUri) async {
    try {
      return await _channel.invokeMethod<bool>(
            'folderAccess',
            {'treeUri': treeUri},
          ) ??
          false;
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<ExternalBackupEntry>> listBackups(String treeUri) async {
    try {
      final res = await _channel.invokeListMethod<Object?>(
            'listBackups',
            {'treeUri': treeUri},
          ) ??
          const [];
      return [
        for (final raw in res)
          if (raw is Map)
            ExternalBackupEntry(
              documentId: raw['documentId'] as String? ?? '',
              name: raw['name'] as String? ?? '',
              sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? -1,
              modifiedAt: (raw['modifiedAt'] as num?)?.toInt() ?? 0,
              isDirectory: raw['isDirectory'] as bool? ?? false,
            ),
      ];
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<({String name, int sizeBytes})> writeBackup({
    required String treeUri,
    required String sourcePath,
    required String fileName,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, Object?>(
        'writeBackup',
        {
          'treeUri': treeUri,
          'sourcePath': sourcePath,
          'fileName': fileName,
        },
      );
      if (res == null) {
        throw ExternalBackupException('The backup write failed.');
      }
      return (
        name: res['name']! as String,
        sizeBytes: (res['sizeBytes'] as num).toInt(),
      );
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<int> copyBackupOut({
    required String treeUri,
    required String documentId,
    required String destPath,
  }) async {
    try {
      return await _channel.invokeMethod<int>(
            'copyBackupOut',
            {
              'treeUri': treeUri,
              'documentId': documentId,
              'destPath': destPath,
            },
          ) ??
          0;
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }
}

/// The external-backup lifecycle on top of [BackupStore] and a
/// [SafBackupChannel]. Folder choice and last-backup facts live
/// in the existing `app_settings` KV (no schema change).
class ExternalBackupStore {
  ExternalBackupStore(this._db, this._backup, this._channel);

  final Database _db;
  final BackupStore _backup;
  final SafBackupChannel _channel;

  static const String _kTreeUri = 'saf_backup.tree_uri';
  static const String _kFolderLabel = 'saf_backup.folder_label';
  static const String _kLastAt = 'saf_backup.last_at';
  static const String _kLastName = 'saf_backup.last_name';

  Future<String?> _get(String key) async {
    final rows = await _db.query('app_settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _set(String key, String value) async {
    await _db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The granted folder, if one was ever chosen on this install.
  Future<({String treeUri, String label})?> folder() async {
    final uri = await _get(_kTreeUri);
    if (uri == null) return null;
    return (treeUri: uri, label: await _get(_kFolderLabel) ?? 'Folder');
  }

  /// Whether Android still honours the grant (false after an
  /// uninstall/reinstall until the folder is picked again).
  Future<bool> hasAccess() async {
    final f = await folder();
    if (f == null) return false;
    return _channel.folderAccess(f.treeUri);
  }

  /// Ask the user for the folder. False = they cancelled.
  Future<bool> chooseFolder() async {
    final picked = await _channel.pickFolder();
    if (picked == null) return false;
    await _set(_kTreeUri, picked.treeUri);
    await _set(_kFolderLabel, picked.label);
    return true;
  }

  /// When the last successful external backup completed.
  Future<DateTime?> lastBackupAt() async {
    final v = await _get(_kLastAt);
    final millis = v == null ? null : int.tryParse(v);
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<String?> lastBackupName() => _get(_kLastName);

  /// Produce a fresh backup zip (the existing internal export)
  /// and copy it into the granted folder under a name that is
  /// guaranteed free, so the write can never land on top of an
  /// existing backup. Records the success in settings. Throws
  /// [ExternalBackupException] with a plain-language reason on
  /// any failure; previous external backups are never touched.
  Future<ExternalBackupEntry> backUpNow({
    required Directory libraryRoot,
    DateTime? now,
  }) async {
    final f = await folder();
    if (f == null) {
      throw ExternalBackupException(
          'Choose the backup folder first.');
    }
    if (!await _channel.folderAccess(f.treeUri)) {
      throw ExternalBackupException(
          'Nimo no longer has access to the backup folder. '
          'Choose it again to renew access.');
    }
    final file = await _backup.exportBackup(
      db: _db,
      libraryRoot: libraryRoot,
      now: now,
    );
    final existing = await _channel.listBackups(f.treeUri);
    final taken = {for (final e in existing) e.name};
    var name = p.basename(file.path);
    if (taken.contains(name)) {
      // Two backups in the same second: -2, -3, … before .zip.
      final stem = name.substring(0, name.length - '.zip'.length);
      var n = 2;
      while (taken.contains('$stem-$n.zip')) {
        n++;
      }
      name = '$stem-$n.zip';
    }
    final written = await _channel.writeBackup(
      treeUri: f.treeUri,
      sourcePath: file.path,
      fileName: name,
    );
    final localSize = await file.length();
    if (written.sizeBytes != localSize) {
      throw ExternalBackupException(
          'The backup copy in the folder is incomplete '
          '(${written.sizeBytes} of $localSize bytes). The '
          'previous backups are unchanged.');
    }
    final stamp = now ?? DateTime.now();
    await _set(_kLastAt, '${stamp.millisecondsSinceEpoch}');
    await _set(_kLastName, written.name);
    return ExternalBackupEntry(
      documentId: '',
      name: written.name,
      sizeBytes: written.sizeBytes,
      modifiedAt: stamp.millisecondsSinceEpoch,
      isDirectory: false,
    );
  }

  /// Finished backups in the folder, newest first. Partials
  /// (interrupted writes) and unrelated files are excluded.
  Future<List<ExternalBackupEntry>> listBackups() async {
    final f = await folder();
    if (f == null) return const [];
    final all = await _channel.listBackups(f.treeUri);
    final backups = all.where((e) => e.isBackupFile).toList()
      ..sort((a, b) => b.name.compareTo(a.name));
    return backups;
  }

  /// Copy [entry] out of the folder into a fresh temp file the
  /// existing restore flow can inspect and restore from.
  Future<File> fetchForRestore(ExternalBackupEntry entry) async {
    final f = await folder();
    if (f == null) {
      throw ExternalBackupException(
          'Choose the backup folder first.');
    }
    final dir = await Directory.systemTemp.createTemp('nimo-restore-');
    final dest = File(p.join(dir.path, entry.name));
    final copied = await _channel.copyBackupOut(
      treeUri: f.treeUri,
      documentId: entry.documentId,
      destPath: dest.path,
    );
    if (entry.sizeBytes >= 0 && copied != entry.sizeBytes) {
      throw ExternalBackupException(
          'That backup could not be read completely. Try '
          'another one.');
    }
    return dest;
  }
}

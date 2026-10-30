/// SET — Backup export/import UI (S4, D-005 + the D-011 guard).
///
/// All file/database work sits behind callbacks wired in main.dart
/// (export via the live connection; restore = close the DB, swap
/// the files, restart the app), so this widget is pure flow:
///
/// Export → one tap, reports where the zip landed.
/// Import → pick a zip → manifest shown → if the current database
/// has data, an explicit "this replaces everything on this
/// device" confirmation is REQUIRED before restore runs (the
/// store enforces the same precondition independently — D-011).
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'backup_store.dart';

class BackupSection extends StatefulWidget {
  const BackupSection({
    super.key,
    required this.onExport,
    required this.onInspect,
    required this.onTargetHasData,
    required this.onRestore,
  });

  /// Export now; returns the created backup file.
  final Future<File> Function() onExport;

  /// Validate + describe a picked backup file.
  final Future<BackupManifest> Function(File zip) onInspect;

  /// Whether the live database currently holds user data.
  final Future<bool> Function() onTargetHasData;

  /// Perform the restore (app closes/swaps/reopens around it).
  /// [replaceConfirmed] must mirror the D-011 confirmation state.
  final Future<void> Function(File zip, {required bool replaceConfirmed})
      onRestore;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;
  String? _status;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final file = await widget.onExport();
      if (!mounted) return;
      setState(() => _status = 'Backup saved:\n${file.path}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Nimo backup', extensions: ['zip']),
      ],
    );
    if (picked == null || !mounted) return;
    final zip = File(picked.path);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final manifest = await widget.onInspect(zip);
      if (!mounted) return;
      final hasData = await widget.onTargetHasData();
      if (!mounted) return;
      var confirmed = !hasData; // empty DB = the fast path (D-011)
      if (hasData) {
        confirmed = await _confirmReplace(manifest) ?? false;
      }
      if (!confirmed) {
        setState(() => _status = 'Import cancelled — nothing changed.');
        return;
      }
      // Pass the actual decision through. The store re-checks
      // whether the target has data at restore time, so data that
      // landed after the check above is still covered by the
      // owner's confirmation — or the restore refuses and can be
      // retried through the dialog.
      await widget.onRestore(zip, replaceConfirmed: confirmed);
      // On success the app restarts itself (new database), so this
      // widget may already be gone — guard everything below.
      if (!mounted) return;
      setState(() => _status = 'Backup restored.');
    } on BackupException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmReplace(BackupManifest manifest) {
    final when = DateTime.fromMillisecondsSinceEpoch(manifest.exportedAt);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything?'),
        content: Text(
          'This backup is from ${when.toLocal()}.\n\n'
          'Restoring it replaces everything on this device — all '
          'current data will be overwritten by the backup. A safety '
          'copy of your current data is taken automatically first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace everything'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Backup', style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.sm),
        Text(
          'One zip file: a database snapshot plus your Library. '
          'Stored in Library/backups — it travels with the folder.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Export backup'),
            ),
            const SizedBox(width: Gap.sm),
            OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import backup'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: Gap.md),
          const LinearProgressIndicator(),
        ],
        if (_status != null) ...[
          const SizedBox(height: Gap.md),
          Text(_status!, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

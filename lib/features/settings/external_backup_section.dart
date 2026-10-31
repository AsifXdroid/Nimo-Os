/// SET — External backup UI (D-043, P0): the SAF-backed second
/// destination for the backup zip, in a folder the user owns.
///
/// Flow mirrors [BackupSection]: folder choice and the copy
/// itself run through [ExternalBackupStore]; restore reuses the
/// app's existing inspect → D-011 confirmation → guarded
/// restore wiring, so an external restore is exactly as safe as
/// an internal one — it just starts from a file that survives
/// uninstall.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import 'backup_store.dart';
import 'external_backup.dart';

class ExternalBackupSection extends StatefulWidget {
  const ExternalBackupSection({
    super.key,
    required this.store,
    required this.libraryRoot,
    required this.onInspect,
    required this.onTargetHasData,
    required this.onRestore,
  });

  final ExternalBackupStore store;
  final Directory libraryRoot;

  /// Validate + describe a backup file (BackupStore.inspectBackup).
  final Future<BackupManifest> Function(File zip) onInspect;

  /// Whether the live database currently holds user data.
  final Future<bool> Function() onTargetHasData;

  /// Perform the restore (app closes/swaps/reopens around it).
  final Future<void> Function(File zip, {required bool replaceConfirmed})
      onRestore;

  @override
  State<ExternalBackupSection> createState() =>
      _ExternalBackupSectionState();
}

class _ExternalBackupSectionState extends State<ExternalBackupSection> {
  bool _busy = false;
  String? _status;
  String? _folderLabel;
  bool _hasAccess = false;
  DateTime? _lastAt;
  String? _lastName;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final folder = await widget.store.folder();
    final access = folder != null && await widget.store.hasAccess();
    final lastAt = await widget.store.lastBackupAt();
    final lastName = await widget.store.lastBackupName();
    if (!mounted) return;
    setState(() {
      _folderLabel = folder?.label;
      _hasAccess = access;
      _lastAt = lastAt;
      _lastName = lastName;
    });
  }

  Future<void> _chooseFolder() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final chosen = await widget.store.chooseFolder();
      if (!mounted) return;
      if (!chosen) {
        setState(() => _status = 'Folder choice cancelled.');
      }
      await _refresh();
    } on ExternalBackupException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Could not open the folder picker: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backUpNow() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final entry =
          await widget.store.backUpNow(libraryRoot: widget.libraryRoot);
      if (!mounted) return;
      setState(() => _status = 'External backup saved:\n${entry.name}');
      await _refresh();
    } on ExternalBackupException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.message);
    } on BackupException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'External backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final entries = await widget.store.listBackups();
      if (!mounted) return;
      if (entries.isEmpty) {
        setState(() => _status = 'No backups found in that folder.');
        return;
      }
      final picked = await showModalBottomSheet<ExternalBackupEntry>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Restore which backup?'),
                subtitle: Text(
                    'Restoring replaces the data on this device '
                    '(a safety copy is taken first).'),
              ),
              for (final e in entries)
                ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(e.name),
                  subtitle: Text(_entrySubtitle(e)),
                  onTap: () => Navigator.pop(context, e),
                ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      final zip = await widget.store.fetchForRestore(picked);
      if (!mounted) return;
      final manifest = await widget.onInspect(zip);
      if (!mounted) return;
      final hasData = await widget.onTargetHasData();
      if (!mounted) return;
      var confirmed = !hasData; // empty DB = the fast path (D-011)
      if (hasData) {
        confirmed = await _confirmReplace(manifest) ?? false;
      }
      if (!confirmed) {
        setState(() => _status = 'Restore cancelled — nothing changed.');
        return;
      }
      await widget.onRestore(zip, replaceConfirmed: confirmed);
      if (!mounted) return;
      setState(() => _status = 'Backup restored.');
    } on ExternalBackupException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.message);
    } on BackupException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Restore failed: $e');
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

  static String _entrySubtitle(ExternalBackupEntry e) {
    final parts = <String>[];
    if (e.modifiedAt > 0) {
      parts.add(_fmtDate(
          DateTime.fromMillisecondsSinceEpoch(e.modifiedAt)));
    }
    if (e.sizeBytes >= 0) parts.add(_fmtSize(e.sizeBytes));
    return parts.isEmpty ? 'Nimo backup' : parts.join(' · ');
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _fmtDate(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} ${t.year}, '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnStyle = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const NeoGlyph(icon: Icons.folder_outlined, size: 36),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text('Backup outside the app',
                  style: AppType.cardHeading(theme.textTheme)),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Text(
          'The same backup zip, copied into a folder you choose — '
          'for example a Nimo/Backups folder inside Documents. '
          'Unlike the copy inside the app, it survives uninstalling '
          'Nimo. After a reinstall, choose the same folder again '
          'to restore from it.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: Gap.md),
        if (_folderLabel == null) ...[
          Text(
            'No folder chosen yet. If Nimo is uninstalled, the '
            'backups stored inside the app are deleted with it.',
            style: warnStyle,
          ),
          const SizedBox(height: Gap.md),
          FilledButton.icon(
            onPressed: _busy ? null : _chooseFolder,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose backup folder'),
          ),
        ] else if (!_hasAccess) ...[
          Text(
            'Nimo no longer has access to “$_folderLabel” — this '
            'is expected after reinstalling. Choose the folder '
            'again to renew access; your backups in it are '
            'untouched.',
            style: warnStyle,
          ),
          const SizedBox(height: Gap.md),
          FilledButton.icon(
            onPressed: _busy ? null : _chooseFolder,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose backup folder again'),
          ),
        ] else ...[
          Text('Folder: $_folderLabel',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: Gap.sm),
          if (_lastAt != null)
            Text(
              'Last external backup: ${_fmtDate(_lastAt!)}'
              '${_lastName == null ? '' : ' ($_lastName)'}',
              style: theme.textTheme.bodyMedium,
            )
          else
            Text(
              'No external backup yet — if Nimo is uninstalled '
              'now, your data cannot be restored.',
              style: warnStyle,
            ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _backUpNow,
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Back Up Now'),
              ),
              const SizedBox(width: Gap.sm),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restore from folder'),
              ),
            ],
          ),
          TextButton(
            onPressed: _busy ? null : _chooseFolder,
            child: const Text('Change folder'),
          ),
        ],
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

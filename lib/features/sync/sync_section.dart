/// SYNC — Settings surface for Stage A sync (S7, §R7.2).
///
/// Plain status + explicit actions, per the spec: last export /
/// last import per device, **Sync now** (export, then check the
/// Library's sync folder for incoming packages), import a package
/// file by hand, the conflicts list as a first-class place, the
/// quarantine list (future-dated ops held back — red-team #7),
/// and Repair: a snapshot restore through the S4 machinery WITH
/// the D-011 guards (automatic pre-restore backup + explicit
/// replaces-everything confirmation over a non-empty database).
///
/// Library FILES (PDFs, media, packs) are not in data packages —
/// they travel with the folder itself via the owner's
/// Syncthing-Fork setup (docs/SYNC_SETUP.md).
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../learn/library_store.dart';
import '../settings/backup_store.dart';
import 'sync_store.dart';

class SyncSection extends StatefulWidget {
  const SyncSection({
    super.key,
    required this.store,
    required this.libraryRoot,
    required this.onInspectBackup,
    required this.onTargetHasData,
    required this.onRestoreBackup,
    this.onSetLibraryRoot,
    this.onResetLibraryRoot,
  });

  final SyncStore store;
  final Directory libraryRoot;

  /// Library location (S7): persist a new Library root
  /// (app_settings.library_root, read at boot — D-015). Without
  /// this the phone's Library stays in app-private storage that
  /// no folder-sync tool can reach, and Stage A cannot work.
  /// Takes effect on the next app launch.
  final Future<void> Function(String path)? onSetLibraryRoot;
  final Future<void> Function()? onResetLibraryRoot;

  /// Repair path (D-011): the same guarded restore the Backup
  /// section uses, wired by the shell (close → swap → restart).
  final Future<BackupManifest> Function(File zip) onInspectBackup;
  final Future<bool> Function() onTargetHasData;
  final Future<void> Function(File zip, {required bool replaceConfirmed})
  onRestoreBackup;

  @override
  State<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<SyncSection> {
  SyncStatus? _status;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Status is decorative: a query racing a database close
    // (backup restore re-bootstraps the whole app; tests close
    // their databases) must never surface as an error — keep the
    // last known state instead.
    final SyncStatus s;
    try {
      s = await widget.store.status();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _status = s);
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final msg = await action();
      if (!mounted) return;
      setState(() => _message = msg);
    } on SyncException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    } on BackupException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _syncNow() => _run(() async {
    final exported = await widget.store.exportPackage(
      libraryRoot: widget.libraryRoot,
    );
    final imported = await widget.store.importFromSyncFolder(
      libraryRoot: widget.libraryRoot,
    );
    final parts = <String>[
      exported.file == null
          ? 'No new changes to send.'
          : 'Package written: ${exported.file!.path.split('/').last} '
                '(${exported.opCount} changes).',
      imported.describe(),
    ];
    return parts.join('\n');
  });

  Future<void> _importPicked() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Nimo sync package', extensions: ['zip']),
      ],
    );
    if (picked == null || !mounted) return;
    await _run(() async {
      final report = await widget.store.importPackage(File(picked.path));
      return 'Import: ${report.describe()}';
    });
  }

  Future<void> _changeLibraryRoot() async {
    final picked = await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (picked == null || !mounted) return;
    // Probe writability BEFORE persisting (S7 review S7): on
    // Android a folder picked through the system picker may not
    // be writable by the app under scoped storage — persisting
    // an unwritable root would strand the Library on next
    // launch. The probe makes the failure immediate and visible
    // on any platform instead.
    try {
      final probe = LibraryStore(Directory(picked));
      await probe.ensureLayout();
      final probeFile = await probe.writeAtomic('sync/.probe', [1]);
      await probeFile.delete();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _message =
            'That folder cannot be written to by the app, so it '
            'cannot hold the Library. Pick a different folder.',
      );
      return;
    }
    await _run(() async {
      await widget.onSetLibraryRoot!(picked);
      return 'Library folder set to:\n$picked\n\n'
          'Restart the app to use it. If you already have sources '
          'in the old Library, copy its contents into the new '
          'folder first — the app picks files up from wherever '
          'the folder lives.';
    });
  }

  Future<void> _repair() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Nimo backup', extensions: ['zip']),
      ],
    );
    if (picked == null || !mounted) return;
    final zip = File(picked.path);
    await _run(() async {
      final manifest = await widget.onInspectBackup(zip);
      if (!mounted) return 'Cancelled.';
      final hasData = await widget.onTargetHasData();
      if (!mounted) return 'Cancelled.';
      var confirmed = !hasData; // empty DB = the fast path (D-011)
      if (hasData) {
        confirmed = await _confirmReplace(manifest) ?? false;
      }
      if (!confirmed) return 'Repair cancelled — nothing changed.';
      await widget.onRestoreBackup(zip, replaceConfirmed: confirmed);
      return 'Repaired from snapshot.';
    });
  }

  Future<bool?> _confirmReplace(BackupManifest manifest) {
    final when = DateTime.fromMillisecondsSinceEpoch(manifest.exportedAt);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repair replaces everything?'),
        content: Text(
          'This snapshot is from ${when.toLocal()}.\n\n'
          'Repair restores it over this device — all current data '
          'here is replaced. A safety copy of your current data is '
          'taken automatically first (and kept in Library/backups).\n\n'
          'Tip: if the other device has newer changes, Sync now '
          'first — repair cannot bring back anything the snapshot '
          'does not contain. After a repair, this device gets a '
          'fresh sync identity and re-publishes its state on the '
          'next Sync now.',
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

  Future<void> _showConflicts() async {
    final conflicts = await widget.store.conflicts();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync conflicts'),
        content: SizedBox(
          width: double.maxFinite,
          child: conflicts.isEmpty
              ? const Text(
                  'No conflicts. When both devices change '
                  'the same thing, the version that was not kept is '
                  'preserved here instead of being lost.',
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: conflicts.length,
                  itemBuilder: (context, i) {
                    final c = conflicts[i];
                    return ListTile(
                      dense: true,
                      title: Text('${c.entity} — ${c.kind}'),
                      subtitle: Text(
                        'Kept: ${_preview(c.keptText)}\n'
                        'Not kept: ${_preview(c.lostText)}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuarantine() async {
    final held = await widget.store.quarantined();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Held sync changes'),
        content: SizedBox(
          width: double.maxFinite,
          child: held.isEmpty
              ? const Text('Nothing is being held.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: held.length,
                  itemBuilder: (context, i) {
                    final q = held[i];
                    return ListTile(
                      dense: true,
                      title: Text('${q['entity']} — ${q['reason']}'),
                      subtitle: Text(
                        'Stamped ${q['hlc']}. '
                        '${_heldHint(q['reason'] as String?)}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Per-reason guidance for held changes (S7 review M2): a
  /// missing-parent hold is NOT a clock problem, and telling the
  /// owner to fix a clock and re-export can never recover it —
  /// the exporter already sent (and recorded) that change.
  static String _heldHint(String? reason) {
    final r = reason ?? '';
    if (r.startsWith('future')) {
      return 'Dated implausibly far in the future (a wrong clock '
          "on the other device). Fix that device's clock, export "
          'again there, and re-import here.';
    }
    if (r == 'missing-parent') {
      return 'Part of this change has not arrived yet. Import '
          'the package that contains the rest, or run Sync now '
          'again once the folder has settled.';
    }
    if (r.startsWith('apply-error')) {
      return 'This change could not be stored and was set aside '
          'so the rest of the package could proceed.';
    }
    return 'Held for inspection.';
  }

  static String _preview(String? text) {
    if (text == null) return '—';
    final flat = text.replaceAll('\n', ' ');
    return flat.length <= 120 ? flat : '${flat.substring(0, 120)}…';
  }

  String _fmtTime(int? ms) {
    if (ms == null) return 'never';
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal().toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Two-device sync, Stage A: data travels in packages you '
          'export and import by hand (or let your Library folder '
          'sync carry them — packages land in Library/sync). Your '
          'Library files themselves travel with the folder via '
          'Syncthing-Fork (setup: docs/SYNC_SETUP.md). The live '
          'database file is never synced directly.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: Gap.md),
        if (s == null)
          const Center(child: CircularProgressIndicator())
        else
          NeoWell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This device: ${s.deviceId.substring(0, 8)}…',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  'Last export: ${_fmtTime(s.lastExportAt)}'
                  '${s.lastExportFile == null ? '' : ' (${s.lastExportFile})'}',
                  style: theme.textTheme.bodySmall,
                ),
                for (final peer in s.peers)
                  Text(
                    'Last import from ${peer.deviceId.substring(0, 8)}…: '
                    '${_fmtTime(peer.lastImportAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (s.peers.isEmpty)
                  Text(
                    'Nothing imported from another device yet.',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        if (widget.onSetLibraryRoot != null) ...[
          const SizedBox(height: Gap.md),
          Text(
            'Library folder: ${widget.libraryRoot.path}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _changeLibraryRoot,
                icon: const Icon(Icons.folder_outlined),
                label: const Text('Change Library folder…'),
              ),
              if (widget.onResetLibraryRoot != null)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.onResetLibraryRoot!();
                          return 'Library folder reset to the '
                              'default — restart the app to use it.';
                        }),
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: const Text('Reset to default'),
                ),
            ],
          ),
        ],
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importPicked,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import a package…'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _showConflicts,
              icon: const Icon(Icons.content_copy_outlined),
              label: Text('Conflicts (${s?.conflictCount ?? 0})'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _showQuarantine,
              icon: const Icon(Icons.schedule_outlined),
              label: Text('Held (${s?.quarantineCount ?? 0})'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _repair,
              icon: const Icon(Icons.build_outlined),
              label: const Text('Repair from a snapshot…'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: Gap.md),
          const LinearProgressIndicator(),
        ],
        if (_message != null) ...[
          const SizedBox(height: Gap.md),
          Text(_message!, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

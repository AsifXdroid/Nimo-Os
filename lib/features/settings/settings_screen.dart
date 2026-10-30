/// SET — the Settings surface (S6, §R2.3): one screen, grouped,
/// nothing deeper than one level. Groups: Reminders (two opt-in
/// toggles, off by default — §R5.6), Backup (the S4 section),
/// Sync (the S7 Stage A section, wired by the shell; on desktop
/// a platform note joins it — reminders schedule in-app only
/// there, §R8.6).
///
/// Reminder times are editable; enabling a toggle is the ONLY
/// moment a permission is requested (TESTING §9/S6). Copy is
/// invitational, and the screen carries the §R5.6 self-watch:
/// after a ≥7-day absence with reminders on, it suggests
/// turning them off.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'backup_section.dart';
import 'reminders.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.reminders,
    required this.backupSection,
    this.syncSection,
  });

  final ReminderController reminders;

  /// The S4 backup export/import section, wired by the shell.
  final BackupSection backupSection;

  /// The S7 sync section, wired by the shell (optional so tests
  /// can mount Settings without a sync store).
  final Widget? syncSection;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ReminderSettings? _settings;
  bool _suggestOff = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.reminders.load();
    final suggest = await widget.reminders.shouldSuggestTurningOff();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _suggestOff = suggest;
    });
  }

  Future<void> _toggleMorning(bool v) async {
    final granted = await widget.reminders.setMorningEnabled(v);
    if (!mounted) return;
    if (v && !granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked for Nimo in system settings — '
            'the reminder is saved and will start once they\'re allowed.',
          ),
        ),
      );
    }
    await _load();
  }

  Future<void> _toggleEvening(bool v) async {
    final granted = await widget.reminders.setEveningEnabled(v);
    if (!mounted) return;
    if (v && !granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked for Nimo in system settings — '
            'the reminder is saved and will start once they\'re allowed.',
          ),
        ),
      );
    }
    await _load();
  }

  Future<void> _pickTime(bool morning) async {
    final s = _settings;
    if (s == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: morning ? s.morningTime : s.eveningTime,
    );
    if (picked == null) return;
    if (morning) {
      await widget.reminders.setMorningTime(picked);
    } else {
      await widget.reminders.setEveningTime(picked);
    }
    await _load();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          Text('Reminders', style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          Text(
            'Gentle nudges, off by default. They are scheduled '
            'inexactly — one may arrive a little after its time — '
            'and nothing depends on them.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                'On desktop, scheduled reminders are not supported '
                'by the platform notification service (§R8.6) — '
                'these toggles are kept for parity, but treat the '
                'phone as the reminder device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_suggestOff) _suggestionCard(context),
          if (s == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Morning plan reminder'),
              subtitle: Text('Daily at ${_fmt(s.morningTime)} — '
                  '"${ReminderCopy.morningTitle}"'),
              value: s.morningEnabled,
              onChanged: _toggleMorning,
            ),
            if (s.morningEnabled)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _pickTime(true),
                  icon: const Icon(Icons.schedule_outlined, size: 18),
                  label: Text('Change time (${_fmt(s.morningTime)})'),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Evening Day Close reminder'),
              subtitle: Text('Daily at ${_fmt(s.eveningTime)} — '
                  '"${ReminderCopy.eveningTitle}"'),
              value: s.eveningEnabled,
              onChanged: _toggleEvening,
            ),
            if (s.eveningEnabled)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _pickTime(false),
                  icon: const Icon(Icons.schedule_outlined, size: 18),
                  label: Text('Change time (${_fmt(s.eveningTime)})'),
                ),
              ),
          ],
          const SizedBox(height: Gap.lg),
          Text('Backup', style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          widget.backupSection,
          const SizedBox(height: Gap.lg),
          Text('Sync', style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          if (widget.syncSection != null)
            widget.syncSection!
          else
            Text(
              'Sync is not wired in this build.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _suggestionCard(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You hadn\'t opened Nimo in over a week while '
                'reminders were on. If they\'re not helping, '
                'turning them off is the kind option.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  FilledButton(
                    onPressed: () async {
                      await widget.reminders.turnAllOff();
                      await _load();
                    },
                    child: const Text('Turn reminders off'),
                  ),
                  const SizedBox(width: Gap.sm),
                  TextButton(
                    onPressed: () async {
                      await widget.reminders.dismissSuggestion();
                      await _load();
                    },
                    child: const Text('Keep them'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

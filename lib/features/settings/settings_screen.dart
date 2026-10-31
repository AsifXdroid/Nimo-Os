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

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import 'backup_section.dart';
import 'reminders.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.reminders,
    required this.backupSection,
    this.syncSection,
    this.themeChoice,
    this.onThemeChanged,
  });

  final ReminderController reminders;

  /// The S4 backup export/import section, wired by the shell.
  final BackupSection backupSection;

  /// The S7 sync section, wired by the shell (optional so tests
  /// can mount Settings without a sync store).
  final Widget? syncSection;

  /// NEO (D-036): the Appearance switch — current choice + the
  /// shell's persist-and-apply callback (optional, same pattern
  /// as the sync section).
  final AppThemeChoice? themeChoice;
  final ValueChanged<AppThemeChoice>? onThemeChanged;

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
        padding: const EdgeInsets.fromLTRB(Space.page, Gap.md, Space.page, Gap.lg),
        children: [
          const NeoPageTitle(
            eyebrow: 'Your Nimo',
            heading: 'A space that feels like yours.',
            sub: 'Offline by design. No account. No cloud.',
          ),
          const SizedBox(height: Gap.lg),
          if (widget.themeChoice != null &&
              widget.onThemeChanged != null) ...[
            // D-039: Appearance is a canvas section, not a panel.
            const NeoSectionHead(title: 'Appearance'),
            const SizedBox(height: Gap.sm),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The Editorial design, in dark or light. Dark is '
                    'Nimo\'s home; light is there whenever you want it.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  SegmentedButton<AppThemeChoice>(
                    segments: const [
                      ButtonSegment(
                        value: AppThemeChoice.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                      ButtonSegment(
                        value: AppThemeChoice.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                    ],
                    selected: {widget.themeChoice!},
                    onSelectionChanged: (sel) =>
                        widget.onThemeChanged!(sel.first),
                  ),
                ],
            ),
            const SizedBox(height: Gap.lg),
          ],
          const NeoSectionHead(title: 'Gentle reminders'),
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
                'by the platform notification service — these '
                'toggles are kept for parity, but treat the phone '
                'as the reminder device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_suggestOff) _suggestionCard(context),
          if (s == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBlock(width: 220),
                  SizedBox(height: Gap.md),
                  SkeletonBlock(width: 180),
                ],
              ),
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
          // D-038 (§6.6): Backup and Sync are DIFFERENT tools —
          // a full snapshot vs moving changes — and now read as
          // two distinct sections instead of one data block.
          const NeoSectionHead(title: 'Backup & restore'),
          const SizedBox(height: Gap.sm),
          // The backup section carries its own structure; the
          // flat wrapper panel is gone (D-039 canvas rule).
          widget.backupSection,
          const SizedBox(height: Gap.lg),
          const NeoSectionHead(title: 'Sync between your devices'),
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
          const SizedBox(height: Gap.lg),
          // The closing note sits on the canvas (D-039).
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NeoGlyph(icon: Icons.lock_outline),
              const SizedBox(height: Space.s4),
              Text(
                'A quieter kind of app.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Space.s2),
              Text(
                'Your personal growth shouldn’t be someone '
                'else’s data.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          const Divider(),
          const SizedBox(height: Gap.md),
          const NimoBrandFooter(),
          const SizedBox(height: Gap.md),
        ],
      ),
    );
  }

  Widget _suggestionCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NeoNotice(
            'You hadn’t opened Nimo in over a week while reminders '
            'were on. If they’re not helping, turning them off is '
            'the kind option.',
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
    );
  }
}

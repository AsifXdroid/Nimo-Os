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

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/brand.dart';
import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../today/today_store.dart';
import 'reminders.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.reminders,
    required this.backupSection,
    this.syncSection,
    this.themeChoice,
    this.onThemeChanged,
    this.todayStore,
  });

  final ReminderController reminders;

  /// UX Phase 5: Today's three live section switches (Week
  /// strip, Day Close banner, Pinned spaces) live here as
  /// ordinary preferences — they moved out of the retired
  /// Customize Home dialog. Optional, same pattern as the
  /// sync section, so tests can mount Settings without one.
  final TodayStore? todayStore;

  /// The S4 backup export/import section, wired by the shell.
  final Widget backupSection;

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

  /// The Today section switches, keyed by the TodayStore
  /// section constants — the same keys Today reads.
  Map<String, bool>? _todaySections;

  /// The stored hero photo path (D-053): null means the
  /// shipped default photograph. Loaded with the switches.
  String? _heroPath;

  /// Labels for the three Today switches — the same words
  /// the retired Customize Home dialog used.
  static const _todaySectionLabels = <String, String>{
    TodayStore.sectionWeekStrip: 'Week strip',
    TodayStore.sectionDayClose: 'Day Close banner',
    TodayStore.sectionPinned: 'Pinned spaces on Today',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.reminders.load();
    final suggest = await widget.reminders.shouldSuggestTurningOff();
    Map<String, bool>? sections;
    String? heroPath;
    final ts = widget.todayStore;
    if (ts != null) {
      sections = {
        for (final key in _todaySectionLabels.keys)
          key: await ts.homeSectionVisible(key),
      };
      heroPath = await ts.heroImagePath();
    }
    if (!mounted) return;
    setState(() {
      _settings = s;
      _suggestOff = suggest;
      _todaySections = sections;
      _heroPath = heroPath;
    });
  }

  Future<void> _toggleTodaySection(String key, bool v) async {
    await widget.todayStore!.setHomeSectionVisible(key, v);
    await _load();
  }

  /// D-053's hero picker, rehomed here when the Customize
  /// Home dialog retired (owner decision, 2026-11-12: no
  /// dialog — the photo controls join the Today switches in
  /// Settings). The picked file is COPIED into app storage
  /// first (a picker may hand back a cache path that later
  /// vanishes), and the store remembers where the copy lives.
  Future<void> _changeHeroImage() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp']),
      ],
    );
    if (picked == null || !mounted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      final dest = File('${dir.path}/nimo_hero_custom.$ext');
      await File(picked.path).copy(dest.path);
      // A previous custom image with a different extension
      // would linger beside the new one — remove siblings.
      await for (final f in dir.list()) {
        if (f is File &&
            f.path.contains('nimo_hero_custom') &&
            f.path != dest.path) {
          await f.delete();
        }
      }
      await widget.todayStore!.setHeroImagePath(dest.path);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not use that image: $e')));
    }
  }

  /// Back to the shipped default photograph — the custom
  /// file is deleted and the stored path cleared (D-053).
  Future<void> _resetHeroImage() async {
    final stored = await widget.todayStore!.heroImagePath();
    if (stored != null) {
      final f = File(stored);
      if (await f.exists()) await f.delete();
    }
    await widget.todayStore!.setHeroImagePath(null);
    await _load();
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
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          Gap.md,
          Space.page,
          Gap.lg,
        ),
        children: [
          const NeoPageTitle(
            eyebrow: 'Your Nimo',
            heading: 'A space that feels like yours.',
            sub: 'Offline by design. No account. No cloud.',
          ),
          const SizedBox(height: Gap.lg),
          if (widget.themeChoice != null && widget.onThemeChanged != null) ...[
            // D-039: Appearance is a canvas section, not a panel.
            Row(
              children: [
                const Expanded(child: NeoSectionHead(title: 'Appearance')),
                NeoInfoButton(
                  title: 'Appearance',
                  message:
                      'The Editorial design, in dark or light. Dark is '
                      'Nimo\'s home; light is there whenever you want it.',
                ),
              ],
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
              onSelectionChanged: (sel) => widget.onThemeChanged!(sel.first),
            ),
            const SizedBox(height: Gap.lg),
          ],
          if (widget.todayStore != null && _todaySections != null) ...[
            Row(
              children: [
                const Expanded(child: NeoSectionHead(title: 'Today')),
                NeoInfoButton(
                  title: 'Today',
                  message:
                      'Choose what your Today page shows: the week '
                      'strip inside the plan card, the Day Close banner, '
                      'and your pinned spaces. You can also change '
                      'the photo at the top of Today.',
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            for (final e in _todaySectionLabels.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.value),
                value: _todaySections![e.key] ?? true,
                onChanged: (v) => _toggleTodaySection(e.key, v),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.image_outlined),
              title: const Text('Hero image'),
              subtitle: Text(
                _heroPath != null ? 'Your photo' : 'Default photograph',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Change image…'),
              onTap: _changeHeroImage,
            ),
            if (_heroPath != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restart_alt_outlined),
                title: const Text('Reset to default'),
                onTap: _resetHeroImage,
              ),
            const SizedBox(height: Gap.lg),
          ],
          Row(
            children: [
              const Expanded(child: NeoSectionHead(title: 'Gentle reminders')),
              NeoInfoButton(
                title: 'Gentle reminders',
                message:
                    'Gentle nudges, off by default. They are scheduled '
                    'inexactly — one may arrive a little after its time — '
                    'and nothing depends on them.',
              ),
            ],
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
              subtitle: Text(
                'Daily at ${_fmt(s.morningTime)} — '
                '"${ReminderCopy.morningTitle}"',
              ),
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
              subtitle: Text(
                'Daily at ${_fmt(s.eveningTime)} — '
                '"${ReminderCopy.eveningTitle}"',
              ),
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

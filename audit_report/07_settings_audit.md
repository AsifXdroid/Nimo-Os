# Settings & Configuration Architecture Audit

## 1. Inventory of Current Settings

Every user-configurable preference and setting in Nimo was audited against code in `lib/features/settings/` and the SQLite table `app_settings`.

| Category | Setting Key / Field | User-Facing Label | Available Options | Default | Functional Verification | Current Location |
|---|---|---|---|---|---|---|
| **Appearance** | `theme_mode` | "Appearance" | `Dark` / `Light` (SegmentedButton) | `Dark` (Midnight base) | Verified working in `AppTheme.neoDark()` / `neoLight()`. | `SettingsScreen` (Top) |
| **Notifications** | `reminder_morning_enabled` | "Morning plan reminder" | Toggle (On / Off) | `Off` | Requests notification permission on first enable. Inexact Alarm. | `SettingsScreen` |
| **Notifications** | `reminder_morning_time` | "Change time (HH:mm)" | TimePicker dialog (24h/12h) | `08:00` | Verified persisted and scheduled via `PluginReminderGateway`. | `SettingsScreen` |
| **Notifications** | `reminder_evening_enabled` | "Evening Day Close reminder" | Toggle (On / Off) | `Off` | Requests notification permission on first enable. | `SettingsScreen` |
| **Notifications** | `reminder_evening_time` | "Change time (HH:mm)" | TimePicker dialog (24h/12h) | `21:00` | Verified persisted and scheduled via `PluginReminderGateway`. | `SettingsScreen` |
| **Data & Storage** | In-App Backup Export | "Export backup now" | Button → generates `.zip` with manifest + DB + Library | User-triggered | Verified: produces SHA-256 verified ZIP file. | `SettingsScreen` (`BackupSection`) |
| **Data & Storage** | In-App Backup Restore | "Restore from backup" | Button → file picker → D-011 guard dialog | User-triggered | Verified: automatic pre-restore backup + overwrite confirmation. | `SettingsScreen` (`BackupSection`) |
| **Data & Storage** | External SAF Backup | "Backup outside the app" | Folder Picker (SAF) + "Back Up Now" | Unset | Verified on Android: survives app uninstallation. | `SettingsScreen` (`ExternalBackupSection`) |
| **Synchronisation** | `library_root` | "Library root folder" | Path picker / Default button | `<app docs>/Library` | Verified: resolves relative paths cleanly. | `SettingsScreen` (`SyncSection`) |
| **Synchronisation** | Sync Package Export | "Export sync package" | Button → generates `.nimo-sync` delta package | User-triggered | Verified: 3-way merge op log generation. | `SettingsScreen` (`SyncSection`) |
| **Synchronisation** | Sync Package Import | "Import sync package" | Button → picks package → merges delta | User-triggered | Verified: conflict copies in `sync_conflicts`. | `SettingsScreen` (`SyncSection`) |
| **Personalisation** | `if_then_line` | "Your if–then line" | Free-form string ("If …, then I will …") | `""` (Empty) | Verified in `RoutineScreen` and `TodayScreen`. | `RoutineScreen` / `TodayScreen` |
| **Personalisation** | `home_show_<section>` | "Customize Home" | 10 toggle switches for Home sections | All `true` | Verified: persists to `app_settings` and toggles sections. | `TodayScreen` Dialog |

---

## 2. Identified Deficiencies in Settings Architecture

### 1. The Monolithic Flat List Anti-Pattern
- In [`lib/features/settings/settings_screen.dart`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/settings/settings_screen.dart), all sections are rendered inside a single scrolling `ListView`:
  - Appearance → Reminders → Backup → External Backup → Sync → Privacy note → Brand footer.
- This creates an excessively long screen where critical data management options (like restoring an external backup or configuring sync) are buried under toggles and reminders.

### 2. Dispersed Configuration
- Some major application settings are completely disconnected from the Settings screen:
  - **Customize Home:** Lives in a modal dialog triggered by a button at the very bottom of Today's plan.
  - **If-Then Implementation Intention:** Lives inside `RoutineScreen`.
  - **Inbox Project Pointer:** Hidden internal configuration with no user visibility.

### 3. Missing Foundational Settings
- **Typography & Font Scaling:** Nimo does not expose text size scaling preferences, forcing users with vision constraints to rely solely on system-wide accessibility settings.
- **Data Export & Cleanup:** Users cannot easily see how much total storage Nimo consumes (database size + extracted PDF text + thumbnails) in one place.
- **Diagnostic / Build Info:** Settings does not display the exact version number, git commit hash, database schema version, or open-source licenses.

---

## 3. Proposed Modern Settings Architecture

We propose restructuring Settings into **four clear, discoverable sub-categories** using a modern card navigation pattern:

```
[ Settings (Knowledge Hub Style) ]
│
├── 1. Appearance & Display
│    ├── Theme Mode: Dark / Light / Follow System (NEW)
│    ├── Text Size: Standard / Large / Compact (NEW)
│    └── Home Customization: Customize visible sections on Today
│
├── 2. Daily Habits & Reminders
│    ├── Morning Plan: Reminder toggle + time picker + If-Then line
│    ├── Evening Close: Reminder toggle + time picker
│    └── Inactivity Self-Watch: Automatic reminder pause after 7 days
│
├── 3. Data, Backup & Storage
│    ├── Storage Footprint: DB size, Library size, Thumbnail cache size (NEW)
│    ├── Clear Cache: Prune temporary thumbnails and extracted PDF caches (NEW)
│    ├── External Backup (SAF): Safe Android backup folder + Back Up Now
│    └── Snapshot Backup & Restore: Import/Export zip with D-011 guard
│
├── 4. Device Sync (LAN Stage A)
│    ├── Peer Device Status
│    ├── Export / Import sync packages
│    └── View sync conflict copies
│
└── 5. About & Diagnostics
     ├── Nimo Version & Build (e.g. v1.2.0 - Schema v8)
     ├── Database Diagnostics: Table row counts, integrity check
     └── Open Source Licenses
```

### Usability Benefits of Proposed Settings Structure:
- **Instant Discoverability:** Users can find Backup or Reminders in 1 tap without scrolling through a 337-line list.
- **Unified Customization:** Home screen customization moves into Appearance where users expect it.
- **Diagnostic Transparency:** Users can verify database health and storage usage directly.

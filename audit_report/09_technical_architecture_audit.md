# Technical Architecture, Data Integrity & Sync Audit

## 1. Codebase Architecture & Modularity

### A. Feature Organization
- **Structure:**
  - `lib/core/`: Database (`app_database.dart`), tokens (`theme.dart`), UI kit (`neo_ui.dart`), IDs, HLC clock, branding.
  - `lib/features/`: Feature modules (`today`, `learn`, `spaces`, `direction`, `goals`, `progress`, `review`, `settings`, `sync`, `quick_add`, `onboarding`).
- **Verdict:** Highly disciplined feature folder separation. Almost all domain logic is cleanly decoupled from Flutter UI widgets.

### B. Oversized Classes & Monolithic Anti-Patterns
- **Critical Violation: `TodayScreen` (`lib/features/today/today_screen.dart`):**
  - **2,139 lines of code in a single file.**
  - Handles daily plan generation, week view, quick add routing, score derivations, day close triggers, pinned spaces, recent item history, and home customizations.
  - *Architectural Risk:* Any change to today's plan requires navigating a massive monolithic file. Rebuilds re-evaluate large widget sub-trees unnecessarily.
  - *Recommendation:* Decompose `TodayScreen` into 4 focused sub-components:
    - `TodayPlanCard`: Only handles routines and daily tasks (~400 lines).
    - `TodayLearnCard`: Handles practice recommendations (~150 lines).
    - `TodayScoresSection`: Handles Done/Self score wells (~150 lines).
    - `TodayHeader`: Handles date, greeting, streak pill, and settings trigger (~200 lines).

### C. State Management
- **Approach:** Standard Flutter `StatefulWidget` with local `FutureBuilder` or `setState` calls backed by stateless Dart domain stores (`TodayStore`, `Store`, `ReviewStore`, `LearnStore`, `GoalsStore`).
- **Evaluation:**
  - This avoids heavyweight state management frameworks (Riverpod, Bloc, Redux), which is a significant advantage for maintainability, startup speed, and binary size.
  - However, because stores do not expose reactive streams (`ValueNotifier` or `Stream`), screens must manually call `setState(_reload)` after child routes pop. If a modal edits data and forgets to trigger a reload, the parent screen displays stale data.

---

## 2. Database Design & Data Integrity

### A. Schema Integrity (`lib/core/db/app_database.dart`)
- Single SQLite database: `daily_life.db`.
- Foreign Keys enabled: `PRAGMA foreign_keys = ON;` strictly enforced.
- Cascading Deletes: Deleting a workspace cascades to projects, items, checklist entries, and topics.
- Timestamps: Epoch milliseconds (`INTEGER`) used consistently across all tables.

### B. Deletion Safety & Confirmation Rails
- **Confirmed Deletions:**
  - Deleting an Item, Workspace, Project, Topic, Source, or Routine template requires user confirmation via `confirmDelete()`.
  - Deleting a completed core habit prompts an explicit warning explaining that the daily streak score may be affected.
- **Tombstones & Sync Identity:**
  - Every syncable entity carries `sync_id`, `updated_hlc`, and `deleted_at_hlc`.
  - Soft-deletes generate tombstone operations, preventing deleted rows on one device from resurrecting after sync.

---

## 3. Synchronization & Backup Audit

### A. Stage A Sync (`lib/features/sync/sync_store.dart`)
- **Diffing Mechanism:**
  - Instead of an error-prone event sourcing log, Nimo compares live database row state against `sync_base` (the last exported/imported state) to generate delta packages.
  - 3-way merge algorithm correctly resolves local edits against remote edits using Hybrid Logical Clocks (`HLC`).
- **Conflict Handling:**
  - Winning side applies via Last-Writer-Wins (LWW).
  - Losing side is **never discarded**; it is safely copied to the `sync_conflicts` table.
- **Quarantine Safety Rail:**
  - Operations stamped more than 1 day in the future (caused by clock skew or tampering) are quarantined in `sync_quarantine` and withheld from the live database.

### B. External SAF Backup (`lib/features/settings/external_backup.dart`)
- **Surviving Uninstallation:**
  - Uses Android Storage Access Framework (`SAF`) via native Kotlin method channels (`SafBackupChannel`).
  - Writes atomic `.partial` files, validates file sizes, and generates SHA-256 digests (`db_sha256`) in the backup manifest.
  - Pre-restore backups are automatically generated before restoring any archive (D-011 / D-016).

---

## 4. Testing & Verification Strategy

- **Test Suite Health:**
  - **616 unit and widget tests** run in **~38 seconds**.
  - All tests pass cleanly (`All tests passed!`).
  - `flutter analyze` runs with **0 issues found**.
- **Coverage Quality:**
  - Spaced repetition scheduler algorithms (`scheduler_test.dart`), streak folds (`streak_test.dart`), and multi-device sync merges (`sync_store_test.dart`) have near 100% test coverage.
  - Widget tests cover empty, populated, and error states across all major flows.

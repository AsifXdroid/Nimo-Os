# Daily Life App — Executable Plan

Status: PLAN v2, updated 2026-10-30 (D-010). S1 and S2 are built
and host-verified. Stages S3–S8 below supersede the original
S3–S6 (reel cards / HTML quizzes / goals & polish / safety net)
and follow the approved research report
(`RESEARCH-2026-10-30.md` §R10.2, in the goal workspace).
Owner decisions: see `docs/DECISIONS.md`.

## 1. What this app is

A personal Android app that is part of daily life:

- **Workspaces** → **Projects** → **typed Items**. A workspace is an area
  of life; a project is a collection inside it; an item's *type* decides
  how it renders and behaves (link card, HTML quiz file, note, checklist,
  goal …). New types are added over time — the app is expected to be
  edited frequently, possibly for years.
- **Home = "Today" dashboard**: today's plan (tick off items daily),
  this week's pending plans, short-term goals. Home reads/plans across
  workspaces; it is not itself a workspace.

## 2. How this plan is executable

Work proceeds in **stages** (S0, S1, …). Each stage has: scope,
deliverables, and **acceptance checks** — observable things that must be
true before the stage is called done. A stage is done only when its
checks pass by actually running the app/tests, recorded in
`docs/PROGRESS_LOG.md`. One stage at a time; no stage starts while the
previous stage's checks are unverified. Every change — in any stage —
follows `docs/EDITING_GUIDE.md`.

## 3. Edit-friendly architecture (rules, not suggestions)

These rules exist because the app *will* be edited constantly. They are
the price of keeping it editable:

1. **Feature-first folders.** `lib/features/<feature>/` holds that
   feature's UI, logic, and data code. `lib/core/` holds only shared
   things (database, theme, common widgets). A feature may use `core`;
   features do not import each other's internals — shared needs move to
   `core` deliberately, and the move is logged as a decision.
2. **Item-type registry.** One registry file maps each item type to its
   card renderer, editor screen, and icon. Adding a new item type =
   one new folder under `lib/features/items/<type>/` + one registry
   line. Nothing else in the app changes.
3. **One database, versioned migrations.** Single `AppDatabase`; schema
   changes are new numbered migrations. Old migrations are never edited
   after they ship.
4. **Tokens, not literals.** Colours, spacing, and text styles come from
   theme tokens in `core`; screens never hardcode them.
5. **Every feature has an ID** (see §6) used in code comments, tests,
   docs, and the progress log — so any part of the app can be traced
   from an idea to its files in seconds.

## 4. Documentation system (the "map")

The docs are the map of the app. They live in `docs/` and are updated
**in the same change** as the code they describe — a change that leaves
docs stale is not finished (see EDITING_GUIDE, Definition of Done).

| File | What it maps |
|---|---|
| `PLAN.md` (this file) | Product definition, stages, architecture rules |
| `docs/FEATURE_MAP.md` | Every feature: ID → purpose → code location → doc section → tests → status |
| `docs/EDITING_GUIDE.md` | The edit protocol: how any change (human or AI) is made and documented |
| `docs/DECISIONS.md` | Decision log (D-001…): what was chosen, why, what it replaced |
| `docs/DATA_MODEL.md` | Tables and fields (created at S1, before first migration) |
| `docs/PROGRESS_LOG.md` | Stage/checkpoint log with dates and verification results |
| `CHANGELOG.md` | User-visible changes per version (created at first build) |

## 5. Stages

### S0 — Foundation & docs scaffold (no features)
- Repo layout per §3; this docs pack in place; feature IDs assigned.
- Confirm D-001 (stack: Flutter + SQLite, proposed).
- **Acceptance:** docs pack complete and cross-linked; FEATURE_MAP lists
  all planned features with status `planned`.

### S1 — Core shell: Workspaces, Projects, Items (CORE / WS / PRJ / ITEM)
- App shell + navigation; workspace & project create/rename/delete;
  generic item model with registry; item types: **note** and
  **checklist** only; SQLite schema v1 via DATA_MODEL.md + migration 1.
- **Acceptance:** data survives app restart (verified on device/emulator);
  migration test passes; create→edit→delete works for workspace, project,
  and both item types.

### S2 — Today dashboard (TODAY / GOAL-basic)
- Daily plan: routine template + one-off tasks for the day; tick/untick;
  unticked-item behaviour per D-002; weekly pending view; short-term
  goals as a simple list on Home.
- **Acceptance:** a new day generates the plan from the template;
  ticks persist per date; weekly view shows exactly the week's pending
  items; yesterday's ticks do not leak into today.

### S3 — Close the loop (REVIEW)
- Schema v3 part 1: `day_reviews`, `streak_state`, `shield_events`,
  `sync_meta`/`sync_ops` scaffold, sync identity columns
  (`sync_id`/`updated_hlc`/`deleted_at_hlc`) on syncable tables,
  `plan_templates` habit fields (starter/anchor/track/core flag),
  `goals.track`. Day Close flow (≤2 min, every step skippable);
  dual scores (Done formula v1 + Self, never merged); Streak
  Shields engine (two counting signals only: core plan done OR
  Day Close done); if–then line in the morning plan; habit fields
  in the routine editor.
- **Acceptance:** Day Close completable in ≤2 min with all steps
  skippable; streak unit tests cover shield spend, weekly cap
  (derived per evaluated date's ISO week), refill, timezone-walk
  monotonicity, night-owl attribution, late-close shield refund;
  score formula versioned + tested incl. empty-plan and >8-item
  cap cases; migration v2→v3 preserves S2 data.

### S4 — Topics & Library (LEARN-data)
- `topics`/`sources` tables; Library folder (owner-picked,
  relative paths); share-intent capture landing as topics
  (reels/links are topic triggers — the old S3 LINK scope, moved
  here per D-010); link_card rework (card → topic trigger);
  PDF/TXT import + reading cards + mark-a-point cloze; backup
  export/import (zip, VACUUM INTO snapshot).
- **Acceptance:** share a reel → topic in inbox in ≤2 taps;
  born-digital PDF imports with text; a marked point becomes a
  cloze card; scanned PDF is flagged, not garbled; backup → wipe →
  restore round-trips in tests.

### S5 — Learn engine (LEARN)
- `questions` + scheduler (simplified SM-2) + immutable
  `review_log`; quiz-pack format + importer (strict validation,
  image-point verify); session feed (finite 12–20 cards:
  mcq/flashcard/cloze/image-point/scenario + ordering + capped
  branching role-play); end-of-session enjoyment rating; Learn
  becomes the 4th nav destination; HTML quiz player as the
  legacy route on Android (old S4 QUIZ scope).
- **Acceptance:** a generated sample pack imports cleanly and
  plays a full session offline; scheduler unit tests (lapse, EF
  floor, cap, due ordering); a missed card resurfaces in-session
  and at 1 day; enjoyment rating asked only for sessions of ≥5
  cards, before session stats are shown.

### S6 — Progress & Sunday (PROGRESS)
- Journey Path progress screen + dual-score charts + calendar
  drill-down; Sunday weekly summary card + archive; reminders
  (opt-in toggles, inexact scheduling); Customize Home gains the
  Day Close banner control.
- **Acceptance:** Journey renders 90 days of synthetic records
  smoothly on device; Sunday summary computes correctly for a
  synthetic week incl. a shield day and a score-divergence week;
  reminders default off and fire inexact within the chosen hour
  on device.

### S7 — Two devices (SYNC Stage A + DESKTOP)
- Linux desktop build (sqflite_common_ffi, wide layouts,
  keyboard in Learn); Syncthing-Fork setup for the Library
  folder; "Sync now" data packages (op-log export/import,
  idempotent, conflict copies instead of silent loss); Sync
  screen with per-device status. Snapshot restore follows the
  D-011 guard (auto pre-restore backup + explicit
  replaces-everything confirmation over a non-empty DB).
- **Acceptance:** the same backup restores identically on the
  laptop build; a week of synthetic ops syncs phone→laptop with
  zero loss/duplication (two-DB integration test); a
  same-note-both-sides edit produces a conflict copy, not a
  loss; the laptop opens the phone's Library sources via
  relative paths.

### S8 — Sync Stage B + polish (SYNC-B)
- mDNS discovery (bonsoir) + QR pairing + pinned-TLS op exchange
  (laptop serves); direct-IP fallback; then the polish backlog
  (Constellation year view, Android home-screen widget — if the
  owner wants them).
- **Acceptance:** fresh pairing completes via QR in <1 min; sync
  succeeds with mDNS disabled (fallback path); a changed laptop
  certificate triggers a hard re-pair stop; sync with the laptop
  off fails gracefully with zero data change.

Later stages are defined when reached — this plan is edited, not
rewritten (changes logged in DECISIONS.md).

## 6. Feature IDs (the mapping keys)

`CORE` app shell · `WS` workspaces · `PRJ` projects · `ITEM` item model
& registry · `TODAY` daily plan · `REVIEW` Day Close, dual scores,
streak shields · `LEARN` topics, sources, questions, sessions ·
`LINK` reel/link cards · `QUIZ` HTML quizzes · `GOAL` goals ·
`PROGRESS` Journey screen, charts, weekly summary · `SYNC` LAN sync
(phone ↔ laptop) · `SET` settings, backup, widget.
Full rows live in `docs/FEATURE_MAP.md`.

## 7. Definition of Done (any change, any stage)

Code works and is verified by running it → tests for the touched
feature pass → FEATURE_MAP / DATA_MODEL / DECISIONS updated if the
change affects them → PROGRESS_LOG entry → report states what was
verified and what was not. Details: `docs/EDITING_GUIDE.md`.

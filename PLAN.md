# Daily Life App — Executable Plan

Status: PLAN v1, defined 2026-10-29. Nothing built yet.
Owner decisions pending: see `docs/DECISIONS.md` (D-002 … D-005).

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

### S3 — Reel link cards (LINK)
- Add link by paste and by Android **share intent** (share from
  Instagram → save in ≤ a few taps); square-preview card grid;
  thumbnail strategy per D-003: try auto-fetch → designed fallback card
  → user-attached image; open link in app/browser.
- **Acceptance:** sharing a reel link from another app creates a card
  with zero typing; a link whose thumbnail cannot be fetched still
  renders a clean card (never a broken image); grid is square-cropped
  and scrollable with 50+ cards.

### S4 — HTML quiz workspace (QUIZ)
- Import `.html` files (file picker + share intent); files stored in
  app storage; play in in-app WebView, fully offline; attempt/score
  tracking only if D-004 says yes.
- **Acceptance:** an imported single-file HTML quiz plays start to
  finish with no network; deleting the item deletes its file;
  quizzes survive app restart.

### S5 — Goals & polish (GOAL / SET)
- Goal progress (manual % or linked checklists); streaks for daily
  plan; global search across items; theme polish.
- **Acceptance:** goal progress reflects its linked items; search finds
  items by title/note across all workspaces.

### S6 — Safety net (SET)
- Export/import: one backup file containing DB + imported files;
  Android home-screen widget showing today's plan.
- **Acceptance:** export → reinstall → import restores workspaces,
  items, and quiz files identically; widget shows today's unticked
  items and refreshes on day change.

Later stages are defined when reached — this plan is edited, not
rewritten (changes logged in DECISIONS.md).

## 6. Feature IDs (the mapping keys)

`CORE` app shell · `WS` workspaces · `PRJ` projects · `ITEM` item model
& registry · `TODAY` daily plan · `LINK` reel/link cards · `QUIZ` HTML
quizzes · `GOAL` goals & streaks · `SET` settings, backup, widget.
Full rows live in `docs/FEATURE_MAP.md`.

## 7. Definition of Done (any change, any stage)

Code works and is verified by running it → tests for the touched
feature pass → FEATURE_MAP / DATA_MODEL / DECISIONS updated if the
change affects them → PROGRESS_LOG entry → report states what was
verified and what was not. Details: `docs/EDITING_GUIDE.md`.

# Feature Map — Daily Life App

The single index that maps every feature to its code, docs, and tests.
**Rule: before editing a feature, find its row here. After editing,
update its row in the same change** (see EDITING_GUIDE.md).

How to read a row: `Code` is the folder that owns the feature.
`Data` lists DB tables the feature owns (details in DATA_MODEL.md).
Status values: `planned` → `in-progress` → `done` → `changed` (with
date + decision ID when a later change alters it).

| ID | Feature | Purpose | Code | Data | Tests | Status |
|---|---|---|---|---|---|---|
| CORE | App shell | Navigation, theme tokens, shared widgets, DB setup | `lib/core/`, `lib/app/` | — | `test/core/` | done (S1, host-verified) |
| WS | Workspaces | Create/rename/delete workspaces; workspace list & ordering | `lib/features/workspaces/` | `workspaces` | `test/features/workspaces/` | done (S1, host-verified) |
| PRJ | Projects | Projects inside a workspace; project view of items | `lib/features/projects/` | `projects` | `test/features/projects/` | done (S1, host-verified) |
| ITEM | Item model & registry | Generic item (type, title, note, timestamps); registry mapping type → renderer/editor/icon. **New item types register here** | `lib/features/items/` | `items` | `test/features/items/` | done (S1, host-verified) |
| ITEM-note | Note item | Plain text note item | `lib/features/items/note/` | (uses `items`) | in ITEM tests | done (S1, host-verified) |
| ITEM-list | Checklist item | Tickable list inside an item | `lib/features/items/checklist/` | `checklist_entries` | in ITEM tests | done (S1, host-verified) |
| TODAY | Today dashboard & daily plan | Home screen ("Hub Home", D-009); routine template + one-off tasks; per-day ticks; weekly pending view; week strip, quick add, pinned spaces, recent items, customize; habit fields on templates (starter/anchor/track/core) and the if–then line (S3) | `lib/features/today/` | `plan_templates`, `day_plans`, `day_plan_items`, `app_settings` | `test/features/today/` | done (S2 + S3 habit fields/if–then, host-verified) |
| REVIEW | Day Close, dual scores, streak shields | Night review (recap, major point, self score — ≤2 min, all steps skippable); Done Score (auto, formula-versioned) + Self Score, never merged; Streak Shields engine (two counting signals only; shields from streak 7, ≤2 held, ≤2 per ISO week); major point can link a topic since S4 | `lib/features/review/` | `day_reviews`, `streak_state`, `shield_events`, `sync_meta`, `sync_ops` | `test/features/review/` | done (S3 + S4 topic wiring, host-verified) |
| LEARN | Topics, sources, questions, sessions | Reels/links as topic triggers; sources (PDF/TXT/link) in a Library folder; quiz packs (versioned `nimo.quizpack`, strict importer, image-point verify); scroll-feed sessions (finite 12–20, interleaved, 7 question types, 5 R4B formats incl. capped branching role-play + boss level); end-of-session enjoyment rating (≥5 cards, before stats); simplified SM-2 + immutable review log; marked points mint cloze questions | `lib/features/learn/` | `topics`, `sources`, `marked_points` (S4); `questions`, `review_log`, `learn_sessions`, `packs` (S5) | `test/features/learn/` | done (S5, host-verified): S4 data layer + S5 engine — pack importer, scheduler, composer/engine, Learn tab (4th destination, D-021), Today 1-tap session launch, Done Score learning block live (streak untouched, red-team #1) |
| LINK | Link cards (reels) | Save links by paste/share intent; square-preview grid; thumbnail fetch + fallback + manual image; open link. Per D-010 the card becomes a topic trigger in S4 (see LEARN) | `lib/features/items/link_card/` | (uses `items`; thumbnail name + provenance in payload) | `test/features/items/` | done (S4, host-verified) |
| QUIZ | HTML quizzes | Import `.html` files into the Library (`html_quizzes/`); play in a hardened WebView on Android (legacy route — quizzes can't feed the scheduler, §R4.4); play-only per D-004 | `lib/features/items/html_quiz/` | (uses `items`; Library-relative `file_rel_path` in payload) | `test/features/items/` | done (S5, host-verified): item type + import + navigation-policy unit tests + non-Android fallback screen; on-device WebView play unverified (owner) |
| GOAL | Goals | Short-term goals on Home; progress steppers | `lib/features/goals/` | `goals` | `test/features/goals/` | basic done (S2, host-verified) |
| PROGRESS | Progress & weekly summary | Journey Path screen; dual-score charts; calendar drill-down; Sunday weekly summary + archive | `lib/features/progress/` | (reads REVIEW/TODAY/LEARN data) | `test/features/progress/` | done (S6, host-verified) |
| SYNC | Two-device sync (phone ↔ laptop) | Stage A: Library folder via Syncthing-Fork (docs/SYNC_SETUP.md) + "Sync now" data packages — state-diff op generation vs `sync_exported`/`sync_base` (D-029, corrected D-033), 3-way merge, per-date day_reviews merge, tombstones, future-date quarantine, conflict copies, Repair via the D-011-guarded snapshot restore; Library-root picker in the Sync section. Stage B (S8): mDNS discovery + QR pairing + pinned-TLS auto sync | `lib/features/sync/`, `lib/core/platform_init.dart` (desktop DB factory), `linux/` | `sync_meta`, `sync_ops`, `sync_base`, `sync_exported`, `sync_peers`, `sync_quarantine`, `sync_conflicts` (v6–v7) | `test/features/sync/` | Stage A done (S7, host-verified; two-DB convergence/quarantine/atomicity suite; Linux GUI build + real phone↔laptop exchange are owner-side, D-030). Stage B planned (S8) |
| SET | Settings, backup, widget | Backup export/import (S4); reminders + settings (S6); Android home-screen Today widget (backlog, S8) | `lib/features/settings/`, `android/` (widget) | — | `test/features/settings/` | backup done (S4, host-verified; D-011 guard per D-016); reminders done (S6, host-verified); widget backlog (S8) |

## Item-type registry (grows by addition only)

| Type key | Renderer | Editor | Added in |
|---|---|---|---|
| `note` | ITEM-note | ITEM-note | S1 |
| `checklist` | ITEM-list | ITEM-list | S1 |
| `link_card` | LINK | LINK | S4 |
| `html_quiz` | QUIZ | QUIZ | S5 |

Adding a row here + a folder + one registry line is the *whole* cost of
a new item type. If an edit seems to require more than that, stop — the
architecture rule is being broken; log a decision instead.

## Status notes

- 2026-10-30 (S6): PROGRESS marked "done (S6, host-verified)"
  and SET's reminders likewise: Journey Path hero (stones from
  the S3 fold's outputs only), hand-rolled dual-score +
  enjoyment charts (D-028 — no `fl_chart`), calendar
  drill-down, Sunday weekly summary (Mon–Sun, shown Sunday
  ≥18:00 on Today, archived in Progress; Done/Self averages
  separate end-to-end), two opt-in reminder toggles (off by
  default, inexact scheduling only, no exact-alarm
  permission). No schema change (still v5). The stage's first
  review was interrupted, so close-out re-ran it: independent
  review 0 MUST / 7 SHOULD / 9 NOTE — all SHOULDs fixed with
  regression tests (error states with retry, fold memoised
  once per load, Journey painter windowed to the viewport,
  `isEmpty` no longer erases habit/card-only weeks, DST-week
  test added; goldens deferred — see PROGRESS_LOG). Suite
  455/455, analyze clean. On-device verification open
  (notification delivery/timing, Journey feel).
- 2026-10-30 (S5): LEARN marked "done (S5, host-verified)" and
  QUIZ "done (S5, host-verified)": schema v5 (questions,
  immutable review_log, learn_sessions, packs registry);
  SM-2-simplified scheduler; `nimo.quizpack` format + strict
  importer (zip/media/hash/dimension validation, image-point
  verify gate, re-import semantics per §R4.4); session
  composer + engine (quotas/interleave per D-023, miss
  resurface once — never in boss sessions, D-025); all five
  R4B v1 formats shipped incl. the boss-level composer preset
  (no slip); Learn is the 4th nav destination (D-021) and
  Today launches a session in 1 tap; Done Score learning
  block live via ReviewStore derivation (D-024) with the
  two-signals streak invariant proven by test. Build →
  independent review (SHIP-AFTER-FIXES: 2 MUST / 10 SHOULD) →
  fix loop: all fixed, incl. two hollow tests exposed by
  mutation spot-checks (7 mutants, 7 killed after fixes).
  Suite 398/398, analyze clean. On-device verification open
  (session feel/timing, WebView play); goldens still deferred
  (same CI/local-golden task as S3/S4).
- 2026-10-30 (S3): REVIEW marked "done (S3, host-verified)" and
  TODAY's S3 parts (habit fields, if–then line) landed: Day Close
  flow + dual scores + Streak Shields fold (two signals only),
  schema v3 with sync identity scaffold, Hub Home Day Close
  banner. Build → independent review (SHIP-AFTER-FIXES) → fix
  loop: M1 core-snapshot (D-013), D-012 grant-at-7 recorded,
  score refresh after Hub edits, HLC tests. Suite 82/82, analyze
  clean. On-device verification open; not yet pushed.
- 2026-10-30 (S2): TODAY marked "done (S2, host-verified)" and GOAL
  "basic done": Hub Home (D-009) with daily plan (template +
  carry-over per D-002), This-week pending view, week strip, quick
  add, pinned spaces, recent items, goals section with steppers, and
  Customize Home (section visibility in `app_settings`). Schema v2
  migration covers all S2 tables plus `workspaces.pinned` — WS grew
  a pin/unpin toggle on each workspace row (pin state is an S2/WS
  addition; the S1 WS behaviour is unchanged). `flutter analyze`
  clean, tests 23/23 including a v1→v2 migration test with S1 data.
  On-device verification still pending (VM cannot build APKs).
- 2026-10-29 (S1): CORE/WS/PRJ/ITEM rows marked "done (S1,
  host-verified)": `flutter analyze` clean, 7/7 tests pass including
  a real-file close/reopen persistence test. The remaining S1
  acceptance item — running the installed APK on the owner's phone —
  is pending because this VM cannot build APKs (see
  toolchain/NOTES.md); build routes are CI or the owner's laptop.
- 2026-10-29 (design preview, D-008 open): CORE theme grew three
  design plates (`AppPlate` in `lib/core/theme.dart`: Calm Focus /
  Midnight / Warm Paper), and `lib/features/design_preview/` holds
  `@Preview` prototypes of TODAY, LINK and WS bodies in all three
  plates (pure UI + sample data; no DB). Tests:
  `test/design_preview_test.dart` renders every body in every plate
  (suite now 10/10). TODAY and LINK rows stay `planned` — the
  prototypes are not their stage implementations.

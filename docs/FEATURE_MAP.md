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
| TODAY | Today dashboard & daily plan | Home screen; routine template + one-off tasks; per-day ticks; weekly pending view | `lib/features/today/` | `plan_templates`, `day_plans`, `day_plan_items` | `test/features/today/` | planned (S2) |
| LINK | Link cards (reels) | Save links by paste/share intent; square-preview grid; thumbnail fetch + fallback + manual image; open link | `lib/features/items/link_card/` | (uses `items`; thumbnail path in payload) | `test/features/link_card/` | planned (S3) |
| QUIZ | HTML quizzes | Import `.html` files; store in app files; play in WebView offline; attempts if D-004 = yes | `lib/features/items/html_quiz/` | (uses `items`; file path in payload) `quiz_attempts`? | `test/features/html_quiz/` | planned (S4) |
| GOAL | Goals & streaks | Short-term goals on Home; progress; daily-plan streaks | `lib/features/goals/` | `goals` | `test/features/goals/` | basic in S2, full in S5 |
| SET | Settings, backup, widget | Export/import backup file; Android home-screen Today widget | `lib/features/settings/`, `android/` (widget) | — | `test/features/settings/` | planned (S6) |

## Item-type registry (grows by addition only)

| Type key | Renderer | Editor | Added in |
|---|---|---|---|
| `note` | ITEM-note | ITEM-note | S1 |
| `checklist` | ITEM-list | ITEM-list | S1 |
| `link_card` | LINK | LINK | S3 |
| `html_quiz` | QUIZ | QUIZ | S4 |

Adding a row here + a folder + one registry line is the *whole* cost of
a new item type. If an edit seems to require more than that, stop — the
architecture rule is being broken; log a decision instead.

## Status notes

- 2026-10-29 (S1): CORE/WS/PRJ/ITEM rows marked "done (S1,
  host-verified)": `flutter analyze` clean, 7/7 tests pass including
  a real-file close/reopen persistence test. The remaining S1
  acceptance item — running the installed APK on the owner's phone —
  is pending because this VM cannot build APKs (see
  toolchain/NOTES.md); build routes are CI or the owner's laptop.

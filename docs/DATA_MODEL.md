# Data Model — Daily Life App

SQLite, one database (`daily_life.db`), foreign keys ON.
Timestamps are epoch milliseconds (INTEGER). Ordering within a parent
is a manual `sort_order` INTEGER. Deletes cascade parent → children.
Schema changes only via new numbered migrations (EDITING_GUIDE rule 5).

## Schema v1 (Stage S1) — tables

### `workspaces` (WS)
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| name | TEXT NOT NULL | |
| sort_order | INTEGER NOT NULL DEFAULT 0 | |
| created_at / updated_at | INTEGER NOT NULL | epoch ms |

### `projects` (PRJ)
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| workspace_id | INTEGER NOT NULL → workspaces(id) ON DELETE CASCADE | |
| name | TEXT NOT NULL | |
| sort_order | INTEGER NOT NULL DEFAULT 0 | |
| created_at / updated_at | INTEGER NOT NULL | epoch ms |

### `items` (ITEM)
One row per item, whatever its type. Type-specific data goes in
`payload` (JSON text) or in a child table owned by that type.
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| project_id | INTEGER NOT NULL → projects(id) ON DELETE CASCADE | |
| type | TEXT NOT NULL | registry key: `note`, `checklist` (v1); `link_card` (S3), `html_quiz` (S4) |
| title | TEXT NOT NULL | |
| note | TEXT | the user's own annotation ("why I saved this") |
| payload | TEXT | JSON, shape defined per type (below) |
| sort_order | INTEGER NOT NULL DEFAULT 0 | |
| created_at / updated_at | INTEGER NOT NULL | epoch ms |

### `checklist_entries` (ITEM-list)
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| item_id | INTEGER NOT NULL → items(id) ON DELETE CASCADE | |
| text | TEXT NOT NULL | |
| is_done | INTEGER NOT NULL DEFAULT 0 | 0/1 |
| sort_order | INTEGER NOT NULL DEFAULT 0 | |

## Schema v2 (Stage S2) — added tables & columns

### `plan_templates` (TODAY)
The routine template: items copied fresh (unticked) into each new
day's plan (D-002).
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| title | TEXT NOT NULL | |
| position | INTEGER NOT NULL DEFAULT 0 | ordering |
| is_active | INTEGER NOT NULL DEFAULT 1 | 0/1; inactive items don't generate |
| created_at | INTEGER NOT NULL | epoch ms |

### `day_plans` (TODAY)
One row per calendar day that has a plan.
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| date | TEXT NOT NULL UNIQUE | 'yyyy-mm-dd', local |
| created_at | INTEGER NOT NULL | epoch ms |

### `day_plan_items` (TODAY)
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| day_plan_id | INTEGER NOT NULL → day_plans(id) ON DELETE CASCADE | |
| title | TEXT NOT NULL | copied at generation time |
| kind | TEXT NOT NULL | `routine` / `oneoff` |
| template_id | INTEGER → plan_templates(id) ON DELETE SET NULL | routine items only |
| done | INTEGER NOT NULL DEFAULT 0 | 0/1, per-date (this row belongs to one day) |
| carried | INTEGER NOT NULL DEFAULT 0 | 0/1; copied from previous day's unticked one-off (D-002) |
| position | INTEGER NOT NULL DEFAULT 0 | ordering within the day |

### `goals` (GOAL-basic)
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| title | TEXT NOT NULL | |
| target | INTEGER NOT NULL | |
| current | INTEGER NOT NULL DEFAULT 0 | clamped 0..target by the store |
| unit | TEXT NOT NULL DEFAULT '' | e.g. 'words' |
| position | INTEGER NOT NULL DEFAULT 0 | ordering |
| created_at | INTEGER NOT NULL | epoch ms |

### `app_settings` (CORE)
Key/value strings. S2 uses `home_show_<section>` = '1'/'0' for Home
section visibility (Customize Home); absent key = visible.
| column | type | notes |
|---|---|---|
| key | TEXT PK | |
| value | TEXT NOT NULL | |

### Changed in v2
- `workspaces` += `pinned INTEGER NOT NULL DEFAULT 0` — pinned to
  Home (WS, S2).

## Payload shapes (JSON in `items.payload`)

- `note`: no payload (body text lives in `items.note`).
- `checklist`: no payload (entries live in `checklist_entries`).
- `link_card` (S3, planned): `{"url": "...", "thumbnail_path": "..."|null}`.
- `html_quiz` (S4, planned): `{"file_path": "..."}` (path inside app
  storage, relative).

## Planned, NOT yet added (added by their stage's migration)

- S4 (QUIZ, only if D-004 is revisited): `quiz_attempts`.

## Migration history

| version | stage | change |
|---|---|---|
| 1 | S1 | workspaces, projects, items, checklist_entries |
| 2 | S2 | plan_templates, day_plans, day_plan_items, goals, app_settings; workspaces += pinned |

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

## Payload shapes (JSON in `items.payload`)

- `note`: no payload (body text lives in `items.note`).
- `checklist`: no payload (entries live in `checklist_entries`).
- `link_card` (S3, planned): `{"url": "...", "thumbnail_path": "..."|null}`.
- `html_quiz` (S4, planned): `{"file_path": "..."}` (path inside app
  storage, relative).

## Planned, NOT in v1 (added by their stage's migration)

- S2 (TODAY): `plan_templates`, `day_plans`, `day_plan_items`.
- S2/S5 (GOAL): `goals`.
- S4 (QUIZ, only if D-004 is revisited): `quiz_attempts`.

## Migration history

| version | stage | change |
|---|---|---|
| 1 | S1 | workspaces, projects, items, checklist_entries |

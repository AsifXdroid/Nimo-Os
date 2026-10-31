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
| type | TEXT NOT NULL | registry key: `note`, `checklist` (v1); `link_card` (S4), `html_quiz` (S5) |
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
| weekdays | INTEGER (v8, D-042) | 7-bit mask Mon–Sun; NULL = every day; a generation-time filter only |
| item_id | INTEGER → items(id) ON DELETE SET NULL (v8) | optional linked resource (note / link card / quiz) |
| url | TEXT (v8) | optional bare web/video link; wins over item_id for the row action |

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
| item_id | INTEGER → items(id) ON DELETE SET NULL (v8, D-042) | linked resource, copied from the template at generation or the source one-off at carry-over |
| url | TEXT (v8) | bare web/video link, copied the same way |

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

## Schema v3 (Stage S3) — added tables & columns

### `day_reviews` (REVIEW)
One row per closed day. The dual scores live in separate columns
and are never merged (§R5.2).
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| date | TEXT NOT NULL UNIQUE | 'yyyy-mm-dd', local |
| major_point | TEXT | the day's one-line major point |
| major_point_topic_id | INTEGER | plain column in v3; FK to `topics` arrives with that table in S4 |
| self_score | INTEGER | owner's 1–10 (Self Score); NULL when skipped |
| self_note | TEXT | optional "why" line |
| done_score | INTEGER | Done Score (auto), computed by formula `score_formula_version` |
| score_formula_version | INTEGER | 1 in S3 |
| closed_at | INTEGER | epoch ms of the FIRST close (re-closes preserve it) |
| is_counted | INTEGER NOT NULL DEFAULT 0 | materialised ONLY by the streak evaluation pass (single derivation, red-team #17) |
| tz_offset | INTEGER | device UTC offset at close, minutes |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity (§R6.3); sync_id UNIQUE |

### `streak_state` (REVIEW)
Single row (id = 1, seeded by the migration). DERIVED state: the
derivation fields are written only by the evaluation pass, which
re-folds `deriveStreak` over all day signals; the one exception is
`shields_intro_shown`, a UI flag.
| column | type | notes |
|---|---|---|
| current_streak / best_streak / total_days | INTEGER NOT NULL DEFAULT 0 | best/total never reset |
| shields_held / refill_progress | INTEGER NOT NULL DEFAULT 0 | shields ≤ 2 held |
| last_counted_date / evaluated_through | TEXT | 'yyyy-mm-dd'; evaluated_through never regresses |
| shields_intro_shown | INTEGER NOT NULL DEFAULT 0 | "You've earned protection" explained once |
| updated_at | INTEGER NOT NULL DEFAULT 0 | epoch ms |

### `shield_events` (REVIEW)
One row per shield-covered date. A MATERIALISATION of the fold,
regenerated wholesale by every evaluation — a refunded shield
(late Day Close, red-team #5b) simply disappears. S7 note: rows
get fresh sync_ids per evaluation; treat as derived/non-synced
or stabilise identity by date before syncing them.
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| date | TEXT NOT NULL | the covered day, 'yyyy-mm-dd' |
| week_key | TEXT NOT NULL | ISO week 'yyyy-Www' of `date` |
| created_at | INTEGER NOT NULL | epoch ms |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity; sync_id UNIQUE |

### `sync_meta` (CORE, sync scaffold §R6.3)
Key/value for sync state. Keys in S3: `device_id` (this device's
UUID, generated once), `hlc_state` ('wallMs:counter' for the HLC).
| column | type | notes |
|---|---|---|
| key | TEXT PK | |
| value | TEXT NOT NULL | |

### `sync_ops` (SYNC scaffold)
Append-only op log shell for S7; created empty in v3, unused by
S3 code. Columns: `op_id` TEXT PK, `entity`, `sync_id`, `op`,
`payload` (JSON), `hlc`, `device_id`, `seq`.

### Changed in v3
- `plan_templates` += `starter_title` / `anchor_text` / `track`
  (TEXT) and `counts_core INTEGER NOT NULL DEFAULT 1` — the
  tiny-habits fields (§R5.5).
- `day_plan_items` += `counts_core INTEGER NOT NULL DEFAULT 1` —
  a SNAPSHOT of the template's flag taken at plan generation
  (D-013): the streak's core signal reads the snapshot, so
  routine edits/deletes never rewrite past days. One-offs store 0.
- `goals` += `track` (TEXT).
- Sync identity on `workspaces`, `projects`, `items`,
  `checklist_entries`, `plan_templates`, `day_plans`,
  `day_plan_items`, `goals`: `sync_id` / `updated_hlc` /
  `deleted_at_hlc` (TEXT) + a UNIQUE INDEX on `sync_id` (SQLite
  can't ADD COLUMN with UNIQUE; NULLs are exempt, so the index is
  safe pre-backfill). At open, `AppDatabase._ensureSyncIdentity`
  fills NULL sync_ids with fresh UUIDs and a baseline HLC — a
  scaffold until S7 makes stores assign identity at insert.
  `app_settings` deliberately carries NO sync identity
  (device-local preferences never sync); `streak_state` is
  derived, `sync_meta`/`sync_ops` are the sync machinery itself.
- `app_settings` keys added (data, not schema): `if_then_line` —
  the owner's if–then line (§R1.3), shown in the morning plan.

## Schema v4 (Stage S4) — added tables & changes

### `topics` (LEARN)
The unit a reel/link *triggers* (§R6.1): an intention, later
fulfilled by sources/questions. Born with sync identity (§R6.3).
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| project_id | INTEGER NOT NULL → projects(id) ON DELETE CASCADE | capture lands in the built-in **Inbox project** (below) |
| title | TEXT NOT NULL | from the trigger (reel caption / link title / typed) |
| trigger_url | TEXT | the reel/link that sparked it |
| status | TEXT NOT NULL DEFAULT 'inbox' | `inbox` / `sourcing` / `learning` / `done` / `parked` |
| track | TEXT | learning track / life area (Arabic, Health, Money…) |
| created_at / updated_at | INTEGER NOT NULL | epoch ms |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity; sync_id UNIQUE |

**Inbox project:** `topics.project_id` is NOT NULL, so capture
needs a home that always exists: a built-in project named
"Inbox" in the default (first) workspace, seeded lazily and
idempotently by `LearnStore.ensureInboxProject()`. Its id is
remembered in `app_settings.inbox_project_id` (a device-local
pointer, re-seeded if it ever dangles). Triage = moving the
topic to a real project (which advances `inbox` → `sourcing`).

### `sources` (LEARN)
The real material attached to a topic.
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| topic_id | INTEGER NOT NULL → topics(id) ON DELETE CASCADE | |
| kind | TEXT NOT NULL | `pdf` / `txt` / `link` / `html_quiz` / `pack` / `file` (generic shared file, S4) |
| title | TEXT NOT NULL | manual title wins over any guessed one |
| file_rel_path | TEXT | path inside the Library (§R6.4), RELATIVE — never absolute |
| url | TEXT | for kind=link |
| text_rel_path | TEXT | extracted-text sidecar (PDF only) at `sources/<pdf-base>.<source-id>.extracted.json`; JSON `{pages:[…]}` so page boundaries survive (the id in the name keeps sidecars collision-proof). For TXT the file itself is the text → NULL |
| extraction_status | TEXT NOT NULL DEFAULT 'ok' | `ok` / `partial` / `scanned_no_text` / `failed` (§R4.5 honesty) |
| created_at | INTEGER NOT NULL | epoch ms |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity; sync_id UNIQUE |

### `marked_points` (LEARN, D-014)
One marked key point from a reading card (§R4.5/§R8.3): Nimo's
own annotation record — the PDF itself is never edited. S5's
Learn engine mints `questions` (cloze) rows from these.
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| source_id | INTEGER NOT NULL → sources(id) ON DELETE CASCADE | |
| topic_id | INTEGER NOT NULL → topics(id) ON DELETE CASCADE | denormalised for topic-level listing |
| sentence | TEXT NOT NULL | the full sentence (the cloze "back") |
| span_text | TEXT NOT NULL | the blanked span (≤ ~8 words, enforced by the store) |
| page | INTEGER | 1-based PDF page; NULL for TXT |
| char_offset | INTEGER | offset of the span in the page's (PDF) or file's (TXT) extracted text |
| chunk_index | INTEGER NOT NULL DEFAULT 0 | which reading card it was marked on (one mark per card, enforced) |
| created_at | INTEGER NOT NULL | epoch ms |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity; sync_id UNIQUE |

### Changed in v4
- `day_reviews` **rebuilt** (create-copy-drop-rename, all columns
  preserved verbatim incl. sync identity and `is_counted`) so
  `major_point_topic_id` becomes a real FK:
  `REFERENCES topics(id) ON DELETE SET NULL` — deleting a topic
  clears the link, never the review. S3 wrote this column as a
  plain INTEGER; S4's Day Close picker now sets it.
- Sync identity: `topics`, `sources`, `marked_points` join
  `AppDatabase.syncableTables`.

### The Library (files, §R6.4)
Root = `<app documents>/Library` by default, overridable via
`app_settings.library_root` (plain path; the laptop route). All
DB references are root-relative. Layout: `sources/`, `media/`,
`packs/`, `html_quizzes/`, `sync/`, `backups/`, `.nimo/`
(`library.json`: library id, format version). **Every write is
temp-then-rename** (red-team #8): content lands in
`<name>.tmp-<rand>` in the same directory, is flushed, then
renamed over the target. Path resolution (`LibraryStore.resolve`)
is a lexical containment check: it refuses absolute paths and
`..` escapes, but it does not follow symlinks — a symlinked
subfolder inside the Library would redirect access outside the
root. Recorded limitation (S4 review): acceptable while all
names are app-generated; revisit before S7 turns folder sync
on. Link-card thumbnails are NOT Library
content: they live in the app cache (`thumbs/`), regenerable,
payload stores only the file name (D-019).

### Backup format (§R6.5, SET)
One zip in `Library/backups/`: `backup.json` (kind, format
version, schema version, exported_at, device_id),
`database.sqlite` (a `VACUUM INTO` snapshot — never a raw copy
of the live files), `library/…` (the Library tree minus
`backups/` itself). Restore implements the **D-011 guard**
(pre-restore backup always; explicit replaces-everything
confirmation over a non-empty DB) — see DECISIONS D-016.

## Schema v5 (Stage S5) — added tables & changes

### `questions` (LEARN)
One row per question, from imported packs or minted in-app from
marked points (D-014). Scheduler state lives on the row (§R4.3).
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| topic_id | INTEGER NOT NULL → topics(id) ON DELETE CASCADE | |
| source_id | INTEGER → sources(id) ON DELETE SET NULL | provenance: the pack source, or the read source for minted cloze |
| pack_id / pack_qid | TEXT | stable external identity (§R4.4); UNIQUE(pack_id, pack_qid) where present — re-imports key on this pair and never reset scheduler state |
| type | TEXT NOT NULL | `mcq` / `flashcard` / `cloze` / `image_point` / `ordering` / `scenario` / `mythfact` (D-022) |
| payload | TEXT NOT NULL | typed JSON per §R4.1, validated by `lib/features/learn/question.dart` |
| difficulty | INTEGER NOT NULL DEFAULT 3 | 1–5 |
| ef / reps / lapses / interval_days / due_at | REAL / INTEGER / INTEGER / INTEGER / INTEGER | SM-2-simplified state (§R4.3): ef starts 2.5, floor 1.3, no EF cut on the first lapse; intervals 1d → 3d → ×ef, cap 180d; due_at epoch ms |
| suspended | INTEGER NOT NULL DEFAULT 0 | retired without deleting history: report-this-question, verify-pending image points, questions dropped by a pack update |
| created_at / updated_at | INTEGER NOT NULL | epoch ms |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity; sync_id UNIQUE |

### `review_log` (LEARN) — IMMUTABLE
Append-only, by API shape: no update or delete method exists
anywhere (TESTING §9/S5). One row per answer attempt, including
resurfaced attempts — exactly the input a future FSRS optimiser
needs (§R4.3).
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| question_id | INTEGER NOT NULL | deliberately NO foreign key — history survives question deletion |
| question_key | TEXT | the question's `sync_id` at review time (the FSRS regrouping key) |
| session_id | INTEGER | the `learn_sessions` row |
| reviewed_at | INTEGER NOT NULL | epoch ms |
| correct | INTEGER NOT NULL | 0/1 (auto-graded, or the honest self-grade for flashcard/cloze) |
| latency_ms | INTEGER | time from presentation to answer |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity; sync_id UNIQUE |

### `learn_sessions` (LEARN)
One row per session. Enjoyment lives here, never on questions
(§R6.1).
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| started_at / ended_at | INTEGER NOT NULL / INTEGER | ended_at NULL while running |
| finished | INTEGER NOT NULL DEFAULT 0 | 1 = reached the end screen; 0 = abandoned |
| kind | TEXT NOT NULL DEFAULT 'review' | `episode` / `review` / `boss` |
| topic_id | INTEGER → topics(id) ON DELETE SET NULL | NULL = mixed session |
| pack_id | TEXT | external pack id for episode/boss sessions |
| cards_total / cards_correct | INTEGER NOT NULL DEFAULT 0 | DISTINCT questions answered / of those, correct on first presentation |
| enjoyment | INTEGER | owner's 1–5 (§R4.6 frozen labels), NULL when not asked or skipped |
| enjoyment_reason | TEXT | optional ≤2-rating chip (Too hard / Too easy / Boring / Too long) |
| format_mix | TEXT | JSON: question type → first-presentation count (§R4B.3 enjoyment-by-format) |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity; sync_id UNIQUE |

A finished session activates its day's Done Score learning
block, derived by ReviewStore from the local date of `ended_at`
(D-024). It NEVER feeds the streak — counted-ness derives only
from the two locked signals (red-team #1).

### `packs` (LEARN, D-020)
The import registry: one row per imported pack id. §R6 lists no
such table, but §R4.4's re-import semantics need durable version
memory.
| column | type | notes |
|---|---|---|
| id | INTEGER PK AUTOINCREMENT | |
| pack_id | TEXT NOT NULL UNIQUE | the pack's external id |
| version / title / language | TEXT NOT NULL / TEXT NOT NULL / TEXT | from pack.json |
| topic_id | INTEGER NOT NULL → topics(id) ON DELETE CASCADE | the topic the pack was imported into |
| source_id | INTEGER → sources(id) ON DELETE SET NULL | the `kind='pack'` source holding the zip |
| arc | TEXT | JSON `{id, title, episode, episodeTitle, teaser}` (§R4B F1/F7) |
| question_count | INTEGER NOT NULL DEFAULT 0 | surviving questions of the current version |
| imported_at / updated_at | INTEGER NOT NULL | epoch ms |
| sync_id / updated_hlc / deleted_at_hlc | TEXT | sync identity; sync_id UNIQUE |

### Changed in v5
- `marked_points` += `question_id INTEGER → questions(id)
  ON DELETE SET NULL` — set when the engine mints the point's
  cloze question; minting skips already-linked points
  (idempotent).
- Sync identity: `questions`, `review_log`, `learn_sessions`,
  `packs` join `AppDatabase.syncableTables`.

## The quiz-pack format (`nimo.quizpack` v1) — the content contract

Packs are generated OUTSIDE the app (by an AI assistant from the
owner's PDFs/TXTs, §R4.4) and imported; this section is the
public contract those generators must target. Implemented by
`lib/features/learn/pack_format.dart` (structure) +
`pack_importer.dart` (container/media/questions) +
`question.dart` (per-type payload rules); the living example is
`test/fixtures/sample_pack.dart` (Arabic Greetings, 13
questions, every type).

Container: a zip (extension `.quizpack`) with `pack.json` at
the root plus media files:

```jsonc
{
  "schema": "nimo.quizpack", "schemaVersion": 1,
  "pack": { "id": "arabic-greetings-01", "title": "Arabic Greetings",
            "version": "1.0.0", "language": "ar",
            "author": "ai-assistant", "tags": ["arabic"],
            "sourceRef": "my-notes.pdf" },
  "media": [ { "id": "m1", "file": "media/hand.png",
               "mime": "image/png", "sha256": "<64 hex>" } ],
  "arc": { "id": "arabic-city-01", "title": "City Errands",
           "episode": 1, "episodeTitle": "Greetings",
           "teaser": "Tomorrow: the café owner argues about the bill" },
  "questions": [ /* typed payloads, §R4.1 — see question.dart */ ]
}
```

Question payloads: `mcq` (2–5 choices, exactly 1 correct in
v1), `flashcard` (front/back), `cloze` (text with `{{answer}}`
spans), `image_point` (media id + target `{cx, cy, r}`,
normalised, r ∈ [0.03, 0.25]), `ordering` (items +
correctOrder permutation), `scenario` (branch-and-bottleneck
graph: 2–5 nodes, 1–3 choices/node, every node reaches an end,
end nodes carry a summary), `mythfact` (statement + isFact +
explanation, D-022). Every question carries an `id` (unique in
the pack, NEVER recycled across versions), optional
`difficulty` 1–5, `explanation`, `hint`, `tags`.

Import rules (validate → import → report; untrusted input
throughout):
- **Pack-level rejects — nothing is written, no files, no
  rows:** zip > 50 MB; total declared uncompressed size
  > 50 MB; any entry name absolute, containing `..` (either
  separator), or duplicated; pack.json missing, unparseable,
  or failing structural validation (wrong schema/version,
  duplicate question ids, > 2,000 questions, a pack or media
  id that would change under filename sanitisation); any
  declared media missing, > 10 MB, mime outside
  {image/jpeg, image/png, image/webp, image/gif}, magic bytes
  not matching the declared mime, dimensions > 8192 per side
  or > 50 MP, or sha256 mismatch; zero questions surviving
  validation; re-importing an older version than the one on
  record.
- **Question-level skips (import proceeds; each skip is
  reported with its reason):** unknown type (§R4.4 — never
  fails the pack); payload failing validation; difficulty
  present but not an int in 1–5; image_point naming
  undeclared media.
- Files land at `packs/<pack.id>.quizpack` and
  `media/<pack.id>/<media.id>.<ext>` in the Library (all
  writes temp-then-rename); a `kind='pack'` source under the
  chosen topic holds the zip path.
- `image_point` questions import SUSPENDED with
  `verifyPending` in the payload: AI-proposed targets are
  often wrong (§R4.1), so the owner tap-verifies each target
  in-app before the question enters rotation.
- **Re-import:** same id + same version = no-op (validation
  still runs). Higher version = content updated in place:
  scheduler state (ef/reps/lapses/interval/due) and history
  are preserved per (pack.id, question.id); a verified
  image_point whose target or image CHANGED is re-gated
  (suspended + verifyPending, S5 review M2); questions the
  new version drops are suspended, never deleted — and if a
  later version re-adds one, it revives (S5 review S2).
  Version compare is dotted-numeric (`1.10.0` > `1.9.0`;
  a missing segment counts as 0).

## Payload shapes (JSON in `items.payload`)

- `note`: no payload (body text lives in `items.note`).
- `checklist`: no payload (entries live in `checklist_entries`).
- `link_card` (S4): `{"url": "...", "topic_id": <topics.id>,
  "thumbnail_name": "..."|absent, "thumbnail_source":
  "user"|"auto"|absent}` — `topic_id` links the card to its
  topic trigger (§R6.2); `thumbnail_name` is a file name in the
  app-cache `thumbs/` dir (absent → designed fallback card,
  D-003/D-019); `thumbnail_source` records which D-003 layer
  produced it, so auto-fetch can never replace a user-attached
  image (added in the S4 review loop).
- `html_quiz` (S5): `{"file_rel_path": "..."}` — the quiz file
  inside the Library `html_quizzes/` folder, relative (§R6.4
  discipline). Played by the legacy Android WebView player
  under a hardened navigation policy (`html_quiz_policy.dart`:
  only file:// URLs inside the quiz's own folder).

## Planned, NOT yet added (added by their stage's migration)

- (QUIZ, only if D-004 is revisited): `quiz_attempts`.

## S6 — no schema change (still v5)

Progress & Sunday added no tables and no migration. The weekly
summary is computed from stored data on demand — there is
deliberately no summary table (§R5.4). Reminders persist as
`app_settings` keys (data, not schema), all device-local and
never synced (`app_settings` carries no sync identity):
`reminder_morning_enabled`, `reminder_morning_time`,
`reminder_evening_enabled`, `reminder_evening_time`,
`reminders_last_open_ms`, `reminder_suggest_off`.

## Schema v6 (Stage S7) — sync machinery, all device-local

Four new tables; NO existing table changes. All four are
device-local machinery — their contents are never themselves
packaged (except `sync_conflicts` ROWS, which travel as an
append-only sync entity so both devices can display them).

### `sync_base` (SYNC)
The last-synced state per row — the merge base. Change
detection and 3-way merge are computed against it (D-029).
| column | type | notes |
|---|---|---|
| entity / sync_id | TEXT | PK (entity, sync_id) |
| content_hash | TEXT | sha256 of the canonical payload (below) |
| hlc | TEXT | stamp of the op that established this base |
| deleted | INTEGER | 1 = the shared state is "row deleted" |

The base is the last state BOTH devices are known to share. It
advances ONLY on import outcomes that apply a peer state
wholesale (fast-forward, remote win, converge, delete applied)
— never at export time, and never for a merge outcome the peer
has not seen yet (a local win, a merged day review), so the
winning state is carried by the next export. The export-time
advance was v6's original design and the independent S7 review
proved it broken (finding M1): when both devices exported
before either imported, each classified the peer's op as a
fast-forward against its own just-advanced base, the two edits
silently swapped with zero conflict copies, and both devices
believed they had converged. Export bookkeeping lives in
`sync_exported` instead (v7, below).

### `sync_exported` (SYNC, v7)
What this device last SENT per row: same shape as `sync_base`
(`entity` / `sync_id` PK, `content_hash`, `hlc`, `deleted`).
Export diffs current state against `sync_exported` (falling
back to `sync_base` for rows never exported) and records what
it sent here. Keeping "last shared" and "last sent" apart is
what makes the concurrent-export interleaving merge as
both-changed (LWW + conflict copy) instead of fast-forward.

### `sync_peers` (SYNC)
Per-device high-water marks: `device_id` PK, `last_export_hlc`,
`last_import_hlc`, `last_export_at`, `last_import_at`. With the
owner's two devices, the single `sync_base` IS the per-peer
base; a third device would need per-peer bases (noted limit).

### `sync_quarantine` (SYNC)
Ops held out of an import: `op_id` UNIQUE, `entity`, `sync_id`,
`hlc`, `payload` (JSON), `reason` (`future-hlc`, `future-date`,
`missing-parent`, `apply-error: …` — an op whose apply failed
at the database level, held per-op via savepoint so the rest
of its package still applies), `source_device`, `received_at`. Quarantined
ops are NOT recorded in `sync_ops`, so re-importing the same
package re-evaluates them; an op that later applies leaves
quarantine. Held ops are listed in Settings → Sync → Held.

### `sync_conflicts` (SYNC)
Visible conflict copies (§R7.2): `entity`, `row_sync_id`,
`kind` (`edit-edit`, `delete-vs-edit`, `major-point`,
`self-note`, `delete-with-unsynced-children`,
`append-only-divergence`), `field` (unused, reserved),
`kept_text` / `lost_text` (JSON payloads, or plain text for
major points), `created_at`. Born with sync identity
(`sync_id` UNIQUE + HLC columns): the rows sync as an
append-only entity.

### Changed in v6
- `syncableTables` still lists `shield_events` for identity
  backfill, but the sync engine's entity list EXCLUDES it (and
  `streak_state`): both are fold materialisations (S3 NOTE N1)
  and re-derive per device; import re-runs `ReviewStore.evaluate`
  whenever day-loop entities changed.
- Deterministic sync_ids for generated plan items (code, not
  schema): routine items `rt-<template sync_id>-<date>`, carried
  one-offs `co-<source item sync_id>-<date>` (§R7.2 dedupe).

### Changed in v8 (D-042)
- `plan_templates` += `weekdays INTEGER` (7-bit mask,
  Mon–Sun; NULL = every day), `item_id INTEGER → items(id)
  ON DELETE SET NULL`, `url TEXT` — weekday scheduling +
  one optional linked resource per task.
- `day_plan_items` += `item_id` / `url`, copied from the
  template at generation and from the source one-off at
  carry-over (code, tested both ways).
- Sync contract (code, not schema): `item_id` rides as
  `item_id_sync` via the `_Fk` mechanism on both entities
  and is registered nullable on import (missing resource →
  plain task, never quarantine); `weekdays` / `url` ride as
  plain fields; `syncEntityOrder` is parents-first for the
  new edge (items before plan_templates). `day_plans.created_at`
  is NOT synced — it is materialised on import from the op
  stamp (syncing it would make two devices that generated
  the same morning conflict over a bookkeeping value).

## The sync package format (`nimo-sync` v1) — the device contract

This format is a contract between the owner's two devices; both
run the same app version in practice, and the importer refuses
anything newer than it understands.

- File: `Library/sync/pkg-<deviceId[0..8]>-<exportSeq:06>.zip`,
  written temp-then-rename (red-team #8). Contents:
  `manifest.json` + `ops.json`.
- Manifest: `{kind: "nimo-sync", format_version: 1, device_id,
  export_seq, created_at, full, op_count, ops_sha256}` — the
  sha256 of the exact `ops.json` bytes; import verifies digest
  AND op count before touching the database.
- Op: `{op_id, entity, sync_id, op: "upsert"|"delete", hlc,
  fields?}`. `fields` is the canonical payload: the entity's
  content columns in fixed order (per-entity list in
  `sync_store.dart` `_specs`), with every foreign key replaced
  by the parent's sync_id under `<column>_sync` (local integer
  ids never cross devices). Two payload exclusions are
  deliberate: `day_reviews.is_counted` (a fold cache, red-team
  #17 — re-derived) and `day_plans.created_at` (per-device
  bookkeeping; including it would manufacture a conflict for
  every shared morning).
- Change detection (D-029, corrected by S7 review M1/D-033):
  an export canonicalises + hashes every syncable row and
  diffs against `sync_exported` ∪ `sync_base` (the last state
  SENT for the row); vanished rows become delete ops; what was
  sent is recorded in `sync_exported`, never in the base. The
  op stamp is the row's own `updated_hlc` when a store stamped
  one after the row was last sent (edit time — LWW compares
  edit times), else a fresh export-time HLC. (The baseline
  matters: the export recording writes the op stamp back into
  `updated_hlc`, so comparing against anything older would
  mistake that echo for an edit stamp and freeze re-exports at
  the first export's stamp.)
- Identity adoption beyond sync_id: `day_reviews`/`day_plans`
  match by date; `packs` match by `pack_id` and `questions` by
  (`pack_id`, `pack_qid`) — both devices importing the same
  `.quizpack` file independently (it travels in the Library)
  mint different row sync_ids for the SAME pack, and without
  adoption the cross-import would collide on the UNIQUE
  `pack_id` and strand the package (S7 review M3). Routine
  plan items adopt by their full natural slot (S3 fix).
- Merge (import, one transaction, all-or-nothing): per entity —
  append-only union (review_log, learn_sessions, sync_conflicts);
  day_reviews/day_plans by natural key (date); day-plan items
  within their date (deterministic ids; a pure `done` divergence
  merges LWW with no copy — a toggle's last action is the
  intent); everything else 3-way vs base with LWW + conflict
  copy of the loser. day_reviews additionally preserves a
  differing losing `self_note` as a `self-note` conflict copy
  (hand-written text is never dropped silently; the score
  fields stay winner-take-all). Deletes are tombstone ops;
  delete-vs-edit keeps the later stamp and copies the loser.
  A delete whose subtree contains a descendant this device
  created or edited since the base is NOT cascaded — it is
  held as a `delete-with-unsynced-children` conflict and the
  subtree stays (S7 review M4). Stale-package guard: an op
  whose stamp does not postdate the base it is merged against
  is skipped and counted (`stale` in the import report), so
  importing an older package after a newer one never rolls a
  row backwards (S7 review S2; the field-wise day_reviews
  merge is exempt — it is idempotent by construction). Known
  edge: a delete op carries no fields, so it cannot be matched
  by natural key — a delete aimed at a day-keyed row this
  device holds under a different sync_id no-ops locally; the
  row later re-exports under its own id and the deleter
  resurrects it with a conflict copy (visible, not silent).
- Quarantine (red-team #7): op HLC wall or a day-keyed date more
  than 1 day in the future is held, never applied. Receiver
  clamping: the local HLC state advances by peer stamps clamped
  to local wall time.
- Idempotence: applied `op_id`s are recorded in `sync_ops`;
  re-import is a no-op. Package defences: 64 MB compressed
  cap, DECLARED entry sizes checked before decompression
  (zip-bomb guard), zip-slip rejection, digest + op-count
  verification, HLC stamps format-validated (an unvalidated
  stamp could bypass the clock quarantine and win every LWW
  comparison lexicographically). (The backup format uses the
  same construction with a 1 GiB cap.)

## Migration history

| version | stage | change |
|---|---|---|
| 1 | S1 | workspaces, projects, items, checklist_entries |
| 2 | S2 | plan_templates, day_plans, day_plan_items, goals, app_settings; workspaces += pinned |
| 3 | S3 | day_reviews, streak_state, shield_events, sync_meta, sync_ops; plan_templates += starter_title/anchor_text/track/counts_core; day_plan_items += counts_core (snapshot, D-013); goals += track; sync identity columns + sync_id unique indexes on all syncable tables (§R6.3) |
| 4 | S4 | topics, sources, marked_points (all with sync identity); day_reviews rebuilt so major_point_topic_id is a real FK → topics(id) ON DELETE SET NULL |
| 5 | S5 | questions, review_log, learn_sessions, packs (all with sync identity); marked_points += question_id → questions(id) ON DELETE SET NULL |
| 6 | S7 | sync_base, sync_peers, sync_quarantine, sync_conflicts (all device-local machinery; no existing table changes) |
| 7 | S7 review | sync_exported (last-sent state per row, split from sync_base so export never advances the shared base — review finding M1, D-033) |
| 8 | D-042 | plan_templates += weekdays / item_id → items(id) SET NULL / url; day_plan_items += item_id / url (all additive, no backfill; links copied at generation + carry-over; item_id syncs as item_id_sync) |

# Decision Log — Daily Life App

One entry per decision: what was chosen, why, and what it replaced.
Entries are never edited after the fact — a changed decision gets a
new entry that supersedes the old one (EDITING_GUIDE rule 3).

## Decided

- **D-001 (2026-10-29) — Docs-first, staged execution.** The app is
  built in stages (PLAN.md §5) with per-stage acceptance checks, and
  every change follows EDITING_GUIDE.md with docs updated in the same
  change. *Why:* the app will be edited frequently over a long period;
  the docs + feature map are what keep it editable.
- **D-006 (2026-10-29) — Stack: Flutter (Dart) + SQLite.** Confirmed
  by owner ("go with them"). Reuses the owner's Quiz Learning App
  experience and patterns. Toolchain is installed under `~/` (not
  `/usr`) so it survives VM replacements — lesson from the REA wipe.
- **D-003 (2026-10-29) — Reel thumbnail strategy: layered.** Confirmed
  by owner: auto-fetch attempt → designed fallback card →
  user-attached image. A card must never render broken.
- **D-002 (2026-10-29) — Unticked items: carry-over default.** Under
  the owner's blanket go-ahead, proceeding with: one-off tasks carry
  to tomorrow automatically until ticked or deleted; routine template
  items regenerate fresh each day (yesterday's unticked routine items
  do not pile up). *Flagged as a default — owner can override before
  S2 starts.*
- **D-004 (2026-10-29) — Quizzes: play-only for v1.** Under the same
  go-ahead: no attempt/score table in v1; the QUIZ map row keeps
  `quiz_attempts` as an optional later addition (adding it later is a
  new migration, no breakage). *Overridable before S4.*
- **D-005 (2026-10-29) — Backup: manual export/import for v1.** One
  backup file, owner-triggered. Automatic backup can be revisited at
  S6. *Overridable before S6.*
- **D-008 (2026-10-30) — Design plate: B "Midnight" (dark).** Three
  plates were implemented as real themes (`AppPlate` in
  `lib/core/theme.dart`) with Widget Previews of the Today, Reels
  and Workspaces bodies in each (`lib/features/design_preview/`):
  A "Calm Focus" (light, indigo #3D5AFE, radius 24), B "Midnight"
  (dark AMOLED #0B0E14, teal #2DD4BF, radius 20), C "Warm Paper"
  (cream #FAF5EC, terracotta #D96C3D, serif display, radius 16).
  The owner viewed all three in a chat preview and picked **B** —
  they like dark mode. `main.dart` now defaults to
  `AppTheme.forPlate(AppPlate.midnight)`; S2/S3 screens are built
  dark-first. Plates A and C remain in the theme file as documented
  options (a light-mode option can be revisited later).

- **D-007 (2026-10-29) — Launcher icon: vector adaptive icon, no
  binary assets.** Owner chose the connector push route for the
  GitHub repo (AsifXdroid/Nimo-Os); that route accepts text files
  only, so the five generated `mipmap-*/ic_launcher.png` files were
  replaced by `mipmap-anydpi-v26/ic_launcher.xml` (adaptive icon:
  `drawable/ic_launcher_foreground.xml` — rounded square + check on
  the theme seed colour, `values/colors.xml`). Trade-offs accepted:
  on API 24–25 (pre-adaptive-icon) devices the launcher falls back to
  a generic icon; a designed custom icon can replace this later —
  if it is a PNG set, that push must go through real git, not the
  snapshot route.

- **D-009 (2026-10-30) — Home layout: "Hub Home".** The owner was
  shown two viewable mockups — the minimal "Focus" layout (plan +
  goals only) and the richer "Hub Home" — and picked Hub Home.
  Home sections, in order: header (date, greeting; search and
  settings icons shown as disabled "Coming soon" placeholders —
  global search is S5, settings S6), week strip (Mon–Sun, pending
  dots, tap a day opens the This-week view), quick-add row (Task /
  Goal / Note / Checklist), today's plan card with a Today | This
  week segmented control, pinned spaces, recent items, goals, and a
  Customize Home dialog (per-section visibility persisted in
  `app_settings`). The app shell is a 3-tab bottom NavigationBar:
  Today · Spaces · Goals.

- **D-010 (2026-10-30) — Research report approved; stages S3–S8
  supersede old S3–S6.** The owner commissioned and approved the
  overnight research report
  (`~/workspace/goals/daily-life-android-app/files/RESEARCH-2026-10-30.md`,
  incl. quality pass + red-team review). Its feature list v2 (§R10.1)
  is now the feature contract, and the re-sequenced stages S3–S8
  (§R10.2) replace the old PLAN S3–S6 (reel cards / HTML quizzes /
  goals & polish / safety net). Key locked mechanics the stages must
  implement as specified: the daily loop (plan → grow → review) is
  the heart; Day Close + dual scores (Done auto / Self, never
  merged); Streak Shields (a day counts ONLY via core plan done OR
  Day Close done — exactly two signals); learning measured by
  enjoyment, not minutes; content via owner-supplied sources and
  externally generated quiz packs; schema v3 carries sync identity
  columns early; sync is staged LAN-only (Stage A files + "Sync
  now" packages, Stage B auto) and the live SQLite file is never
  file-synced. The owner also granted a standing go-ahead
  (2026-10-30) to build S3→S8 stage by stage with a
  build → review → fix loop and full docs updates, without waiting
  for per-stage approval.
- **D-011 (2026-10-30) — Repair-sync overwrite guard (applies at
  S7).** From the approved report's red-team MUST-FIX #3: a snapshot
  "Repair sync" restore must never silently overwrite a device
  holding newer unsynced data. Decided: BOTH guards — (1) an
  automatic pre-restore backup is always taken before a snapshot
  import/restore, and (2) restoring over a non-empty database
  requires an explicit "this replaces everything on this device"
  confirmation. Restoring into an empty database is the fast path
  (guard 1 still applies). Until implemented this way at S7, Repair
  sync must not ship.
- **D-012 (2026-10-30) — First shield is granted when a run reaches
  7 (S3 review S1).** §R5.3's narrative ("at 7 the app says 'You've
  earned protection'") and the owner's round-3 summary ("from day
  7 up to 2 shields") conflict with the report's pseudocode, whose
  refill-only rule would deliver the first shield on day 14.
  Decided for the narrative: when a run first reaches streak 7 and
  no shield is held, 1 shield is granted immediately (re-arms after
  a reset); the pseudocode's refill rule (1 per 7 counted days
  while protected, max 2 held, max 2 shield-days per ISO week)
  governs all later shields. Recorded because the S3 reviewer found
  the divergence implemented but undecided; the behaviour is pinned
  by streak tests and matches the owner's stated model.
- **D-013 (2026-10-30) — Core-ness is snapshotted onto plan items
  (S3 review M1).** The streak's core signal must be stable under
  routine edits: `day_plan_items.counts_core` copies the template's
  flag at plan generation, and the fold reads only the snapshot.
  Editing a template's counts_core — or deleting the template —
  affects future days only (the routine editor's stated contract),
  never past counted-ness; "totals/best never reset" (§R5.3) holds
  by construction.

- **D-014 (2026-10-30) — Marked points are their own table.**
  §R4.5's "point" (a sentence + key span, marked while reading)
  is stored in `marked_points`, not minted into `questions` at
  mark time. S5's Learn engine mints questions from these
  records, so the act of marking stays a pure capture (no quiz
  decisions while reading), and one point can feed several
  question formats later.
- **D-015 (2026-10-30) — Library root resolution.** The Library
  lives at `<app documents>/Library` by default; an
  `app_settings.library_root` value (plain path) overrides it —
  the laptop route of §R6.4, and what tests use. The DB only
  ever stores Library-relative paths, so moving the folder (or
  syncing it elsewhere) never breaks a source.
- **D-016 (2026-10-30) — D-011's guard is implemented in S4 for
  backup restore.** Both halves, enforced at the store level
  (not just the UI): an automatic pre-restore backup is always
  taken first, and restoring over a non-empty database requires
  the explicit replaces-everything confirmation; restoring into
  an empty database is the fast path. "Non-empty" counts every
  root content table including `day_plans` (S4 review fix). This
  entry records the implementation D-011 anticipated for S7;
  D-011 itself still binds Repair sync at S7 unchanged.
- **D-017 (2026-10-30) — Mark-a-point validation rules (§R4.5).**
  A mark is stored only when: the span occurs inside the
  sentence; the span is at most 8 words; there is at most one
  mark per (source, reading card); and the same sentence is not
  already marked for that source (compared case- and
  whitespace-insensitively). Violations raise
  `MarkedPointException` and write nothing — a half-valid mark
  would poison S5's question generation.
- **D-018 (2026-10-30) — TXT decoding is strict UTF-8 in S4;
  the §R4.5 fallback encoding is deferred, knowingly.** TXT
  sources decode as UTF-8 (BOM stripped); undecodable bytes
  land as `extraction_status = failed` with the file retained —
  never silently imported as mojibake. §R4.5 asks for a
  fallback encoding (e.g. Windows-1256 for Arabic sources) on
  decode failure. Deferred to a later stage: Dart has no
  built-in cp1256 codec, and a hand-written mapping table that
  cannot be verified here risks producing exactly the garbled
  text the rule exists to prevent. Until then the recourse is
  the same honest one as for scanned PDFs: read/convert the
  file elsewhere. Flagged as an open spec gap by the S4 review.
- **D-019 (2026-10-30) — Link thumbnails live in the app cache.**
  Thumbnail files sit in app-private cache storage (`thumbs/`),
  not the Library: they are regenerable and stay out of the
  synced/backed-up tree. The item payload stores only the file
  NAME plus its D-003 provenance (`thumbnail_source`:
  user/auto), so a restored payload can never point outside
  the cache and auto-fetch can never demote a user image.
- **D-020 (2026-10-30) — A `packs` registry table exists (S5).**
  §R6 lists no table for imported packs, but §R4.4's re-import
  semantics (same version = no-op, higher version = update in
  place, never reset scheduler state) need durable version
  memory per pack id. One row per pack id: version, title,
  language, topic link, the `kind='pack'` source link, and the
  arc JSON. A deliberate, recorded deviation from §R6's list.
- **D-021 (2026-10-30) — End-state navigation resolved
  (red-team #11).** Final layout: **Today · Learn · Progress ·
  Spaces · Goals** (§R2.3's screen proposals + §R2.4's rail
  order). S5 ships four destinations (Today · Learn · Spaces ·
  Goals) in a data-driven shell keyed by destination id; S6
  inserts Progress between Learn and Spaces with no
  restructure. The mockup-first gate is lifted by D-010's
  standing go-ahead, so the approved report's own layout is
  the design of record.
- **D-022 (2026-10-30) — Myth-vs-Fact is its own question
  type (`mythfact`).** §R4B.5 #2 allowed either a type or a
  rendering mode of true/false MCQ. Chosen: own payload
  `{statement, isFact, explanation}` — one validation rule
  set, one card widget; MCQ stays purely MCQ.
- **D-023 (2026-10-30) — Session composition quotas read
  §R4.2's three buckets literally.** ~55% due reviews, ~20%
  previously-missed (a subset of due, given its own bucket),
  ~25% new; shortfalls back-fill due-first, then new. Boss
  sets compose from due + new sorted by difficulty (the
  hardest material he has, §R4B #5's "hardest due items"
  read to include hard new cards from the arc's pack).
  Implemented in `session_composer.dart`.
- **D-024 (2026-10-30) — Session attribution + enjoyment
  timing.** A finished session activates its day's Done Score
  learning block by the local date of `ended_at`; ReviewStore
  derives it inside closeDay and refreshDoneScoreIfClosed, so
  Day Close, Hub plan edits, and session completion all stay
  consistent — and the streak derivation is never touched
  (red-team #1). Enjoyment is asked only on natural
  completion, never on abandon (an interrupted session is not
  the moment to interrogate), always before stats (§R9.9
  #11). The teach-back end-card (F8) appears on episode
  sessions only.
- **D-025 (2026-10-30) — Boss-level hints: the softened
  default (red-team #10).** Boss sessions run hints-off with
  ONE unscored hint available per session (MCQ: names one
  wrong choice to eliminate; other types: the payload's
  authored `hint`). Using it never changes grading, and boss
  sessions are one-pass — misses do NOT resurface in-session
  (S5 review S3); they return via the scheduler at 1 day,
  stated plainly on the end screen (§R4B.4).
- **D-026 (2026-10-30) — Cloze grading is reveal-and-self-
  grade in v1.** §R4.1 offers exact/normalised match or
  self-grade. Minted cloze comes from the owner's own marked
  points, where honest self-grading (the flashcard rule)
  fits; typed-answer grading can be added per card later
  with no schema change.
- **D-027 (2026-10-30) — Pack media dimension caps (S5).**
  Import rejects any image over 8192 px per side or
  50 MP total, read from the file header at import time
  (PNG/JPEG/GIF/WebP), per TESTING §7's MASVS-CODE row: a
  small hostile file declaring huge dimensions would
  otherwise be fully decoded at play time and OOM the app.
- **D-028 (2026-10-30) — Charts are hand-rolled painters, no
  `fl_chart` (S6).** §R3/§R10.2 named `fl_chart` for the
  dual-score and enjoyment charts; S6 shipped hand-rolled
  `CustomPainter`s instead (~150 lines in
  `lib/features/progress/charts.dart` for two line series and
  a scatter): the app needs exactly two series styles on a
  fixed axis set, theme tokens map 1:1 onto painter colours,
  and a chart package would add dependency surface plus its
  own theming fight for glanceable axes. Revisit only if a
  chart needs interaction (scrubbing/zoom) the painters can't
  cheaply do. (Cited by `charts.dart` from the build; the
  entry itself was recorded at S6 close-out — the citation
  preceded the record, S6 review S2.)

- **D-029 (2026-10-30) — Sync change detection is a state diff
  against `sync_base`, not a store-written op log (S7).** §R7.2
  describes packages as "ops since the peer's last acknowledged
  sequence", but the S3 scaffold's `sync_ops` was never written
  by any store, and only the S4/S5 stores stamp `updated_hlc`.
  Retrofitting op-writing into every store would have touched
  all of S1–S6 for S7's sake. Instead: export canonicalises
  every syncable row (FKs as parent sync_ids), hashes it, and
  diffs against `sync_base` (the last state both devices are
  known to share); vanished rows become delete ops. Import is a
  3-way merge (base/local/remote), which is what makes
  §R7.2's conflict copies possible. Consequences, accepted:
  op stamps are the row's own edit stamp where a store stamps
  one, else export-time (conflict copies backstop the
  difference); op granularity is per-row, not per-field (except
  day_reviews' score/point split and plan items' done flag,
  which §R7.2 names explicitly). Base-advance discipline (found
  in S7 testing): the base advances only to a state the peer is
  known to hold; a local merge win never advances it, or the
  winner would never travel and the devices diverge for good.
- **D-030 (2026-10-30) — Linux desktop verification level (S7).**
  The VM has the GTK3 runtime but no GTK3 development files,
  and apt there cannot supply them (toolchain/NOTES.md #7), so
  the Linux GUI build cannot complete in the VM. Verified here:
  `linux/` scaffolding (Android untouched), analyze clean, and
  the full test suite green against the FFI database factory —
  the same factory + SQLite path the Linux build runs. The GUI
  build itself runs on the owner's Arch laptop
  (`toolchain/build_linux_on_laptop.sh`, one pacman line).
  Desktop behaviour as built: share-intent absent (Android-only
  plugin, gated in main); HTML quizzes open in the system
  browser (§R8.4 fallback); reminders are inert on desktop —
  the generated Linux plugin registrant does not include
  flutter_local_notifications at all, so scheduling silently
  no-ops (the Settings copy already told the owner the phone is
  the reminder device; the gateway's failures are caught and
  can never block boot).
- **D-031 (2026-10-30) — S7 test strategy: seeded model-based
  harness, no new test packages.** TESTING.md §3.4 named
  `property_testing` ^0.2.1 as a candidate for stateful merge
  tests and §4.1 named `mocktail` for a fake sync peer. S7 uses
  neither: the merge is exercised by a seeded-`Random` two-real-
  database harness (the doc's own stated fallback — real DBs
  beat fakes for store behaviour, §4.1's first principle), and
  Stage A has no transport to fake (packages are files).
  `mocktail` stays the named candidate for S8's LAN transport.
  Mutation spot-checks landed as named boundary tests instead:
  quarantine horizon (exactly +1 day applies, +1 ms is held)
  and the zero-padded HLC comparator (counter 9 vs 10).

- **D-032 (2026-10-30) — A restored database is adopted, not
  impersonated (S7 review S2).** Snapshot restore (Backup or
  Repair) replaces the whole database file, including the
  source device's `device_id`, `sync_base`, peer high-waters and
  export sequence. On the next boot after a restore, the app
  resets that bookkeeping (`SyncStore.adoptRestoredDatabase`,
  wired in main's restore path): fresh device_id, sync_base /
  sync_peers / sync_quarantine cleared, export sequence reset;
  `sync_ops` dedupe history and `sync_conflicts` content are
  kept, and all row sync_ids survive (data identity ≠ device
  identity), so the device re-publishes its state as a full
  package and peers converge without duplicates. Accepted
  consequence, stated in SYNC_SETUP: deletions the peer made
  after the snapshot was taken reappear — a snapshot cannot
  contain them.

- **D-033 (2026-10-30) — "Last shared" and "last sent" are
  separate sync state (S7 independent review, round 2).** The
  review's full report landed after S7's first close-out and
  carried four probe-verified MUST-FIX findings; this decision
  records the structural one, the rest are rule completions
  documented in DATA_MODEL's package-format section:
  - **M1 → schema v7 `sync_exported`.** v6 advanced `sync_base`
    at export time; with both devices exporting before either
    imported (the normal folder-sync interleaving), each
    importer saw `local == base` for its own edit and applied
    the peer's op as a fast-forward: the edits silently
    swapped, zero conflict copies, permanent divergence. The
    base now advances ONLY on import outcomes that apply a
    peer state wholesale; export diffs and records against
    `sync_exported`. Corollary fix: the op-stamp reuse rule
    compares the row's `updated_hlc` against the last SENT
    stamp, not the base — the export recording writes the op
    stamp back into the row, and against a lagging base that
    echo froze re-exports at their first stamp (caught by the
    pre-existing edit-edit test).
  - **M2:** `syncEntityOrder` is parents-first in fact, not
    just in comment (`projects` before `topics`); the Held
    dialog explains each hold by its own reason.
  - **M3:** `packs` adopt identity by `pack_id`, `questions`
    by (`pack_id`, `pack_qid`) — independent pack imports on
    both devices are an expected flow. Backstop: a per-op
    SAVEPOINT turns any unforeseen apply-time constraint
    failure into an `apply-error` quarantine of that one op
    instead of a permanently unimportable package.
  - **M4:** a delete never cascades over a descendant that
    differs from its shared base; it is held as a
    `delete-with-unsynced-children` conflict instead.
  - Also: stale-package guard (an op not newer than its base
    never rolls a row back; day_reviews exempt — idempotent
    field merge), day_reviews `self_note` conflict copies,
    declared-size zip checks before decompression, HLC format
    validation, per-file tolerance in folder import, desktop
    database under the application-support directory (the FFI
    default is CWD-relative), and a writability probe before
    a picked Library folder is persisted.

- **D-034 (2026-10-30) — Share-intent capture is in-house; the
  `receive_sharing_intent` plugin is removed.** Every published
  version is defective under this project's toolchain (1.9.0
  declares compileSdk 37 → `checkReleaseAarMetadata` failure;
  1.8.1 declares neither JVM target → Java 11 / Kotlin 17
  mismatch at target validation; both apply the Kotlin Gradle
  Plugin that future Flutter versions hard-fail). The owner
  chose the proper fix over a Gradle force-override.
  Implementation: `MainActivity` decodes ACTION_SEND /
  ACTION_SEND_MULTIPLE itself and serves the unchanged
  `ShareIntentService` contract over the
  `app.dailylife/share_intent` channels (`AppShareIntentService`
  in `capture_service.dart`). Scope held to what the app
  actually used: text shares (bare URLs still upgrade to links
  in Dart) and file shares (copied to the app cache; the
  Library imports promptly, as before). The plugin's unused
  extras (video thumbnails/durations, ACTION_VIEW handling) are
  NOT reproduced. One deliberate improvement: a warm share that
  arrives before Dart listens is buffered natively and flushed
  on listen, where the plugin dropped it.

- **D-035 (2026-10-30) — Brand: Route A colours; the mascot is a
  static logo, never a character.** The owner supplied a Nimo
  brand board (lavender soft-3D mascot, wordmark, tagline
  "a little better, every day") and decided: (1) **Route A** —
  lavender/plum belongs to the brand only; teal stays the
  functional UI accent; D-008 and the Neo-dark colour system are
  NOT reopened. Lavender is never a button/progress/selection/
  state colour. (2) The mascot is used as **one consistent static
  logo** — header top-left, launcher icon, brand areas — with
  **no expressions, poses, character states, contextual
  reactions, Rive/Lottie, or mascot celebrations**. This
  supersedes the motion spec rev. 1's expression mapping in
  full. (3) The premium motion work (animated counts/bars, warm
  Tier-2 feedback for session end + Day Close, Tier-3 goal
  celebration, skeletons, ambient Today header) proceeds
  **independently of the mascot**, built from colour, copy and
  motion only, framework widgets only (no animation package).
  Dark-surface rule: the board's plum wordmark is unreadable on
  AMOLED, so in-app branding = Face Mark + "Nimo" in the theme's
  on-surface colour; plum wordmark is for light surfaces only.
  Assets prepared (not yet in the app): `files/logo-assets/` in
  the goal workspace — board crops, flat vector Face Mark + Leaf,
  monochrome silhouette for Android 13 themed icons, Android
  vector drafts. The icon set lands via real git at
  implementation (binary files, D-007). Full spec:
  `MOTION_AND_MASCOT_SPEC-2026-10-30.md` rev. 2 in the goal
  files.

- **D-036 (2026-10-30) — The Neo UI is implemented, in dark AND
  light; D-035's logo lands with it. Motion is NOT included.**
  Owner-approved implementation (2026-10-30 21:56 IST) of the
  redesign exploration's Candidate D direction, scoped by the
  owner's repeat-back approval: Neo UI + static logo, motion
  explicitly left out (the MOTION spec stays paper-only).
  What shipped in code:
  - **Theme system rebuilt in `lib/core/theme.dart`:** Neo
    tokens as the single source — `Space` (4pt scale s1–s12 +
    `page` margin 20 + touch 48), `RadiusToken` roles
    (8/12/18/24/round), semantic colours per brightness. `Gap`
    survives as aliases onto the Neo steps, so existing screens
    read on the Neo grid without a rewrite. Two full themes:
    `AppTheme.neoDark()` (Neo-dark, Midnight base — D-008's
    dark-first choice becomes the default theme MODE) and
    `AppTheme.neoLight()` (Neo light surfaces #EEEDF0 family).
  - **Route A in both themes (per the approved assumption):**
    teal is the functional primary in dark (#2DD4BF) and light
    (deepened #0B7263 for contrast). Neo light's original plum
    functional accent (#756181) is NOT used — lavender/plum is
    brand-only, exactly as D-035 locked. Surfaces flattened
    (card = radius 24 + 1px outline, elevation 0) per audit §D3.
  - **Theme switch:** Settings → Appearance segmented Dark/Light,
    persisted in `app_settings.theme_mode`, read at bootstrap,
    applied via MaterialApp themeMode; default dark. No system
    option (dark-first by decision).
  - **Static logo:** `lib/core/brand.dart` draws the Face Mark
    as vector shapes (CustomPainter — no raster asset, so it
    travels the text-only snapshot route). Placements: Today
    AppBar top-left (`NimoBrand`: mark + "Nimo" in on-surface
    colour, per D-035 §1.3) and the Settings brand footer
    (mark + wordmark + "a little better, every day").
  - **Launcher icon:** D-007's check-mark vector replaced by the
    Face Mark vector foreground; background #2F6B4F retired for
    the brand's deep lavender-plum #38304F; a monochrome layer
    (silhouette, eyes knocked out, even-odd) added for Android
    13+ themed icons. App label is now "Nimo" (was
    "daily_life_app"); MaterialApp title likewise.
  - **Page-margin pass:** the five tab screens' + Settings' root
    lists now use the Neo `page` margin (20) horizontally.
  - **Untouched, deliberately:** all stores, data, sync, the
    pdfrx reader internals, every screen's structure and copy
    (except the Today AppBar brand), and the whole motion spec.
    The redesign candidates A/B/C were NOT picked — Neo's design
    language was implemented over the app's existing D-021
    navigation and layouts, which Neo itself shares.
  - Verification: analyze clean; full suite 492/492 (6 new
    D-035/D-036 tests: theme colours/Route A in both modes,
    shape/type discipline, choice persistence mapping, brand
    rendering in both themes, Settings switch callback);
    build-risk scan clean (no dependency/Gradle changes).

- **D-037 (2026-10-30) — The Neo screens are actually built:
  every screen rebuilt to the Neo prototype's composition,
  components and copy, on top of D-036's token layer.** Owner
  correction (2026-10-30 22:26 IST): D-036 shipped tokens,
  colours, logo and margins over the UNCHANGED S2–S7 layouts —
  that was not the "implement the new UI" the owner asked for.
  Owner instruction (22:33 IST): "Build them one by one and
  then push it." This entry records what the rebuild did and
  the interpretation calls it required, so the owner can
  reverse any of them cheaply.
  - **Component kit (`lib/core/neo_ui.dart`, new):** raised
    panels and raised-sm cards with per-brightness shadows
    taken from the two prototype files' `--raised` /
    `--raised-sm` values (light = true neumorphic dual shadow;
    dark = soft black drop + faint highlight + 1px outline
    ring); inset wells approximated with a top-left inner-shade
    gradient + outline (Flutter has no native inner shadow);
    page-title block (eyebrow + headline + sub), section heads
    with quiet text actions, inset progress tracks, 29px
    checkbox squares, tags, tint notices, glyph tiles, hairline
    list rows, score wells, chips, round stepper buttons.
  - **Screens rebuilt to the prototype's composition and
    editorial copy:** Today (greeting intro + streak pill,
    plan panel with Neo checks, plum learning card, score
    wells, Day Close card, goal strips), Learn (page title +
    learning-pulse panel), Topics + Topic detail, Progress
    (Journey Path kept; the two-signals streak notice verbatim;
    dual-score panel; calendar panel), Weekly summary, Spaces
    (workbench: space cards, in-page project accordions,
    recently-touched panel), Projects, Items, Item detail,
    Goals (cards + steppers + direction-not-deadline aside),
    Settings (titled panels + a quiet privacy panel). Sub-
    screens dressed in the same language: Routine (incl. the
    if–then prompt panel), Day Close (panels, score-well
    reveal, never-averaged notice), Session (track + tag,
    enjoyment screen, stats), Reading (raised reader paper),
    PDF (engine untouched; theme only), image-verify list,
    share-confirm sheet, sync status well.
  - **Interpretation calls (owner did not answer the two
    questions put to them at 22:26; each is reversible):**
    1. **Accent: teal stays functional in BOTH themes.** The
       approved D-036 repeat-back explicitly flagged the plum
       assumption and was approved without requesting plum;
       neither the 22:26 complaint nor the 22:33 instruction
       mentions colour. Route A (D-035) stands. One theme
       token flips this if the owner wants faithful plum.
    2. **Surfaces follow the two prototype files** (neumorphic
       light, outline-drop dark) — the 22:26 complaint
       overrides the repeat-back's "flattened" line, which was
       part of what went wrong in D-036.
    3. **The learning card keeps the prototype's plum #62536F
       in both themes** — both files keep it literally; it is
       a content panel, not the functional accent.
    4. **App data beats prototype where they conflict:** Done
       Score stays 0–100 and Self Score 1–10 (score.dart
       formula v1); the prototype's /10-for-both was NOT
       adopted. Score wells take the scale as a suffix.
    5. **Learn pulse third number is packs-in-library, not the
       prototype's enjoyment average** — the engine store
       exposes no enjoyment-average API; enjoyment trend lives
       in Progress, where session data is aggregated.
    6. **Goal steppers now disable at their bounds** (0 and
       target); previously the buttons were always enabled and
       the store clamped. Same outcomes, clearer affordance.
  - **Copy changes that moved tests:** Day Close step 2 is now
    "Name one thing worth remembering."; the reveal labels are
    "Done score · auto" / "Self score · yours" with the Done
    value rendered "N / 100"; Learn's pulse labels are "due to
    revisit" / "new to explore"; Progress's journey card is
    "Your journey path". Affected tests updated to match —
    behaviour assertions unchanged.
  - **Untouched, deliberately:** all stores, data model, sync
    engine, session/Day Close flows and step order, the pdfrx
    PDF engine, navigation (D-021), and the whole motion spec
    (still paper-only, per the owner's exclusion).
  - Verification: `flutter analyze` clean; full suite
    **492/492** (no tests added or removed; expectations
    updated for the copy above). No dependency or Gradle
    changes, so the build-risk surface is unchanged from
    D-036's green CI run.

- **D-038 (2026-10-31) — Visual-harmony refinement programme
  (six stages), incorporating an audit correction and the
  Hallmark skill.** The owner supplied a UI/UX refinement
  brief and then approved the assistant's audited revision of
  it (2026-10-31 10:16 IST), with clarifications:
  - **Brief §4.1's premise was FALSE and is replaced.** The
    brief claimed the app relies on a decorative handwritten
    typeface; verified against the code, the app has never
    shipped a custom font (no font assets, no font packages,
    `fontFamily` only in the unpicked Plate C preview). The
    impression came from generated design concepts. Typography
    work therefore BUILDS a role system on the system sans —
    no bundled font, no runtime font fetching (a bundled
    display font is a separate future decision with its own
    asset-delivery route; binary assets cannot travel the
    connector snapshot route, D-007).
  - **Surface hierarchy approved (supersedes D-037's
    panel-everything outcome):** Level 0 canvas-direct
    sections, Level 1 content surfaces (flat or raised),
    Level 2 emphasis. Borders/shadows opt-in, not universal.
  - **Learning card (supersedes D-037 call 3):** the literal
    #62536F plum block is replaced in Stage 2 by a restrained
    plum treatment / neutral surface with lavender branding.
    Stage 1 already moved its colours into tokens
    (`FeatureColors`).
  - **Motion REOPENED (supersedes the D-036/D-037
    exclusions):** Stage 6 implements the rev. 2 motion spec —
    numeric transitions, progress animation, tick
    micro-transitions, skeletons, warm session/Day Close
    feedback, one major goal-completion celebration,
    reduced-motion support. Mascot stays a static logo; no
    expressions, poses or character animation (§5 of the
    owner's clarifications).
  - **Stage order:** 1 foundation → 2 Today → 3 Learn /
    Progress / Spaces / Goals → 4 Settings → 5 theme parity →
    6 motion + accessibility. Per stage: analyze + full suite
    + report + in-chat preview where possible + push. Real
    device screenshots are the owner's (the VM cannot render
    the app). All business rules untouched.
  - **Stage 1 (this entry's implementation):** `AppType` role
    system in theme.dart (display / pageTitle / sectionHeading
    / cardHeading 16·w600 NEW / body / caption / eyebrow /
    statistic-tabular / technical 13), built on D-037's values
    (body 15/16 kept; line heights added; action labels w600);
    `AppIconSize` roles (18/20/24); `NeoSurfaceLevel`
    (flat/raised/emphasis) on NeoPanel + NeoRaisedSm; new
    `NeoSection` (Level-0 canvas grouping); kit components
    moved onto the roles (NeoEyebrow, NeoScoreWell statistic,
    NeoTag, NeoNotice, Learn pulse numbers). Verified: analyze
    clean, tests **496/496** (4 new D-038 tests in
    neo_theme_test.dart).
  - **Test fix in the same stage (not a product change):**
    sync_store_test's same-morning dedupe test used fixed
    2026-10-30 dates while the stores stamp ops with the real
    clock; once the calendar moved past 2026-10-30 the S7
    future-date quarantine (>1 day) correctly held the ops and
    the test failed. The scenario now anchors to the real
    current day; product behaviour unchanged and arguably
    proven by the failure.
  - **Hallmark adopted as an audit lens (owner instruction
    2026-10-31, `nutlope/hallmark` v2.0.0, installed as a
    custom skill, scripts NOT run — it targets HTML/CSS; its
    gates are applied to Flutter by translation, and this
    project's DECISIONS.md is its "locked design.md", which
    Hallmark's own pre-flight says overrides its defaults).**
    Audit of the current app, evidence-based: CLEAN — no
    invented metrics (all numbers come from stores), no
    card-in-card (wells-in-panels are deliberate devices),
    token discipline after Stage 1 (the learning card was the
    only literal-colour cluster in production screens).
    WAIVED ON THE RECORD — Floor 9 (no eyebrows / tracked
    caps): NeoEyebrow is the owner's own prototype voice,
    chosen twice; the audit's underlying point is noted, and
    Stages 2–4 will thin eyebrows inside cards/wells (page
    titles keep them as identity). NOTED (Reflex, app
    translation) — Floor 10 middle-dot meta strings are used
    widely for stats lines; Stages 3–4 will break 3+-fact
    joins into stacked captions, keeping short two-part joins.
    Floor 6/7 (focus visibility, reduced motion) land in
    Stage 6, already approved there.
  - **Programme COMPLETE 2026-10-31:** all six stages built,
    verified and pushed in sequence (Stage 1 `364e69a2`,
    Stage 2 `2b4c8b2f`, Stage 3 `21c8bb9c`, Stage 4 `9867489f`,
    Stage 5 `b0b1a869`, Stage 6 — see PROGRESS_LOG). Final
    suite: analyze clean, **521/521**. Stage 6 scope note:
    the motion spec's ambient drift (§5) and first-entry
    stagger were NOT in this programme's approval list and
    remain unbuilt; press feedback is Material ink. Remaining
    judgement is on-device (motion feel, wells, parity in
    real light) — the owner's.

- **D-039 (2026-10-31) — "Editorial" renovation programme
  (owner master brief + `nimo_editorial_concept.html`).**
  A full UI/UX renovation to an editorial design language:
  green-charcoal dark (`#111411`) + warm paper light, pale
  mint functional teal (`#A9D5C6`/`#6EAA98`), plum
  `#C5A9D4` brand-only (D-035 Route A UNCHANGED), serif/
  sans/mono type families (Playfair Display / DM Sans /
  DM Mono, OFL), hairline-ruled composition instead of
  panel-first surfaces, two rationed feature surfaces
  (deep tint + paper), radius scale 3/10/17/full. Stage 0
  audit + system + plan:
  `files/RENOVATION_STAGE0-2026-10-31.md` in the goal
  workspace. Stages 1–7 per the brief (foundation → shell/
  Today → Learn → Progress/Spaces/Goals → Settings/
  secondary → parity/motion/a11y → QA), each analyze +
  full suite + push, per the brief's execution strategy.
  Standing calls: the concept's triangle mark NOT adopted
  (Face Mark stays, D-035); plan timeline shows no clock
  times (the data model has none — never invent data);
  brand tagline unchanged ("a little better, every day");
  Material icon set retained (one consistent set over a
  mixed one). Font binaries cannot travel the connector
  push (D-007 constraint): families are wired with
  fallbacks in Stage 1; the real faces land only if the
  owner supplies the .ttf files once (route A, recommended)
  — non-blocking either way. `redesign_explore/` +
  `design_preview/` (dead, unpushed) to be deleted in
  Stage 1. All D-001…D-038 product rules preserved
  verbatim; presentation-only by construction.
  - **Stage 1 DONE 2026-10-31 (owner-approved Stage 0 +
    font Route A):** theme + kit rebuilt on the Editorial
    system (see PROGRESS_LOG); analyze clean, tests 517/517
    (521 − 6 deleted smoke tests + 2 new). Font status:
    families wired with fallbacks; binaries NOT yet in the
    repo — the owner supplies the 8 .ttf + 3 OFL files per
    `assets/fonts/README.md`, then a text-only follow-up
    commit adds the pubspec `fonts:` block. Until then the
    app renders Noto Serif / Roboto / Roboto Mono fallbacks.
    Remote residue: `design_preview.dart` +
    `design_preview_test.dart` remain on GitHub (connector
    cannot delete); owner to delete via web UI.
    **PROGRAMME COMPLETE 2026-10-31: Stages 2–7 pushed —
    `45b7275b` (shell/Today), `a1ec92ce` (Learn), `6e10ed05`
    (Progress/Spaces/Goals), `566710cc` (Settings/secondary),
    `05609096` (parity/motion/a11y: guard at 44 computed
    pairs; paperMuted deepened #60685E→#5A6357; deepAccent
    added after the guard caught the light-theme pulse
    accent at ~1.9:1 on deep). Final: analyze clean,
    531/531. Completion report:
    `files/RENOVATION_COMPLETE-2026-10-31.md` (goal folder).
    Fonts: integrated later the same day (see the Open
    section) — the app now renders the real faces.**

- **D-040 (2026-10-31) — Today header: compact +
  customizable (owner brief, built as a Stage 2 follow-on).**
  The streak count moves into the brand header as a compact
  chip beside the Face Mark + "Nimo" (flame + "N day(s)" in
  mono micro type; flame + number only under 360dp wide; a
  full-height tap target that opens Progress, where the
  streak detail lives). It reads the SAME hub load as
  everything else — no second streak calculation — and the
  standalone streak row/pill on Today is REMOVED, so the
  streak is never displayed twice (shield detail remains in
  the scores section and in Progress). Settings moves from
  the intro's date row into the AppBar beside the chip.
  Customize Home gains a **Header** group: a master switch
  "Show editorial greeting" plus per-element switches for
  the date label, eyebrow, greeting heading and tagline;
  element switches are disabled while the master is off.
  Hidden means hidden: the greeting block and its spacing
  render NOTHING (no placeholder), and the following
  sections move up. All five prefs persist through the
  existing TodayStore app_settings mechanism
  (`home_show_header_*`), defaults on; existing section
  prefs untouched; no streak/scoring/schema change. Eight
  widget tests cover the brief's validation list
  (`test/features/today/today_header_test.dart`), including
  the no-gap offset check, the narrow-screen compact chip
  and both themes. Final: analyze clean, 540/540.**

- **D-041 (2026-10-31) — Status-bar inset fix (owner bug
  report, screenshots of Learn + Spaces).** Root cause: the
  app renders edge-to-edge (transparent status bar, no
  SystemChrome override anywhere), and a Scaffold body is
  inset ONLY by an AppBar. Today and every secondary screen
  have AppBars — safe. The four custom-header destinations
  (Learn, Progress, Spaces, Goals) built their editorial
  headers as body content with a fixed top padding, so
  their eyebrow/title rendered UNDER the status indicators.
  Not a spacing problem — a missing inset convention.
  **Fix, once, shared:** `PageTop` in the kit
  (`lib/core/neo_ui.dart`) — a SafeArea(top-only) wrapper
  applied to those four screens' Scaffold bodies (both of
  Learn's, incl. its loading state). The whole viewport now
  starts below the status bar, so content also cannot
  scroll under the indicators; the consumed inset is
  stripped from the MediaQuery below (no double-apply).
  AppBar screens deliberately untouched (the bar insets
  itself; wrapping them would double-apply). The shell's
  NavigationBar already handles the bottom/gesture inset.
  No typography, palette or spacing changes. Regression
  coverage: `test/features/shared/page_top_test.dart`
  (5 tests: PageTop consumes the inset exactly once with a
  no-wrapper control at dy 0; all five destinations' headers
  clear a fake 47dp inset; the Learn viewport starts below
  it and stays there while scrolling; the header position
  TRACKS the inset, 24 vs 47 — proving it is not a fixed
  pad; Settings as the AppBar/nested control; Spaces at
  320dp in light). Mutation-checked: removing PageTop from
  Goals makes the suite fail. Final: analyze clean,
  545/545 (APK via CI, as always in this VM).**

## Open — awaiting owner

- D-037's interpretation call 1 (teal accent in both themes)
  stands; call 2 (surfaces) and call 3 (plum learning card)
  are superseded by D-038 above.
- D-039 font route: RESOLVED 2026-10-31 — the binaries were
  acquired from Google Fonts directly and integrated
  (commits `bb3cce1` + `4a1f197`); see the PROGRESS_LOG
  entry "Post-programme fixes". The design_preview pair is
  also fully deleted now (`09000d6c` + `93131f89`).

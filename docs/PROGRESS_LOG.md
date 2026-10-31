## 2026-11-01 — D-042: Today's Plan Phase 1 (test branch)
- **Built to the owner's authorization (two discussion
  rounds first):** plan sectioned into Daily To-do /
  Today; × removed for a management sheet; one linked
  resource per task (URL or Spaces note/link-card/quiz);
  weekday scheduling; audio deferred to Phase 2; make-daily
  deferred. Full reasoning in DECISIONS D-042.
- **Schema v8, additive only** (weekdays/item_id/url on
  plan_templates; item_id/url on day_plan_items), links
  copied at generation + carry-over, sync registered
  (item_id as _Fk + nullableFks; entity order parents-first;
  day_plans.created_at materialised on import, not synced —
  a latent fresh-plan import failure the new round-trip
  test exposed and this change fixes).
- **Gates: analyze clean; 559/559 tests executed and
  passing** (545 baseline + 14 new: 8 store, 1 migration,
  1 sync round-trip with shifted local ids, 4 widget).
  One existing test touched: the sync migration fixture's
  rewind now also drops the v8 columns (assertions
  unchanged). APK via CI on the `test` branch. NOT merged
  to main (owner's branch workflow).

## 2026-10-31 — D-041: status-bar inset fix (owner bug report)
- **Root cause (investigated, not assumed):** edge-to-edge
  rendering + only-an-AppBar-insets-the-body. Of the app's
  22 Scaffolds, exactly five lacked an AppBar: Learn (×2),
  Progress, Spaces, Goals — the four NeoPageTitle
  destinations. Their fixed top padding put the eyebrow
  under the status icons (owner screenshots). Today +
  all secondary screens were already correct via their
  AppBars, which is why Today "handled it differently".
- **Shared fix:** `PageTop` wrapper in the kit (SafeArea,
  top only, with the convention documented on the class),
  applied to the four screens' bodies. Viewport starts
  below the status bar → scrolling can't slide content
  under the indicators; inset consumed once (stripped
  from the MediaQuery below); bottom nav untouched (the
  shell's NavigationBar owns the gesture inset). No
  per-screen padding hacks, no design changes.
- **Regression tests:** 5 new in
  `test/features/shared/page_top_test.dart`, covering all
  five destinations, Settings as the AppBar control, two
  inset values (tracks the system, not fixed), scrolling,
  320dp + light theme — and mutation-verified (removing
  PageTop from Goals fails them). Analyze clean,
  **545/545**. APK build remains CI-only in this VM
  (Gradle daemon dispatch, pre-compile; unchanged).

## 2026-10-31 — D-040: Today header — streak chip + greeting customization (main chat)
- Owner brief (Stage 2 follow-on): make the Today header
  compact and customizable. **Header group in Customize
  Home:** master "Show editorial greeting" + Date label /
  Eyebrow line / Greeting heading / Tagline switches
  (element switches disabled while the master is off),
  persisted via the existing TodayStore app_settings
  mechanism — restarts keep them, existing section prefs
  untouched.
- **Streak chip in the brand header:** flame + mono
  "N day(s)" beside the Face Mark, fed by the same hub
  load (no second calculation); flame + number only under
  360dp; 48dp tap height; tapping opens Progress (full
  streak detail). Settings moved into the AppBar beside it.
- **No duplication, no gaps:** the standalone streak
  row/pill is deleted from Today (week strip remains;
  shield detail stays in the scores section + Progress).
  With the greeting off, the block and its spacing render
  nothing and the next sections move up — proven by an
  offset assertion in the tests.
- Validation: 8 new widget tests (all-visible, master-off
  incl. no-gap, date-only off, eyebrow+tagline off, heading
  off, seeded streak=1 + chip tap, 320dp compact, light
  theme) — note: the harness found that openInMemory() is a
  sqflite-cached shared DB, so each test harness uses its
  own temp file. Analyze clean, **540/540**.

# Progress Log — Daily Life App

Newest first. Each entry: date, feature IDs / stage, what changed,
what was verified (and how), what remains open.

## 2026-10-31 — Post-programme fixes: build failure + font integration (main chat)
- **Build failure (owner-reported) — root cause:** the
  owner's web-UI deletion removed only
  `lib/features/design_preview/design_preview.dart`
  (commit `09000d6c`); its test,
  `test/design_preview_test.dart`, remained and imports the
  deleted file → analyze/test/build fail (CI run #30:
  Failure, 45s, exit code 1). Reproduced locally with the
  exact remote file: `uri_does_not_exist` + 3 undefined
  preview classes. Audit miss, recorded honestly: the pair
  was treated as two independent orphans and the deletion
  was delegated to manual web-UI steps because the snapshot
  push path cannot delete — but the connector's full MCP
  toolset DOES expose `delete_file` (via call-tool), which
  was never checked. **Fix:** the orphaned test deleted via
  the connector, commit `93131f89` — no restoration (the
  preview code was genuinely obsolete D-008 prototypes).
  CI run #31 for `93131f89`: 10m 58s, no error annotations
  (only the standard deprecation warnings) — build green
  again. Local gates on the fixed tree: pub get ✓, analyze
  clean, tests 531/531 at the fix, 532/532 final.
- **Fonts INTEGRATED (supersedes the "pending" notes):**
  the environment has internet; official static instances
  were downloaded from Google Fonts (Playfair Display
  1.203 — 500/600/500-italic; DM Sans 4.004 — 400/500/700;
  DM Mono 1.000 — 400/500) and verified with fontTools
  (family names, OS/2 weight classes, italic flags; NO
  variable-font table in any file — the names are real).
  OFL licences from the google/fonts repo. Binaries reached
  GitHub via the web upload UI (the connector's file tools
  are text-only; git/gh/SSH routes were checked and are
  unavailable here): commit `bb3cce1`, blob SHAs verified
  identical to the downloaded files. Pubspec `fonts:` block
  + guard test (`test/font_assets_test.dart`: FontManifest
  + TTF bytes load from the bundle) pushed as `4a1f197`.
  The app now renders the real Editorial faces.

## 2026-10-31 — D-039 Stage 7: QA + programme completion (main chat)
- Full final gates on the completed tree: `flutter analyze`
  clean; `flutter test` **531/531**.
- Sweeps: all six D-039 stage commits confirmed on remote
  main in order; no user-facing "Neo" copy remains; no
  hardcoded colours in feature screens (only the kit's own
  score-well gradient stops); no TODO/FIXME in lib; lib is
  25,224 lines (26,748 at Stage 0 — legacy deletions).
- Completion report delivered:
  `files/RENOVATION_COMPLETE-2026-10-31.md` — stage/commit
  table, design decisions, parity results, and the stated
  limitations (no screenshots possible in this environment;
  font binaries pending from the owner under Route A; CI
  runs for the D-039 pushes not yet checked; two orphaned
  remote files await web-UI deletion).
- **The D-039 Editorial programme is complete.** Remaining
  owner-side: font upload (one follow-up commit from me),
  orphaned-file deletion, and on-device judgement of the
  renovated app in dark and light.

## 2026-10-31 — D-039 Stage 6: parity, motion, accessibility (main chat)
- Parity, computed not eyeballed (the D-038 method): the
  guarded pair set grows by 7 pairs per theme — onDeep,
  deepMuted and deepAccent on deep; onPaper and paperMuted
  on paper; onDeepAccent on deepAccent; the secondary mark
  on scaffold at the graphical floor. **44 pairs total now
  pass** (30 core + 14 new).
- Two real fixes from the guard: (1) `paperMuted` deepened
  #60685E → #5A6357 — at 4.58 on dark-theme paper it was
  the thinnest margin in the system; now 4.96/5.48.
  (2) **Light-theme pulse bug**: the Learn pulse's "All
  topics" link and session button used the scheme primary
  (dark green in light mode) on the deep panel — ratio
  ~1.9, nearly invisible. `EditorialColors` gains
  `deepAccent`/`onDeepAccent` (the pale mint + its ink, in
  BOTH themes, because the deep surface is the same device
  in both), and the pulse now uses them.
- Motion: the D-038 system is untouched and carries the
  new surfaces (AnimatedCount in the pulse, score tweens,
  WarmReveal, skeletons, the single reduced-motion gate) —
  no new animation was added by the renovation.
- Accessibility: plan-row checkbox semantics survived the
  timeline rebuild verbatim; feature panels carry real
  text; space rows are text-bearing InkWells; the
  320dp @ 200%-text layout test still passes.
- Verified here: `flutter analyze` clean; `flutter test`
  **531/531** (517 + 14 new parity tests).

## 2026-10-31 — D-039 Stage 5: Settings + secondary UI (main chat)
- Settings: Appearance becomes a canvas section (head +
  copy + segmented control); the stale "The Neo design"
  copy now reads "The Editorial design". The Backup
  wrapper panel is removed (the section carries its own
  structure); the closing note sits on the canvas. Sync
  and backup sections audited — no panels inside; they
  inherit the theme.
- Routine editor: template rows on the canvas; the
  if–then habit-prompt block on the canvas.
- Day Close: the recap step loses its panel (the other
  steps were already canvas); flow, optional-everything
  semantics and the reveal are unchanged.
- Sheets/dialogs: bottom sheets take the concept's modal
  radius (17px top corners); dialogs keep 10. Dialog and
  sheet bodies inherit Stage 1 component themes; empty,
  loading (skeletons) and error states audited as already
  typographic and consistent.
- Verified here: `flutter analyze` clean; `flutter test`
  **517/517**.

## 2026-10-31 — D-039 Stage 4: Progress, Spaces, Goals (main chat)
- Progress: the Journey keeps its single justified hero
  panel (the path art is the visual). The numbers/charts
  card, the calendar and the archive leave their flat
  panels for ruled canvas composition; the streak header
  was already a canvas stat row.
- Weekly summary: sections are now ruled canvas sections
  (serif head over a hairline) instead of stacked panels —
  the Sunday letter reads as a letter. The Progress-side
  "This week" card becomes a bare hairline row.
- Spaces: the 2-column tile grid becomes the concept's
  ROWS — 48px bordered squares with serif initials, name,
  counts, chevron; the selected space's square fills with
  the container tint and a mint edge, and its detail panel
  below is unchanged. Recently touched on the canvas.
- Projects and project Items/Topics lists: canvas rows.
- Goals: audited, no code change — goal cards (first
  raised, rest flat) and the closing pace panel already
  match the Editorial hierarchy under the Stage 1 kit;
  serif/mono roles apply automatically. Item detail's quiz
  panel likewise stands (single-object detail).
- Verified here: `flutter analyze` clean; `flutter test`
  **517/517**. Preview:
  `files/nimo-editorial-stage4-progress-spaces-preview.html`.

## 2026-10-31 — D-039 Stage 3: Learn (main chat)
- Learn hub: the pulse moves onto the DEEP FeaturePanel
  (serif title + mono "All topics" action on deep green,
  AnimatedCount cells in onDeep, hint in deepMuted; the
  D-038 collapse-when-empty behaviour and the "Begin a short
  session →" anchor preserved). Pack rows and the verify
  doorway leave their flat panels for canvas hairline rows.
  Continue-episode cards keep their (now hairline) panels;
  arc titles are serif via the Stage 1 role change.
- Topics & Library: Inbox and All-topics lists on the
  canvas; the source-library block goes flat.
- Topic detail: "Sparked by", Sources and Marked points
  lists on the canvas.
- Reading: the reader chunk now sits on the PAPER feature
  surface in both themes (text in onPaper) — `FeaturePanel`
  gained a `circles` opt-out so no line-art sits behind long
  reading text. PDF chrome unchanged (pdfrx owns the page).
- Image-verify queue: canvas rows.
- Sessions/question cards: no hardcoded colours existed;
  prompts render in the serif titleLarge role and all
  surfaces follow the scheme — interaction layouts and the
  five card formats are untouched, per the brief (the
  interaction matters more than the dressing).
- Verified here: `flutter analyze` clean; `flutter test`
  **517/517**. Preview:
  `files/nimo-editorial-stage3-learn-preview.html`.

## 2026-10-31 — D-039 Stage 2: app shell + Today (main chat)
- Shell: the bottom nav gains the concept's ruled edge (a
  hairline above the bar); labels stay sentence-case (tests
  tap them by name) in the Stage 1 mono styling.
- Today, recomposed on the canvas: the date is now the
  concept's mono uppercase chip; the dead search placeholder
  button (disabled since S2, "Coming soon") is REMOVED per
  the brief §7 — no decorative controls; Settings remains.
- Daily progress leaves its panel: streak row + hairline +
  week-as-type (today = filled mint circle; done days now
  dotted in deep mint/secondary, was tertiary).
- The plan is a TIMELINE: hairline rail through 11px node
  marks (filled mint when done), checks moved to the right
  edge as circles; no clock times (the model has none).
  Track/count, Today/This-week toggle, add field and the
  if–then block unchanged in behaviour. The week view also
  sits on the canvas now.
- Learning card = the PAPER FeaturePanel: mono desk label,
  serif headline, counts as the quiet sub, "Measured in
  enjoyment, not minutes." preserved verbatim (test anchor),
  round outline arrow still starts a session in one tap.
  The lavender tile/arrow treatment is retired (it belonged
  to the superseded restrained-plum direction). Topics &
  Library is a canvas hairline row, not a panel.
- Day Close = the concept's RULED BAND: hairlines above and
  below, circled moon mark, serif title, one solid
  FilledButton (Begin Day Close / Close yesterday /
  Revisit reflection); the late-window "Close today instead"
  stays beside it.
- Pinned spaces: circle avatars become bordered squares with
  a serif initial (the concept's space glyph treatment).
- Scores wells, quick-add, Sunday card, Recently touched,
  goal strips: composition unchanged (they inherit the
  Stage 1 kit); Customize Home and every section toggle
  preserved.
- Verified here: `flutter analyze` clean; `flutter test`
  **517/517**. Preview:
  `files/nimo-editorial-stage2-today-preview.html`.

## 2026-10-31 — D-039 Stage 1: Editorial design-system foundation (main chat)
- Stage 0 approved by the owner as-is; font Route A chosen
  (bundle the real faces; owner supplies the .ttf files).
- `theme.dart` rebuilt on the Editorial system: green-
  charcoal dark (#111411 canvas, #181D19 surface, #202720
  raised) + paper light (#DFDBC9 canvas, #E8E5DA surface);
  mint #A9D5C6 / deepened #2F6B57 functional; plum tertiary
  tint, brand-only (Route A intact); semantics re-tinted
  warm. Type re-familied: Playfair Display (display/page/
  section/feature titles), DM Sans (UI/body/statistics),
  DM Mono (eyebrow/technical/nav labels) — wired BY NAME
  with platform fallbacks; no pubspec font block until the
  binaries land (a missing-asset reference would break the
  build). Radius scale 3/10/17/999. `EditorialColors`
  extension carries the two feature surfaces (deep #1C2822
  both themes; paper #E8E5DA dark / #F2F0E8 light).
  Navigation bar themed: canvas bg, mono labels, mint
  selected icon.
- Kit (`neo_ui.dart`) genuinely re-founded, not re-tokenised
  only: ALL neumorphic shadows deleted (hairline + tone in
  both themes now); NeoCheck is a circle; NeoEyebrow gains
  the concept's 24px leading rule in the accent; NeoNotice
  rides primaryContainer; NeoGlyph is the concept's bordered
  square; NeoChip/NeoTag/steppers on the editorial radius;
  section-head actions in mono; NEW `FeaturePanel` (deep /
  paper) with the concentric circle line-art. Motion system
  untouched and compatible.
- Legacy cleanup: `redesign_explore/` (never pushed) and
  `design_preview/` deleted locally after import/route/test
  verification (nothing referenced them at runtime; their
  smoke tests deleted with them, −6 tests). NOTE: the
  design_preview pair WAS in two old snapshots, and the
  connector cannot delete — the two remote copies are
  orphaned until the owner deletes them on GitHub (can ride
  along with the font upload).
- Font delivery pack: `assets/fonts/README.md` lists the
  exact 8 .ttf filenames + 3 OFL licence files required.
- Verified here: `flutter analyze` clean; `flutter test`
  **517/517** (521 baseline − 6 deleted smoke tests + 2 new
  foundation tests; the 18 computed parity pairs pass on
  the new palette unchanged). Preview:
  `files/nimo-editorial-stage1-preview.html`.

## 2026-10-31 — D-038 Stage 6: motion, accessibility, responsive (main chat)
- Motion foundation: `lib/core/motion.dart` — the spec's
  tokens (micro 150 / standard 250 cubic(0.32,0.72,0,1) /
  emphasis 400 / celebration ≤800), one reduced-motion gate
  every animation passes through, framework widgets only.
- AnimatedCount (interruptible int tween, optional whole-line
  format) + animated NeoTrack fill + NeoScoreWell numbers —
  Done and Self tween separately, same duration, never
  merged. Applied: score wells, Learn pulse, Progress streak
  header, session stats. NeoCheck settles over `micro` — a
  tick gets that and nothing more.
- Tier 2 warm feedback: WarmReveal (rise 10px + fade,
  emphasis) on the session-complete surface (enjoyment line
  in the warm semantic colour) and the Day Close reveal.
- Tier 3: GoalCompletionBadge — springs in with one glow
  pulse when a goal CROSSES to complete (Goals tab card
  detects the crossing; Today strips track previous
  fractions), then sits as a quiet state ("Goal reached —
  nicely done."). Never on revisit, never on app open.
- Skeletons per spec §6: 150ms delay-before-show, pulse only
  after 600ms visible, static under reduced motion; applied
  to Today / Learn / Progress / Spaces / Goals / Topics
  first loads + Settings' reminder wait. In-place work
  (sync, backup, calendar) keeps progress indicators.
- A11y: plan rows announce as checkboxes with state;
  NeoTrack exposes a percentage value; steppers already at
  the 48dp touch token. Test guards 320dp width at 200%
  text scaling (no overflow).
- NOT built, deliberately: ambient background drift and
  first-entry list stagger (in the motion spec but not in
  the owner's D-038 approval list); press-scale on panels
  (Material ink is Android's press feedback).
- Verified here: `flutter analyze` clean; `flutter test`
  **521/521** (514 + 7 motion tests proving tween behaviour,
  reduced-motion snapping, the skeleton gate, the crossing
  celebration, and the 200%/320dp composition). Preview:
  `files/nimo-stage6-motion-preview.html`.
- **D-038 programme complete: all six stages pushed.**

## 2026-10-31 — D-038 Stage 5: light/dark parity (main chat)
- Method: the VM cannot render the app, so parity was proven
  arithmetically — both themes' resolved ColorSchemes were
  read from the running code (a throwaway probe test, since
  deleted) and every foreground/background pair the UI uses
  was computed against WCAG floors (4.5 text / 3.0 components).
- Result: 32/32 pairs pass in both themes. One thin margin
  fixed: light `onSurfaceVariant` deepened #696471 → #5E5967
  (flat-surface captions 4.71 → 5.56). Charts and the Journey
  Path verified scheme-driven (no hard-coded colours);
  geometry is shared by construction (one theme builder);
  seed-derived container pairs are M3-generated.
- Parity is now GUARDED: 18 new tests in neo_theme_test.dart
  compute the core pairs from the live themes and fail below
  their floors.
- Verified here: `flutter analyze` clean; `flutter test`
  **514/514** (496 + 18). Audit page:
  `files/nimo-stage5-parity-preview.html`.
- Next: Stage 6 — motion, accessibility, responsive polish.

## 2026-10-31 — D-038 Stage 4: Settings refinement (main chat)
- Owner directed the use of the installed design skills for
  the remaining stages (Hallmark as the audit lens, Apple
  Design + Emil design-eng for motion/polish judgement,
  ponytail for restraint). Stage 4 applies them as review
  discipline; Stage 6 is where their motion rules bite.
- Settings regrouped per §6.6 with NO behaviour change:
  Appearance and the closing note go flat; reminders stay on
  the canvas; the old "Your data, in your hands" + "Sync"
  block splits into two distinct sections — "Backup &
  restore" (the backup section in its own flat panel, headed
  "Full snapshot backup" with an explicit "unlike sync, a
  backup copies everything" line) and "Sync between your
  devices".
- Sync section internally grouped: overview (copy shortened;
  the old paragraph's doc references removed) · Status (well;
  device id in the technical role) · Library folder (path in
  the technical role) · Manual transfer (Sync now, Import a
  package) · Advanced (Conflicts / Held / Repair, with a
  plain-language explainer). Group labels use the caption
  treatment from Stage 2's score wells.
- The desktop reminder note loses its "(§R8.6)" doc-speak.
- Verified here: `flutter analyze` clean; `flutter test`
  **496/496** (no expectation changes needed — labels and
  flows untouched). Preview:
  `files/nimo-stage4-settings-preview.html`.
- Next: Stage 5 — light/dark parity.

## 2026-10-31 — D-038 Stage 3: Learn, Progress, Spaces, Goals (main chat)
- Learn: the pulse panel shrinks to its content — with
  nothing due and nothing new, the three zero cells collapse
  (the import hint carries the state; the session button was
  already disabled at zero). Packs and image-verify panels go
  flat; the pulse stays the screen's raised element. Session
  questions were verified already focal (titleLarge prompts
  in question_cards.dart) — no change made there.
- Progress: Journey stays the raised hero; numbers/charts,
  calendar and archive panels go flat; the streak header's
  values move to the tabular statistic role. The streak-rule
  notice already sat on the canvas.
- Spaces: workspace selector tiles compacted (padding
  20→16, both states); the selected workspace panel stays
  raised as the primary content.
- Goals: first goal raised, later goals flat (§6.5 "later
  goals visually quieter"); goal titles use the cardHeading
  role; the pace note panel goes flat.
- Topics & Library: Inbox/topic panels flat; the library
  stats line loses its middle-dot join for two mini statistics
  and the path takes the technical role (Hallmark thinning).
- Verified here: `flutter analyze` clean; `flutter test`
  **496/496** (widget_test's Learn anchor updated to the
  compact pulse's enjoyment line). Preview:
  `files/nimo-stage3-screens-preview.html`.
- Next: Stage 4 — Settings refinement.

## 2026-10-31 — D-038 Stage 2: Today, the reference screen (main chat)
- Daily progress merged: the streak pill and week strip are
  now ONE flat panel (streak row, hairline, week cells); when
  the owner hides the week strip, the streak survives as the
  standalone pill, unchanged.
- Learning card rebuilt per the approved revision: neutral
  Neo surface + one lavender book tile + lavender-deep action;
  the plum block is gone. Stage 1's `FeatureColors` retired —
  the card uses BrandColors directly.
- Hierarchy pass: quick-add tiles, pinned tiles and the
  Sunday card go flat; the plan panel stays raised (primary
  content); Recently touched moves onto the canvas (NeoSection,
  hairline rows, no panel).
- Quiet progress: score wells gain a thin proportion track
  (Done /100, Self /10; hidden before close); Day Close reveal
  wells match. Score-well labels leave the eyebrow style for
  sentence-case captions (Hallmark thinning, Stages 2–4);
  page-title eyebrows stay as identity.
- Today goal steppers now disable at their bounds, matching
  the Goals tab. Day Close card heading uses the cardHeading
  role. All copy and behaviour otherwise unchanged.
- Verified here: `flutter analyze` clean; `flutter test`
  **496/496** (one expectation updated for the sentence-case
  score labels). Preview:
  `files/nimo-stage2-today-preview.html`.
- Next: Stage 3 — Learn, Progress, Spaces, Goals.

## 2026-10-31 — D-038 Stage 1: design-system foundation (main chat)
- Owner approved the audited refinement programme (10:16 IST):
  six stages; brief §4.1's handwritten-font premise corrected
  on code evidence (no custom font has ever shipped); surface
  hierarchy L0/L1/L2; learning-card plum superseded; motion
  reopened for Stage 6. Full record: DECISIONS.md D-038.
- Foundation landed: `AppType` typography roles on the system
  sans (card-heading role new; line heights; semibold action
  labels), `AppIconSize` roles, `NeoSurfaceLevel`
  flat/raised/emphasis on NeoPanel + NeoRaisedSm, new
  `NeoSection` (canvas-direct grouping), kit components on the
  roles (eyebrow, score statistic, tag, notice, Learn pulse),
  learning-card colours tokenised into `FeatureColors`.
- Hallmark skill (nutlope/hallmark v2.0.0) installed as a
  custom skill at the owner's instruction and applied as an
  audit lens: clean on invented metrics / card-in-card / token
  discipline; eyebrow rule waived on the record (owner's
  prototype voice; thinning inside cards scheduled for
  Stages 2–4); middle-dot stat strings noted for Stages 3–4.
  Its scripts were not run (HTML/CSS tooling).
- Test fix (no product change): the sync dedupe test's fixed
  2026-10-30 scenario dates broke once the real calendar
  passed them (S7 future-date quarantine held the ops, as
  designed); the scenario now anchors to the real day.
- Verified here: `flutter analyze` clean; `flutter test`
  **496/496** (492 + 4 new). Preview:
  `files/nimo-stage1-foundation-preview.html` in the goal
  workspace (type roles + surface levels, both themes).
- Next: Stage 2 — Today as the reference implementation.

## 2026-10-30 — D-037: Neo screens rebuilt, one by one (main chat)
- Owner correction (22:26 IST): D-036 was a token/theme layer
  over unchanged layouts, not the Neo UI implementation asked
  for. Owner instruction (22:33 IST): "Build them one by one
  and then push it." Full record: DECISIONS.md D-037.
- New component kit `lib/core/neo_ui.dart` (raised panels/wells
  from the prototype files' shadow values, page titles, section
  heads, tracks, checks, notices, score wells, steppers).
- Every screen rebuilt to the prototype's composition and
  copy: Today, Learn, Topics, Topic detail, Progress, Weekly,
  Spaces (workbench + project accordions), Projects, Items,
  Item detail, Goals, Settings; sub-screens dressed: Routine,
  Day Close, Session, Reading, PDF (theme only), image verify,
  share sheet, sync/backup sections.
- Interpretation calls recorded in D-037: teal stays the
  functional accent in both themes (Route A; the approved
  assumption the owner never countermanded); surfaces follow
  the two files (neumorphic light / outline-drop dark); the
  learning card keeps the prototype's plum #62536F; Done Score
  stays /100 against the prototype's /10; Learn pulse shows
  packs count (no enjoyment-average API exists); goal steppers
  disable at bounds.
- Verified here: `flutter analyze` clean; `flutter test`
  **492/492** (expectations updated only where D-037 copy
  changed: Day Close heading/labels, Learn pulse labels,
  journey heading, widget-test anchors). No dependency/Gradle
  changes.
- Open: on-device look/feel check of the rebuilt screens in
  both themes (owner), incl. whether the neumorphic light
  surfaces and the approximated inset wells read well on a
  real device.

## 2026-10-30 — D-036: Neo UI (dark + light) + static logo implemented (main chat)
- Owner-approved via repeat-back (21:56 IST): implement the Neo
  UI and the D-035 static logo in the real app; motion explicitly
  excluded. Full decision record: DECISIONS.md D-036.
- Theme system rebuilt on Neo tokens (Space/RadiusToken/semantic
  set; Gap kept as aliases); `neoDark()` + `neoLight()` themes
  with teal functional in both (Route A); Settings Appearance
  switch persisted in `app_settings.theme_mode`, dark default.
- Logo: vector Face Mark (`lib/core/brand.dart`) in the Today
  AppBar (top-left) + Settings brand footer; launcher icon =
  Face Mark vector on brand lavender-plum #38304F with an
  Android 13 monochrome layer; app label/title now "Nimo".
- Page-margin (20) pass on the five tab screens + Settings.
- Verified here: `flutter analyze` clean, `flutter test`
  **492/492** (6 new tests in `test/neo_theme_test.dart`);
  build-risk scan clean (no dependency/Gradle changes — res XML
  + Dart only, so AAPT resource linking of the new icon vectors
  is the one thing only CI can prove).
- Open: on-device look/feel check in both themes (owner);
  launcher icon rendering at real sizes (owner's drawer).

## 2026-10-30 — D-034: share capture reimplemented in-house, plugin removed (main chat)
- Owner chose the proper fix over forcing the plugin's JVM
  targets from our Gradle config. `receive_sharing_intent` is
  GONE from pubspec/lock and the resolved plugin set (verified
  by grep + scanner). MainActivity (stock 3 lines until now)
  decodes ACTION_SEND / ACTION_SEND_MULTIPLE and serves the
  unchanged ShareIntentService contract over
  `app.dailylife/share_intent` channels; Dart side is
  `AppShareIntentService` with the plugin-era conversion
  semantics preserved exactly (bare-URL text upgrades to a
  link; files arrive as app-cache copies). Manifest filters
  were already ours — comment updated only. One improvement
  over the plugin: warm shares arriving before Dart listens
  are buffered natively and flushed on listen.
- Tests: the 3 plugin-mock tests were rewritten against mock
  channel handlers with identical expectations; the rest of
  capture_service_test is untouched.
- Post-removal build-risk scan (hardened skill): 10 plugins,
  zero FAIL/CHECK. jni's NDK/CMake step remains the one
  never-yet-exercised stage, as recorded in the audit doc.
- Verified here: `flutter analyze` clean, `flutter test`
  **483/483** (count unchanged — 3 tests rewritten in place).
  The Kotlin side compiles for the first time in CI — that is
  the known verification gap of this environment, stated
  plainly rather than papered over.

## 2026-10-30 — CI failure 3: RSI 1.8.1 JVM-target mismatch; skill hardened in response (main chat)
- The `969f7c04` build failed at `:receive_sharing_intent:
  compileReleaseKotlin` — JVM targets 11 (Java) vs 17 (Kotlin).
  Root cause is a DEFECT OF OMISSION: 1.8.1's build.gradle
  declares neither compileOptions nor kotlinOptions (verified by
  reading the file), so each side took a different toolchain
  default; Kotlin 2.x target validation rejects the mix. 1.9.0
  sets 17/17 explicitly (also verified) — the downgrade traded
  the compileSdk defect for this one. The log's KGP warning also
  names this plugin (it applies kotlin-android itself): future
  Flutter hard-fails KGP plugins, so both published versions are
  dead ends under this toolchain.
- Skill `flutter_android_build_risk_audit` updated: scanner now
  checks JVM-target coherence including omission (re-scan flags
  RSI 1.8.1 as CHECK-omission); playbook gained a defects-of-
  omission section and candidate-check step 2b. Fix decision
  (Gradle override vs in-house replacement) is the owner's.

## 2026-10-30 — CI fix 2: receive_sharing_intent pinned exactly to 1.8.1 (main chat)
- Owner approved the audit's recommendation. pubspec now pins
  `receive_sharing_intent: 1.8.1` EXACTLY (no caret — `^1.8.0` is
  what floated to 1.9.0) with the reason recorded in a comment.
  1.8.1 verified from its pub.dev archive before pinning:
  compileSdk 34, Gradle file clean on the full risk battery, and
  the identical Dart API surface this app uses (getInitialMedia /
  getMediaStream / reset); 1.9.0's changes were iOS-side plus the
  SDK bump, so the downgrade costs nothing on Android.
- Verified here: lock resolves 1.8.1; the resolved plugin's
  build.gradle declares compileSdk 34; `flutter analyze` clean;
  `flutter test` **483/483** (unchanged — no Dart code touched).
- Audit doc updated with the confirmation. One known unknown
  remains for the CI run: jni's native (CMake/NDK) compile step
  has not yet been explicitly exercised end-to-end.

## 2026-10-30 — CI build failed AGAIN on the fix push; diagnosis audited, no fix applied (main chat)
- The `2999a875` build also failed (owner report; error text
  requested). Owner's instruction: understand before fixing.
- Full audit written to `docs/CI_BUILD_AUDIT-2026-10-30.md`:
  pattern = new pinned toolchain (AGP 9.1.0 / Kotlin 2.4.0 /
  Gradle 9.3.1 / compileSdk 36) vs lagging plugin Gradle scripts,
  compounded by the workflow's unpinned `channel: stable`; our
  gates are all host-Dart and structurally cannot see Gradle-side
  failures (APK builds exist only in CI for this project).
- Ranked suspects for failure 2 (both unreachable in run 1, which
  died earlier in the build): (1) receive_sharing_intent 1.9.0
  hard-codes compileSdk 37 vs the app's 36 (AAR-metadata check /
  missing android-37 platform); (2) jni 1.1.1's CMake/NDK native
  build (flutter.ndkVersion) on the runner. All other resolved
  plugins audited clean-to-low; our own android/ files clean.
  Awaiting the FAILURE block to identify it conclusively.

## 2026-10-30 — CI fix: flutter_inappwebview moved to the 6.2.0 beta line (main chat)
- The S3–S7 push's Build APK run failed in Gradle:
  `flutter_inappwebview_android-1.1.3/android/build.gradle` calls
  `getDefaultProguardFile('proguard-android.txt')`, which AGP 9
  removed. Verified locally: 1.1.3 IS the latest stable android
  impl and contains exactly those lines — no stable upgrade path.
- Fix: `flutter_inappwebview: ^6.2.0-beta.3` (resolves android impl
  1.2.0-beta.3 + platform interface 1.4.0-beta.3); its build.gradle
  uses `proguard-android-optimize.txt` (verified in the resolved
  pub-cache copy). A narrower fix — overriding only the android
  impl — was tried first and rejected by evidence: the stable
  app-facing code no longer compiles against the beta platform
  interface (missing PlatformInAppBrowserEvents members), caught
  by the test run, not by analyze. The whole stack moves together;
  revert to stable once a stable release resolves an android impl
  >= 1.2.0 (note also recorded in pubspec.yaml).
- Verified here: `flutter analyze` clean, `flutter test`
  **483/483**. Changed files only: pubspec.yaml, pubspec.lock,
  this log. Pushed as its own commit so the workflow re-runs;
  the APK result is CI-side (watch Actions).

## 2026-10-30 — Partial S8 excised before the S3–S7 push (owner-directed)

- S8 is owner-gated; a briefly-started S8 run was stopped and its partial,
  unreviewed work was removed from the tree so this push carries only the
  verified S3–S7 state: `lib/features/sync/lan/` (7 files) and the two LAN
  test files were moved out, and the S8-only dependencies (pointycastle,
  bonsoir, qr_flutter) were removed from pubspec.yaml. `sync_store.dart`
  was inspected — it contains no LAN references and was left unchanged.
- The S8 draft is stashed at `~/workspace/daily-life-app-s8-partial/`
  (with a README) for the future gated S8; its first task will be to audit
  the stash against the then-current tree.
- Post-excision verification: `flutter analyze` — No issues found;
  `flutter test` — 483/483 (the exact post-S7 counts).

## 2026-10-30 — S7 review round 2: the full independent report, fixed (schema v7)

- The independent reviewer's COMPLETE report arrived after the
  S7 entry below was written. Its headline "0 MUST" summary was
  wrong — the report carried **4 probe-verified MUST-FIX** and
  7 SHOULD-FIX findings (the tree had changed mid-review,
  closing its S1–S3; M1–M4 stood). All fixed in this round;
  the S7 entry below stands as the record of the first pass,
  and this entry corrects its review accounting.
- **M1 (critical):** export advanced `sync_base`, so when both
  devices exported before either imported, peer ops were
  misread as fast-forwards — edits silently swapped, zero
  conflicts, permanent divergence. Fix: schema **v7** adds
  `sync_exported` (last-sent state); the base advances only on
  wholesale import outcomes (D-033). Corollary found by the
  pre-existing edit-edit test: the op-stamp reuse baseline is
  now the last SENT stamp (the export recording's stamp echo
  otherwise froze re-exports at their first stamp).
- **M2:** `syncEntityOrder` now truly parents-first
  (`projects` before `topics`; first-sync topics were being
  quarantined as missing-parent); Held dialog explains each
  hold by its actual reason (a missing-parent hold is not a
  clock problem, and the old copy's remedy could never work).
- **M3:** `packs`/`questions` adopt identity by natural key
  (`pack_id`; `pack_id`+`pack_qid`) — independent quiz-pack
  imports on both devices no longer poison packages via
  UNIQUE(pack_id); per-op SAVEPOINT backstop quarantines any
  unforeseen apply failure (`apply-error`) instead of
  aborting the package forever; database errors surface as
  SyncException.
- **M4:** parent deletes no longer cascade over locally
  diverged/unsynced descendants — held as
  `delete-with-unsynced-children` conflicts, subtree kept.
- **SHOULD-FIX:** S1 day_reviews `self_note` conflict copies;
  S2 stale-package guard (older package after newer one can
  no longer roll a row back; counted as `stale`); S3 folder
  import tolerates + names bad files (`failedFiles`); S4
  declared entry sizes checked before decompression; S5 HLC
  stamps format-validated (garbage stamps bypassed quarantine
  and won LWW); S6 desktop database moved to the
  application-support directory (FFI default is CWD-relative —
  launching from another directory opened a different, empty
  database); S7 Library-folder picker now probes writability
  before persisting + bootstrap falls back to the default
  Library if a persisted root becomes unwritable (Android
  scoped-storage writability itself remains owner-side
  verification — SYNC_SETUP §1). NOTEs: N5 comments corrected;
  N6 section-test waits bumped (its flakiness was also the
  source of the earlier `_load()` guard, which covers N7).
- **Tests: 8 new** (M1 concurrent-export, M2 topics
  first-sync, M3 pack adoption, M4 cascade guard, S1-review
  self-note, S2 stale, S3 poisoned folder, S5 malformed
  stamp); migration test extended to v7. **Final:
  `flutter analyze` clean, `flutter test` 483/483** (455
  baseline + 20 S7 + 8 round-2). Schema is now **v7**.
- Still unverified (owner-side, unchanged): real two-device
  exchange over Syncthing, the Linux GUI build/run on the Arch
  laptop, the Android Library-folder pick under scoped
  storage. Push still HELD; S8 still gated.

## 2026-10-30 — S7 built, reviewed, fixed: Two devices (SYNC Stage A + DESKTOP)

- **Sub-step A — Linux desktop.** `linux/` scaffolding added
  (Android untouched); `sqflite_common_ffi` promoted to a runtime
  dependency and wired by platform (`lib/core/platform_init.dart`
  — FFI factory on desktop, native on Android);
  `AppDatabase` unchanged otherwise. Desktop adaptations:
  share-intent gated to Android in main (no desktop
  implementation exists; capture entry points never fire);
  HTML quizzes open in the system browser on desktop (§R8.4
  fallback); reminder toggles kept with an honest desktop note
  (the generated Linux registrant doesn't include
  flutter_local_notifications — desktop reminders are inert,
  D-030); session screen gained keyboard support (Enter/Space
  continue, 1–5 enjoyment); Sync section gained the
  Library-folder picker (nothing could set `library_root`
  before — Stage A folder sync was unreachable on the phone
  without it). **Verification level (D-030):** the GUI build
  cannot complete in this VM — GTK3 dev files absent, apt has
  no candidate (ninja 1.12.1 was curl-fetched to ~/tools/ninja;
  CMake then stops at the gtk+-3.0 pkg-config check). Verified
  here instead: analyze clean + the whole suite green on the
  FFI factory, the same DB path the Linux build runs. Owner
  runs `toolchain/build_linux_on_laptop.sh` (one pacman line)
  for the GUI build. Setup incl. Syncthing-Fork + Avahi (S8)
  checklist: `docs/SYNC_SETUP.md`.
- **Sub-step B — sync package engine** (`lib/features/sync/`).
  Schema v6 (additive only): `sync_base`, `sync_peers`,
  `sync_quarantine`, `sync_conflicts`. Change detection is a
  state diff vs `sync_base` (D-029 — no store writes sync_ops;
  retrofitting all S1–S6 stores was rejected). Packages:
  `Library/sync/pkg-<device>-<seq>.zip`, manifest + ops digest
  verified, temp-then-rename writes. Import: one transaction,
  3-way merge, FKs as parent sync_ids, day_reviews/day_plans by
  date, deterministic plan-item ids (`rt-…`/`co-…`, TodayStore),
  done-toggle LWW without copies, conflict copies for every
  other loss (and conflict rows themselves sync), tombstones,
  future-dated quarantine (>1 day, by HLC and by date),
  receiver HLC clamping, derived data never synced (streak
  re-evaluates after import). Two design corrections came out
  of testing, both divergence-class: op stamps carry the row's
  EDIT stamp where a store stamps one (export-time stamps made
  the later exporter beat the later editor), and a local merge
  win never advances `sync_base` (the winner must still
  travel). `day_plans.created_at` left the payload for the same
  reason `is_counted` was already out.
- **Sub-step C/D — UI + Repair.** Settings → Sync shows device
  id, last export/import per peer, Sync now (export + folder
  check), package import, Conflicts and Held lists, Library
  folder control, and Repair = the S4 snapshot restore under
  the D-011 guards (store-level, re-tested here). After any
  restore the app adopts the database with a fresh sync
  identity (D-032).
- **Review loop.** Independent reviewer (no S7 code): 0 MUST,
  4 SHOULD, all fixed — S1 quarantined packages no longer
  advance the local HLC state; S2 post-restore sync adoption
  (D-032); S3 plan-item adoption now keys on the full natural
  slot (plan+template+position, exactly one match); S4 the
  folder-drop exchange path is now integration-tested. Plus a
  full-suite flake the reviewer-era runs exposed: SyncSection's
  status reload could query a closing database during restore
  re-bootstrap — now guarded (status is decorative, failure
  keeps last state). NOTE-level: Repair dialog now advises
  Sync-now-first (N5); sync-screen goldens (N7) deferred —
  alchemist remains unadopted project-wide; the widget test
  covers the section's states.
- **Tests (TESTING §9/S7).** Baseline 455 → **475/475, analyze
  clean** (final full run; earlier failures recorded in the
  re-verification entry below are all resolved: migration_v5
  pin → schemaVersion-relative, html_quiz expectation → the
  new desktop fallback, the two load-flaky sync tests → the
  base/stamp corrections + the `_load` guard). New suite
  `test/features/sync/` (20): v6 migration, first-sync full
  package, incremental + idempotent re-import, both-sides edit
  conflict + copy propagation, day_reviews per-date merge
  (scores by HLC, point preserved, null never erases),
  tombstone propagation, future-HLC and future-date quarantine
  + re-import after clock fix, horizon boundary exactly +1 day
  vs +1 ms and HLC counter 9-vs-10 (mutation spot-checks),
  tampered/truncated package atomicity, missing-parent hold
  and later apply, deterministic morning dedupe + toggle sync,
  seeded model-based two-device convergence (40 randomised
  steps, dumps equal, both exports empty), folder-drop
  exchange, HLC-state quarantine isolation, restored-device
  adoption, Repair D-011 guards, Library symlink-escape
  refusal, SyncSection widget smoke. Mocktail/property_testing
  not adopted (D-031).
- **Unverified (owner-side, stated plainly):** the Linux GUI
  binary (build on the Arch laptop, then confirm the same
  backup restores identically there — PLAN S7 acceptance), a
  real phone↔laptop package exchange over the home LAN incl.
  Syncthing-Fork carrying the Library, on-device share/PDF
  behaviour unchanged from S4/S5 status. MobSF per-stage APK
  scan (TESTING §9/S7) not run — no new APK was built in this
  stage. S8 does not start without the owner's explicit go
  (instruction recorded above).

## 2026-10-30 — Owner instruction (main chat): push HELD; finish S7; S8 gated
- The push stays held (owner confirmed after the not-ready verdict
  below).
- S7 is to be completed ("clear the S7") — including fixing the
  findings from the pre-push re-verification below (stale
  migration_v5 version pin, html_quiz platform-message failure,
  flaky sync tests).
- **S8 must NOT start until the owner explicitly says so.** This
  supersedes the standing autonomous S3→S8 go-ahead for S8 only;
  the go-ahead remains in force through S7's completion.

## 2026-10-30 — Pre-push re-verification (main chat): NOT ready — 4 failures on the current tree
- Owner asked for a readiness confirmation before the S3–S6 push.
  Independent re-run on the exact tree: `flutter analyze` clean;
  `flutter test` **467 passed / 4 failed** (471 total — the tree is
  S6-complete PLUS in-progress S7 sync work, not a clean S6 cut).
- Deterministic failures (fail in full run AND in isolation):
  1. `test/features/learn/migration_v5_test.dart:87-88` — stale
     version pin: asserts `schemaVersion == 5`; S6 raised it to 6.
     Test-maintenance miss, data-survival assertions not implicated.
  2. `test/features/items/html_quiz_detail_test.dart` — expects the
     text "HTML quizzes play in the Android app." on a non-Android
     host; 0 found. Stale test OR a real desktop-behaviour change —
     needs a look (matters for S7's Linux build either way).
- Flaky under full-suite load (failed in full run, passed isolated):
  two `sync_store_test.dart` tests (S7 WIP) — day_reviews HLC merge;
  two-device morning dedupe.
- Everything else about the push is ready: manifest 156 files,
  1.3 MiB, all UTF-8; remote divergence clean (PROGRESS_LOG strict
  superset, 0 remote-only lines). But the CI workflow runs the test
  suite before building, so pushing this tree would very likely
  produce a red run and no APK. Push held pending owner decision:
  fix/stabilise these tests first, or wait for the S7 checkpoint.

## 2026-10-30 — S6 built, reviewed (at close-out), fixed: Progress & Sunday (PROGRESS, SET reminders)

- Built per RESEARCH-2026-10-30 §R10.2/§R3/§R5.4/§R5.6/§R8.1:
  Progress becomes the 5th nav destination (D-021 final order
  Today · Learn · Progress · Spaces · Goals). Journey Path hero
  (Concept 1, §R3): stones for counted days only — classified
  strictly from the S3 streak fold's outputs via
  `ReviewStore.currentFold` (red-team #17: no second derivation
  of counted-ness anywhere in PROGRESS); stone fill = Done,
  inlay dot = Self, cracked-outline stone for shield days
  (distance does not advance), dotted bridges over missed days,
  milestones at 7/30/66/100/365 counted days, totals/best in
  the header (never reset). Numbers view: dual-score chart +
  enjoyment trend as hand-rolled painters (D-028), plain
  calendar with day drill-down. Sunday weekly summary (§R5.4):
  pure `summarizeWeek` over the Mon–Sun week — counted X/7,
  shield days stated neutrally, Done and Self averages computed
  and displayed SEPARATELY (never merged; divergence named in
  words only), enjoyment median + most-enjoyed topic/format,
  major points, habits by track, forward line (Sunday's
  unticked one-offs + if–then); shown on Today Sunday ≥18:00,
  archived in Progress; no summary table (recomputed, §R6).
  Reminders (§R5.6/§R8.1): two opt-in toggles, OFF by default,
  `inexactAllowWhileIdle` only, no exact-alarm permission
  anywhere, permission requested only on toggle-on, toggle-off
  cancels, tap payloads route to Today / Day Close, ≥7-day
  absence self-watch suggests turning them off. **No schema
  change — still v5** (reminders are `app_settings` keys; see
  DATA_MODEL S6 note).
- Review history: the build's own review was interrupted
  before completing, so this close-out re-ran the independent
  review from scratch (reviewer had written none of the S6
  code) plus a coordinator pass over every S6 file.
  **Result: 0 MUST / 7 SHOULD / 9 NOTE.** The three hard rules
  were verified clean with file:line evidence: counted-ness
  comes only from the fold; no Done+Self blended value exists
  anywhere (the divergence check and the chart's ×10 drawing
  coordinate are comparisons/rendering only, §R5.2-sanctioned);
  reminders are inexact-only with defaults OFF.
- Fix loop (all SHOULDs fixed, each regression-tested):
  S1 docs currency (this entry; FEATURE_MAP rows + note;
  DATA_MODEL S6 note) · S2 dangling D-028 recorded in
  DECISIONS · S3 Progress/summary error states — was an
  infinite spinner; now a message + retry (2 widget tests) ·
  S4 fold evaluated ~6× per screen load → memoised once per
  store instance/day + calendar future hoisted out of `build`
  (counting-store test pins exactly 1 fold per load) · S5
  Journey painter windowed to the visible slot range (was:
  whole history painted per repaint) · S6
  `WeeklySummary.isEmpty` erased habit-only / cards-only
  weeks as "nothing recorded" → habits + cardsReviewed now
  count as activity (pure tests; mutation spot-check: removing
  the habits clause fails the new test — mutant killed) · S7
  DST-week boundary test added (EU fall-back week; verified
  under `TZ=Europe/Berlin` where the week spans 169h and the
  Sunday-23:30 session stays in its week). NOTE fixes folded
  in: N3 Journey `Semantics` summary label · N4 unscored
  counted stones are outline-only (was an invented 45% fill;
  `journeyStoneFill` pinned by test) · N7 enjoyment trend
  excludes future-dated sessions · N9 in-progress week reads
  "so far" in the summary + card.
- TESTING §9 S6 adoption record: boundary matrix ✓ (month/
  year boundaries from the build; DST week added at close-out;
  summary "generated exactly once" holds by construction —
  pure recompute, determinism-tested) · large-fixture: 365-day
  Journey render widget test ✓ (host), device frame budget
  unverified · security: reminder opt-in/reversible flow
  host-tested with a fake gateway ✓ · **goldens DEFERRED**
  (alchemist still not adopted project-wide — same open item
  as S3–S5; painters are covered by model + widget tests
  meanwhile).
- Known limitations (review NOTEs, recorded not fixed): N1
  chart draws Self ×10 as a drawing coordinate on the shared
  axis (documented in-code; no combined value exists) · N2
  milestones are number gates — no owner "why" text (needs
  storage + owner input) · N5 "mastered" counts questions
  reviewed this week whose CURRENT interval ≥21d (the true
  "reached 21d this week" event is not stored in review_log)
  · N6 habit history follows the template: deleting a template
  drops its track's past rows from summaries, and the carried
  line is empty for a week whose Sunday plan was never
  generated · N8 the main.dart tap-routing handler and
  SettingsScreen have no widget tests (controller + router
  are unit-tested) · ReviewStore.currentFold scans signals
  twice internally (S3 code; the S6 memo bounds it to once
  per screen load).
- Verified: baseline re-run before the review — analyze
  clean, 444/444; after fixes — **analyze clean, 455/455**
  (11 new tests). Unverified (owner/device): notification
  delivery + timing on a real phone (inexact alarms, OEM
  behaviour), the permission prompt flow on-device, Journey
  visual feel and 60 fps over long histories on a mid phone,
  Sunday card in real use. Nothing pushed.

## 2026-10-30 — S5 built, reviewed, fixed: Learn engine (LEARN, QUIZ)

- Built per RESEARCH-2026-10-30 §R10.2 under D-010's standing
  go-ahead, in verified sub-steps (data layer → importer →
  composer/engine → cards → screens/nav → HTML-quiz player),
  each landed green before the next started. Schema **v5**
  (migrations 1–4 untouched): `questions`, `review_log`
  (immutable, append-only by API shape), `learn_sessions`,
  `packs` registry (D-020); `marked_points.question_id` links
  minted cloze (D-014 payoff); all new tables born with sync
  identity (§R6.3).
- LEARN engine (`lib/features/learn/`): pure SM-2-simplified
  scheduler (§R4.3: 1d→3d→×EF, cap 180d, EF floor 1.3, no
  first-lapse EF cut) with glados property tests; payload
  validation for 7 question types (`mcq`, `flashcard`,
  `cloze`, `image_point`, `ordering`, `scenario` capped
  branching with graph-integrity checks, `mythfact` D-022);
  session composer (55/20/25 buckets D-023, warm-up/hardest-
  last ordering, ≤2 back-to-back type/topic, ~40% format
  cap) + SessionRun (answers persist scheduler + log
  immediately; a miss resurfaces once, 5–8 cards later —
  except boss sessions, which are one-pass, D-025); cards
  for every type with immediate explanatory feedback and
  report-this-question suspend; image-point grading in
  shorter-side units over a letterbox-safe surface (§R8.5).
- Quiz packs (`nimo.quizpack` v1 — full contract in
  DATA_MODEL): strict importer — zip hygiene from the raw
  central directory, 50 MB pack / 10 MB media caps, mime
  allow-list + magic bytes + sha256, header dimension caps
  (D-027), per-question skip+report, pack-level rejects
  write nothing; image_point imports suspended behind the
  in-app tap-verify step (§R4.1); re-import semantics
  (same version no-op, higher updates content in place,
  scheduler state preserved, dropped questions suspended
  not deleted). A `packs/` + `media/<pack.id>/` Library
  layout; pack source rows under the target topic.
- Formats (§R4B top 5 — ALL shipped, no slip): scroll-feed
  episodes with arc wrapper + teach-back end-card (episode
  sessions), Myth-vs-Fact battles, tap-on-image pointing,
  capped branching conversation role-play (chat UI, scored
  as one item), boss level (hardest-first composition,
  one unscored hint per D-025) + beat-yesterday end-screen
  comparison vs his own recent medians. Enjoyment rating:
  frozen labels, asked only when ≥5 cards answered, only
  on natural completion, always before stats (D-024).
- Navigation: Learn becomes the 4th destination in a
  data-driven shell (D-021: final Today · Learn · Progress ·
  Spaces · Goals; S6 inserts Progress with no restructure).
  Today launches a review session in 1 tap (Start button on
  the Hub Learn card); Learn landing is session-first
  (§R2.3) with due/new counts, Continue-arc cards, pack
  import, and the image-verify queue. Topic detail gained
  "Build cloze cards" (mint) + pack import.
- REVIEW wiring: the Done Score's +2/+2 learning block is
  live — ReviewStore derives "a finished session ended on
  this local date" inside closeDay/refreshDoneScoreIfClosed
  (D-024). The streak fold is untouched: a session-only day
  is NOT counted, proven by test (red-team #1).
- QUIZ: `html_quiz` item type — import into the Library,
  Android WebView player behind a pure navigation policy
  (only file:// inside the quiz's own folder; hardened
  settings per TESTING §7); non-Android shows the plain
  fallback message (§R8.4). Play-only per D-004.
- Review loop: independent review (SHIP-AFTER-FIXES)
  verified checks 2/3/4 outright (scheduler, two-signals,
  enjoyment gating) and found **2 MUST + 10 SHOULD**, all
  fixed in-stage: M1 pack/media ids that fold under
  filename sanitisation could overwrite another pack's
  files (now rejected at validation); M2 a pack update
  changing an image_point target bypassed the verify gate
  (now re-gated); phase-2 import errors now honour the
  PackException contract; retired questions revive when a
  later pack version re-adds them; boss sessions are
  one-pass; the session screen routes system-back through
  finish/abandon (PopScope) so a completed session can't
  silently lose its score contribution; image dimension
  caps at import (D-027); scenario validation bails early
  on oversized graphs; the boss gate no longer double-
  counts new ⊆ due; the composer's tail-triple hole is
  repaired. Mutation spot-checks (TESTING §10.2): 7
  mutants across scheduler/importer/composer/scenario/
  score-wiring — 5 killed immediately; the 2 survivors
  (media size cap, scenario end-reachability) were hollow
  tests, now rewritten to isolate their guard and both
  mutants verified killed.
- TESTING §9/S5 checklist: build ✓; importer adversarial
  suite ✓ (schema/zip-slip/oversize/coords/unknown types,
  atomic rejects); SM-2 property tests ✓; review-log
  append-only by API shape ✓; session state machine can't
  skip the enjoyment rule ✓ (widget tests incl. back-pop
  paths); goldens — DEFERRED with the same reason as
  S3/S4 (alchemist CI/local-golden split is its own task);
  WebView hardening ✓ item-by-item at the settings/policy
  level (hostile-quiz containment is on-device only —
  the policy unit tests cover the navigation rules);
  Patrol — not adopted (needs a device/emulator; none in
  this VM); MASVS-CODE re-checked in review ✓ (dimension
  caps added from it, D-027).
- Verified (host): `flutter analyze` clean; `flutter test`
  **398/398** (162 baseline + 236 new across the stage),
  independently re-run by the coordinator after the fix
  loop, with both formerly-surviving mutants re-checked
  dead. Sample-pack end-to-end test: the generated Arabic
  Greetings pack (13 questions, 6 types playable + gated
  image_point) imports cleanly and plays a full episode
  session offline; a miss resurfaces in-session and lands
  at 1 day.
- NOT verified (owner, on device): session feel/timing
  and the ≤2-tap friction budget in the hand; HTML quiz
  playback inside the WebView; image-point verify drag on
  a real photo; RTL rendering of Arabic cards on device.
  Known limitations carried forward: zip entry COUNT is
  uncapped (sizes are capped); a scenario card can loop
  forever on an escapable cycle (validation guarantees an
  exit exists, not that it's taken); re-importing a pack
  into a different topic leaves pre-existing questions on
  the old topic; S5 not pushed (push stays owner-gated).

## 2026-10-30 — S4 built, reviewed, fixed: Topics & Library (LEARN-data, LINK, SET-backup)
- Built per RESEARCH-2026-10-30 §R10.2 under D-010's standing
  go-ahead. Schema **v4** (migrations 1–3 untouched): `topics`,
  `sources`, `marked_points` with sync identity columns (§R6.3);
  `day_reviews` rebuilt so `major_point_topic_id` is a real FK
  (`REFERENCES topics(id) ON DELETE SET NULL`, dangling v3 ids
  nulled by a CASE guard in the copy); Inbox project seeded
  idempotently in the default workspace (pointer in
  `app_settings`); Hub Home reads the Inbox count WITHOUT
  seeding (looking at the app must not create a workspace).
- LEARN-data (`lib/features/learn/`): topics/sources CRUD +
  status flow; Library folder (§R6.4 layout, relative paths
  only, **every write temp-then-rename** per red-team #8);
  untrusted filenames sanitised (`file_names.dart`: both slash
  kinds, whitelist, no dot-only names); share-intent capture via
  `receive_sharing_intent` (cold + warm, one-field confirm
  sheet, §R9.5); PDF via `pdfrx` + TXT native reading cards;
  extraction classified honestly (ok / partial /
  scanned_no_text / failed — a scanned PDF says so, OCR stays
  out); **mark-a-point** (D-014 table, D-017 rules) stored
  cloze-ready for S5. Day Close's major-point step can pick a
  topic (S3's N7 closed).
- LINK: link cards are topic triggers (card + topic + link
  source in one creation); D-003 thumbnails layered — user
  image (payload provenance `thumbnail_source`, S4 review fix)
  → og:image auto-fetch (capped, any failure = fallback) →
  designed fallback card; thumbnail cache reads are
  containment-checked like Library paths.
- SET: backup export/import (§R6.5) — zip of VACUUM INTO
  snapshot + manifest + Library tree; restore implements the
  **D-011 guard** (D-016): pre-restore backup always, explicit
  replaces-everything confirmation over a non-empty DB
  (counting `day_plans` too — review fix), staged snapshot
  verified (integrity + FK check + version) before a
  rollback-capable swap; zip-slip and zip-bomb defences;
  future schema/format refused. Android backup-exclusion rules
  NOT touched (owner-gated, unchanged from S3's open items).
- Verified: `flutter analyze` clean; `flutter test` **162/162**
  (baseline 82 → +80). Includes: v3→v4 real-file migration
  (S3 data verbatim + FK behaviour + dangling-id hardening);
  backup round-trip on real files; D-011 refusal/confirmation
  at store level; torn-write + concurrent-reader atomicity;
  mocked share-intent channel (cold + warm); mark-a-point from
  a TXT fixture end to end. Manual mutation spot-checks
  (TESTING.md §10.2): 5 mutants on restoreBackup / writeAtomic /
  sanitizeFileName — guard flip, dropped pre-restore backup,
  skipped snapshot verification, in-place write, backslash
  split dropped — **5/5 killed** (the in-place-write mutant is
  killed by a new concurrent-readers-never-see-a-torn-file
  test written for exactly that purpose).
- Independent review (reviewer wrote none of the code): verdict
  SHIP-AFTER-FIXES — 4 MUST, 8 SHOULD, 6 NOTE. All MUSTs and
  SHOULDs fixed in-stage, each with a regression test where
  host-testable: plan-only DBs bypassed the D-011 guard (M1);
  a failed restore left the app bound to a closed database —
  re-bootstrap is now in a `finally` (M2); a vanished shared
  file was "saved" as an empty topic with a success message —
  now a loud `CaptureException`, nothing created (M3); one
  failed share permanently jammed the share queue — the drain
  now isolates failures and always releases (M4). SHOULDs:
  rollback-capable DB swap + sidecars moved with the swap;
  UI passes its real confirmation through; thumbnail
  `fileFor` containment + 10 MB attach cap; corrupt sidecar
  can no longer spin the reader forever (validated decode,
  catch-all degrade, screen error state); §R4.5 fallback
  encoding deferred knowingly (D-018); auto-fetch can no
  longer overwrite a user thumbnail (D-003); topic deletion
  removes its Library files; zip/entry size caps. NOTEs
  actioned: migration CASE guard, manifest format_version
  check, snapshot FK check, HLC read-modify-write wrapped in
  a transaction, Day Close close-failure recovery, type-
  tolerant payload reads in the item screens; sidecar names
  carry the source id (collision-proof). Recorded limitation:
  Library path resolution is lexical (no symlink following) —
  revisit before S7 sync (DATA_MODEL).
- TESTING.md adoption this stage: **adopted** — §9 S4
  checklist (migration real-file test, adversarial import
  suite incl. traversal/oversize/torn-write, share-intent
  channel mocks, backup guard at store level); §10.2 manual
  mutation spot-checks (above); integration_test smoke harness
  added (device run is the owner's — cannot run in this VM).
  **Deferred with reason** — alchemist goldens for the new
  screens (same CI/local-golden task as S3's deferral).
  **Owner-side open items** — unchanged from S3: CI security
  scans (workflow YAML the connector cannot write) and Android
  backup-exclusion rules (owner-gated).
- Environment note: `pdfrx_engine`'s native-assets hook needs
  clang on this VM; LLVM 20.1.8 was installed to `~/tools/llvm`
  (apt is proxy-blocked) — see `toolchain/NOTES.md` #6.
- **Unverified (device-only, stated plainly):** on-device share
  intent (cold start from another app, SEND_MULTIPLE), real
  pdfrx PDF rendering and real pdfrx_engine text extraction
  (host tests use the fake-extractor seam), the
  integration_test smoke run, and the S4 APK itself (built via
  GitHub Actions after the owner pushes; S4 is NOT pushed —
  local only, like S3).

## 2026-10-30 — S3 built, reviewed, fixed: Close the Loop (REVIEW)
- Built per RESEARCH-2026-10-30 §R10.2 under D-010's standing
  go-ahead. Schema **v3** (migrations 1–2 untouched): `day_reviews`,
  `streak_state` (seeded single row), `shield_events`, `sync_meta`,
  `sync_ops` scaffold; `plan_templates` += starter/anchor/track/
  counts_core (habit fields, §R5.5); `day_plan_items` +=
  counts_core snapshot (D-013); `goals` += track; sync identity
  columns + unique indexes on all syncable tables (§R6.3), with an
  open-time NULL backfill until S7 assigns identity at insert.
- REVIEW (`lib/features/review/`): Day Close flow (Recap → Major
  point → Self Score → Reveal; every step skippable; 5 taps with
  everything skipped; yesterday closable in the late window until
  today's first tick); Done Score formula v1 (weights 1 up to 8
  items, ½ beyond, learning block +2/+2 reserved for S5,
  empty-plan + closed = 60) and Self Score stored/shown separately,
  never merged; Streak Shields as a pure fold over exactly two
  signals (core plan done via snapshotted flags, or Day Close) —
  grant at 7 (D-012), ≤2 held, ≤2 per ISO week derived per date,
  refill 1/7 protected days, late close refunds via re-fold.
  Hub Home gained the Day Close banner + if–then line; routine
  editor gained the habit-details dialog.
- Verified: `flutter analyze` clean; `flutter test` **82/82**
  (baseline 23). Includes: v2→v3 real-file migration test with S2
  data; streak/score named boundary cases + glados property tests;
  night-owl closable-window tests; end-to-end late-close refund;
  backwards-clock monotonicity; Day Close widget flow (all skips,
  leak tracking on). Manual mutation spot-checks (TESTING.md
  §10.2): 8 builder mutants — 4 survived the first pass (weekly
  cap, refill threshold, 80% threshold, one tautological
  empty-plan assertion) → killing tests added → 8/8 killed;
  reviewer ran 3 more (all killed); post-fix snapshot-bypass and
  80% mutants re-killed.
- Independent review (reviewer did not write the code): verdict
  SHIP-AFTER-FIXES. MUST M1 — toggling counts_core/deleting a
  template retroactively rewrote streak history — fixed by the
  D-013 snapshot + regression test. SHOULDs fixed: D-012 records
  the at-7 grant (S1); banner offers "Close today instead" during
  the late window (S2); Hub plan edits refresh a closed day's
  Done Score (S3); HLC gained direct tests (S4). NOTEs: closeDay
  is now a true UPSERT and `is_counted` is written only by
  evaluate (N2); shield_events get fresh sync_ids per evaluate —
  S7 must treat them as derived/non-synced or stabilise identity
  (N1); future-clock folds self-heal (N6); `major_point_topic_id`
  becomes settable when topics land in S4 (N7).
- TESTING.md adoption this stage: **adopted** — glados property
  tests (streak walk + score); leak tracking in the Day Close and
  Hub Home widget tests (dev dep `leak_tracker_flutter_testing`).
  **Deferred with reason** — very_good_analysis (no mid-stage lint
  swap; staged follow-up per TESTING.md §3.1 rollout note);
  alchemist goldens (CI/local golden split is its own task).
  **Owner-side open items** — CI security scans (OSV-Scanner,
  gitleaks, Dependabot: workflow YAML the connector cannot write)
  and Android backup-exclusion rules (§7's #1 storage risk; they
  change device-transfer behaviour, so they need the owner's
  explicit go-ahead, not a silent change).
- Open: on-device verification of S3 (the VM cannot build APKs;
  S2's on-device check is also still open). S3 is NOT pushed —
  the push is a separate owner-gated step, as with S2.

## 2026-10-30 — S2 pushed to GitHub as one snapshot commit
- Owner approved the push in the main chat. Pre-push checks run in
  the main chat: manifest rebuilt (54 files, 194 KiB, all UTF-8;
  `.github/workflows/build-apk.yml` excluded — the working version
  already lives on GitHub); `flutter analyze` clean and
  `flutter test` **23/23** re-run independently of the build report;
  divergence check — remote commits since the S1 sync were only the
  owner's workflow commits, three of my PROGRESS_LOG updates, and
  the probe commits; the one real divergence (this log, reorganized
  newest-first during S2) verified as a strict superset (0
  remote-only lines), so overwriting loses nothing.
- `push_files` now works (the owner's permission changes took
  effect; two-file probe pushed and cleaned up first). S2 landed as
  single commit `2655793f31b1c84af79722b2f7e93ab428a116b0` — 54
  files (45 updated/carried + 9 new). The push triggers the Build
  APK workflow; on-device verification of S2 remains open.

## 2026-10-30 — S2 built and host-verified: Today dashboard (Hub Home) + goals-basic
- Owner approved the "Hub Home" layout from viewable mockups
  (D-009). Built: schema v2 migration (migration 1 untouched) —
  `plan_templates`, `day_plans`, `day_plan_items`, `goals`,
  `app_settings`, `workspaces.pinned`. App shell is now a 3-tab
  bottom NavigationBar (Today · Spaces · Goals).
- TODAY (`lib/features/today/`): TodayStore (plan generation per
  D-002 — active template items fresh/unticked + previous day's
  unticked one-offs copied as carried, idempotent; per-date ticks;
  Mon–Sun weekly pending + per-day pending counts; Home section
  visibility in `app_settings`), Hub Home screen (header with
  disabled search/settings placeholders, week strip, quick add for
  task/goal/note/checklist, plan card with progress + ROUTINE /
  CARRIED badges + inline add + This-week view, pinned spaces,
  recent items, goals section, Customize Home dialog), and the
  RoutineScreen template editor.
- GOAL-basic (`lib/features/goals/`): GoalsStore (add, delete,
  progress clamped 0..target) + Goals tab screen.
- WS: pin/unpin toggle on each workspace row; pinned spaces and
  recent items read through the S1 Store (pinned list, per-workspace
  item counts, latest-5 recent items join).
- Verified by running: `flutter analyze` → no issues.
  `flutter test` → **23/23 passed** (was 10/10): v1→v2 migration
  keeps S1 data + creates S2 tables; plan generation from template;
  carry-over exactly once + idempotency; tick isolation between
  days; weekly pending exactness; goals add/clamp/delete; pinned
  toggle; recent-items query; updated app-boot widget test (boots
  to Hub Home, Spaces tab shows Workspaces); design-preview tests
  still pass.
- Implementation note: new stores follow the S1 pattern exactly
  (plain classes over the database, constructor-injected) — the
  codebase has no provider/ChangeNotifier, and none was added.
- Not verified: on-device behaviour (this VM cannot build APKs —
  see toolchain/NOTES.md); S2 acceptance is host-verified only
  until the owner runs a CI-built APK and confirms the day-rollover
  behaviour on the phone.

## 2026-10-29 — Repo created by owner; access verified; awaiting push
- Owner created the GitHub repo: **AsifXdroid/Nimo-Os** (private,
  empty). Muse's GitHub access to it verified by an actual read
  call (`list_commits` → "409 Git Repository is empty" — the repo is
  reachable and empty, not a permission error).
- Next: owner pushes from the unzipped project with remote
  `https://github.com/AsifXdroid/Nimo-Os.git`; the push triggers the
  Build APK workflow automatically.

## 2026-10-29 — Owner chose GitHub Actions; repo prepared for push
- Owner's choice: they will push the repo and run the workflow.
- Repo state prepared: git repo on branch `main`, no commits yet
  (first commit is part of the owner's push). `git add -A --dry-run`
  verified **48 files** would be included (lib 10, android 19,
  docs 5, test 2, toolchain scripts + NOTES 4, workflow, PLAN,
  pubspec…); `*.log`, `.dart_tool/`, `build/`, `local.properties`
  correctly ignored. Diagnostic scratch scripts removed; README
  replaced with a real project README.
- Awaiting: owner's push → workflow run → APK artifact download →
  on-device S1 check (install, create data, kill/reopen app).

## 2026-10-30 — Overnight research delivered (R1–R10 + R4B, quality pass + red-team)
- Owner-commissioned research completed and delivered early at the
  owner's request: `~/workspace/goals/daily-life-android-app/files/RESEARCH-2026-10-30.md`
  (2,234 lines). Covers product science, UI, progress visuals
  (recommends Journey Path), learning engine + fun-first formats,
  daily-loop mechanics, schema v3, staged sync, platform checks,
  flaw/conflict audits, feature list v2 and a re-sequenced S3–S8
  stage plan superseding old S3–S6 (pending owner approval).
- Quality pass corrected real errors (incl. a wrong-paper citation);
  red-team review: 3 MUST-FIX (2 fixed in place; snapshot
  "Repair sync" data-loss guard left as an owner decision),
  8 SHOULD-FIX, 7 NOTE.

## 2026-10-30 — D-008 decided: Plate B Midnight; features discussion opened
- Owner viewed the three plates in a viewable chat preview (the
  Widget Preview code alone wasn't visible to them — noted for how
  previews get presented in future) and picked **B Midnight**: "I
  like dark mode mostly." Preview widget state corroborates
  (plate = midnight).
- Change: `main.dart` defaults to
  `AppTheme.forPlate(AppPlate.midnight)`; DECISIONS.md D-008 moved
  to Decided. Plates A/C kept as options.
- Next: owner wants to discuss the app's features before S2 starts.

## 2026-10-29 — Design plates as real code + Widget Previews (D-008 open)
- Owner asked for the UI and design options as a preview of the real
  app code (not a mockup image). Added `AppPlate` (Calm Focus /
  Midnight / Warm Paper) to `lib/core/theme.dart` — `AppTheme.light()`
  unchanged for the running app; `AppTheme.forPlate()` returns any
  plate.
- Added `lib/features/design_preview/design_preview.dart`: pure-UI
  prototypes of the Today dashboard (S2), the reel board with the
  D-003 fallback card (S3) and the workspaces list (S1), each with
  three `@Preview`s (one per plate, phone size 390×780, group
  "Design plates"). Sample data only; no DB/dart:io so the web-based
  previewer can render them.
- Verified by running: `flutter analyze` → no issues.
  `flutter test` → **10/10 passed** (7 S1 + 3 new plate smoke tests
  rendering every body in every plate). `flutter widget-preview
  start` created the `.widget_preview` scaffolding and connected its
  analysis server, then stopped at "Failed to locate browser" — this
  VM has no Chrome, so the visual render itself is NOT verified
  here; it renders on the owner's machine (IDE Widget Preview tab or
  the CLI's Chrome view).
- Open: owner picks a plate (D-008). Unpicked plates stay in the
  theme file as documented options, app keeps Plate A meanwhile.

## 2026-10-29 — S1 built and host-verified; APK build blocked by VM
- Toolchain installed under `~/tools` (survives VM replacement):
  Temurin JDK 17.0.21, Flutter 3.47.8 / Dart 3.13.7, Android SDK
  platforms 35+36, build-tools 35+36, platform-tools. Two proxy
  workarounds were needed (Java can't tunnel through this proxy):
  SDK packages installed from curl-fetched zips, Gradle distribution
  pre-seeded. Full details: `toolchain/NOTES.md`.
- S1 code complete per FEATURE_MAP: CORE (DB + migrations, theme),
  WS/PRJ screens (create/rename/delete), ITEM registry + note and
  checklist types with editors, Store data layer.
- Verified by running: `flutter analyze` → no issues. `flutter test`
  → **7/7 passed**: workspace/project/item CRUD, cascade delete,
  payload round-trip, checklist toggle/order, **real-file DB
  close/reopen persistence**, and an app-boot widget test.
- **Blocked: APK build in this VM.** Gradle's client↔daemon loopback
  IPC fails at platform level (minimal Java loopback repro stalls;
  Python equivalent works). Evidence + ruled-out causes in
  `toolchain/NOTES.md`. Prepared routes: GitHub Actions workflow
  (`.github/workflows/build-apk.yml`) or the owner's laptop
  (`toolchain/build_on_laptop.sh`). Awaiting owner's choice.
- Remaining S1 acceptance item: install + run on the owner's phone
  (also covers the "survives restart" check on-device).

## 2026-10-29 — Decisions confirmed; capability check done
- Owner confirmed the proposed decisions ("go with them"): D-006
  stack = Flutter + SQLite, D-003 thumbnails = layered; D-002/D-004/
  D-005 recorded as defaults under that go-ahead (overridable before
  their stages). S0 gate now met.
- Environment capability check (actual commands run): no Flutter /
  Dart / JDK / Android SDK installed; download endpoints for Flutter,
  pub.dev, and Google Android repo all reachable (HTTP 200); 149 GB
  disk free; **no /dev/kvm** (no usable emulator) and ~8 GB RAM /
  2 CPU (builds will be slow). Conclusion reported to owner: full
  code + tests + release APK can be produced here; on-device visual
  verification happens on the owner's phone.
- Open: owner's go-ahead for toolchain install + S1 start.

## 2026-10-29 — S0 started: planning pack created
- Created: `PLAN.md` (product definition, 7 stages S0–S6 with
  acceptance checks, edit-friendly architecture rules, doc system),
  `docs/FEATURE_MAP.md` (11 feature rows, all `planned`),
  `docs/EDITING_GUIDE.md` (edit protocol + definition of done),
  `docs/DECISIONS.md` (D-001 decided; D-002…D-006 open).
- Verified: files written and cross-references checked by reading
  them back. No code exists yet — nothing to run.
- Open: owner decisions D-002…D-006. Next stage gate: S0 completes
  when D-006 (stack) is confirmed; S1 then creates DATA_MODEL.md and
  the app skeleton.

## 2026-10-29 — Connector push attempted; blocked on install write permission
- Owner chose the connector push with the icon swap. Icons done per
  D-007 (5 PNGs removed; adaptive vector icon added; XML validated).
- Snapshot prepared per procedure: 46 text files, 98 KiB, all UTF-8;
  repo re-verified empty immediately before the push.
- Push result: FAILED — GitHub returned 403 "Resource not accessible
  by integration" when creating the git tree. The Muse GitHub App
  installation evidently lacks Contents *write* on this repo (reads
  work). Nothing was pushed; no sync record written.
- Meanwhile the repo gained its first commit by the owner
  (564c4d1 "Initial commit", 2026-10-29 16:50 UTC): exactly one file,
  an **empty** README.md (no .gitignore/LICENSE). The snapshot's real
  README will replace it — nothing of value is overwritten, but the
  retry needs the owner's OK plus the permission fix first.
- Next: owner enables Contents read/write for the app installation
  (or pushes from their laptop instead); retry then re-checks the
  branch head (564c4d1) before writing.
- Retry (same day, after owner said write access enabled): identical
  failure — 403 "Resource not accessible by integration" on tree
  creation. Repo verified unchanged afterwards (head still 564c4d1,
  "Initial commit"). Write tools ARE advertised for this connector
  and auth is connected, so the block is the App installation's
  permissions (or Muse's own connector read/write control), not
  the request shape. Owner given the exact checklist: GitHub
  Settings → Installations → meta-muse-ai → Contents must say
  "Read and write"; accept any pending permission update; also
  check Muse's GitHub connector isn't set to read-only. If
  Contents is read-only with no upgrade path, the connector route
  cannot write and the laptop push is the fallback.
- Diagnosis (owner asked to pin it down): a single-file write probe
  via the connector SUCCEEDED (`.muse-write-probe.txt`, commit
  1046532 on main). So Contents *write itself works* — the failure is
  specific to `push_files`, whose multi-file tree call
  (POST /git/trees) GitHub denies to this integration ("Resource not
  accessible by integration"). Workaround candidates put to owner:
  (a) 46 single-file connector writes (46 commits; probe file's
  deletion folds into that batch), or (b) laptop push (one commit).
  Probe file left in place until the owner picks, so its deletion
  rides along with the chosen route.
- Outcome: owner picked the file-by-file route. **46 of 47 writes
  landed** (head `ede4b3fa30db`, the probe-deletion commit; probe file
  gone). The single failure is the workflow file itself: creating
  `.github/workflows/*` needs GitHub's separate **Workflows**
  permission, which this integration token also lacks — same 403.
  Owner to add that one file via the GitHub web UI (their own
  identity is not subject to the restriction); its commit triggers
  the first Build APK run. All other S1 content is in the repo.
  Note for the future: workflow-file changes likewise cannot go
  through this connector — web UI or real git for those.
- Owner added the workflow via web UI (commit d2e9db7, 2026-10-29
  17:31 UTC) but with two defects found on re-check: filename is
  `build- apk. yml` (spaces — extension " yml" is not `.yml`, so
  Actions ignores it), and the pasted content's last line is split
  (`retention` / `-days: 30` instead of `retention-days: 30`).
  Everything else byte-identical. Fix is owner-side (rename + one
  line in the web editor); that commit will trigger the first run.
- Owner renamed the file to `build-apk.yml` (commit b24de9dd,
  2026-10-29 17:45 UTC) — name now correct. Content re-diffed: the
  tail is STILL split (`retention` / `-days: 30`, 1269 bytes vs
  correct 1268), so the YAML remains invalid; the rename commit's
  run cannot succeed. Owner given the one-line fix to apply in the
  web editor; that commit re-triggers the build.
- Owner fixed the line and reports (2026-10-29 ~23:31 IST): the
  Build APK run SUCCEEDED and the app installed and opened on their
  phone. The full pipeline (code here → GitHub Actions → APK →
  device) is now proven end to end. Remaining S1 acceptance item:
  owner to confirm the persistence check (create data, swipe away,
  reopen — data still there).
- Owner feedback on first run: "the app was not what I expected, it
  was a very basic one." Expected at S1: this stage is the core
  shell only (workspaces/projects/items, note + checklist, plain
  Material UI). The parts from the original vision — Today
  dashboard (S2), reel cards (S3), in-app quizzes (S4), goals (S5)
  — are the upcoming stages. Next-step choice put to the owner.

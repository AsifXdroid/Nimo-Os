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

## Open — awaiting owner

- (none blocking S1)

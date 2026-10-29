# Editing Guide — how every change is made (human or AI)

This app is edited often and over a long time. This guide is the
contract that keeps it editable: anyone editing — including a future
AI session with no memory of today — follows these steps, in order.

## Before touching anything

1. Read `PLAN.md` §3 (architecture rules) and §5 (current stage).
2. Find the feature's row in `docs/FEATURE_MAP.md`. That row names the
   owning folder, its tables, and its tests. Work **inside** that
   folder. If the change doesn't fit any row, it is either a new
   feature (add a row + ID first) or it belongs in `lib/core/`
   (shared) — decide which, and say so in the change report.
3. Check `docs/DECISIONS.md` for decisions touching this feature.
   A decision is changed only by adding a new decision entry that
   supersedes it — never by silently editing the old one.

## While editing

4. Stay inside the owning folder. Cross-feature needs go through
   `lib/core/`; features never import each other's internals.
5. Schema change? Add a **new numbered migration** and update
   `docs/DATA_MODEL.md` in the same change. Never edit a shipped
   migration.
6. New item type? Folder under `lib/features/items/<type>/` + one
   registry line + one FEATURE_MAP row. Nothing else changes.
7. UI change? Use theme tokens from `core`; no hardcoded colours or
   sizes in feature code.

## Before calling it done (Definition of Done)

8. Run the feature's tests and the full suite; run the app and check
   the changed behaviour actually happens. Report what was run and
   what was not — never report unverified success.
9. Update docs **in the same change**:
   - FEATURE_MAP row (status / locations if moved),
   - DATA_MODEL.md (if schema changed),
   - DECISIONS.md (new entry if a choice was made or changed),
   - CHANGELOG.md (if user-visible),
   - PROGRESS_LOG.md (date, feature IDs touched, what was verified).
10. The change report names: feature IDs touched, files changed,
    tests run + result, docs updated. If any of the four is missing,
    the change is not finished.

## Standing rules

- No commits without the owner's explicit approval for that commit.
- No silent behaviour changes: if a requirement is ambiguous, record
  the ambiguity as an open decision in DECISIONS.md and ask — do not
  pick silently.
- Docs and code disagree? The code is what runs, but the *docs* are
  the intent — flag the disagreement in the report and fix one of
  them in the same change; never leave them quietly inconsistent.

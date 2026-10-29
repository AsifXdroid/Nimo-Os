# Daily Life App

A personal Android app: **Workspaces → Projects → typed Items**, with a
"Today" dashboard for the daily plan, weekly pending plans, and
short-term goals. Flutter + SQLite, offline-first.

- **Start here:** [PLAN.md](PLAN.md) — product definition, stages
  S0–S6 with acceptance checks, architecture rules.
- **Editing the app?** Read [docs/EDITING_GUIDE.md](docs/EDITING_GUIDE.md)
  first, and find your feature in [docs/FEATURE_MAP.md](docs/FEATURE_MAP.md).
- Data model: [docs/DATA_MODEL.md](docs/DATA_MODEL.md) · Decisions:
  [docs/DECISIONS.md](docs/DECISIONS.md) · Progress:
  [docs/PROGRESS_LOG.md](docs/PROGRESS_LOG.md)

## Status

S1 complete and host-verified (workspaces/projects/items, note +
checklist items; analyze clean, 7/7 tests). APK builds run in GitHub
Actions — see below.

## Building the APK

The agent VM cannot run Gradle (see [toolchain/NOTES.md](toolchain/NOTES.md)),
so APKs are built by **GitHub Actions**: push to `main` (or run the
"Build APK" workflow manually from the Actions tab) and download the
`daily-life-app-release-apk` artifact from the run.

Alternative: build on a machine with Flutter installed via
`toolchain/build_on_laptop.sh`.

## Develop

```sh
flutter pub get
flutter analyze
flutter test
```

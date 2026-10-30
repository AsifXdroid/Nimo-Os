# TESTING.md — Testing & security playbook (Nimo OS / Daily Life App)

> Written 2026-10-30 at the owner's request: tools and skills for finding **errors, bugs and
> vulnerabilities beyond generic unit/widget tests**, mapped onto the S3→S8 pipeline.
> Status: **recommendations only** — nothing in this doc adds a package or installs a tool.
> Adoption happens inside each stage build, one stage at a time, and is recorded in
> `DECISIONS.md` + `FEATURE_MAP.md` (per `EDITING_GUIDE.md`) when it lands.
> Versions below were checked against pub.dev / vendor docs on 2026-10-30. Items that could
> not be fully verified are marked **[unverified]** inline and listed again in §11.

Project facts this playbook is fitted to (read 2026-10-30):

- Flutter 3.47.8 / Dart 3.13.7, toolchain in `~/tools`; SQLite via `sqflite` + real-file
  tests via `sqflite_common_ffi`. Stores are plain classes (constructor injection,
  FutureBuilder UI) — no provider, no codegen anywhere in the app.
- Current suite: 23/23 host tests passing (S2 state). Tests already use **real databases**
  (in-memory/file via ffi), not mocks — this playbook protects that pattern.
- CI (`.github/workflows/build-apk.yml`, owner-maintained via web UI — the connector cannot
  write workflow files): runs `flutter analyze` + `flutter test`, then builds the release APK.
- **APK cannot be built in this VM** (Gradle loopback IPC is broken) and there is **no
  emulator** (no /dev/kvm). Anything needing a device runs on the owner's phone; anything
  needing an APK runs in GitHub Actions.
- Threat model: personal, local-only app, one user, own devices. No accounts, no server,
  no other people's data. Security work is sized to that — see §7.

---

## 1. What we already have (found installed / in place)

### 1.1 Muse skills already in `~/workspace/custom-skills/` that plug into stage QA

| Skill | What it adds to our stage workflow |
|---|---|
| `test_driven_development` | Discipline for the risky engines (streak, score, SM-2, sync merge): write the failing invariant test first, then the code. Use for every S3/S5/S7 engine function. |
| `systematic_debugging` | Root-cause protocol when a test or on-device check fails — stops "guess-and-patch" loops during the build → review → fix cycle. |
| `verification_before_completion` | The gate before a stage is called done: evidence (test output, analyze output) before any success claim. Already matches the owner's standing rule. |
| `dart_add_unit_test` | Scaffolds `package:test` unit tests for pure logic (score formula, HLC, pack validator). |
| `flutter_add_widget_test` | Scaffolds widget tests in the project's existing style. |
| `flutter_add_integration_test` | Configures `integration_test` and converts ad-hoc device explorations into permanent integration tests — the bridge to §4.4. |
| `dart_generate_test_mocks` | Mockito-style mock generation. Available but **not our default** — see §5.3 for why real-DB tests win here, and where mocks do earn their place (S7 transport). |
| `dart_collect_coverage` | Coverage collection/reporting workflow for the per-stage coverage ratchet (§8). |
| `dart_run_static_analysis` | Analyzer workflow beyond the default run — pairs with the stricter lint set in §5.1. |
| `dart_fix_runtime_errors` | Triage of runtime failures surfaced by tests/device runs. |
| `flutter_add_widget_preview` | Fast visual iteration on new screens before goldens are locked (§4.3). Already used for the design plates. |
| `ponytail_review` | Per-change review pass that explicitly asks "is risky code tested?" — run on each stage diff before the fix loop closes. |
| `ponytail_audit` | Whole-repo audit (bugs, security holes, untested risky code) — run once per stage, at the review step, not per commit. |
| `requesting_code_review` / `receiving_code_review` | Structure for the stage review step and for acting on its findings without silently dropping any. |
| `subagent_driven_development`, `executing_plans`, `writing_plans` | The pipeline mechanics themselves: stage plan → build subagent → independent verify. |

**Gap:** there is no dedicated mobile-security skill in the local catalog. The security
layer (§6–§7) is therefore checklist-driven (OWASP MASVS) rather than skill-driven. If a
future skill search finds a maintained MASVS/MASTG skill, evaluate it then — do not install
an unverified one mid-pipeline.

### 1.2 Already in the project

- `flutter_lints` ^6.0.0 baseline, `flutter analyze` clean, CI runs analyze + test per push.
- Real-DB test harness pattern (`sqflite_common_ffi`) — the highest-fidelity seam we have;
  most "integration" risk in this app is store/SQL behaviour, and it is already covered
  at that seam.
- The workflow file on GitHub is correct and builds release APKs (S1/S2 verified).

---

## 2. Layered test strategy

One pyramid, sized to a one-person project. Each layer names what it catches that the
layers below it cannot.

| Layer | What | Catches | Runs where |
|---|---|---|---|
| L0 Static | `flutter analyze` + strict lints (§5.1), format check | Type slips, unawaited futures, dead code, unsafe casts before runtime | VM + CI per push |
| L1 Unit / property | Pure-function tests + property tests (§5.2) for streak walk, score formula, SM-2 scheduling, HLC, pack validation, sync merge | Logic errors across the *whole input space*, boundary off-by-ones | VM + CI per push |
| L2 Store / DB | Real-SQLite tests per store (existing pattern), migration tests per schema version | SQL errors, constraint violations, migration data loss | VM + CI per push |
| L3 Widget + golden | Widget tests; golden screenshots (§4.3) for shipped screens in the Midnight plate | Layout regressions, theme/token breakage, overflow | VM + CI per push (CI goldens) |
| L4 Flow (host) | Multi-screen widget flows with fake clock + real DB (e.g. close-the-day end to end) | Wiring mistakes between screens/stores that unit tests miss | VM + CI per push |
| L5 Device flow | `integration_test` / Patrol (§4.4) on the owner's phone | Platform channels (share intent, notifications, file picker), real rendering, midnight rollover | Owner's phone, per stage |
| L6 Security | MASVS checklist pass (§7), dependency + secrets scanning (§6), MobSF on the release APK | Vulnerabilities, not bugs: exposed backups, WebView misconfig, vulnerable deps | CI per push (scans) + per stage (checklist, MobSF) |

Per-stage emphasis (details in §9): **S3** = L1 property tests for streak/score.
**S4** = adversarial import/backup tests (L2/L6). **S5** = importer fuzz + WebView
hardening + scheduler properties. **S6** = goldens + calendar boundary matrices.
**S7** = sync-merge stateful property tests + restore-guard tests + MobSF.
**S8** = transport security checks + performance traces + full L6 pass.

---

## 3. Adopt-now list (at the stage named, not all at once)

Exact versions verified 2026-10-30 unless marked. "Adopt" still means: added inside that
stage's build, logged in `DECISIONS.md`, suite green before/after.

### 3.1 `very_good_analysis` ^11.0.0 — stricter lints (adopt in S3)
- Dev dependency only; `analysis_options.yaml` switches its include from
  `flutter_lints` to `package:very_good_analysis/analysis_options.11.0.0.yaml`
  (pin the versioned file, not the floating one, so lint behaviour can't change under us).
- 11.0.0 is built for Dart 3.13 — matches our SDK. ~190 rules: adds real bug-catchers
  flutter_lints lacks (unawaited-future and async-misuse rules, `strict-casts` /
  `strict-inference` / `strict-raw-types` language modes).
- Rollout that avoids a noise flood: adopt with CI still non-fatal for one stage,
  burn down findings in the fix loop, then switch CI to
  `flutter analyze --fatal-warnings` from the next stage on.
- This replaces any need for `dart_code_metrics` (see Rejected, §5).

### 3.2 Leak tracking in widget tests — built into the SDK (adopt in S3, costs nothing)
- `flutter_test` already ships leak tracking (`leak_tracker` 11.0.2 /
  `leak_tracker_flutter_testing` 3.0.10 ride along as flutter_test dependencies):
  undisposed `TextEditingController`s / `AnimationController`s / focus nodes fail the
  widget test instead of leaking silently on device.
- Enable via `test/flutter_test_config.dart`. **[unverified]** the exact enablement API
  for Flutter 3.47.8 (the API surface changed across releases — `LeakTesting` settings
  vs the older experimental flag). Verify against the installed SDK's own docs/source
  at adoption; budget 30 minutes, expect a few "leaks" in existing screens to fix or
  explicitly ignore with a reason.

### 3.3 `alchemist` ^0.14.0 — golden tests (adopt in S3 for Today/Close; grow per stage)
- Successor to the discontinued `golden_toolkit` (§5). Why it fits this project exactly:
  the UI is theme-driven (Midnight plate tokens), so a token change *should* repaint
  everything — goldens are how we notice when it also repainted something unintended.
- Decisive feature for us: **separate local and CI goldens**. CI goldens render with a
  platform-independent test font, so they pass on the GitHub Linux runner; local goldens
  keep real rendering for the VM. Plain `matchesGoldenFile` goldens generated in this VM
  routinely fail on other machines over font rasterisation — alchemist exists to kill
  exactly that flakiness.
- Discipline: goldens are reviewed like code. A golden diff is either a bug (fix) or an
  intended design change (regenerate + say so in the stage report). Never regenerate
  blindly to make CI green.

### 3.4 `glados` ^1.1.7 — property-based tests for the risky engines (adopt in S3)
- Pure-Dart property testing (`forAll` over generated inputs, with shrinking). Target
  list, in risk order: streak day-walk (shields, caps, refills, week boundaries),
  Day Score formula (monotonicity, clamping, empty-plan rule), SM-2 scheduler (S5),
  quiz-pack validator (S5), sync merge (S7).
- Honest caveat: 1.1.7 is from Dec 2023 and maintenance is rated poor by FlutterGems.
  Acceptable because it is a **dev-only, pinned** dependency testing pure functions —
  if it ever breaks, the fallback is seam-free: seeded `Random` loops in plain
  `package:test` express the same invariants with ~20 lines of helper.
- Alternatives noted, not chosen: `wheatley` (Glados' named successor, same `forAll`
  API; **[unverified]** current version — pub.dev page is quiet), `property_testing`
  ^0.2.1 (adds shrinking + *stateful* runners — attractive for S7 sync merge; young,
  single-ecosystem provenance; re-evaluate at S7).

### 3.5 `integration_test` (SDK) now; Patrol when native surfaces arrive (S4/S5)
- `integration_test` ships with the Flutter SDK — no version to pin. Adopt in S4 for
  the first real-device flows (share-intent capture, file import) run on the owner's
  phone via `flutter test integration_test/...` — this VM cannot run them (no emulator),
  so they live in a per-stage device checklist (§9), not in CI.
- **Patrol** (LeanCode): `patrol` ^4.10.0 + `patrol_cli` ^4.8.0 (versions per pub.dev
  changelog crawl 2026-10-30; the publisher listing still showed 4.9.0 — re-confirm the
  pair at adoption, they must match Patrol's compatibility table). Adopt at **S5**, when
  flows start crossing into native UI that `integration_test` cannot touch: notification
  permission dialogs (S6 reminders), WebView interaction (S5 HTML quizzes), share sheet.
  Until a flow needs a native surface, Patrol is overhead — native Gradle/Xcode setup
  plus a second CLI to keep in lockstep.
- Middle step available anytime: `patrol_finders` ^3.6.0 standalone gives widget tests
  the nicer `$` finder syntax without any native setup.

### 3.6 CI security scanning — three cheap additions (adopt in S3, owner applies YAML)
All three run in under ~2 minutes and belong in a separate lightweight workflow (or a
second job) so they never block the APK build:

1. **OSV-Scanner** (Google) against `pubspec.lock` — officially supports Dart lockfiles.
   Use the `google/osv-scanner-action` or install the binary in the job
   (`osv-scanner --lockfile=pubspec.lock`). Catches known-vulnerable dependency versions,
   including transitive ones, against the OSV database (which ingests pub.dev advisories).
2. **Dependabot** — GitHub natively supports the `pub` ecosystem (dependency graph,
   alerts, and version-update PRs). Add `.github/dependabot.yml` with two entries:
   `package-ecosystem: "pub"` (weekly) and `package-ecosystem: "github-actions"`
   (monthly — keeps the workflow actions themselves patched). Free, zero maintenance.
3. **gitleaks** — `gitleaks/gitleaks-action@v2` is free for personal-account repos
   (a license key is only required for organisation-owned repos; this repo is personal).
   Low value today (no secrets exist in this app) but near-zero cost, and it is the
   tripwire that matters the day a sync pairing secret or signing key wanders toward a
   commit in S7/S8. Equivalent alternative: run the gitleaks CLI binary in the job.

### 3.7 Coverage ratchet (adopt in S3, no new package)
- `flutter test --coverage` in CI; publish `coverage/lcov.info` as a run artifact.
  Use the already-installed `dart_collect_coverage` skill locally for HTML reports.
- Rule: **no global percentage gate.** Ratchet per-file on the risky engines only —
  streak/score/scheduler/merge files stay at ~100% line coverage (their property tests
  make this cheap), UI files are covered by goldens + widget tests instead. A single
  global number invites gaming and punishes UI code unfairly.

### 3.8 `mobsfscan` in CI (adopt in S4, informational only)
- `MobSF/mobsfscan` GitHub Action scans source and emits SARIF to the repo Security tab:
  manifest misconfigurations, hardcoded-secret patterns, insecure Android settings.
- Honest limit: its rules target native Android/iOS code and manifests — it sees our
  `AndroidManifest.xml` and Gradle config, **not** Dart logic. Treat findings as a
  manifest checklist, not an app audit. Full MobSF is §6.2.

---

## 4. Deliberately minimal: mocking and performance

### 4.1 Mocking — why we need almost none, and the one exception
- Our stores are plain classes over sqflite, and tests already run them against **real**
  SQLite files (ffi). A mocked database would test our assumptions about SQLite instead
  of SQLite — for a data app, the real-DB test is both cheaper and truer. **No mocking
  library is adopted for store tests.** This is a decision, not an omission.
- Where mocks *do* earn their place: seams that are not ours — platform channels
  (share-intent, file picker, notifications) in S4/S6, and the LAN transport/clock in
  S7, where a fake peer is the only way to test merge behaviour deterministically.
- If/when that day comes: **`mocktail` ^1.0.5** (verified current, Apr 2026) — same API
  shape as Mockito with **no code generation**, which keeps the project's zero-codegen
  property. Mockito (5.x) is rejected for this project: it drags in `build_runner` and
  generated `.mocks.dart` files to solve a problem we mostly don't have (§5).

### 4.2 Performance testing — hooks, not a platform
- No perf tooling to adopt now. The app is local CRUD + lists; the realistic perf risks
  are (a) Today screen rebuild cost as data grows, (b) Journey path rendering (S6),
  (c) sync package processing on large libraries (S7).
- Hooks already in the SDK: `integration_test`'s `binding.traceAction` / timeline
  summaries on device, Flutter DevTools profiling on the owner's phone, and a seeded
  "1,000 items / 365 days" fixture DB for L2/L4 tests so slow queries fail tests, not
  thumbs. Adopt the fixture in S6 (when a year of data exists in the model); add trace
  actions in S8 polish if any screen feels slow. Anything more (dedicated perf CI,
  benchmark suites) is ceremony for a personal app.

---

## 5. Rejected / deferred — with reasons

| Candidate | Verdict | Reason |
|---|---|---|
| `golden_toolkit` | **Rejected** | Marked **discontinued** on pub.dev (0.15.0 is final). `alchemist` is its maintained successor and adds the CI-golden split we need. |
| `dart_code_metrics` | **Rejected** | **Discontinued** on pub.dev (5.7.6 final). Its successor (DCM) is a commercial product; per-stage cost/benefit for a personal app is poor, and `very_good_analysis` + analyzer strict modes cover the bug-finding share of its value. Metrics-for-metrics'-sake (coupling/complexity dashboards) is not a gap this project has. |
| `custom_lint` (own rules) | **Deferred to post-S8** | The framework is mid-transition: the upstream repo was reported archived (May 2026) **[unverified — single source: a dependent package's pub.dev README]** and the ecosystem (e.g. `riverpod_lint` 3.1.x) is migrating to Dart's official analyzer-plugin system. Writing project rules (e.g. "no raw SQL string interpolation") on a moving foundation is wasted work; the same invariant is enforceable today as a grep-level check in the stage review. Revisit once the official plugin system settles. |
| `mockito` | **Rejected** | Codegen tax (`build_runner`, generated files) for a need §4.1 shows we barely have. `mocktail` covers the exception cases with zero codegen. |
| CodeQL (GitHub code scanning) | **Rejected** | CodeQL does not support Dart — it would scan nothing of our app code and imply coverage that doesn't exist. (Verified: CodeQL's published language list excludes Dart.) Our SAST layer is the analyzer + strict lints + mobsfscan, honestly labelled. |
| Mutation testing tooling | **Does not exist for Dart** | See §10. No public automated mutation tool supports Dart (Stryker has no Dart runner; Google's Dart mutation testing is internal). Substitute: manual mutation spot-checks + boundary matrices (§10). Anyone selling us a Dart mutation score is selling fiction. |
| SQLCipher / `sqflite_sqlcipher` | **Not now** | Full verdict in §7.3: cost (key-management risk, fork maintenance, broken tooling/sync assumptions) exceeds benefit under the current threat model. Revisit triggers are named there. |
| Full MobSF per push | **Rejected (per-stage instead)** | The full framework wants ~4 GB RAM / 2 CPU and minutes per scan via Docker + REST API. Feasible and worth it **per stage on the release APK** (§6.2); wasteful and flaky as a per-push gate for a one-person repo. `mobsfscan` (§3.8) is the per-push stand-in. |
| `dart_pre_commit` | **Deferred (optional convenience)** | Real and maintained (6.1.1), and it even bundles an osv-scanner task — but it optimises a git-hook workflow this project doesn't use (work happens in the agent VM; pushes are snapshot commits). OSV scanning lands in CI instead (§3.6). Revisit if local pre-push checks ever become the norm. |

---

## 6. Security scanning toolchain

### 6.1 Per push (CI, cheap, §3.6 recap)
OSV-Scanner on `pubspec.lock` · Dependabot (pub + github-actions) · gitleaks ·
mobsfscan (from S4). All free at this repo's scale; all fail-soft initially (report,
don't block) for their first stage, then blocking once the baseline is clean.

### 6.2 Per stage (on the release APK from Actions)
**MobSF full static scan** — run the official Docker image
(`opensecurity/mobile-security-framework-mobsf`) locally in the VM or on the owner's
laptop, upload the stage's release APK via its REST API, export the JSON report, and
file it in the stage's `hidden_files/` with findings triaged into the stage report.
It checks what mobsfscan can't: the *built* artefact — permissions actually merged,
debuggable flag, exported components, certificate, embedded URLs/secrets, MASVS-mapped
findings. One scan per stage is the right cadence; dynamic analysis is out of scope
(MobSF's dynamic mode needs an emulator/rooted device and buys little for a local app).

### 6.3 Repository hygiene notes
- Keep `pubspec.lock` committed (it is) — OSV and Dependabot both key off it, and
  reproducible builds need it. Consider `dart pub get --enforce-lockfile` in CI at S8.
- The GitHub Actions APK artifact is the app the owner installs: keep retention at
  30 days (already set) and treat artifact links as private distribution.

---

## 7. Security checklist frame: OWASP MASVS v2.1, mapped to this app

MASVS v2.1.0 has 8 categories / 24 controls. Below is the honest mapping for a
local-only, single-user app — including the categories that legitimately shrink.

| Category | Relevance here | Concrete checks for this app |
|---|---|---|
| **MASVS-STORAGE** | **High** — the DB *is* the product | DB lives in the app-private directory only (never shared storage). **Android backup exposure is the #1 real risk:** set backup rules (`dataExtractionRules` / `fullBackupContent`) to exclude the database and export folder from cloud backup and device-transfer, or a plaintext copy of the owner's whole life-log rides along to Google Drive. Export/backup zips are plaintext by design (D-005 lineage) — the UI must say so at export time, and exports go to a user-chosen location, never auto-uploaded. No sensitive content in logs (`debugPrint` audit in review). Sync "Repair" restore keeps the decided guards: automatic pre-restore backup + explicit replace-everything confirmation on a non-empty DB. |
| **MASVS-CRYPTO** | Low today, real at S7 | No hand-rolled crypto, ever. Sync identity values, pairing codes and any nonce come from `Random.secure()`. If backup encryption is ever added, it uses a maintained AEAD construction with the key story decided *first* (§7.3). |
| **MASVS-AUTH** | Mostly N/A | No accounts, no sessions. S7/S8 LAN pairing *is* an authentication surface: QR + short PIN, pair once, remember the peer, refuse silent re-pairing. |
| **MASVS-NETWORK** | Low today, real at S7/S8 | Today: the only network calls are reel-thumbnail/oEmbed fetches — HTTPS only, cleartext traffic disabled in the manifest, no user data in those requests beyond the reel URL the owner saved. S8 LAN sync: TLS with a **pinned** peer certificate/fingerprint exchanged at pairing (self-signed is fine *because* it's pinned); no plaintext sync protocol "because it's just the LAN". |
| **MASVS-PLATFORM** | **High at S5** — WebView + share intent | HTML quizzes run in `flutter_inappwebview` (Android): JavaScript on only if a quiz needs it, **file access and content access off**, no JavaScript bridge that can reach the filesystem or app data, navigation locked to the quiz's own files, `file://` loads only from the app-owned Library folder. Share-intent receiver (S4) treats incoming text/URLs/files as untrusted input: validate scheme, cap size, sanitise filenames (path traversal). Audit the manifest each stage: no exported component without a reason. |
| **MASVS-CODE** | **High at S5** — imported content | The quiz-pack importer is the app's biggest attack surface (files the owner got from elsewhere): strict schema validation, **zip-slip check on every extracted path**, caps on file count/size/image dimensions, reject-on-any-error (never partial-import a bad pack). PDF/TXT parsing treats input as hostile (malformed files must fail a test, not crash the app — fuzz cases in §9/S4–S5). All SQL parameterised — no string-interpolated queries anywhere (review grep each stage). Dependencies kept current via §6.1. |
| **MASVS-RESILIENCE** | Low — accepted | Obfuscation (`--obfuscate --split-debug-info`) is cheap and can be switched on at S8, but root detection / anti-tamper for a personal app on the owner's own phone is theatre. Recorded as consciously accepted, not overlooked. |
| **MASVS-PRIVACY** | High by design | No analytics, no trackers, no third-party SDKs that phone home; permissions minimal and opt-in (notifications only, from S6, off by default). This category is already the app's founding constraint — the checklist exists to catch *drift* (e.g. a future package that adds a tracker). MobSF's tracker report per stage is the tripwire. |

### 7.3 SQLite encryption verdict (SQLCipher) — honest cost/benefit
**Not warranted now.** Reasoning:
- Android already encrypts app-private storage at rest (file-based encryption, device
  lock). The realistic attackers for this app are (a) cloud-backup leakage — fixed by
  backup rules above, cheaper and completely; (b) a stolen *unlocked* phone — SQLCipher
  doesn't help unless the key is passphrase-entered per session, which would tax the
  daily loop the whole product depends on; (c) LAN sync interception — fixed by pinned
  TLS at the transport, not by DB encryption.
- Costs are real: a forked sqflite to audit and keep patched, key management whose
  failure mode is *total data loss* (forgotten key = the owner's entire history gone),
  and friction with plain-SQLite tooling, debugging and the sync-package format.
- **Revisit triggers** (any one reopens the decision): backups start leaving the
  owner's control (shared/cloud storage); the DB starts holding credentials or other
  people's data; the app is ever distributed beyond the owner; sync leaves the LAN.

---

## 8. CI vs local split (what runs where, and why)

| Check | Per push (GitHub Actions) | Per stage (VM / phone / laptop) |
|---|---|---|
| `flutter analyze` (strict from S4) | ✅ blocking | ✅ (already the local norm) |
| Unit + property + store tests | ✅ blocking | ✅ |
| Widget tests + **CI goldens** (alchemist) | ✅ blocking | local goldens for design work |
| Coverage artifact | ✅ informational | ratchet review in stage report |
| OSV-Scanner, gitleaks, mobsfscan, Dependabot | ✅ report → blocking after baseline | — |
| Patrol / integration_test device flows | ❌ (no devices in CI) | ✅ owner's phone checklist |
| MobSF full APK scan | ❌ (heavy) | ✅ once per stage on the Actions-built APK |
| MASVS checklist pass (§7) | ❌ | ✅ stage review step, findings into report |
| Manual mutation spot-checks (§10) | ❌ | ✅ on the stage's riskiest engine only |
| Perf traces / large-fixture runs | ❌ | ✅ S6/S8, on device |

Workflow-file changes are owner-applied via the GitHub web UI (the connector lacks the
Workflows permission) — every CI item above is written to be a small, paste-able job.

---

## 9. Per-stage QA checklist (build → tests → goldens → security → review)

Copy this into each stage's report; every box is either ticked with evidence or carried
as an explicit open item. "Build" always means: analyze clean + full suite green in the
VM, then the Actions APK built from the pushed snapshot.

### S3 — Close the Loop (streak, score, Day Close)
- [ ] Build: `very_good_analysis` adopted (non-fatal), analyze + tests green.
- [ ] Tests: **property tests (glados) for the streak walk and score formula** —
      invariants: shield balance never negative, never above cap, ≤2 shield-days/week,
      no shields before the streak first reaches 7, totals/best never decrease;
      score is monotonic in completed items, clamped to range, empty-plan rule = 60.
- [ ] Tests: boundary matrix (§10.1) as named cases: midnight/DST-adjacent dates,
      night-owl close after midnight, timezone change mid-streak, catch-up walk over
      a multi-week gap (evaluated day-by-day, not from a weekly counter).
- [ ] Tests: v2→v3 migration test preserves S1/S2 data; leak tracking enabled and clean
      on Today + Day Close screens.
- [ ] Goldens: first alchemist goldens — Today (Hub) and Day Close, Midnight plate.
- [ ] Security: backup-exclusion rules added for the new tables' data; no new SQL
      string interpolation (grep); OSV + gitleaks + Dependabot live in CI.
- [ ] Review: manual mutation spot-check on the streak engine (§10); `ponytail_audit`
      pass; stage report lists every surviving mutant found and the test that now kills it.

### S4 — Topics & Library
- [ ] Build: analyze + tests green; `integration_test` harness present.
- [ ] Tests: adversarial import suite — malformed/oversized TXT, truncated PDF,
      filename path-traversal attempts, duplicate imports; all fail cleanly, no crash,
      no partial writes. Backup export→import round-trip on a real file DB.
- [ ] Tests: Library writes are temp-then-rename (sync-safety rule) — test simulates a
      torn write and shows the old file intact.
- [ ] Goldens: Library + Topic screens.
- [ ] Security: share-intent input matrix (schemes, sizes, filenames) as tests;
      manifest export audit; mobsfscan live in CI; MobSF full scan #1 on the S4 APK.
- [ ] Device: share a link/file into the app on the phone; import a real PDF end-to-end.
- [ ] Review: MASVS-STORAGE + PLATFORM rows re-checked against what S4 actually built.

### S5 — Learn Engine
- [ ] Build: analyze + tests green.
- [ ] Tests: **quiz-pack importer adversarial suite** — schema violations, zip-slip
      paths, oversized media, out-of-bounds image-point coordinates, unknown question
      types: all rejected atomically. Valid sample packs (all 5 question types) import
      and play.
- [ ] Tests: SM-2 property tests — intervals monotonic in grade, ease factor floored,
      review-log append-only (no update/delete path exists — assert by API shape);
      session state machine can't skip the enjoyment rating rule (asked only at ≥5
      cards, and *before* any stats are shown).
- [ ] Goldens: Learn session cards (one per question type) + session summary.
- [ ] Security: **WebView hardening checklist** (§7 PLATFORM row) verified item by item
      for the HTML quiz player; a hostile sample quiz (script trying to navigate away /
      read files) demonstrably contained. Patrol adopted for the WebView + share flows.
- [ ] Device: full Learn session on the phone incl. one HTML quiz; enjoyment flow timed
      (Day Close + rating still ≤ the friction budget).
- [ ] Review: MASVS-CODE row re-checked; importer code gets the `ponytail_review` pass.

### S6 — Progress & Sunday
- [ ] Build: analyze (now `--fatal-warnings` in CI) + tests green.
- [ ] Tests: calendar boundary matrix — week containing month/year boundaries, Sunday
      summary generated exactly once, DST weeks; large-fixture DB (365 days) renders
      Journey + charts within a sane frame budget on device.
- [ ] Goldens: Journey path states (early/mid/long streak), dual-score chart, Sunday
      summary — the visual centre of the app gets the deepest golden coverage.
- [ ] Security: reminder permission flow is opt-in and reversible; no permission is
      requested before the owner enables the toggle (device-verified).
- [ ] Device: Sunday summary arrives/reads correctly; reminder fires (or provably
      doesn't, when off).
- [ ] Review: progress visuals vs the "no guilt mechanics" design rule — a missed week
      must look neutral, not punishing (design review item, recorded in the report).

### S7 — Two Devices (Sync Stage A)
- [ ] Build: analyze + tests green on **both** Android and Linux targets.
- [ ] Tests: **two-database sync harness** — generate two DBs, diverge them, exchange
      packages, assert convergence; **stateful property tests** for merge: commutative,
      idempotent, tombstones win correctly, per-date `day_reviews` merge keeps the
      HLC-later scores and preserves the loser as a conflict copy.
- [ ] Tests: future-dated record quarantine (records >1 day ahead are held, not
      applied); wrong-clock scenario; torn/partial package file rejected.
- [ ] Tests: **restore guards** — snapshot import into a non-empty DB takes the
      automatic pre-restore backup and requires the replace-everything confirmation;
      empty-DB restore is the fast path (the decided MUST-FIX behaviour).
- [ ] Goldens: sync screen states (idle, exchanging, conflict, done) on both platforms.
- [ ] Security: MobSF full scan on the S7 APK; MASVS full pass (§7) — first stage where
      NETWORK/AUTH rows have real content (pairing design reviewed even though Stage B
      transport lands in S8); sync package contents audited (nothing leaves the device
      that the owner didn't put in the library/data).
- [ ] Device: real phone↔laptop exchange over the home LAN, both directions, incl. a
      deliberately conflicted day closed on both devices while apart.
- [ ] Review: sync merge code gets manual mutation spot-checks (§10.3 invariants).

### S8 — Sync Stage B + polish
- [ ] Build: analyze + tests green; release build with `--obfuscate --split-debug-info`
      verified installable and functional on the phone.
- [ ] Tests: pairing flow tests (fake peer via mocktail if needed — §4.1); replayed /
      duplicated sync messages are no-ops; interrupted transfer resumes or restarts
      cleanly, never half-applies.
- [ ] Security: pinned-TLS verification — a third device with a different certificate
      is refused; pairing PIN brute-force is rate-limited by design (re-pairing requires
      physical interaction on both devices). Final MASVS pass; `pub get
      --enforce-lockfile` in CI.
- [ ] Device: unattended overnight sync between phone and laptop; battery/data sanity.
- [ ] Review: full `ponytail_audit`; TESTING.md itself reviewed — anything in §5
      whose reason has expired gets re-decided in `DECISIONS.md`.

---

## 10. Mutation testing: the honest substitute

**Reality check:** there is no usable automated mutation-testing tool for Dart today.
Stryker (JS/.NET/Scala) has no Dart runner; Google's internal Dart mutation testing
has never been released; the Dart community literature is explicitly *manual* mutation
testing. So we do the two things that recover most of the value:

1. **Boundary/edge-case matrices as named tests** (the mutants mutation tools generate
   are overwhelmingly boundary flips — `>` vs `>=`, off-by-one, cap checks — so a
   deliberate matrix kills the same class):
   - *Streak (§9/S3):* streak lengths 0,1,2,3,6,7,8; shields 0,1,2 held; shield-days
     this week 0,1,2; gap lengths 1,2,7,30 days; week boundary Sun→Mon; close before/
     after midnight; clock moved ±1 day.
   - *Score:* 0 items, 1 item, all done, none done, carried items only, empty plan
     (= 60 rule), self-score present/absent (dual scores never merged — assert both
     survive independently).
   - *Sync merge (S7):* same record edited both sides; delete vs edit; same date
     closed both sides; identical packages applied twice; out-of-order packages;
     future-dated records; HLC ties.
2. **Manual mutation spot-checks** in the stage review: pick the stage's riskiest
   function, hand-apply 3–5 classic mutants (flip a comparison, drop a cap, swap an
   order), run the suite — every mutant must fail a test. Survivors are findings:
   write the test that kills them before the stage closes, and list them in the
   stage report. Fifteen minutes per stage; catches hollow tests that coverage
   numbers alone would bless.

If a maintained Dart mutation tool ever ships, it slots into §8's per-stage column
without changing anything else in this playbook.

---

## 11. Verification notes (what backs the claims above)

Verified 2026-10-30 against pub.dev pages/changelogs or vendor docs: patrol 4.10.0 /
patrol_cli 4.8.0 (pub.dev changelog; publisher listing lagged at 4.9.0 — re-confirm the
pair at adoption), patrol_finders 3.6.0, alchemist 0.14.0, golden_toolkit discontinued
(0.15.0 final), dart_code_metrics discontinued (5.7.6 final), very_good_analysis 11.0.0
(Dart 3.13 build), glados 1.1.7 (Dec 2023; maintenance rated poor), mocktail 1.0.5,
leak_tracker 11.0.2 as a flutter_test dependency, OSV-Scanner's official Dart/pubspec.lock
support, GitHub Dependabot/dependency-graph support for the pub ecosystem, gitleaks-action
v2 licensing (free for personal accounts), MASVS v2.1.0 structure (8 categories,
24 controls), MobSF Docker image + resource needs, CodeQL's lack of Dart support,
absence of a public Dart mutation-testing tool.

Explicitly **[unverified]** / single-source: wheatley's current version; the exact
leak-tracking enablement API for Flutter 3.47.8 (check the installed SDK at adoption);
the custom_lint upstream archival (one dependent package's README); DCM's current
pricing. None of the adopt-now items depend on an unverified claim.

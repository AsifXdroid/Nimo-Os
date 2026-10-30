# CI Build Audit — 2026-10-30

Why the release build failed twice in a row, what class of problem
this is, why none of our gates can see it, and what else is carrying
the same risk. **No fixes applied** — this is the diagnosis the owner
asked for before any further fix.

## The two failures

- **Failure 1** (S3–S7 push, commit `1395f68b`): Gradle *project
  evaluation* — `flutter_inappwebview_android-1.1.3/android/
  build.gradle:44` calls `getDefaultProguardFile(
  'proguard-android.txt')`, removed in AGP 9. Verified at the time:
  1.1.3 was the latest stable and contained exactly those lines.
- **Failure 2** (fix push, commit `2999a875`): **CONFIRMED —
  suspect #1 below, exactly as ranked.** The owner supplied the
  FAILURE block: `Execution failed for task
  ':app:checkReleaseAarMetadata'` — `receive_sharing_intent`
  requires compile against API 37+, app is compiled against
  android-36, and AGP 9.1.0's maximum recommended compileSdk is 36.
  The log also shows the build ran 5m 49s (vs 2m 48s for run 1):
  evaluation, plugin compilation, and the CMake *tooling* install
  all passed — fix #1 verifiably held. (jni's native compile step
  itself is not explicitly confirmed by the excerpt.)
  Root-cause amplifier found during the fix archaeology: our
  pubspec constraint is `^1.8.0`, written in S4 when it resolved
  to 1.8.1 (compileSdk 34). It silently floated to 1.9.0
  (compileSdk 37) when the lockfile re-resolved during S5–S7 —
  so this build was the first ever attempted against 1.9.0.
  **Toolchain drift has a twin: constraint drift.**

## The pattern

The project's Android toolchain is new and pinned by the Flutter
template: **AGP 9.1.0, Kotlin 2.4.0, Gradle 9.3.1, compileSdk 36,
JDK 17** (android/settings.gradle.kts). The plugin ecosystem lags
that toolchain: plugin Gradle scripts and SDK declarations written
against AGP 7/8 break under AGP 9 in several distinct ways
(removed DSL calls, AAR-metadata compileSdk checks, native-build
requirements). Any plugin can carry the disease; the build only
finds them **one at a time, in build order**.

Compounding factor: the CI workflow installs Flutter with
`channel: stable` and **no version pin**, so the CI toolchain
floats to the newest stable on every run while the dev VM is fixed
at 3.47.8. The Android build can therefore break with **zero code
changes** on our side, purely from toolchain drift.

## Why our tests cannot detect any of this

Every verification gate we run — `flutter analyze`, `flutter test`
(483 tests), the review loop, mutation checks — executes **Dart on
a host VM**. None of them ever:

- evaluates a Gradle build script,
- runs the AAR-metadata checks,
- compiles a plugin's Kotlin/Java or native (CMake/NDK) code,
- runs R8/ProGuard, AAPT resource linking, or manifest merging.

All of that happens only inside `flutter build apk`, which **cannot
run in the dev VM** (Gradle's Java loopback IPC is broken at
platform level — see toolchain/NOTES.md) and does not run in the
build side chat either. The first environment that ever executes
the Android build for a new dependency set is **CI, after a push**.
This failure class is therefore structurally invisible locally:
Dart-green says nothing about Android-build-green. (Demonstrated
twice in this episode alone: the first inappwebview override
attempt passed analyze and failed test *compilation*; the proguard
issue passed everything and failed Gradle *evaluation*.)

## Audit of the resolved Android plugins (this build, post-fix)

Authoritative set from `.flutter-plugins-dependencies` (11 Android
plugins). Each plugin's `android/build.gradle` was read and scanned
for removed/renamed DSL, dead repositories, SDK declarations, and
native-build requirements.

| Plugin | Finding | Risk |
| --- | --- | --- |
| flutter_inappwebview_android 1.2.0-beta.3 | proguard call fixed (optimize variant, verified in the resolved pub-cache copy); still uses `lintOptions` (tolerated — failure 1's error pointed past it to line 44); own buildscript pins AGP 8.13.1 classpath (resolved fine in run 1) | Low now |
| **receive_sharing_intent 1.9.0** | **hard-coded `compileSdk 37`** (line 44) while the app compiles against **36** | **High — suspect #1 for failure 2**: AAR-metadata check (`checkReleaseAarMetadata`) rejects libraries whose recorded minCompileSdk exceeds the app's compileSdk; alternatively the android-37 platform may not even be installed on the runner. Never reached in run 1 (build died earlier, at evaluation) |
| **jni 1.1.1** (pdfrx's FFI bridge) | `externalNativeBuild` (CMake) + `ndkVersion = flutter.ndkVersion` (Flutter 3.47 pins NDK 28.2.x) | **Medium — suspect #2**: if the CI runner lacks that NDK, AGP must download it mid-build; failure would surface as an NDK/CMake error during assembleRelease. Also never reached in run 1 |
| flutter_local_notifications 22.3.3 | compileSdk 36 (= app), `lintOptions` | Low |
| flutter_timezone 5.1.1 | compileSdk 35 (< app, fine), `lintOptions` | Low |
| sqflite_android 2.4.5 | `lintOptions` only | Low |
| jni_flutter 1.0.4+1 | compileSdk 35 | Low |
| file_selector_android, url_launcher_android | minSdk declarations only | Low |
| path_provider_android 2.3.1 | no android/ Gradle script at all (Dart-implemented) | None |

Not in this build (present in the pub cache from the excised S8
partial work — **will become risks the day S8 is released**):
`bonsoir_android 7.1.4`, `google_mobile_ads 8.0.0` (has
`lintOptions`), `video_player_android`, `webview_flutter_android`.
They must go through this same audit before S8 ships.

Our own files: `android/app/build.gradle.kts` and
`settings.gradle.kts` are clean on every pattern checked
(namespace set, JVM target 17, no legacy DSL, no `package=`
attribute in the manifest).

## What would confirm failure 2's identity

The run's **FAILURE block** ("What went wrong" + the failing task
name, e.g. `checkReleaseAarMetadata`, or the "Running Gradle task"
line). Each suspect fails at a distinct stage with a distinct
signature:

- `compileSdk 37` / AAR metadata → receive_sharing_intent.
- NDK / CMake wording → jni.
- Another plugin's `build.gradle` line number → a further
  evaluation-time removal (the audit found no other candidate
  lines, so this would itself be new information).

## Recommended mitigations (for owner decision — none applied)

1. **Pin the CI Flutter version** to the dev toolchain (3.47.8) in
   the workflow, so CI stops drifting away from what was verified
   locally. (Workflow-file edit — owner does it via web UI, as
   before.)
2. **Add this Gradle-script audit to the pre-push checklist** —
   run it whenever a stage adds/changes an Android plugin; it is a
   five-minute mechanical scan (this report's method).
3. **Treat "new Android plugin" as a build-risk event**: the stage
   isn't build-verified until a CI build of that dependency set has
   gone green once (e.g. a throwaway dispatch run), because CI is
   the only place the Android build exists.
4. For the concrete suspects, decide per finding once failure 2's
   identity is confirmed — e.g. align receive_sharing_intent
   (upgrade/downgrade/replace) rather than raising the app's
   compileSdk toward an SDK platform that may not exist on the
   runner yet.

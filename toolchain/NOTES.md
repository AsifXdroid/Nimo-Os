# Toolchain notes — Daily Life App (agent VM)

Everything lives under `~/tools` (persistent across VM replacements):
JDK 17 (Temurin), Flutter 3.47.8, Android SDK (platforms 35/36,
build-tools 35/36, platform-tools). Source `~/tools/env.sh` before
any flutter/gradle command. `setup.sh` + `setup.log` record the
original install.

## Environment quirks discovered 2026-10-29 (verified, not guessed)

1. **Proxy**: egress goes through an authenticated HTTP proxy
   (`$https_proxy`). curl/pub/Dart honour the env vars; **Java does
   not** — Java HTTPS tunneling through this proxy crashes
   (`NoSuchElementException` in `HttpURLConnection.doTunneling0`).
   Consequences, and the workarounds used:
   - `sdkmanager` cannot download → SDK packages were installed by
     fetching the exact zips from `repository2-1.xml` with curl and
     unzipping into the SDK layout; license hash files written
     manually (standard public hashes). `flutter doctor` still says
     "license status unknown" (it asks sdkmanager, which has no
     package metadata) — cosmetic here.
   - Gradle wrapper download → distribution pre-seeded into the
     wrapper dists dir with the `.ok` marker (hash dir computed from
     the distribution URL).
   - **Java user.home is `/root`** (processes run as uid 0 with
     HOME=/home/hatch), so `GRADLE_USER_HOME` is exported in
     `env.sh` to pin Gradle's home to `~/.gradle`.
2. **Gradle cannot build in this VM (hard blocker for APKs).**
   The Gradle client↔daemon handshake uses Java loopback TCP, and
   Java loopback delivery is broken at platform level here:
   a minimal same-JVM Java test (ServerSocket accept + read on
   127.0.0.1) reproducibly stalls >5 s and never delivers, while an
   equivalent Python socket test succeeds instantly. Gradle daemons
   start and listen, but the client's first dispatch dies with
   `MessageIOException: Could not write '/127.0.0.1:<port>' /
   Broken pipe`, and each daemon then finds its registry entry
   removed and stops. Tested and ruled out: proxy props, wrapper
   download, GRADLE_USER_HOME on disk vs tmpfs, `daemon=false`,
   stale registries, process reaping, localhost interception.
   `flutter analyze` and `flutter test` do NOT use Gradle — they
   work fine. **APK builds therefore happen via GitHub Actions
   (`.github/workflows/build-apk.yml`) or the owner's laptop
   (`build_on_laptop.sh`).**
3. **Memory**: ~8 GB total but only ~0.3–0.8 GB typically available
   (the root overlay's upper dir is RAM-backed), no swap (the
   `~/tools/swapfile` could not be activated — swapon not
   permitted). Builds/tests here must stay small; gradle.properties
   already carries low-memory settings.
4. **flutter test output**: piping `flutter test` through the agent
   shell stalls it; redirect to a log file instead (as in
   `toolchain/test_run.log`). Widget tests that touch the FFI
   database must run inside `tester.runAsync` (fake-async deadlock
   otherwise) — see test/widget_test.dart.
5. /tmp is a 512 MB tmpfs — do not put Gradle homes or big
   extractions there.
6. **LLVM/clang (added 2026-10-30, S4)**: `pdfrx_engine`'s
   `pdfium_dart` dependency has a native-assets build hook that
   compiles a small C gate library via `native_toolchain_c`; for a
   Linux→Linux same-arch build it accepts ONLY clang (+ llvm-ar +
   lld) — gcc is not offered. This VM has gcc but no clang, and apt
   is unusable (the egress proxy returns 407 for the Debian
   archive). Fix: prebuilt LLVM 20.1.8 unpacked at `~/tools/llvm`
   (from the llvm-project GitHub release
   `LLVM-20.1.8-Linux-X64.tar.xz`, 2,021,269,412 bytes — verify the
   byte count before extracting; a truncated download silently
   produced a tree whose `bin/clang` symlink dangled). `env.sh`
   prepends `~/tools/llvm/bin` to PATH. First `flutter test` run
   also downloads the PDFium binary (bblanchon/pdfium-binaries via
   GitHub) once into the pub cache.

7. **Linux desktop build attempt (2026-10-30, S7)**: scaffolding
   (`flutter create --platforms=linux`) is in the repo. The build
   itself stops at CMake configuration in this VM: ninja was
   missing (fixed — a static ninja 1.12.1 binary now lives in
   `~/tools/ninja`, curl-fetched from the ninja-build releases,
   NOT on env.sh's PATH yet) and, decisively, the GTK3
   *development* files (headers, `gtk+-3.0.pc`, linker symlinks)
   are absent — only the GTK runtime libraries are installed —
   and `apt-get download libgtk-3-dev` has no candidate here
   (the apt lists cover installed packages only). So: analyze +
   full host tests (which exercise the same FFI database path
   the Linux build uses) are the VM-level verification; the GUI
   build runs on the owner's Arch laptop via
   `toolchain/build_linux_on_laptop.sh` (one pacman line:
   `gtk3 ninja cmake pkgconf clang sqlite`). Also observed: the
   generated Linux plugin registrant contains only
   file_selector_linux, flutter_timezone, url_launcher_linux
   (+ jni FFI) — flutter_local_notifications does not register
   on Linux in this build, so desktop reminders are inert by
   construction (matches the §R8.6 caveat, stronger form).

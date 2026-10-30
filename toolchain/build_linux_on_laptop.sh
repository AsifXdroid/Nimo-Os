#!/bin/bash
# Build the Daily Life App LINUX DESKTOP binary on the owner's
# laptop (Arch Linux) — Stage S7. The agent VM cannot finish this
# build: it has the GTK3 runtime but no GTK3 development files
# (headers / pkg-config), and apt there cannot supply them
# (verified 2026-10-30, toolchain/NOTES.md). On Arch everything
# needed is one pacman line.
#
# One-time prerequisites (Arch):
#   sudo pacman -S --needed gtk3 ninja cmake pkgconf clang sqlite
#   # Flutter itself: official tarball into ~/tools/flutter (as
#   # for the APK script), then once:
#   flutter config --enable-linux-desktop
#
# `sqlite` provides libsqlite3, which the desktop database
# (sqflite_common_ffi) loads at runtime. `clang` is also what the
# pdfrx PDF engine's native build hook requires.
set -e
cd "$(dirname "$0")/.."

command -v flutter >/dev/null || {
  echo "flutter not found on PATH. Install Flutter first, e.g.:"
  echo "  mkdir -p ~/tools && cd ~/tools"
  echo "  # download flutter_linux_*-stable.tar.xz from https://docs.flutter.dev/get-started/install/linux"
  echo "  tar xf flutter_linux_*-stable.tar.xz"
  echo "  export PATH=\$HOME/tools/flutter/bin:\$PATH"
  exit 1
}
pkg-config --exists gtk+-3.0 || {
  echo "GTK3 development files not found. On Arch:"
  echo "  sudo pacman -S --needed gtk3 ninja cmake pkgconf clang sqlite"
  exit 1
}

flutter pub get
flutter analyze
flutter test
flutter build linux --release
echo
echo "Linux build: build/linux/x64/release/bundle/"
echo "Run it with: build/linux/x64/release/bundle/daily_life_app"

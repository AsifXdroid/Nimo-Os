#!/bin/bash
# Build the Daily Life App APK on the owner's laptop (Arch Linux).
# Alternative to the GitHub Actions route — see toolchain/NOTES.md
# for why the agent VM cannot produce the APK itself.
#
# Prerequisite: Flutter installed and on PATH (official tarball into
# ~/tools/flutter works; run `flutter doctor` once and accept the
# Android licenses it offers). This script does not install anything.
set -e
cd "$(dirname "$0")/.."

command -v flutter >/dev/null || {
  echo "flutter not found on PATH. Install Flutter first, e.g.:"
  echo "  mkdir -p ~/tools && cd ~/tools"
  echo "  # download flutter_linux_*-stable.tar.xz from https://docs.flutter.dev/get-started/install/linux"
  echo "  tar xf flutter_linux_*-stable.tar.xz"
  echo "  export PATH=\$HOME/tools/flutter/bin:\$PATH"
  echo "  flutter doctor --android-licenses"
  exit 1
}

flutter pub get
flutter analyze
flutter test
flutter build apk --release
echo
echo "APK built: build/app/outputs/flutter-apk/app-release.apk"
sha256sum build/app/outputs/flutter-apk/app-release.apk

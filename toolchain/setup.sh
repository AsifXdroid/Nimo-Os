#!/bin/bash
# Daily Life App — toolchain setup. Everything under ~/tools so it
# survives VM replacement (lesson from the REA /usr wipe, 2026-10-23).
set -x
TOOLS="$HOME/tools"
mkdir -p "$TOOLS/dl"
cd "$TOOLS/dl"

# Swap (best effort): this VM shows only ~300MB MemAvailable.
if [ ! -f "$TOOLS/swapfile" ]; then
  fallocate -l 4G "$TOOLS/swapfile" 2>/dev/null || dd if=/dev/zero of="$TOOLS/swapfile" bs=1M count=4096
  chmod 600 "$TOOLS/swapfile"
  mkswap "$TOOLS/swapfile" || true
fi
swapon "$TOOLS/swapfile" 2>/dev/null || true
free -h

export _JAVA_OPTIONS="-Xmx512m"

# --- JDK 17 (Temurin) ---
if [ ! -x "$TOOLS/jdk/bin/java" ]; then
  curl -L -o jdk.tar.gz "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
  mkdir -p "$TOOLS/jdk"
  tar xzf jdk.tar.gz -C "$TOOLS/jdk" --strip-components=1
fi
export JAVA_HOME="$TOOLS/jdk"
"$JAVA_HOME/bin/java" -version

# --- Flutter SDK (latest stable) ---
if [ ! -x "$TOOLS/flutter/bin/flutter" ]; then
  curl -s https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json -o releases.json
  VER=$(python3 -c "
import json
d = json.load(open('releases.json'))
h = d['current_release']['stable']
r = [x for x in d['releases'] if x['hash'] == h][0]
print(r['version'])")
  echo "FLUTTER_VERSION=$VER"
  curl -L -o flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${VER}-stable.tar.xz"
  tar xf flutter.tar.xz -C "$TOOLS"
fi
export PATH="$TOOLS/flutter/bin:$PATH"

# --- Android SDK cmdline-tools ---
export ANDROID_HOME="$TOOLS/android-sdk"
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  curl -L -o cmdtools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
  unzip -q -o cmdtools.zip -d "$TOOLS/dl/cmdtools_tmp"
  cp -r "$TOOLS/dl/cmdtools_tmp/cmdline-tools/." "$ANDROID_HOME/cmdline-tools/latest/"
fi
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
yes | sdkmanager --licenses > /dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-35" "platforms;android-36" "build-tools;35.0.0" "build-tools;36.0.0"

# --- env file for all future shells ---
cat > "$TOOLS/env.sh" <<EOF
export JAVA_HOME="$TOOLS/jdk"
export ANDROID_HOME="$TOOLS/android-sdk"
export PATH="$TOOLS/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:\$JAVA_HOME/bin:\$PATH"
EOF

flutter config --android-sdk "$ANDROID_HOME" || true
flutter --version
flutter doctor -v 2>&1 | tail -30
echo "SETUP_DONE"

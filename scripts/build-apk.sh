#!/usr/bin/env bash
# Build the TorrentLens debug APK with the toolchain in $HOME.
#
#   scripts/build-apk.sh            # arm64 only (the engine ABI that ships)
#   scripts/build-apk.sh --all      # every ABI
#
# The engine native library (libtorrent4j) ships for arm64-v8a, so the default
# build targets that ABI. Pass --all to include armeabi-v7a/x86_64 Flutter
# runtimes as well (the engine will still be arm64-only).
set -euo pipefail

cd "$(dirname "$0")/.."

export JAVA_HOME="${JAVA_HOME:-$HOME/toolchain/jdk17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$HOME/toolchain/flutter/bin:$JAVA_HOME/bin:$PATH"

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: flutter not found. Install the Flutter stable SDK and put it on PATH." >&2
  exit 1
fi
if [ ! -d "$JAVA_HOME" ]; then
  echo "error: JDK 17 not found at $JAVA_HOME. Set JAVA_HOME." >&2
  exit 1
fi
if [ ! -d "$ANDROID_HOME" ]; then
  echo "error: Android SDK not found at $ANDROID_HOME. Set ANDROID_HOME." >&2
  exit 1
fi

echo "flutter: $(flutter --version 2>/dev/null | head -1)"
echo "JAVA_HOME=$JAVA_HOME"
echo "ANDROID_HOME=$ANDROID_HOME"

flutter pub get
flutter analyze

# Optional: tests are fast on the Dart VM and need no device.
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  flutter test
fi

if [ "${1:-}" = "--all" ]; then
  flutter build apk --debug
else
  flutter build apk --debug --target-platform android-arm64
fi

APK="build/app/outputs/flutter-apk/app-debug.apk"
echo
echo "APK: $APK ($(du -h "$APK" | cut -f1))"

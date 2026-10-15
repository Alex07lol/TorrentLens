#!/usr/bin/env bash
# Repeatable toolchain bootstrap for TorrentLens builds in the cloud VM.
# No root required: everything lands in $HOME/toolchain and $HOME/android-sdk.
set -euo pipefail
export JAVA_HOME="${JAVA_HOME:-$HOME/toolchain/jdk17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export GRADLE_BIN="${GRADLE_BIN:-$HOME/toolchain/gradle/bin/gradle}"

if [ ! -x "$JAVA_HOME/bin/java" ]; then
  mkdir -p "$HOME/toolchain" && cd "$HOME/toolchain"
  curl -sSL -o jdk17.tar.gz "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
  tar xzf jdk17.tar.gz && mv jdk-17* jdk17 && rm jdk17.tar.gz
fi

if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  mkdir -p "$ANDROID_HOME/cmdline-tools" && cd "$ANDROID_HOME"
  curl -sSL -o cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  unzip -q cmdline-tools.zip -d cmdline-tools && mv cmdline-tools/cmdline-tools cmdline-tools/latest && rm cmdline-tools.zip
fi

if [ ! -x "$GRADLE_BIN" ]; then
  mkdir -p "$HOME/toolchain" && cd "$HOME/toolchain"
  curl -sSL -o gradle.zip "https://services.gradle.org/distributions/gradle-9.8.1-bin.zip"
  unzip -q gradle.zip && mv gradle-9.8.1 gradle && rm gradle.zip
fi

PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager --install "platform-tools" "platforms;android-35" "build-tools;35.0.0" >/dev/null
echo "toolchain ready: java=$($JAVA_HOME/bin/java -version 2>&1 | head -1)"

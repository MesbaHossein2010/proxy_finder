#!/usr/bin/env bash
# Runs once when the Codespace is first created.
# Everything here downloads onto GitHub's cloud machine, not your local PC/bandwidth.
set -e

FLUTTER_DIR="$HOME/flutter"
ANDROID_SDK_DIR="$HOME/android-sdk"

# --- Flutter SDK ---
if [ ! -d "$FLUTTER_DIR" ]; then
  git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR" --depth 1
fi
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$FLUTTER_DIR/bin:$PATH"

# --- Android command-line tools (no full Android Studio needed) ---
mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"
cd "$ANDROID_SDK_DIR/cmdline-tools"
curl -o cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q cmdline-tools.zip
mv cmdline-tools latest
rm cmdline-tools.zip

echo 'export ANDROID_SDK_ROOT="$HOME/android-sdk"' >> "$HOME/.bashrc"
echo 'export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"' >> "$HOME/.bashrc"
export ANDROID_SDK_ROOT="$ANDROID_SDK_DIR"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

yes | sdkmanager --licenses > /dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

flutter config --android-sdk "$ANDROID_SDK_ROOT"
flutter precache --android
flutter doctor

echo "Setup complete. Open a new terminal (or run 'source ~/.bashrc') to pick up PATH changes."

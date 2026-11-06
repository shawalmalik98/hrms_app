#!/usr/bin/env bash
# Builds the release APK and installs it over the app already on the phone.
# Login, saved settings and offline punches stay (same app, just updated).
#
#   ./update_app.sh
#
# Needs: the phone connected by USB with USB debugging on.
set -e
cd "$(dirname "$0")"

PACKAGE="com.example.hrms_app"
APK="build/app/outputs/flutter-apk/app-release.apk"

# Find adb: PATH first, then the usual Android SDK folders.
ADB="$(command -v adb || true)"
if [ -z "$ADB" ]; then
  for sdk in "$ANDROID_SDK_ROOT" "$ANDROID_HOME" \
             "$LOCALAPPDATA/Android/sdk" "$HOME/AppData/Local/Android/sdk" \
             "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    for exe in adb adb.exe; do
      if [ -n "$sdk" ] && [ -x "$sdk/platform-tools/$exe" ]; then
        ADB="$sdk/platform-tools/$exe"
        break 2
      fi
    done
  done
fi
if [ -z "$ADB" ]; then
  echo "adb not found. Install Android SDK platform-tools or add adb to PATH."
  exit 1
fi

if ! "$ADB" devices | tail -n +2 | grep -qw "device"; then
  echo "No phone found. Connect it by USB, turn on USB debugging and allow"
  echo "this computer on the phone, then run this again."
  exit 1
fi

# A higher build number every time, so Android treats it as an update.
BUILD_NUMBER=$(( $(date +%s) / 60 ))

echo "Building release APK..."
flutter build apk --release --build-number="$BUILD_NUMBER"

echo "Installing on the phone..."
if ! "$ADB" install -r "$APK"; then
  echo
  echo "Install failed. If it says INSTALL_FAILED_UPDATE_INCOMPATIBLE, the app"
  echo "on the phone was signed with a different key. Uninstall it once from"
  echo "the phone, then run this again (you will have to log in again)."
  exit 1
fi

"$ADB" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
echo "Done. The app on the phone is updated."

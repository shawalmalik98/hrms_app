#!/usr/bin/env bash
# Builds the release APK and prepares the files the app downloads to update
# itself. No USB or paid service needed.
#
#   ./build_release.sh                       # default notes
#   NOTES="Offline attendance fixed" ./build_release.sh
#
# Then copy the two files from the dist/ folder to the portal server so that
# they open at:
#   http://192.168.88.71:8001/app/version.json
#   http://192.168.88.71:8001/app/hrms.apk
# (on the server: the web root's public/app/ folder). Phones that already have
# the app will require the update the next time they open it.
set -e
cd "$(dirname "$0")"

BASE_URL="${APK_BASE_URL:-http://192.168.88.71:8001/app}"
NOTES="${NOTES:-Bug fixes and improvements.}"
# Every update is mandatory. Phones on an older build only honour "force".
FORCE=true

# Higher every time, the app updates only when this is bigger than its own.
BUILD_NUMBER=$(( $(date +%s) / 60 ))
VERSION_NAME="$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')"

echo "Building release APK (build $BUILD_NUMBER)..."
# 64-bit ARM only (every phone of the last ~8 years): a universal APK carries
# the same code three more times (32-bit ARM and x86) and is about 2.5x bigger.
flutter build apk --release --target-platform android-arm64 --build-number="$BUILD_NUMBER"

mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/hrms.apk

# Keep the notes JSON safe.
SAFE_NOTES="$(printf '%s' "$NOTES" | sed 's/\\/\\\\/g; s/"/\\"/g')"
cat > dist/version.json <<EOF
{
  "version_code": $BUILD_NUMBER,
  "version_name": "$VERSION_NAME",
  "apk_url": "$BASE_URL/hrms.apk",
  "notes": "$SAFE_NOTES",
  "force": $FORCE
}
EOF

echo
echo "Ready in dist/:"
echo "  dist/hrms.apk"
echo "  dist/version.json"
echo "Copy both to the server's public/app/ folder."

#!/bin/bash
# Build build/PodPointer.app from Sources/*.swift (no Xcode project needed, only the Command Line Tools).
#
# Signing:
#   * If scripts/setup-signing.sh has been run, the app is signed with a stable local
#     certificate, so the Accessibility permission survives rebuilds.
#   * Otherwise it is ad-hoc signed and macOS treats every build as a new app
#     (you must re-enable it under Accessibility after each rebuild).
#
# Environment:
#   BUNDLE_ID   bundle identifier (default: io.github.podpointer)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="${BUNDLE_ID:-io.github.podpointer}"
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"
APP=build/PodPointer.app
KC="$HOME/Library/Keychains/podpointer-sign.keychain-db"
KC_PASS_FILE="$ROOT/.signing/keychain-password"
IDENTITY="PodPointer Local Signing"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>PodPointer</string>
  <key>CFBundleDisplayName</key><string>PodPointer</string>
  <key>CFBundleExecutable</key><string>PodPointer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMotionUsageDescription</key><string>PodPointer reads the AirPods motion sensors to turn the charging case into a pointer.</string>
</dict>
</plist>
PLIST

echo "Compiling…"
swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/PodPointer" \
  -framework AppKit -framework CoreMotion -framework CoreAudio -framework ApplicationServices

if [ -f "$KC" ] && [ -f "$KC_PASS_FILE" ]; then
  # codesign only looks up identities in the keychain search list:
  # add our keychain temporarily and restore the original list afterwards.
  security unlock-keychain -p "$(cat "$KC_PASS_FILE")" "$KC"
  ORIG=()
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; ORIG+=("${line#\"}")
  done < <(security list-keychains -d user)
  restore() {
    for _ in 1 2 3 4 5; do   # the preference write can be raced by securityd; verify and retry
      sleep 0.3
      security list-keychains -d user -s "${ORIG[@]}"
      security list-keychains -d user | grep -q podpointer-sign || return 0
    done
    echo "!! Could not restore the keychain search list. Run: security list-keychains -d user -s ${ORIG[*]}"
  }
  trap restore EXIT
  security list-keychains -d user -s "${ORIG[@]}" "$KC"
  codesign --force --keychain "$KC" -s "$IDENTITY" "$APP"
  restore; trap - EXIT
  echo "Signed with \"$IDENTITY\" (Accessibility permission persists across rebuilds)"
else
  codesign --force -s - "$APP"
  echo "Ad-hoc signed. Run scripts/setup-signing.sh once to keep the Accessibility permission across rebuilds."
fi

echo "Built $ROOT/$APP"

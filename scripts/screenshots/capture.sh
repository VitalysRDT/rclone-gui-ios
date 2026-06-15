#!/usr/bin/env bash
# scripts/screenshots/capture.sh
#
# Reproducible App Store screenshot pipeline.
#
# Captures REAL app screens on the iPhone 6.9" and iPad 13" simulators, seeded
# with privacy-safe demo data, then composites them into the marketing frames
# (translated copy per App Store language) via compose-frames.py.
#
# Requirements:
#   - A RcloneKit.xcframework that includes an `ios-arm64-simulator` slice
#     (build with scripts/build-rclone.sh after adding the iossimulator target,
#      or unzip a CI artifact). Without it the app cannot run on the simulator.
#   - Xcode (DEVELOPER_DIR), Google Chrome (HTML→PNG), python3.
#
# The app is launched with debug-only flags handled by DemoSeeder.swift and the
# `--demo-screen` router in MainTabView.swift:
#   --seed-demo                              seed remotes/files/SwiftData
#   -hasCompletedOnboarding YES              skip onboarding
#   -security.requireBiometricsAtLaunch NO   skip the Face ID gate
#   --demo-screen <id>                       deep-link to a surface
#   -AppleLanguages (xx) -AppleLocale xx_XX  force UI language
#
# Output: fastlane/screenshots/<locale>/{iphone,ipad}_NN_id.png
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BID="com.rougetet.rclone-gui"
SCHEME="Rclone GUI"
IPHONE_NAME="${IPHONE_NAME:-iPhone 17 Pro Max}"   # App Store iPhone 6.9" (1320x2868)
IPAD_NAME="${IPAD_NAME:-iPad Pro 13-inch (M5)}"   # App Store iPad 13"    (2064x2752)
SHOTS_DIR="${SHOTS_DIR:-/tmp/rclone-shots}"
APP_PATH="${APP_PATH:?Set APP_PATH to the built RcloneGUI.app (Debug-iphonesimulator)}"

# screen id -> --demo-screen arg
SCREENS=( "01_remotes:files" "02_wizard:wizard" "03_folder:folder" "04_file:file" \
          "05_home:home" "06_import:import" "07_photos:photos" "08_security:security" )

udid_for () { xcrun simctl list devices available | grep -F "$1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'; }

capture_device () {
  local udid="$1" device="$2"; shift 2
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid"
  xcrun simctl install "$udid" "$APP_PATH"
  for loc in "$@"; do
    local lang="${loc%%:*}" apple="${loc##*:}"
    local out="$SHOTS_DIR/$device/$lang"; mkdir -p "$out"
    xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
    xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi \
      --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
      --batteryState charged --batteryLevel 100 --operatorName "" >/dev/null 2>&1 || true
    for entry in "${SCREENS[@]}"; do
      local name="${entry%%:*}" arg="${entry##*:}"
      xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
      sleep 1
      xcrun simctl launch "$udid" "$BID" --seed-demo -hasCompletedOnboarding YES \
        -security.requireBiometricsAtLaunch NO --demo-screen "$arg" \
        -AppleLanguages "($lang)" -AppleLocale "$apple" >/dev/null 2>&1
      sleep 8
      xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null 2>&1
      echo "  ✓ $device [$lang] $name"
    done
  done
}

IPHONE_UDID="$(udid_for "$IPHONE_NAME")"
IPAD_UDID="$(udid_for "$IPAD_NAME")"
echo "iPhone sim: $IPHONE_UDID  ·  iPad sim: $IPAD_UDID"

# Only the FR and EN UI are captured; the other App Store languages reuse the
# EN screenshots with translated marketing copy (see compose-frames.py).
echo "== iPhone =="; capture_device "$IPHONE_UDID" iphone fr:fr_FR en:en_US
echo "== iPad ==";   capture_device "$IPAD_UDID"   ipad   fr:fr_FR en:en_US

echo "== Compose frames =="
SHOTS_DIR="$SHOTS_DIR" python3 "$ROOT/scripts/screenshots/compose-frames.py" iphone
SHOTS_DIR="$SHOTS_DIR" python3 "$ROOT/scripts/screenshots/compose-frames.py" ipad

echo "== Deploy to fastlane/screenshots =="
map="en:en-US fr:fr-FR de:de-DE es:es-ES it:it ko:ko pl:pl zh:zh-Hans"
for pair in $map; do
  lang="${pair%%:*}"; loc="${pair##*:}"; dest="$ROOT/fastlane/screenshots/$loc"
  mkdir -p "$dest"
  for dev in iphone ipad; do
    for src in "${FRAMES_DIR:-/tmp/rclone-frames}"/$dev/$lang/*.png; do
      cp "$src" "$dest/${dev}_$(basename "$src")"
    done
  done
done
echo "Done. Upload with: bundle exec fastlane upload_screenshots"

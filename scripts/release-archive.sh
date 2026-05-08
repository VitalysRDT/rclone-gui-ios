#!/bin/bash
# release-archive.sh
#
# Builds a release archive of Rclone GUI ready for export to App Store Connect
# or Ad Hoc distribution. Requires:
#   - Apple Developer Program membership (paid)
#   - App ID `com.rougetet.Rclone-GUI` configured on Apple Developer Portal
#     with capabilities: App Groups, Keychain Sharing, iCloud (CloudKit), Push
#   - App Group `group.com.rougetet.rclone-gui` declared
#   - Valid distribution provisioning profile (auto-managed by Xcode)
#
# Usage:
#   scripts/release-archive.sh                  # archive only
#   scripts/release-archive.sh --export appstore  # archive + IPA for TestFlight
#   scripts/release-archive.sh --export adhoc     # archive + IPA for ad-hoc
#
# Output: build/RcloneGUI-release.xcarchive (+ build/export/ if --export)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="Rclone GUI.xcodeproj"
SCHEME="Rclone GUI"
ARCHIVE_PATH="build/RcloneGUI-release.xcarchive"
EXPORT_DIR="build/export"

EXPORT_MODE=""
if [[ "${1:-}" == "--export" ]]; then
    EXPORT_MODE="${2:-appstore}"
fi

echo "==> Cleaning previous archive"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

echo "==> Archiving (Release config)"
START=$(date +%s)
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive | xcpretty || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "ERROR: archive not created at $ARCHIVE_PATH"
    exit 1
fi

ELAPSED=$(($(date +%s) - START))
echo "==> Archive created in ${ELAPSED}s : $ARCHIVE_PATH"

if [[ -n "$EXPORT_MODE" ]]; then
    case "$EXPORT_MODE" in
        appstore)
            OPTIONS_PLIST="scripts/ExportOptions-AppStore.plist"
            ;;
        adhoc)
            OPTIONS_PLIST="scripts/ExportOptions-AdHoc.plist"
            ;;
        *)
            echo "ERROR: --export must be 'appstore' or 'adhoc' (got: $EXPORT_MODE)"
            exit 1
            ;;
    esac

    echo "==> Exporting IPA via $OPTIONS_PLIST"
    mkdir -p "$EXPORT_DIR"
    xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$OPTIONS_PLIST" \
        -allowProvisioningUpdates | xcpretty || true

    echo "==> Export complete : $EXPORT_DIR"
    ls -la "$EXPORT_DIR"
fi

echo "==> Done"

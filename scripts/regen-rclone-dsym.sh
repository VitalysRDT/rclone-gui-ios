#!/usr/bin/env bash
# scripts/regen-rclone-dsym.sh
# Regenerate the dSYM bundle for an existing RcloneKit.xcframework without
# re-running gomobile bind (which takes 5–15 min cold).
#
# This works ONLY if the framework binary still contains DWARF info. If the
# binary was built with -ldflags="-s -w" (as the old build-rclone.sh did),
# dwarfdump will report "no debug symbols in executable" and you must rebuild
# with the updated scripts/build-rclone.sh that drops -s -w.
#
# Usage: ./scripts/regen-rclone-dsym.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XCFRAMEWORK="$PROJECT_ROOT/Frameworks/RcloneKit.xcframework"
SLICE_DIR="$XCFRAMEWORK/ios-arm64"
FRAMEWORK_BINARY="$SLICE_DIR/RcloneKit.framework/RcloneKit"
DSYM_DIR="$SLICE_DIR/dSYMs"
DSYM_BUNDLE="$DSYM_DIR/RcloneKit.framework.dSYM"

[ -f "$FRAMEWORK_BINARY" ] || { echo "ERROR: $FRAMEWORK_BINARY not found"; exit 1; }

echo "Binary UUID : $(xcrun dwarfdump --uuid "$FRAMEWORK_BINARY" | awk '{print $2}')"

# Probe: does the binary still carry DWARF?
if ! xcrun dwarfdump --debug-info "$FRAMEWORK_BINARY" 2>&1 | head -3 | grep -q "DWARF"; then
    echo ""
    echo "ERROR: the existing binary has no DWARF (it was built with -s -w)."
    echo "       Re-run ./scripts/build-rclone.sh to produce a binary with DWARF,"
    echo "       then this script becomes unnecessary (build-rclone.sh now"
    echo "       extracts the dSYM in the same pass)."
    exit 2
fi

echo "Extracting dSYM..."
rm -rf "$DSYM_DIR"
mkdir -p "$DSYM_DIR"
xcrun dsymutil "$FRAMEWORK_BINARY" -o "$DSYM_BUNDLE"

DSYM_UUID=$(xcrun dwarfdump --uuid "$DSYM_BUNDLE" | awk '{print $2}')
BIN_UUID=$(xcrun dwarfdump --uuid "$FRAMEWORK_BINARY" | awk '{print $2}')
echo "dSYM UUID   : $DSYM_UUID"
[ "$BIN_UUID" = "$DSYM_UUID" ] || { echo "ERROR: UUID mismatch"; exit 1; }

echo "Declaring DebugSymbolsPath in xcframework Info.plist..."
/usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0:DebugSymbolsPath string dSYMs" \
    "$XCFRAMEWORK/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :AvailableLibraries:0:DebugSymbolsPath dSYMs" \
        "$XCFRAMEWORK/Info.plist"

echo ""
echo "✓ dSYM regenerated:"
echo "  $DSYM_BUNDLE"
echo ""
echo "Next steps:"
echo "  1. Archive the app again (Product → Archive)"
echo "  2. The archive's dSYMs folder should now contain RcloneKit.framework.dSYM"
echo "  3. Re-upload to App Store Connect"

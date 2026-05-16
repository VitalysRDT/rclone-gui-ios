#!/usr/bin/env bash
# scripts/build-rclone.sh
# Build librclone as an iOS xcframework via gomobile.
#
# Usage:
#   ./scripts/build-rclone.sh [tag]
#
# Args:
#   tag — rclone git tag to checkout (default: v1.68.0)
#
# Requirements:
#   - Go 1.22+      (brew install go)
#   - Xcode CLT     (xcode-select --install)
#   - gomobile      (auto-installed if missing)
#
# Output:
#   Frameworks/RcloneKit.xcframework
#
# After running:
#   1. Open "Rclone GUI.xcodeproj" in Xcode
#   2. Drag Frameworks/RcloneKit.xcframework into the project navigator
#   3. Target "Rclone GUI" → General → Frameworks, Libraries, and Embedded Content
#      → ensure RcloneKit.xcframework is set to "Embed & Sign"
#   4. Build (⌘B). If RcloneCore.shared.version() returns a non-mock string,
#      the binding is wired correctly.

set -euo pipefail

RCLONE_TAG="${1:-v1.68.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$PROJECT_ROOT/.build/rclone"
OUTPUT_DIR="$PROJECT_ROOT/Frameworks"
XCFRAMEWORK="$OUTPUT_DIR/RcloneKit.xcframework"

START_TS=$(date +%s)

echo "=========================================="
echo "  Build librclone iOS xcframework"
echo "=========================================="
echo "Tag           : $RCLONE_TAG"
echo "Project root  : $PROJECT_ROOT"
echo "Work dir      : $WORK_DIR"
echo "Output        : $XCFRAMEWORK"
echo ""

# --- Sanity checks -----------------------------------------------------------

command -v go >/dev/null 2>&1 || {
    echo "ERROR: 'go' not found."
    echo "Install with: brew install go    # need ≥ 1.22"
    exit 1
}
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo "Go version    : $GO_VERSION"

command -v xcrun >/dev/null 2>&1 || {
    echo "ERROR: 'xcrun' not found. Install Xcode Command Line Tools:"
    echo "       xcode-select --install"
    exit 1
}
echo "Xcode SDK     : $(xcrun --show-sdk-path 2>/dev/null | head -1)"

# --- Install / init gomobile -------------------------------------------------

if ! command -v gomobile >/dev/null 2>&1; then
    echo ""
    echo "Installing gomobile (golang.org/x/mobile/cmd/gomobile)..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    GOPATH="${GOPATH:-$HOME/go}"
    export PATH="$PATH:$GOPATH/bin"
    if ! command -v gomobile >/dev/null 2>&1; then
        echo "ERROR: gomobile not on PATH after install. Check that \$GOPATH/bin is on PATH."
        echo "       Try: export PATH=\"\$PATH:\$(go env GOPATH)/bin\""
        exit 1
    fi
fi
echo "gomobile      : $(command -v gomobile)"

# Init is idempotent and downloads the iOS support code if needed
gomobile init

# --- Clone rclone ------------------------------------------------------------

mkdir -p "$WORK_DIR"
if [ ! -d "$WORK_DIR/rclone/.git" ]; then
    echo ""
    echo "Cloning rclone @ $RCLONE_TAG..."
    git clone --depth 1 --branch "$RCLONE_TAG" \
        https://github.com/rclone/rclone.git "$WORK_DIR/rclone"
else
    echo ""
    echo "Updating rclone clone to $RCLONE_TAG..."
    pushd "$WORK_DIR/rclone" >/dev/null
    # Fetch the requested tag if not already present
    git fetch --tags --depth 1 origin "$RCLONE_TAG" 2>/dev/null || true
    git checkout "$RCLONE_TAG"
    popd >/dev/null
fi

# --- Build via gomobile bind -------------------------------------------------
#
# gomobile cannot bind librclone directly because RPC returns (string, int) —
# gomobile only supports 0, 1, or (T, error). We bind a small Swift-friendly
# wrapper at scripts/rclone-bridge/ which exposes RPC as a struct return.

BRIDGE_DIR="$PROJECT_ROOT/scripts/rclone-bridge"
[ -d "$BRIDGE_DIR" ] || { echo "ERROR: bridge dir not found at $BRIDGE_DIR"; exit 1; }

cd "$BRIDGE_DIR"

echo ""
echo "Resolving bridge module dependencies (go mod tidy)..."
go mod tidy

mkdir -p "$OUTPUT_DIR"

# Clean previous output to avoid xcframework merge conflicts
if [ -e "$XCFRAMEWORK" ]; then
    echo ""
    echo "Removing previous $XCFRAMEWORK..."
    rm -rf "$XCFRAMEWORK"
fi

echo ""
echo "Running 'gomobile bind' on rclone-bridge (5–15 min cold, 2–5 min warm)..."
echo ""

# Targets:
#   -target=ios            iPhone device (arm64)
#   -target=iossimulator   Simulator (arm64 + amd64)
# We currently restrict to ios device only because rclone's transitive deps
# (gopsutil) include cgo files that include <libproc.h> which is unavailable
# in the iOS Simulator x86_64 SDK. The arm64 simulator slice has the same
# limitation. Until we stub gopsutil/cpu we ship device-only and run the
# app on a real iPhone.
# Note on ldflags: we previously passed -ldflags="-s -w" to shrink the binary,
# but `-w` strips DWARF debug info and `-s` strips the symbol table. With both,
# `dsymutil` cannot extract a dSYM and App Store Connect rejects the archive
# upload ("The archive did not include a dSYM for the RcloneKit.framework").
# We now keep symbols + DWARF; Xcode's archive pipeline will strip the embedded
# binary for distribution while keeping the dSYM bundled for crash symbolication.
gomobile bind \
    -target=ios/arm64 \
    -o "$XCFRAMEWORK" \
    -tags="rclone_no_serve_dlna" \
    .

# --- Static archive → dynamic framework --------------------------------------
#
# gomobile bind emits an `ar` static archive packaged inside a .framework
# directory. When Xcode archives an app that embeds this "framework", it
# auto-generates a tiny stub dylib for it (you can see the line
# "Injecting stub binary into codeless framework" in the build log). That
# stub carries an LC_UUID that App Store Connect then demands a dSYM for —
# and there is no dSYM because the static archive has no debug map that
# dsymutil understands. Result: archive upload rejected with
# "did not include a dSYM for the RcloneKit.framework with the UUIDs [...]"
#
# Fix: convert the static archive into a real iOS dynamic library before
# leaving build-rclone.sh. We force-load every object from the .a into the
# dylib, give it the @rpath install name Xcode expects, then dsymutil can
# extract a dSYM with a UUID that matches the binary one-to-one.

SLICE_DIR="$XCFRAMEWORK/ios-arm64"
FRAMEWORK_DIR="$SLICE_DIR/RcloneKit.framework"
FRAMEWORK_BINARY="$FRAMEWORK_DIR/RcloneKit"
STATIC_ARCHIVE="$FRAMEWORK_DIR/RcloneKit.a"
DSYM_DIR="$SLICE_DIR/dSYMs"
DSYM_BUNDLE="$DSYM_DIR/RcloneKit.framework.dSYM"

if [ ! -f "$FRAMEWORK_BINARY" ]; then
    echo "ERROR: Expected framework binary not found at $FRAMEWORK_BINARY"
    exit 1
fi

# Read project deployment target so the wrapper dylib has the same min iOS.
DEPLOY_TARGET=$(grep -m1 "IPHONEOS_DEPLOYMENT_TARGET" "$PROJECT_ROOT/Rclone GUI.xcodeproj/project.pbxproj" \
    | awk '{print $3}' | tr -d ';' || echo "16.0")
echo ""
echo "Wrapping gomobile static archive into dynamic framework (iOS $DEPLOY_TARGET)..."

# Move .a aside, build dylib in its place.
mv "$FRAMEWORK_BINARY" "$STATIC_ARCHIVE"

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang \
    -isysroot "$SDK_PATH" \
    -arch arm64 \
    -target "arm64-apple-ios${DEPLOY_TARGET}" \
    -dynamiclib \
    -Wl,-force_load,"$STATIC_ARCHIVE" \
    -framework Foundation \
    -framework CoreFoundation \
    -framework Security \
    -lresolv \
    -install_name "@rpath/RcloneKit.framework/RcloneKit" \
    -Xlinker -object_path_lto -Xlinker "$STATIC_ARCHIVE.lto.o" \
    -o "$FRAMEWORK_BINARY"

# Sanity: confirm the binary is now a real Mach-O dylib with an LC_UUID.
if ! file "$FRAMEWORK_BINARY" | grep -q "dynamically linked shared library"; then
    echo "ERROR: wrapper did not produce a dylib:"
    file "$FRAMEWORK_BINARY"
    exit 1
fi

# --- dSYM extraction ---------------------------------------------------------
#
# Now that RcloneKit is a real dylib carrying DWARF + an LC_UUID, dsymutil
# can extract a matching .dSYM. We place it inside the xcframework under
# ios-arm64/dSYMs/ and declare DebugSymbolsPath in the xcframework Info.plist
# so Xcode picks it up at archive time.

echo ""
echo "Extracting dSYM with dsymutil..."
mkdir -p "$DSYM_DIR"
# dsymutil reads the dylib's debug map, which references object files inside
# RcloneKit.a (the gomobile static archive we just force-loaded). The archive
# must therefore still be on disk at this point — we only delete it afterwards.
xcrun dsymutil "$FRAMEWORK_BINARY" -o "$DSYM_BUNDLE"

# Now the dSYM is built, the raw archive and the LTO intermediate are no
# longer needed (and Xcode would refuse the framework if a .a sat alongside
# the dylib at archive time).
rm -f "$STATIC_ARCHIVE" "$STATIC_ARCHIVE.lto.o"

# Confirm the UUID matches between binary and dSYM (App Store Connect checks this).
BIN_UUID=$(xcrun dwarfdump --uuid "$FRAMEWORK_BINARY" | awk '{print $2}')
DSYM_UUID=$(xcrun dwarfdump --uuid "$DSYM_BUNDLE" | awk '{print $2}')
echo "Binary UUID : $BIN_UUID"
echo "dSYM UUID   : $DSYM_UUID"
if [ "$BIN_UUID" != "$DSYM_UUID" ]; then
    echo "ERROR: UUID mismatch — symbolication would fail."
    exit 1
fi

# Patch xcframework Info.plist to declare the DebugSymbolsPath. Apple's
# xcframework format supports a per-slice DebugSymbolsPath key (relative to
# the slice directory) so Xcode locates the dSYM when archiving consumers.
echo "Declaring DebugSymbolsPath in xcframework Info.plist..."
/usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0:DebugSymbolsPath string dSYMs" \
    "$XCFRAMEWORK/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :AvailableLibraries:0:DebugSymbolsPath dSYMs" \
        "$XCFRAMEWORK/Info.plist"

# --- Report ------------------------------------------------------------------

ELAPSED=$(($(date +%s) - START_TS))
echo ""
echo "=========================================="
echo "  ✓ Build complete in ${ELAPSED}s"
echo "=========================================="
echo "Output  : $XCFRAMEWORK"
du -sh "$XCFRAMEWORK"
echo ""
echo "Next:"
echo "  1. Open Rclone GUI.xcodeproj in Xcode"
echo "  2. Drag $XCFRAMEWORK into the project navigator"
echo "  3. Target 'Rclone GUI' → Frameworks, Libraries, and Embedded Content → Embed & Sign"
echo "  4. Build (⌘B) and verify RcloneCore.shared.version() returns a real version string"
echo ""

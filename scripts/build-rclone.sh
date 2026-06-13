#!/usr/bin/env bash
# scripts/build-rclone.sh
# Build librclone as an iOS + macOS xcframework via gomobile.
#
# Usage:
#   ./scripts/build-rclone.sh [tag]
#
# Args:
#   tag — rclone git tag to checkout (default: v1.74.3)
#         v1.74.x / v1.73.x add the Drime, Internxt, Filen and Shade backends.
#         Conservative alternative: v1.73.5 (last 1.73 patch).
#
# Requirements:
#   - Go 1.22+      (brew install go)
#   - Xcode CLT     (xcode-select --install)
#   - gomobile      (auto-installed if missing)
#
# Output:
#   Frameworks/RcloneKit.xcframework  (two slices: ios-arm64 + macos-arm64)
#
# After running:
#   1. Open "Rclone GUI.xcodeproj" in Xcode
#   2. Drag Frameworks/RcloneKit.xcframework into the project navigator
#   3. Target "Rclone GUI" → General → Frameworks, Libraries, and Embedded Content
#      → ensure RcloneKit.xcframework is set to "Embed & Sign"
#   4. Build (⌘B) for an iPhone AND for "My Mac". If RcloneCore.shared.version()
#      returns a non-mock string on both, the binding is wired correctly.

set -euo pipefail

# Drime / Internxt / Filen / Shade landed in rclone v1.73.0 (2026-01-30).
# Default to the latest stable (v1.74.3) so they ship; override with an arg
# (e.g. ./build-rclone.sh v1.73.5) for a more conservative bump.
RCLONE_TAG="${1:-v1.74.3}"
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

# Read project deployment targets so each wrapper dylib carries the matching
# minimum OS version. The macOS slice (Apple Silicon) lets the app run natively
# on macOS; the iOS slice remains device-only (arm64).
PBXPROJ="$PROJECT_ROOT/Rclone GUI.xcodeproj/project.pbxproj"
IOS_MIN=$(grep -m1 "IPHONEOS_DEPLOYMENT_TARGET" "$PBXPROJ" | awk '{print $3}' | tr -d ';' || echo "16.0")
MAC_MIN=$(grep -m1 "MACOSX_DEPLOYMENT_TARGET" "$PBXPROJ" | awk '{print $3}' | tr -d ';' || echo "13.0")
echo "iOS  min      : $IOS_MIN"
echo "macOS min     : $MAC_MIN"

STAGE_DIR="$WORK_DIR/stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# --- wrap_slice : static archive → dynamic framework (per slice) -------------
#
# gomobile bind emits an `ar` static archive packaged inside a .framework
# directory. When Xcode archives an app that embeds this "framework", it
# auto-generates a tiny stub dylib for it ("Injecting stub binary into codeless
# framework" in the build log). That stub carries an LC_UUID App Store Connect
# then demands a dSYM for — and there is no dSYM because the static archive has
# no debug map dsymutil understands. Result: archive upload rejected.
#
# Fix: convert the static archive into a real dynamic library before assembling
# the xcframework. We force-load every object from the .a into the dylib, give
# it the @rpath install name Xcode expects, then dsymutil extracts a dSYM whose
# UUID matches the binary one-to-one.
#
# Args:
#   $1 framework_dir   path to the slice's RcloneKit.framework
#   $2 sdk             xcrun --sdk value (iphoneos | macosx)
#   $3 target_triple   clang -target value (e.g. arm64-apple-ios26.4)
#   $4 dsym_out        path to write RcloneKit.framework.dSYM
wrap_slice() {
    local framework_dir="$1" sdk="$2" target_triple="$3" dsym_out="$4"

    # Locate the Mach-O binary inside the bundle. gomobile emits a flat layout
    # on iOS (RcloneKit.framework/RcloneKit); macOS frameworks may use a
    # versioned layout (RcloneKit.framework/Versions/A/RcloneKit). -type f skips
    # the top-level symlink in the versioned case, so we always land on the real
    # binary regardless of layout.
    local framework_binary
    framework_binary=$(find "$framework_dir" -type f -name RcloneKit | head -1)
    if [ -z "$framework_binary" ] || [ ! -f "$framework_binary" ]; then
        echo "ERROR: framework binary not found under $framework_dir"
        exit 1
    fi
    local static_archive="$framework_binary.a"

    echo ""
    echo "Wrapping slice ($sdk, $target_triple)..."
    echo "  binary: $framework_binary"

    # Move .a aside, build dylib in its place.
    mv "$framework_binary" "$static_archive"

    local sdk_path
    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    xcrun --sdk "$sdk" clang \
        -isysroot "$sdk_path" \
        -arch arm64 \
        -target "$target_triple" \
        -dynamiclib \
        -Wl,-force_load,"$static_archive" \
        -framework Foundation \
        -framework CoreFoundation \
        -framework Security \
        -lresolv \
        -install_name "@rpath/RcloneKit.framework/RcloneKit" \
        -Xlinker -object_path_lto -Xlinker "$static_archive.lto.o" \
        -o "$framework_binary"

    if ! file "$framework_binary" | grep -q "dynamically linked shared library"; then
        echo "ERROR: wrapper did not produce a dylib:"
        file "$framework_binary"
        exit 1
    fi

    echo "  extracting dSYM..."
    # dsymutil reads the dylib's debug map, which references object files inside
    # the static archive we just force-loaded — it must still be on disk here.
    xcrun dsymutil "$framework_binary" -o "$dsym_out"
    rm -f "$static_archive" "$static_archive.lto.o"

    local bin_uuid dsym_uuid
    bin_uuid=$(xcrun dwarfdump --uuid "$framework_binary" | awk '{print $2}')
    dsym_uuid=$(xcrun dwarfdump --uuid "$dsym_out" | awk '{print $2}')
    echo "  binary UUID : $bin_uuid"
    echo "  dSYM UUID   : $dsym_uuid"
    if [ "$bin_uuid" != "$dsym_uuid" ]; then
        echo "ERROR: UUID mismatch — symbolication would fail."
        exit 1
    fi
}

# --- Build each slice via gomobile bind --------------------------------------
#
# One gomobile invocation per target into its own staging xcframework. We keep
# the output framework named RcloneKit.framework (Swift imports it as the
# RcloneKit module) by outputting to <stage>/<plat>/RcloneKit.xcframework.
#
# Note on ldflags: we previously passed -ldflags="-s -w" to shrink the binary,
# but `-w` strips DWARF and `-s` strips the symbol table — dsymutil then cannot
# extract a dSYM and App Store Connect rejects the archive. We keep symbols +
# DWARF; Xcode's archive pipeline strips the embedded binary for distribution
# while keeping the dSYM bundled for crash symbolication.
echo ""
echo "Running 'gomobile bind' for ios/arm64 (5–15 min cold, 2–5 min warm)..."
echo ""
gomobile bind \
    -target=ios/arm64 \
    -o "$STAGE_DIR/ios/RcloneKit.xcframework" \
    -tags="rclone_no_serve_dlna" \
    .

echo ""
echo "Running 'gomobile bind' for macos/arm64 (5–15 min cold, 2–5 min warm)..."
echo ""
gomobile bind \
    -target=macos/arm64 \
    -o "$STAGE_DIR/macos/RcloneKit.xcframework" \
    -tags="rclone_no_serve_dlna" \
    .

# Each single-target gomobile output is an xcframework with exactly one slice
# directory. Resolve the RcloneKit.framework inside each.
IOS_FRAMEWORK=$(find "$STAGE_DIR/ios" -type d -name RcloneKit.framework | head -1)
MAC_FRAMEWORK=$(find "$STAGE_DIR/macos" -type d -name RcloneKit.framework | head -1)
[ -d "$IOS_FRAMEWORK" ] || { echo "ERROR: iOS framework not produced by gomobile"; exit 1; }
[ -d "$MAC_FRAMEWORK" ] || { echo "ERROR: macOS framework not produced by gomobile"; exit 1; }

IOS_DSYM="$STAGE_DIR/ios/RcloneKit.framework.dSYM"
MAC_DSYM="$STAGE_DIR/macos/RcloneKit.framework.dSYM"

wrap_slice "$IOS_FRAMEWORK" iphoneos "arm64-apple-ios${IOS_MIN}"     "$IOS_DSYM"
wrap_slice "$MAC_FRAMEWORK" macosx   "arm64-apple-macos${MAC_MIN}"   "$MAC_DSYM"

# --- Assemble the multi-slice xcframework ------------------------------------
#
# xcodebuild -create-xcframework owns the Info.plist (one AvailableLibraries
# entry per slice) and wires DebugSymbolsPath for each via -debug-symbols, so we
# no longer hand-patch the plist. The previous output is removed above.
echo ""
echo "Assembling 2-slice xcframework (ios-arm64 + macos-arm64)..."
xcodebuild -create-xcframework \
    -framework "$IOS_FRAMEWORK" -debug-symbols "$IOS_DSYM" \
    -framework "$MAC_FRAMEWORK" -debug-symbols "$MAC_DSYM" \
    -output "$XCFRAMEWORK"

# --- Report ------------------------------------------------------------------

ELAPSED=$(($(date +%s) - START_TS))
echo ""
echo "=========================================="
echo "  ✓ Build complete in ${ELAPSED}s"
echo "=========================================="
echo "Output  : $XCFRAMEWORK"
du -sh "$XCFRAMEWORK"
echo ""
echo "Slices  :"
/usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "$XCFRAMEWORK/Info.plist" 2>/dev/null \
    | grep -E "LibraryIdentifier" || true
echo ""
echo "Next:"
echo "  1. Open Rclone GUI.xcodeproj in Xcode"
echo "  2. Drag $XCFRAMEWORK into the project navigator (if not already referenced)"
echo "  3. Target 'Rclone GUI' → Frameworks, Libraries, and Embedded Content → Embed & Sign"
echo "  4. Build (⌘B) for an iPhone AND for 'My Mac'; verify RcloneCore.shared.version()"
echo "     returns a real version string on both."
echo ""

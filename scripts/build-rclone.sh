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
gomobile bind \
    -target=ios/arm64 \
    -o "$XCFRAMEWORK" \
    -ldflags="-s -w" \
    -tags="rclone_no_serve_dlna" \
    .

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

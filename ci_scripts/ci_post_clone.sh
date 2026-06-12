#!/bin/sh
# Xcode Cloud post-clone hook.
#
# Frameworks/RcloneKit.xcframework (~315 MB) is gitignored, so it is absent from
# the fresh Xcode Cloud checkout. Regenerate it from rclone via gomobile before
# the build, otherwise the link step fails ("RcloneKit.xcframework not found").
set -e

# Xcode Cloud checks out the repo at CI_PRIMARY_REPOSITORY_PATH; fall back to the
# repo root relative to this script (ci_scripts/..) when run outside Xcode Cloud.
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

# Go (>= 1.22) is required by gomobile. Homebrew is available on Xcode Cloud.
if ! command -v go >/dev/null 2>&1; then
  echo "Installing Go via Homebrew..."
  brew install go
fi
export PATH="/opt/homebrew/bin:$PATH"
echo "Using $(go version)"

# Builds Frameworks/RcloneKit.xcframework (ios-arm64 + macos-arm64).
# gomobile is auto-installed by the script if missing.
./scripts/build-rclone.sh

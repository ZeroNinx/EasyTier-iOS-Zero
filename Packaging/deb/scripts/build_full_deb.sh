#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DEB_DIR/../.." && pwd)"

CONFIGURATION="${CONFIGURATION:-Debug}"

xcodebuild \
    -quiet \
    -project "$REPO_ROOT/EasyTier.xcodeproj" \
    -scheme EasyTier \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    build

(
    cd "$REPO_ROOT/Daemon"
    cargo build --release
)

"$SCRIPT_DIR/build_deb.sh"

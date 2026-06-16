#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DEB_DIR/../.." && pwd)"

APP_PATH="${1:-${APP_PATH:-}}"
DAEMON_BIN="${2:-${DAEMON_BIN:-}}"
VERSION="${VERSION:-0.1.0}"
PACKAGE_ID="com.zeroninx.easytier"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Usage: $0 /path/to/EasyTier.app /path/to/easytierd" >&2
    echo "Or set APP_PATH and DAEMON_BIN." >&2
    exit 2
fi

if [ -z "$DAEMON_BIN" ] || [ ! -f "$DAEMON_BIN" ]; then
    echo "Usage: $0 /path/to/EasyTier.app /path/to/easytierd" >&2
    echo "Or set APP_PATH and DAEMON_BIN." >&2
    exit 2
fi

BUILD_DIR="$DEB_DIR/build"
STAGE="$BUILD_DIR/${PACKAGE_ID}_${VERSION}_rootless"
DIST="$DEB_DIR/dist"
CONTROL_DIR="$STAGE/DEBIAN"

rm -rf "$STAGE"
mkdir -p "$CONTROL_DIR" \
    "$STAGE/var/jb/Applications" \
    "$STAGE/var/jb/usr/bin" \
    "$STAGE/var/jb/Library/LaunchDaemons" \
    "$DIST"

cp "$DEB_DIR/control" "$CONTROL_DIR/control"
sed -i '' "s/^Version: .*/Version: $VERSION/" "$CONTROL_DIR/control"
cp "$DEB_DIR/postinst" "$CONTROL_DIR/postinst"
cp "$DEB_DIR/prerm" "$CONTROL_DIR/prerm"
cp "$DEB_DIR/postrm" "$CONTROL_DIR/postrm"
chmod 755 "$CONTROL_DIR/postinst" "$CONTROL_DIR/prerm" "$CONTROL_DIR/postrm"

ditto "$APP_PATH" "$STAGE/var/jb/Applications/EasyTier.app"
cp "$DAEMON_BIN" "$STAGE/var/jb/usr/bin/easytierd"
chmod 755 "$STAGE/var/jb/usr/bin/easytierd"

cp "$DEB_DIR/LaunchDaemons/com.zeroninx.easytierd.plist" \
    "$STAGE/var/jb/Library/LaunchDaemons/com.zeroninx.easytierd.plist"
chmod 644 "$STAGE/var/jb/Library/LaunchDaemons/com.zeroninx.easytierd.plist"

OUT="$DIST/${PACKAGE_ID}_${VERSION}_iphoneos-arm64.deb"
dpkg-deb -Zxz -b "$STAGE" "$OUT"
echo "$OUT"

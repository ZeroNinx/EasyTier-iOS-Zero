#!/bin/sh
set -e

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DEB_DIR/../.." && pwd)"

PACKAGE_ID="com.zeroninx.easytier"
APP_ENTITLEMENTS="$DEB_DIR/Entitlements/app.plist"
DAEMON_ENTITLEMENTS="$DEB_DIR/Entitlements/daemon.plist"

CONFIGURATION="${CONFIGURATION:-Debug}"
VERSION="${VERSION:-$(sed -n 's/^Version: //p' "$DEB_DIR/control" | head -n 1)}"
APP_PATH="${APP_PATH:-}"
DAEMON_BIN="${DAEMON_BIN:-}"
PACKAGE_ONLY=0

usage() {
    cat >&2 <<EOF
Usage:
  $0 [--configuration Debug|Release] [--version VERSION]
  $0 --package-only --app /path/to/EasyTier.app --daemon /path/to/easytierd [--version VERSION]

Environment variables are also supported:
  CONFIGURATION, VERSION, APP_PATH, DAEMON_BIN

Default mode builds the EasyTier Xcode scheme for iphoneos, builds easytierd for
aarch64-apple-ios, then stages and signs a rootless jailbreak deb.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --build)
            PACKAGE_ONLY=0
            shift
            ;;
        --package-only)
            PACKAGE_ONLY=1
            shift
            ;;
        --configuration)
            CONFIGURATION="${2:-}"
            [ -n "$CONFIGURATION" ] || {
                usage
                exit 2
            }
            shift 2
            ;;
        --version)
            VERSION="${2:-}"
            [ -n "$VERSION" ] || {
                usage
                exit 2
            }
            shift 2
            ;;
        --app)
            APP_PATH="${2:-}"
            [ -n "$APP_PATH" ] || {
                usage
                exit 2
            }
            PACKAGE_ONLY=1
            shift 2
            ;;
        --daemon)
            DAEMON_BIN="${2:-}"
            [ -n "$DAEMON_BIN" ] || {
                usage
                exit 2
            }
            PACKAGE_ONLY=1
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
        *)
            if [ -z "$APP_PATH" ]; then
                APP_PATH="$1"
            elif [ -z "$DAEMON_BIN" ]; then
                DAEMON_BIN="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage
                exit 2
            fi
            PACKAGE_ONLY=1
            shift
            ;;
    esac
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        echo "Install it and ensure it is available in PATH." >&2
        exit 2
    fi
}

is_ios_arm64_binary() {
    binary="$1"
    [ -f "$binary" ] || return 1
    file "$binary" | grep -q "arm64" || return 1
    otool -l "$binary" 2>/dev/null | grep -q "platform 2\\|LC_VERSION_MIN_IPHONEOS"
}

newer_than() {
    left="$1"
    right="$2"
    [ -z "$right" ] && return 0
    [ "$(stat -f "%m" "$left")" -gt "$(stat -f "%m" "$right")" ]
}

find_latest_app() {
    candidates="$(mktemp)"
    find "$REPO_ROOT" -path "*/Build/Products/*-iphoneos/EasyTier.app" -type d 2>/dev/null >> "$candidates" || true
    if [ -n "${HOME:-}" ] && [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
        find "$HOME/Library/Developer/Xcode/DerivedData" \
            -path "*/Build/Products/*-iphoneos/EasyTier.app" \
            -type d 2>/dev/null >> "$candidates" || true
        find "$HOME/Library/Developer/Xcode/DerivedData" \
            -path "*/Index.noindex/Build/Products/*-iphoneos/EasyTier.app" \
            -type d 2>/dev/null >> "$candidates" || true
    fi

    latest=""
    while IFS= read -r candidate; do
        [ -d "$candidate" ] || continue
        is_ios_arm64_binary "$candidate/EasyTier" || continue
        if newer_than "$candidate" "$latest"; then
            latest="$candidate"
        fi
    done < "$candidates"
    rm -f "$candidates"

    [ -n "$latest" ] && printf "%s\n" "$latest"
}

find_latest_daemon() {
    candidates="$(mktemp)"
    find "$REPO_ROOT/Daemon/target" -path "*/release/easytierd" -type f 2>/dev/null >> "$candidates" || true

    latest=""
    while IFS= read -r candidate; do
        [ -f "$candidate" ] || continue
        is_ios_arm64_binary "$candidate" || continue
        if newer_than "$candidate" "$latest"; then
            latest="$candidate"
        fi
    done < "$candidates"
    rm -f "$candidates"

    [ -n "$latest" ] && printf "%s\n" "$latest"
}

build_products() {
    require_command xcodebuild
    require_command cargo
    require_command protoc

    echo "Building EasyTier.app ($CONFIGURATION, iphoneos)."
    xcodebuild \
        -quiet \
        -project "$REPO_ROOT/EasyTier.xcodeproj" \
        -scheme EasyTier \
        -configuration "$CONFIGURATION" \
        -sdk iphoneos \
        -destination "generic/platform=iOS" \
        build

    echo "Building easytierd (aarch64-apple-ios release)."
    (
        cd "$REPO_ROOT/Daemon"
        cargo build --release
    )
}

stage_package() {
    require_command file
    require_command otool
    require_command ditto
    require_command dpkg-deb
    require_command ldid

    if [ -z "$APP_PATH" ]; then
        APP_PATH="$(find_latest_app || true)"
    fi
    if [ -z "$DAEMON_BIN" ]; then
        DAEMON_BIN="$(find_latest_daemon || true)"
    fi

    if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
        echo "Missing EasyTier.app iphoneos build product." >&2
        usage
        exit 2
    fi
    if ! is_ios_arm64_binary "$APP_PATH/EasyTier"; then
        echo "Invalid EasyTier.app: expected an iOS arm64 executable at:" >&2
        echo "  $APP_PATH/EasyTier" >&2
        file "$APP_PATH/EasyTier" >&2 || true
        exit 2
    fi

    if [ -z "$DAEMON_BIN" ] || [ ! -f "$DAEMON_BIN" ]; then
        echo "Missing easytierd iOS arm64 build product." >&2
        echo "Do not use Daemon/target/release/easytierd; that is a macOS host binary." >&2
        usage
        exit 2
    fi
    if ! is_ios_arm64_binary "$DAEMON_BIN"; then
        echo "Invalid easytierd: expected an iOS arm64 executable at:" >&2
        echo "  $DAEMON_BIN" >&2
        file "$DAEMON_BIN" >&2 || true
        exit 2
    fi

    if [ ! -f "$APP_ENTITLEMENTS" ] || [ ! -f "$DAEMON_ENTITLEMENTS" ]; then
        echo "Missing packaging entitlements under $DEB_DIR/Entitlements." >&2
        exit 2
    fi

    echo "Using app: $APP_PATH"
    echo "Using daemon: $DAEMON_BIN"
    echo "Building full jailbreak deb. Remove any Xcode/sideloaded EasyTier app with the same bundle identifier before installing this package."

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
    rm -rf "$STAGE/var/jb/Applications/EasyTier.app/_CodeSignature"
    rm -f "$STAGE/var/jb/Applications/EasyTier.app/embedded.mobileprovision"
    ldid -S"$APP_ENTITLEMENTS" "$STAGE/var/jb/Applications/EasyTier.app/EasyTier"

    cp "$DAEMON_BIN" "$STAGE/var/jb/usr/bin/easytierd"
    chmod 755 "$STAGE/var/jb/usr/bin/easytierd"
    ldid -S"$DAEMON_ENTITLEMENTS" "$STAGE/var/jb/usr/bin/easytierd"

    cp "$DEB_DIR/LaunchDaemons/com.zeroninx.easytierd.plist" \
        "$STAGE/var/jb/Library/LaunchDaemons/com.zeroninx.easytierd.plist"
    chmod 644 "$STAGE/var/jb/Library/LaunchDaemons/com.zeroninx.easytierd.plist"

    OUT="$DIST/${PACKAGE_ID}_${VERSION}_iphoneos-arm64.deb"
    dpkg-deb --root-owner-group -Zxz -b "$STAGE" "$OUT"
    echo "$OUT"
}

if [ "$PACKAGE_ONLY" -eq 0 ]; then
    build_products
fi

stage_package

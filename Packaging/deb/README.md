# Rootless Debian Package

This directory contains the rootless jailbreak package definition for EasyTier for iOS 15+ Jailbreak.

Install EasyTier through the generated package, not through Xcode or a sideloading tool at the same time. If an app with the same `CFBundleIdentifier` is still installed, Dopamine/SpringBoard may report a duplicate app.

## Contents

```text
control                         Debian package metadata
postinst, prerm, postrm          maintainer scripts
Entitlements/                    ldid entitlements for the app and daemon
LaunchDaemons/                   launchd plist for easytierd
scripts/build_deb.sh             single build and packaging entry point
build/                           generated staging tree, ignored by git
dist/                            generated .deb output, ignored by git
```

Installed paths:

```text
/var/jb/Applications/EasyTier.app
/var/jb/usr/bin/easytierd
/var/jb/Library/LaunchDaemons/com.zeroninx.easytierd.plist
```

User data is created and preserved under:

```text
/var/mobile/Library/Application Support/EasyTier/
```

## Build

Full local build and package:

```sh
Packaging/deb/scripts/build_deb.sh
```

Release package:

```sh
CONFIGURATION=Release VERSION=0.2.0 Packaging/deb/scripts/build_deb.sh
```

Package existing iOS arm64 products:

```sh
Packaging/deb/scripts/build_deb.sh \
  --package-only \
  --app /path/to/EasyTier.app \
  --daemon /path/to/easytierd \
  --version 0.2.0
```

The script validates that both `EasyTier.app/EasyTier` and `easytierd` are iOS arm64 binaries before packaging.

Output:

```text
Packaging/deb/dist/com.zeroninx.easytier_${VERSION}_iphoneos-arm64.deb
```

See the root README for the verified macOS/Xcode/Rust/tooling versions.

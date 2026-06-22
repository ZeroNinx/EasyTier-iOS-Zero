# Rootless Debian Package

This directory contains the rootless jailbreak package definition for EasyTier for iOS 15+ Jailbreak.

This workflow packages EasyTier as a rootless jailbreak app plus a LaunchDaemon. The desktop entry is installed under `/var/jb/Applications`, and runtime data is not written to the mobile user's Application Support directory.

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
/var/jb/usr/bin/easytierd
/var/jb/Applications/EasyTier.app
/var/jb/Library/LaunchDaemons/com.zeroninex.easytierd.plist
```

Runtime data is created under:

```text
/var/jb/var/lib/easytier/
```

Legacy mobile-side EasyTier app/data containers are removed by bundle identifier during install and removal.

## Build

Full local build and package:

```sh
Packaging/deb/scripts/build_deb.sh
```

Release package:

```sh
CONFIGURATION=Release VERSION=0.3.0 Packaging/deb/scripts/build_deb.sh
```

Package existing iOS arm64 products:

```sh
Packaging/deb/scripts/build_deb.sh \
  --package-only \
  --app /path/to/EasyTier.app \
  --daemon /path/to/easytierd \
  --version 0.3.0
```

The script validates that both `EasyTier.app/EasyTier` and `easytierd` are iOS arm64 binaries before packaging.

Output:

```text
Packaging/deb/dist/com.zeroninex.easytier_${VERSION}_iphoneos-arm64.deb
```

See the root README for the verified macOS/Xcode/Rust/tooling versions.

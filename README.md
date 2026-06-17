# EasyTier for iOS 15+ Jailbreak

[简体中文](README_CN.md) | [English](README.md)

EasyTier for iOS 15+ rootless jailbreak environments.

### Overview

This repository provides an iOS client package for jailbroken devices, with a SwiftUI app and the `easytierd` runtime daemon packaged as a rootless `.deb`.

### Build

The full package build is driven by `Packaging/deb/scripts/build_full_deb.sh`.

Known requirement: Xcode 14 or newer. The script also expects a macOS build environment with Xcode command line tools, Rust with the `aarch64-apple-ios` target, `protoc`, `dpkg-deb`, and `ldid` available.

Prepare the Rust iOS target and `protoc`:

```sh
ci_scripts/ci_post_clone.sh
```

Build the app, daemon, and rootless deb package:

```sh
CONFIGURATION=Release VERSION=0.1.19 Packaging/deb/scripts/build_full_deb.sh
```

`CONFIGURATION` defaults to `Debug`, and `VERSION` defaults to the package version used by the deb scripts. The output is written to:

```text
Packaging/deb/dist/com.zeroninx.easytier_${VERSION}_iphoneos-arm64.deb
```

To package existing iOS arm64 build products instead of running the full build:

```sh
APP_PATH=/path/to/EasyTier.app DAEMON_BIN=/path/to/easytierd VERSION=0.1.19 Packaging/deb/scripts/build_deb.sh
```

### Installation

Install the generated `.deb` in a rootless jailbreak environment. Before installing, remove any EasyTier app installed by Xcode or a sideloading tool with the same bundle identifier.

### Status

This is not an official EasyTier release.

### License

GNU General Public License v3.0 or later - See [LICENSE](LICENSE) file

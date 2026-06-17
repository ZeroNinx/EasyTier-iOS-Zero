# EasyTier for iOS 15+ Jailbreak

[简体中文](README_CN.md) | [English](README.md)

EasyTier client package for iOS 15+ rootless jailbreak environments. This fork packages a SwiftUI app, the EasyTier core wrapper, and the privileged `easytierd` daemon into one rootless `.deb`.

This is not an official EasyTier release.

See [docs/ROADMAP.md](docs/ROADMAP.md) for current scope and remaining work.

## Repository Layout

```text
EasyTier/                  SwiftUI app
EasyTierShared/            Shared Swift constants and helpers
EasyTierNetworkExtension/  Original NetworkExtension target kept for compatibility
EasyTierWidgetExtension/   iOS widget target
Core/                      Rust static library wrapping EasyTier core
Daemon/                    Rust jailbreak daemon and IPC server
Packaging/deb/             Rootless jailbreak deb metadata, entitlements, launchd plist, scripts
ci_scripts/                Build bootstrap helpers
docs/                      Public roadmap and project notes
```

## Build Environment

The current local build has been verified with:

- macOS 12.6.2
- Xcode 14.2, iPhoneOS SDK 16.2
- Rust/Cargo 1.96.0
- Rust target `aarch64-apple-ios`
- `protoc` 3.21.12
- `dpkg-deb` 1.21.18
- `ldid` 2.1.5

Required commands:

```text
xcodebuild xcrun rustup rustc cargo protoc dpkg-deb ldid file otool ditto
```

The deb script prepends `/opt/homebrew/bin:/usr/local/bin` to `PATH`, because Homebrew-installed `protoc`, `dpkg-deb`, and `ldid` are commonly located there.

Install the Rust iOS target:

```sh
rustup target add aarch64-apple-ios
```

Install package tools with Homebrew if they are missing:

```sh
brew install protobuf dpkg ldid
```

`ci_scripts/ci_post_clone.sh` can prepare Rust and `protoc` for CI-like environments, but it does not replace the Xcode, `dpkg-deb`, or `ldid` requirements.

## Build

There is one deb build entry point:

```sh
Packaging/deb/scripts/build_deb.sh
```

By default it:

1. Builds the `EasyTier` Xcode scheme for `iphoneos`.
2. Builds `Daemon` with Cargo. `Daemon/.cargo/config.toml` pins the daemon target to `aarch64-apple-ios`.
3. Stages the rootless filesystem tree.
4. Re-signs the app executable and daemon with the packaging entitlements.
5. Produces a rootless `.deb`.

Release build:

```sh
CONFIGURATION=Release VERSION=0.2.0 Packaging/deb/scripts/build_deb.sh
```

Defaults:

- `CONFIGURATION=Debug`
- `VERSION` is read from `Packaging/deb/control`

Output:

```text
Packaging/deb/dist/com.zeroninx.easytier_${VERSION}_iphoneos-arm64.deb
```

Package existing iOS arm64 build products without rebuilding:

```sh
Packaging/deb/scripts/build_deb.sh \
  --package-only \
  --app /path/to/EasyTier.app \
  --daemon /path/to/easytierd \
  --version 0.2.0
```

Both `EasyTier.app/EasyTier` and `easytierd` must be iOS arm64 binaries. The script rejects macOS host binaries.

## Installation

Install the generated `.deb` on a rootless jailbreak device. Before installing, remove any EasyTier app installed by Xcode or a sideloading tool with the same bundle identifier, otherwise SpringBoard/Dopamine may report a duplicate app.

The package installs:

```text
/var/jb/Applications/EasyTier.app
/var/jb/usr/bin/easytierd
/var/jb/Library/LaunchDaemons/com.zeroninx.easytierd.plist
```

Runtime data and logs are stored under:

```text
/var/mobile/Library/Application Support/EasyTier/
```

## License

GNU General Public License v3.0 or later. See [LICENSE](LICENSE).

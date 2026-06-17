# Debian Package

This directory contains the rootless jailbreak package for EasyTier for iOS 15+ Jailbreak.

This is a full deb workflow: install EasyTier through the package, not through Xcode
or sideloading at the same time. If an Xcode/sideloaded build with the same
`CFBundleIdentifier` is still installed, Dopamine/SpringBoard may report a duplicate
app.

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

Build requirements:

- macOS with Xcode 14 or newer and Xcode command line tools.
- Rust with the `aarch64-apple-ios` target.
- `protoc`.
- `dpkg-deb`.
- `ldid`.

Prepare the Rust iOS target and `protoc`:

```sh
ci_scripts/ci_post_clone.sh
```

Full build:

```sh
CONFIGURATION=Release VERSION=0.1.19 Packaging/deb/scripts/build_full_deb.sh
```

`build_full_deb.sh` builds the `EasyTier` Xcode scheme for `iphoneos`, builds
`Daemon` with Cargo, then invokes `build_deb.sh` to stage, sign, and package the
rootless deb. `CONFIGURATION` defaults to `Debug`; `VERSION` defaults to the
package version used by the deb scripts.

Output:

```text
Packaging/deb/dist/com.zeroninx.easytier_${VERSION}_iphoneos-arm64.deb
```

Advanced packaging from existing build products:

```sh
APP_PATH=/path/to/EasyTier.app DAEMON_BIN=/path/to/easytierd VERSION=0.1.19 Packaging/deb/scripts/build_deb.sh
```

Both `EasyTier.app/EasyTier` and `easytierd` must be iOS arm64 binaries.

Before installing the full deb on device, remove any existing EasyTier app installed
by Xcode or a sideloading tool. The package itself installs the app under
`/var/jb/Applications/EasyTier.app`.

# Debian Package

This directory contains the rootless jailbreak package for EasyTier for iOS 15+ Jailbreak.

This workflow packages EasyTier as a rootless jailbreak app plus a LaunchDaemon.
The desktop entry is installed under `/var/jb/Applications`, not as a
user-installed app, and runtime data is not written to the mobile user's
Application Support directory.

Installed paths:

```text
/var/jb/usr/bin/easytierd
/var/jb/Applications/EasyTier.app
/var/jb/Library/LaunchDaemons/com.zeroninex.easytierd.plist
```

Runtime data is created and preserved under:

```text
/var/jb/var/lib/easytier/
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

Full package build:

```sh
VERSION=0.1.19 Packaging/deb/scripts/build_full_deb.sh
```

`build_full_deb.sh` builds the `EasyTier` Xcode scheme for `iphoneos`, builds
`Daemon` with Cargo, then invokes `build_deb.sh` to stage, sign, and package the
rootless deb. `CONFIGURATION` defaults to `Debug`; `VERSION` defaults to the
package version used by the deb scripts.

Output:

```text
Packaging/deb/dist/com.zeroninex.easytier_${VERSION}_iphoneos-arm64.deb
```

Advanced packaging from existing build products:

```sh
APP_PATH=/path/to/EasyTier.app DAEMON_BIN=/path/to/easytierd VERSION=0.1.19 Packaging/deb/scripts/build_deb.sh
```

Both `EasyTier.app/EasyTier` and `easytierd` must be iOS arm64 binaries.

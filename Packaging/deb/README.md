# Debian Package

This directory contains the rootless jailbreak package for the personal fork.

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

Build:

```sh
Packaging/deb/scripts/build_full_deb.sh
```

Advanced packaging from existing build products:

```sh
APP_PATH=/path/to/EasyTier.app DAEMON_BIN=/path/to/easytierd VERSION=0.1.0 Packaging/deb/scripts/build_deb.sh
```

Before installing the full deb on device, remove any existing EasyTier app installed
by Xcode or a sideloading tool. The package itself installs the app under
`/var/jb/Applications/EasyTier.app`.

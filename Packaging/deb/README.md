# Debian Package

This directory contains the rootless jailbreak package skeleton for the personal fork.

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
Packaging/deb/scripts/build_deb.sh /path/to/EasyTier.app /path/to/easytierd
```

or:

```sh
APP_PATH=/path/to/EasyTier.app DAEMON_BIN=/path/to/easytierd VERSION=0.1.0 Packaging/deb/scripts/build_deb.sh
```

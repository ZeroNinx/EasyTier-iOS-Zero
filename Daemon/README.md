# easytierd

`easytierd` is the privileged runtime daemon used by the rootless jailbreak package.

Current scope:

- Create `/var/mobile/Library/Application Support/EasyTier/{runtime,logs}`.
- Listen on `127.0.0.1:37657` for newline-delimited JSON IPC from the GUI.
- Start and stop the EasyTier core session on request.
- Create and configure the `utun` interface and routes required by the running network.
- Expose daemon status, daemon version, core running info, interface traffic counters, and log tails.
- Write `easytierd.log`; the embedded core writes `easytier-core.log`.

The deb package installs the daemon at:

```text
/var/jb/usr/bin/easytierd
```

The launchd plist is installed at:

```text
/var/jb/Library/LaunchDaemons/com.zeroninx.easytierd.plist
```

The daemon target is pinned to iOS arm64 by `Daemon/.cargo/config.toml`. From this directory:

```sh
cargo build --release
```

The output used by the deb package is:

```text
Daemon/target/aarch64-apple-ios/release/easytierd
```

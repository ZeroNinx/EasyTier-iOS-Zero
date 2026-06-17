# easytierd

`easytierd` is the runtime daemon for EasyTier for iOS 15+ Jailbreak.

Current scope:

- Create `/var/mobile/Library/Application Support/EasyTier/{runtime,logs}`.
- Listen on `127.0.0.1:37657`.
- Accept newline-delimited JSON IPC.
- Implement read-only `ping`, `status`, and `tailLog`.

This daemon does not start EasyTier Core or configure `utun` yet.

# easytierd

`easytierd` is the jailbreak runtime daemon for this personal fork.

Current scope:

- Create `/var/mobile/Library/Application Support/EasyTier/{runtime,logs}`.
- Listen on `runtime/easytierd.sock`.
- Accept newline-delimited JSON IPC.
- Implement read-only `ping`, `status`, and `tailLog`.

This daemon does not start EasyTier Core or configure `utun` yet.

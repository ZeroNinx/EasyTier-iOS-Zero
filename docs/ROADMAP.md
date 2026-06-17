# Roadmap

This project currently focuses on rootless jailbreak devices running iOS 15 or newer.

## Current Scope

- SwiftUI GUI for editing EasyTier profiles, controlling connections, viewing status, and reading logs.
- `easytierd` LaunchDaemon for privileged runtime operations.
- Local TCP IPC between the GUI and daemon.
- Manual `utun` creation and route configuration from the daemon.
- Rootless `.deb` packaging for the app, daemon, launchd plist, maintainer scripts, and entitlements.

## Verified

- App and daemon can be packaged into one rootless `.deb`.
- The daemon can be started by launchd and contacted by the GUI.
- The GUI can start and stop EasyTier core sessions through daemon IPC.
- The daemon can attach EasyTier core to a `utun` interface and apply IPv4 routes.
- Peer visibility and basic traffic routing have been validated on a jailbroken device.

## Open Work

- Continue reducing legacy NetworkExtension-only code paths where they are no longer used by the jailbreak runtime.
- Improve DNS handling for MagicDNS and override DNS modes.
- Add more explicit diagnostics for route and `utun` failures.
- Expand release documentation after more devices and jailbreak environments have been tested.
- Add automated checks for packaging metadata and maintainer scripts.

## Out of Scope

- App Store and TestFlight distribution.
- Non-jailbroken iOS runtime support for this package path.
- Requesting private NetworkExtension entitlements for the jailbreak runtime.

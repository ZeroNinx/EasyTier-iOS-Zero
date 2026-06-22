import Foundation

enum AppPaths {
    static let jailbreakBaseURL = URL(fileURLWithPath: "/var/jb/var/lib/easytier", isDirectory: true)

    static var runtimeDirectoryURL: URL {
        jailbreakBaseURL.appendingPathComponent("runtime", isDirectory: true)
    }

    static var logsDirectoryURL: URL {
        jailbreakBaseURL.appendingPathComponent("logs", isDirectory: true)
    }

    static var daemonLogURL: URL {
        logsDirectoryURL.appendingPathComponent("easytierd.log")
    }

    static let daemonIPCAddress = "127.0.0.1"
    static let daemonIPCPort: UInt16 = 37657

    static var rootlessDaemonURL: URL {
        URL(fileURLWithPath: "/var/jb/usr/bin/easytierd")
    }

    static let daemonLaunchLabel = "com.zeroninex.easytierd"

    static var daemonLaunchJob: String {
        "system/\(daemonLaunchLabel)"
    }

    static var daemonLaunchPlistURL: URL {
        URL(fileURLWithPath: "/var/jb/Library/LaunchDaemons/\(daemonLaunchLabel).plist")
    }
}

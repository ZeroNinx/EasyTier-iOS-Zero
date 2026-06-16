import Foundation

enum AppPaths {
    static let jailbreakBaseURL = URL(fileURLWithPath: "/var/mobile/Library/Application Support/EasyTier", isDirectory: true)

    static var runtimeDirectoryURL: URL {
        jailbreakBaseURL.appendingPathComponent("runtime", isDirectory: true)
    }

    static var logsDirectoryURL: URL {
        jailbreakBaseURL.appendingPathComponent("logs", isDirectory: true)
    }

    static var daemonSocketURL: URL {
        runtimeDirectoryURL.appendingPathComponent("easytierd.sock")
    }

    static var daemonLogURL: URL {
        logsDirectoryURL.appendingPathComponent("easytierd.log")
    }

    static var daemonBinDirectoryURL: URL {
        jailbreakBaseURL.appendingPathComponent("bin", isDirectory: true)
    }

    static var bundledInstallDaemonURL: URL {
        daemonBinDirectoryURL.appendingPathComponent("easytierd")
    }

    static var rootlessDaemonURL: URL {
        URL(fileURLWithPath: "/var/jb/usr/bin/easytierd")
    }

    static var rootfulDaemonURL: URL {
        URL(fileURLWithPath: "/usr/bin/easytierd")
    }

    static var daemonCandidateURLs: [URL] {
        [
            rootlessDaemonURL,
            bundledInstallDaemonURL,
            rootfulDaemonURL,
        ]
    }
}

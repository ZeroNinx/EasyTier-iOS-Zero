import Darwin
import Foundation

enum DaemonInstaller {
    static let bundledResourceName = "easytierd"

    static func installedBinaryURL() -> URL? {
        AppPaths.daemonCandidateURLs.first { url in
            FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    static func bundledBinaryURL() -> URL? {
        Bundle.main.url(forResource: bundledResourceName, withExtension: nil)
    }

    static func installBundledDaemon() throws -> URL {
        guard let sourceURL = bundledBinaryURL() else {
            throw DaemonInstallerError.bundledDaemonMissing
        }

        try FileManager.default.createDirectory(
            at: AppPaths.daemonBinDirectoryURL,
            withIntermediateDirectories: true
        )

        let destinationURL = AppPaths.bundledInstallDaemonURL
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        guard chmod(destinationURL.path, 0o755) == 0 else {
            throw DaemonInstallerError.chmodFailed(String(cString: strerror(errno)))
        }
        return destinationURL
    }
}

enum DaemonInstallerError: LocalizedError {
    case bundledDaemonMissing
    case chmodFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledDaemonMissing:
            return String(localized: "daemon_bundled_missing")
        case .chmodFailed(let message):
            return String(format: String(localized: "daemon_chmod_failed %@"), message)
        }
    }
}

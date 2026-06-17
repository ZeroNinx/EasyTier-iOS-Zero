import Darwin
import Foundation

enum JailbreakDaemonControllerError: LocalizedError {
    case missingDaemon(URL)
    case missingLaunchDaemon(URL)
    case missingCommand(String)
    case spawnFailed(String, String)
    case waitFailed(String, String)
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .missingDaemon(let url):
            return "easytierd not found at \(url.path)"
        case .missingLaunchDaemon(let url):
            return "LaunchDaemon plist not found at \(url.path)"
        case .missingCommand(let name):
            return "\(name) not found"
        case .spawnFailed(let command, let message):
            return "\(command) failed to launch: \(message)"
        case .waitFailed(let command, let message):
            return "\(command) wait failed: \(message)"
        case .commandFailed(let command, let status):
            return "\(command) failed with status \(status)"
        }
    }
}

enum JailbreakDaemonController {
    private static let launchctlCandidates = [
        "/bin/launchctl",
        "/var/jb/bin/launchctl",
        "/usr/bin/launchctl",
        "/var/jb/usr/bin/launchctl"
    ]

    private static let killallCandidates = [
        "/usr/bin/killall",
        "/var/jb/usr/bin/killall",
        "/bin/killall",
        "/var/jb/bin/killall"
    ]

    static func start() async throws {
        try await Task.detached(priority: .userInitiated) {
            try startSync()
        }.value
    }

    static func stop() async {
        await Task.detached(priority: .userInitiated) {
            stopSync()
        }.value
    }

    private static func startSync() throws {
        guard FileManager.default.isExecutableFile(atPath: AppPaths.rootlessDaemonURL.path) else {
            throw JailbreakDaemonControllerError.missingDaemon(AppPaths.rootlessDaemonURL)
        }
        guard FileManager.default.fileExists(atPath: AppPaths.daemonLaunchPlistURL.path) else {
            throw JailbreakDaemonControllerError.missingLaunchDaemon(AppPaths.daemonLaunchPlistURL)
        }
        let launchctl = try findExecutable(named: "launchctl", candidates: launchctlCandidates)

        _ = runIgnoringFailure(launchctl, ["bootstrap", "system", AppPaths.daemonLaunchPlistURL.path])
        _ = runIgnoringFailure(launchctl, ["enable", AppPaths.daemonLaunchJob])
        _ = runIgnoringFailure(launchctl, ["kickstart", "-k", AppPaths.daemonLaunchJob])
    }

    private static func stopSync() {
        if let launchctl = firstExecutable(launchctlCandidates) {
            _ = runIgnoringFailure(launchctl, ["bootout", AppPaths.daemonLaunchJob])
            _ = runIgnoringFailure(launchctl, ["bootout", "system", AppPaths.daemonLaunchPlistURL.path])
        }
        if let killall = firstExecutable(killallCandidates) {
            _ = runIgnoringFailure(killall, ["easytierd"])
            Thread.sleep(forTimeInterval: 0.5)
            _ = runIgnoringFailure(killall, ["-9", "easytierd"])
        }
    }

    private static func findExecutable(named name: String, candidates: [String]) throws -> String {
        guard let path = firstExecutable(candidates) else {
            throw JailbreakDaemonControllerError.missingCommand(name)
        }
        return path
    }

    private static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    private static func runIgnoringFailure(_ executable: String, _ arguments: [String]) -> Int32 {
        (try? run(executable, arguments)) ?? -1
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let status = try spawnAndWait(executable: executable, arguments: arguments)
        guard status == 0 else {
            throw JailbreakDaemonControllerError.commandFailed(
                ([executable] + arguments).joined(separator: " "),
                status
            )
        }
        return status
    }

    private static func spawnAndWait(executable: String, arguments: [String]) throws -> Int32 {
        var argv = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        defer {
            for pointer in argv where pointer != nil {
                free(pointer)
            }
        }

        var pid: pid_t = 0
        let spawnResult = argv.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(&pid, executable, nil, nil, buffer.baseAddress, nil)
        }
        guard spawnResult == 0 else {
            throw JailbreakDaemonControllerError.spawnFailed(
                executable,
                String(cString: strerror(spawnResult))
            )
        }

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            if errno == EINTR {
                continue
            }
            throw JailbreakDaemonControllerError.waitFailed(
                executable,
                String(cString: strerror(errno))
            )
        }

        if status & 0x7f == 0 {
            return (status >> 8) & 0xff
        }
        return status
    }
}

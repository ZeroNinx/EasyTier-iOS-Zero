import Darwin
import Foundation

import EasyTierShared

struct JailbreakIPCRequest: Codable {
    let id: String
    let command: String
    var limit: Int?
    var profileName: String?
    var options: EasyTierOptions?

    init(
        command: String,
        limit: Int? = nil,
        profileName: String? = nil,
        options: EasyTierOptions? = nil
    ) {
        self.id = UUID().uuidString
        self.command = command
        self.limit = limit
        self.profileName = profileName
        self.options = options
    }
}

struct JailbreakIPCResponse: Codable {
    let id: String
    let ok: Bool
    let status: String?
    let data: DataPayload?
    let error: ErrorPayload?

    struct DataPayload: Codable {
        let lines: [String]?
        let version: String?
        let runningInfo: String?
    }

    struct ErrorPayload: Codable {
        let code: String
        let message: String
    }
}

enum JailbreakIPCCommand {
    static let ping = "ping"
    static let start = "start"
    static let stop = "stop"
    static let status = "status"
    static let tailLog = "tailLog"
    static let version = "version"
    static let runningInfo = "runningInfo"
}

enum JailbreakIPCError: LocalizedError {
    case invalidEndpoint(String)
    case socketFailed(String)
    case connectFailed(endpoint: String, message: String)
    case writeFailed(String)
    case readFailed(String)
    case invalidResponse
    case daemonError(String)
    case daemonOutdated(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "Invalid daemon IPC endpoint: \(endpoint)"
        case .socketFailed(let message):
            return "Failed to create IPC socket: \(message)"
        case .connectFailed(let endpoint, let message):
            return "Failed to connect daemon IPC endpoint \(endpoint): \(message)"
        case .writeFailed(let message):
            return "Failed to write IPC request: \(message)"
        case .readFailed(let message):
            return "Failed to read IPC response: \(message)"
        case .invalidResponse:
            return "Invalid IPC response."
        case .daemonError(let message):
            return message
        case .daemonOutdated(let command):
            return String(format: String(localized: "daemon_update_required %@"), command)
        }
    }
}

final class JailbreakIPCClient {
    private let host: String
    private let port: UInt16

    init(host: String = AppPaths.daemonIPCAddress, port: UInt16 = AppPaths.daemonIPCPort) {
        self.host = host
        self.port = port
    }

    func ping() async throws {
        let response = try await send(.init(command: JailbreakIPCCommand.ping))
        guard response.ok else {
            throw JailbreakIPCError.daemonError(response.error?.message ?? "Daemon ping failed.")
        }
    }

    func status() async throws -> TunnelRuntimeStatus {
        let response = try await send(.init(command: JailbreakIPCCommand.status))
        guard response.ok else {
            throw JailbreakIPCError.daemonError(response.error?.message ?? "Daemon status failed.")
        }
        return TunnelRuntimeStatus(ipcStatus: response.status, error: response.error?.message)
    }

    func version() async throws -> String {
        let response = try await send(.init(command: JailbreakIPCCommand.version))
        if response.error?.code == "unknownCommand" {
            throw JailbreakIPCError.daemonOutdated(JailbreakIPCCommand.version)
        }
        guard response.ok, let version = response.data?.version else {
            throw JailbreakIPCError.daemonError(response.error?.message ?? "Daemon version failed.")
        }
        return version
    }

    func start(profileName: String, options: EasyTierOptions) async throws -> TunnelRuntimeStatus {
        let response = try await send(.init(
            command: JailbreakIPCCommand.start,
            profileName: profileName,
            options: options
        ))
        if response.error?.code == "unknownCommand" {
            throw JailbreakIPCError.daemonOutdated(JailbreakIPCCommand.start)
        }
        guard response.ok else {
            throw JailbreakIPCError.daemonError(response.error?.message ?? "Daemon start failed.")
        }
        return TunnelRuntimeStatus(ipcStatus: response.status, error: response.error?.message)
    }

    func stop() async throws -> TunnelRuntimeStatus {
        let response = try await send(.init(command: JailbreakIPCCommand.stop))
        if response.error?.code == "unknownCommand" {
            throw JailbreakIPCError.daemonOutdated(JailbreakIPCCommand.stop)
        }
        guard response.ok else {
            throw JailbreakIPCError.daemonError(response.error?.message ?? "Daemon stop failed.")
        }
        return TunnelRuntimeStatus(ipcStatus: response.status, error: response.error?.message)
    }

    func tailLog(limit: Int = 200) async throws -> [String] {
        let response = try await send(.init(command: JailbreakIPCCommand.tailLog, limit: limit))
        guard response.ok else {
            throw JailbreakIPCError.daemonError(response.error?.message ?? "Daemon log request failed.")
        }
        return response.data?.lines ?? []
    }

    func runningInfo() async throws -> NetworkStatus? {
        let response = try await send(.init(command: JailbreakIPCCommand.runningInfo))
        guard response.ok else {
            throw JailbreakIPCError.daemonError(response.error?.message ?? "Daemon running info failed.")
        }
        guard let rawInfo = response.data?.runningInfo,
              let data = rawInfo.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(NetworkStatus.self, from: data)
    }

    private func send(_ request: JailbreakIPCRequest) async throws -> JailbreakIPCResponse {
        try await Task.detached(priority: .userInitiated) {
            try self.sendSync(request)
        }.value
    }

    private func sendSync(_ request: JailbreakIPCRequest) throws -> JailbreakIPCResponse {
        let endpoint = "\(host):\(port)"

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw JailbreakIPCError.socketFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        let parseResult = host.withCString { source in
            inet_pton(AF_INET, source, &address.sin_addr)
        }
        guard parseResult == 1 else {
            throw JailbreakIPCError.invalidEndpoint(endpoint)
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            throw JailbreakIPCError.connectFailed(
                endpoint: endpoint,
                message: String(cString: strerror(errno))
            )
        }

        let payload = try JSONEncoder().encode(request) + Data([0x0A])
        try payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw JailbreakIPCError.writeFailed("empty payload")
            }
            var written = 0
            while written < payload.count {
                let result = Darwin.write(fd, base.advanced(by: written), payload.count - written)
                guard result > 0 else {
                    throw JailbreakIPCError.writeFailed(String(cString: strerror(errno)))
                }
                written += result
            }
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count >= 0 else {
                throw JailbreakIPCError.readFailed(String(cString: strerror(errno)))
            }
            if count == 0 {
                break
            }
            if let newlineIndex = buffer[..<count].firstIndex(of: 0x0A) {
                response.append(buffer, count: newlineIndex)
                break
            }
            response.append(buffer, count: count)
        }

        guard !response.isEmpty else {
            throw JailbreakIPCError.invalidResponse
        }
        return try JSONDecoder().decode(JailbreakIPCResponse.self, from: response)
    }
}

extension TunnelRuntimeStatus {
    init(ipcStatus: String?, error: String? = nil) {
        switch ipcStatus {
        case "invalid":
            self = .invalid
        case "stopped":
            self = .stopped
        case "starting":
            self = .starting
        case "running":
            self = .running
        case "stopping":
            self = .stopping
        case "failed":
            self = .failed(error)
        case "daemonUnavailable":
            self = .daemonUnavailable
        default:
            self = .invalid
        }
    }
}

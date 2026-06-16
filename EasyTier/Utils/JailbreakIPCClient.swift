import Darwin
import Foundation

import EasyTierShared

struct JailbreakIPCRequest: Codable {
    let id: String
    let command: String
    var limit: Int?

    init(command: String, limit: Int? = nil) {
        self.id = UUID().uuidString
        self.command = command
        self.limit = limit
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
    }

    struct ErrorPayload: Codable {
        let code: String
        let message: String
    }
}

enum JailbreakIPCCommand {
    static let ping = "ping"
    static let status = "status"
    static let tailLog = "tailLog"
}

enum JailbreakIPCError: LocalizedError {
    case invalidSocketPath
    case connectFailed(String)
    case writeFailed
    case readFailed
    case invalidResponse
    case daemonError(String)

    var errorDescription: String? {
        switch self {
        case .invalidSocketPath:
            return "Invalid daemon socket path."
        case .connectFailed(let message):
            return message
        case .writeFailed:
            return "Failed to write IPC request."
        case .readFailed:
            return "Failed to read IPC response."
        case .invalidResponse:
            return "Invalid IPC response."
        case .daemonError(let message):
            return message
        }
    }
}

final class JailbreakIPCClient {
    private let socketURL: URL

    init(socketURL: URL = AppPaths.daemonSocketURL) {
        self.socketURL = socketURL
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

    func tailLog(limit: Int = 200) async throws -> [String] {
        let response = try await send(.init(command: JailbreakIPCCommand.tailLog, limit: limit))
        guard response.ok else {
            throw JailbreakIPCError.daemonError(response.error?.message ?? "Daemon log request failed.")
        }
        return response.data?.lines ?? []
    }

    private func send(_ request: JailbreakIPCRequest) async throws -> JailbreakIPCResponse {
        try await Task.detached(priority: .userInitiated) {
            try self.sendSync(request)
        }.value
    }

    private func sendSync(_ request: JailbreakIPCRequest) throws -> JailbreakIPCResponse {
        let path = socketURL.path
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw JailbreakIPCError.invalidSocketPath
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw JailbreakIPCError.connectFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        var address = sockaddr_un()
        let sunPathSize = MemoryLayout.size(ofValue: address.sun_path)
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: sunPathSize) { buffer in
                path.withCString { source in
                    strncpy(buffer, source, sunPathSize - 1)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw JailbreakIPCError.connectFailed(String(cString: strerror(errno)))
        }

        let payload = try JSONEncoder().encode(request) + Data([0x0A])
        try payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw JailbreakIPCError.writeFailed
            }
            var written = 0
            while written < payload.count {
                let result = Darwin.write(fd, base.advanced(by: written), payload.count - written)
                guard result > 0 else {
                    throw JailbreakIPCError.writeFailed
                }
                written += result
            }
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count >= 0 else {
                throw JailbreakIPCError.readFailed
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

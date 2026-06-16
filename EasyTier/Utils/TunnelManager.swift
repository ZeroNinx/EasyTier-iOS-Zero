import Foundation
import EasyTierShared

enum TunnelRuntimeStatus: Equatable {
    case invalid
    case stopped
    case starting
    case running
    case stopping
    case failed(String?)
    case daemonUnavailable

    var isConnected: Bool {
        switch self {
        case .running, .stopping:
            return true
        case .invalid, .stopped, .starting, .failed, .daemonUnavailable:
            return false
        }
    }

    var isPending: Bool {
        switch self {
        case .starting, .stopping:
            return true
        case .invalid, .stopped, .running, .failed, .daemonUnavailable:
            return false
        }
    }

    var allowsConfigurationChanges: Bool {
        switch self {
        case .invalid, .stopped, .failed, .daemonUnavailable:
            return true
        case .starting, .running, .stopping:
            return false
        }
    }

    var localizationKey: String {
        switch self {
        case .invalid:
            return "runtime_status_invalid"
        case .stopped:
            return "runtime_status_stopped"
        case .starting:
            return "runtime_status_starting"
        case .running:
            return "runtime_status_running"
        case .stopping:
            return "runtime_status_stopping"
        case .failed:
            return "runtime_status_failed"
        case .daemonUnavailable:
            return "runtime_status_daemon_unavailable"
        }
    }
}

enum TunnelManagerError: LocalizedError {
    case daemonUnavailable
    case commandUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .daemonUnavailable:
            return String(localized: "runtime_status_daemon_unavailable")
        case .commandUnsupported(let command):
            return String(format: String(localized: "daemon_command_unsupported %@"), command)
        }
    }
}

@MainActor
protocol TunnelManagerProtocol: ObservableObject {
    var status: TunnelRuntimeStatus { get }
    var connectedDate: Date? { get }
    var isLoading: Bool { get }
    var lastError: String? { get }

    func refreshStatus() async
    @MainActor
    func connect(profile: NetworkProfile) async throws
    func disconnect() async
    func runningInfo() async throws -> NetworkStatus?
    func networkSnapshot() async throws -> TunnelNetworkSettingsSnapshot?
}

@MainActor
final class MockTunnelManager: TunnelManagerProtocol {
    @Published private(set) var status: TunnelRuntimeStatus = .stopped
    @Published private(set) var connectedDate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    func refreshStatus() async {
        status = connectedDate == nil ? .stopped : .running
    }

    func connect(profile: NetworkProfile) async throws {
        status = .starting
        try await Task.sleep(nanoseconds: 500_000_000)
        connectedDate = Date()
        status = .running
    }

    func disconnect() async {
        status = .stopping
        try? await Task.sleep(nanoseconds: 500_000_000)
        connectedDate = nil
        status = .stopped
    }

    func runningInfo() async throws -> NetworkStatus? {
        MockNEManager.dummyRunningInfo
    }

    func networkSnapshot() async throws -> TunnelNetworkSettingsSnapshot? {
        nil
    }
}

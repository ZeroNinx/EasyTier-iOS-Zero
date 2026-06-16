import Foundation

import EasyTierShared

@MainActor
final class JailbreakTunnelManager: TunnelManagerProtocol {
    @Published private(set) var status: TunnelRuntimeStatus = .daemonUnavailable
    @Published private(set) var connectedDate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = String(localized: "runtime_status_daemon_unavailable")

    private let client = JailbreakIPCClient()

    func refreshStatus() async {
        do {
            status = try await client.status()
            lastError = nil
        } catch {
            status = .daemonUnavailable
            lastError = error.localizedDescription
        }
    }

    func connect(profile: NetworkProfile) async throws {
        await refreshStatus()
        if status == .daemonUnavailable {
            throw TunnelManagerError.daemonUnavailable
        }
        lastError = String(format: String(localized: "daemon_command_unsupported %@"), "start")
        throw TunnelManagerError.commandUnsupported("start")
    }

    func disconnect() async {
        await refreshStatus()
        connectedDate = nil
    }

    func runningInfo() async throws -> NetworkStatus? {
        nil
    }

    func networkSnapshot() async throws -> TunnelNetworkSettingsSnapshot? {
        nil
    }
}

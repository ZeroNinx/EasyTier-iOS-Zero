import Foundation

import EasyTierShared

@MainActor
final class JailbreakTunnelManager: TunnelManagerProtocol {
    @Published private(set) var status: TunnelRuntimeStatus = .daemonUnavailable
    @Published private(set) var connectedDate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String? = String(localized: "runtime_status_daemon_unavailable")
    @Published private(set) var serviceVersion: String?

    private let client = JailbreakIPCClient()
    private let daemonStoppedKey = "easytier.daemonStoppedByUser"

    private var daemonStoppedByUser: Bool {
        get { UserDefaults.standard.bool(forKey: daemonStoppedKey) }
        set { UserDefaults.standard.set(newValue, forKey: daemonStoppedKey) }
    }

    func refreshStatus() async {
        do {
            status = try await client.status()
            if !status.isConnected {
                connectedDate = nil
            }
            do {
                serviceVersion = try await client.version()
                lastError = nil
            } catch {
                if serviceVersion == nil {
                    lastError = error.localizedDescription
                }
            }
        } catch {
            status = daemonStoppedByUser ? .stopped : .daemonUnavailable
            connectedDate = nil
            serviceVersion = nil
            lastError = daemonStoppedByUser ? nil : error.localizedDescription
        }
    }

    func connect(profile: NetworkProfile) async throws {
        isLoading = true
        status = .starting
        defer { isLoading = false }

        do {
            try await JailbreakDaemonController.start()
            try await waitForDaemon()
            daemonStoppedByUser = false
            let options = try EasyTierOptionsBuilder.generate(from: profile)
            let profileName = profile.networkName.isEmpty ? "default" : profile.networkName
            let nextStatus = try await client.start(profileName: profileName, options: options)
            status = nextStatus
            connectedDate = nextStatus.isConnected ? Date() : nil
            lastError = nil
        } catch {
            status = .failed(error.localizedDescription)
            connectedDate = nil
            lastError = error.localizedDescription
            throw error
        }
    }

    func disconnect() async {
        isLoading = true
        status = .stopping
        defer { isLoading = false }

        do {
            status = try await client.stop()
        } catch {
            if !daemonStoppedByUser {
                lastError = error.localizedDescription
            }
        }
        await JailbreakDaemonController.stop()
        daemonStoppedByUser = true
        status = .stopped
        connectedDate = nil
        lastError = nil
    }

    func runningInfo() async throws -> NetworkStatus? {
        try await client.runningInfo()
    }

    func networkSnapshot() async throws -> TunnelNetworkSettingsSnapshot? {
        nil
    }

    private func waitForDaemon() async throws {
        var lastError: Error?
        for _ in 0..<20 {
            do {
                try await client.ping()
                return
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw lastError ?? TunnelManagerError.daemonUnavailable
    }
}

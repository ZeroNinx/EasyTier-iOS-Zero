import Combine
import Foundation
import NetworkExtension

import EasyTierShared

extension TunnelRuntimeStatus {
    init(_ status: NEVPNStatus) {
        switch status {
        case .invalid:
            self = .invalid
        case .disconnected:
            self = .stopped
        case .connecting:
            self = .starting
        case .connected, .reasserting:
            self = .running
        case .disconnecting:
            self = .stopping
        @unknown default:
            self = .invalid
        }
    }
}

@MainActor
final class NetworkExtensionTunnelManagerAdapter: TunnelManagerProtocol {
    @Published private(set) var status: TunnelRuntimeStatus = .invalid
    @Published private(set) var connectedDate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let legacyManager: NetworkExtensionManager
    private var cancellables = Set<AnyCancellable>()

    init(legacyManager: NetworkExtensionManager = NetworkExtensionManager()) {
        self.legacyManager = legacyManager
        legacyManager.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.status = TunnelRuntimeStatus(status)
            }
            .store(in: &cancellables)
        legacyManager.$connectedDate
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectedDate)
        legacyManager.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        syncFromLegacy()
    }

    func refreshStatus() async {
        do {
            try await legacyManager.load()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
        }
        syncFromLegacy()
    }

    func connect(profile: NetworkProfile) async throws {
        do {
            let options = try EasyTierOptionsBuilder.generate(from: profile)
            NetworkExtensionManager.saveOptions(options)
            try await legacyManager.connect()
            lastError = nil
            syncFromLegacy()
        } catch {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    func disconnect() async {
        await legacyManager.disconnect()
        syncFromLegacy()
    }

    func runningInfo() async throws -> NetworkStatus? {
        await withCheckedContinuation { continuation in
            legacyManager.fetchRunningInfo { info in
                continuation.resume(returning: info)
            }
        }
    }

    func networkSnapshot() async throws -> TunnelNetworkSettingsSnapshot? {
        await withCheckedContinuation { continuation in
            legacyManager.fetchLastNetworkSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func syncFromLegacy() {
        status = TunnelRuntimeStatus(legacyManager.status)
        connectedDate = legacyManager.connectedDate
        isLoading = legacyManager.isLoading
    }
}

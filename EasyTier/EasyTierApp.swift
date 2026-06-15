import EasyTierShared
import SwiftUI

@main
struct EasyTierApp: App {
    #if targetEnvironment(simulator)
        @StateObject var manager = MockNEManager()
    #else
        @StateObject var manager = NetworkExtensionManager()
    #endif

    init() {
        let values: [String: Any] = [
            "logLevel": LogLevel.info.rawValue,
            "statusRefreshInterval": 1.0,
            "logPreservedLines": 1000,
            "useRealDeviceNameAsDefault": true,
            "plainTextIPInput": false,
            "includeAllNetworks": false,
            "excludeLocalNetworks": true,
            "excludeCellularServices": true,
            "excludeAPNs": true,
            "excludeDeviceCommunication": true,
            "enforceRoutes": false,
        ]
        UserDefaults.standard.register(defaults: values)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
    }
}

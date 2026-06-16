import Foundation
#if os(iOS)
import UIKit
#else
import SystemConfiguration
#endif

import EasyTierShared
import TOMLKit

enum EasyTierOptionsBuilder {
    static func generate(from profile: NetworkProfile) throws -> EasyTierOptions {
        var options = EasyTierOptions()
        var config = profile.toConfig()
        if config.hostname == nil && UserDefaults.standard.bool(forKey: "useRealDeviceNameAsDefault") {
#if os(iOS)
            config.hostname = UIDevice.current.name
#else
            config.hostname = SCDynamicStoreCopyComputerName(nil, nil) as String?
#endif
        }

        let encoded = try TOMLEncoder().encode(config).string ?? ""
        options.config = encoded
        if let ipv4 = config.ipv4 {
            options.ipv4 = ipv4
        }
        if let ipv6 = config.ipv6 {
            options.ipv6 = ipv6
        }
        if let mtu = config.flags?.mtu {
            options.mtu = mtu
        } else {
            options.mtu = config.flags?.enableEncryption ?? true ? 1360 : 1380
        }
        if let routes = config.routes {
            options.routes = routes
        }
        if let logLevel = UserDefaults.standard.string(forKey: "logLevel"),
           let logLevel = LogLevel(rawValue: logLevel) {
            options.logLevel = logLevel
        }
        if profile.enableMagicDNS {
            options.magicDNS = true
        }
        if profile.enableOverrideDNS {
            options.dns = profile.overrideDNS.compactMap { $0.text.isEmpty ? nil : $0.text }
        }

        return options
    }
}

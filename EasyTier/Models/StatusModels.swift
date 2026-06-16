import Foundation
import SwiftUI

private struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element] = []

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                elements.append(value)
            } else {
                _ = try? container.decode(DiscardedValue.self)
            }
        }
    }
}

private struct DiscardedValue: Decodable {
    init(from decoder: Decoder) throws {}
}

private extension KeyedDecodingContainer {
    func decodeLossyArray<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element] {
        (try? decodeIfPresent(LossyArray<Element>.self, forKey: key)?.elements) ?? []
    }
}

struct NetworkStatus: Codable {
    enum NATType: Int, Codable {
        case unknown = 0
        case openInternet = 1
        case noPAT = 2
        case fullCone = 3
        case restricted = 4
        case portRestricted = 5
        case symmetric = 6
        case symUDPFirewall = 7
        case symmetricEasyInc = 8
        case symmetricEasyDec = 9

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let rawValue = try? container.decode(Int.self),
               let value = NATType(rawValue: rawValue) {
                self = value
                return
            }
            if let rawValue = try? container.decode(String.self) {
                switch rawValue
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "")
                    .replacingOccurrences(of: "-", with: "") {
                case "openinternet":
                    self = .openInternet
                case "nopat":
                    self = .noPAT
                case "fullcone":
                    self = .fullCone
                case "restricted":
                    self = .restricted
                case "portrestricted":
                    self = .portRestricted
                case "symmetric":
                    self = .symmetric
                case "symudpfirewall", "symmetricudpfirewall":
                    self = .symUDPFirewall
                case "symmetriceasyinc":
                    self = .symmetricEasyInc
                case "symmetriceasydec":
                    self = .symmetricEasyDec
                default:
                    self = .unknown
                }
                return
            }
            self = .unknown
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        var description: LocalizedStringKey {
            switch self {
            case .unknown:          return "unknown"
            case .openInternet:     return "open_internet"
            case .noPAT:            return "no_pat"
            case .fullCone:         return "full_cone"
            case .restricted:       return "restricted"
            case .portRestricted:   return "port_restricted"
            case .symmetric:        return "symmetric"
            case .symUDPFirewall:   return "symmetric_udp_firewall"
            case .symmetricEasyInc: return "symmetric_easy_inc"
            case .symmetricEasyDec: return "symmetric_easy_dec"
            }
        }
    }

    struct UUID: Codable, Hashable {
        var part1: UInt32
        var part2: UInt32
        var part3: UInt32
        var part4: UInt32
    }

    struct PeerFeatureFlag: Codable, Hashable {
        var isPublicServer: Bool
        var avoidRelayData: Bool
        var kcpInput: Bool
        var noRelayKcp: Bool
        var supportConnListSync: Bool
        var quicInput: Bool
        var noRelayQuic: Bool

        enum CodingKeys: String, CodingKey {
            case isPublicServer = "is_public_server"
            case avoidRelayData = "avoid_relay_data"
            case kcpInput = "kcp_input"
            case noRelayKcp = "no_relay_kcp"
            case supportConnListSync = "support_conn_list_sync"
            case quicInput = "quic_input"
            case noRelayQuic = "no_relay_quic"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isPublicServer = try container.decodeIfPresent(Bool.self, forKey: .isPublicServer) ?? false
            avoidRelayData = try container.decodeIfPresent(Bool.self, forKey: .avoidRelayData) ?? false
            kcpInput = try container.decodeIfPresent(Bool.self, forKey: .kcpInput) ?? false
            noRelayKcp = try container.decodeIfPresent(Bool.self, forKey: .noRelayKcp) ?? false
            supportConnListSync = try container.decodeIfPresent(Bool.self, forKey: .supportConnListSync) ?? false
            quicInput = try container.decodeIfPresent(Bool.self, forKey: .quicInput) ?? false
            noRelayQuic = try container.decodeIfPresent(Bool.self, forKey: .noRelayQuic) ?? false
        }
    }

    struct IPv4Addr: Codable, Hashable, CustomStringConvertible {
        var addr: UInt32

        init?(_ s: String) {
            let components = s.split(separator: ".").compactMap { UInt32($0) }
            guard components.count == 4 else { return nil }
            let addr =
                (components[0] << 24) | (components[1] << 16)
                | (components[2] << 8) | components[3]
            self.addr = addr
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(UInt32.self) {
                addr = value
                return
            }
            if let value = try? container.decode(String.self),
               let parsed = IPv4Addr(value) {
                addr = parsed.addr
                return
            }
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            addr = try keyed.decodeIfPresent(UInt32.self, forKey: .addr) ?? 0
        }

        enum CodingKeys: String, CodingKey {
            case addr
        }

        var description: String {
            let ip = addr
            return
                "\((ip >> 24) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
        }
    }

    struct IPv4CIDR: Codable, Hashable, CustomStringConvertible {
        var address: IPv4Addr
        var networkLength: Int

        init(address: IPv4Addr, networkLength: Int) {
            self.address = address
            self.networkLength = networkLength
        }

        var description: String {
            return "\(address.description)/\(networkLength)"
        }

        enum CodingKeys: String, CodingKey {
            case address
            case networkLength = "network_length"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                let parts = value.split(separator: "/", maxSplits: 1)
                if let address = IPv4Addr(String(parts.first ?? "")) {
                    self.address = address
                    networkLength = parts.count > 1 ? Int(parts[1]) ?? 32 : 32
                    return
                }
            }

            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            address = try keyed.decodeIfPresent(IPv4Addr.self, forKey: .address) ?? IPv4Addr("0.0.0.0")!
            networkLength = try keyed.decodeIfPresent(Int.self, forKey: .networkLength) ?? 32
        }
    }

    struct IPv6Addr: Codable, Hashable, CustomStringConvertible {
        var part1: UInt32
        var part2: UInt32
        var part3: UInt32
        var part4: UInt32
        
        init?(_ s: String) {
            var addr = in6_addr()
            guard inet_pton(AF_INET6, s, &addr) == 1 else {
                return nil
            }
            
            let data = withUnsafeBytes(of: addr) { Data($0) }
            
            self.part1 = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.part2 = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.part3 = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.part4 = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        }
        
        var description: String {
            var addr = in6_addr()
            let p1 = part1.bigEndian
            let p2 = part2.bigEndian
            let p3 = part3.bigEndian
            let p4 = part4.bigEndian
            
            withUnsafeMutableBytes(of: &addr) { ptr in
                ptr.storeBytes(of: p1, toByteOffset: 0, as: UInt32.self)
                ptr.storeBytes(of: p2, toByteOffset: 4, as: UInt32.self)
                ptr.storeBytes(of: p3, toByteOffset: 8, as: UInt32.self)
                ptr.storeBytes(of: p4, toByteOffset: 12, as: UInt32.self)
            }
            
            var buffer = [UInt8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            
            if inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            // fallback
            let parts = [part1, part2, part3, part4]
            let segments = parts.flatMap { part -> [UInt16] in
                [UInt16(part >> 16), UInt16(part & 0xFFFF)]
            }
            return segments.map { String(format: "%04x", $0) }.joined(separator: ":")
        }
    }

    struct IPv6CIDR: Codable, Hashable {
        var address: IPv6Addr
        var networkLength: Int

        enum CodingKeys: String, CodingKey {
            case address
            case networkLength = "network_length"
        }
        
        var description: String {
            return "\(address.description)/\(networkLength)"
        }
    }

    struct Url: Codable, Hashable {
        var url: String

        init(url: String) {
            self.url = url
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                url = value
                return
            }
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            url = (try? keyed.decode(String.self, forKey: CodingKeys.url))
                ?? (try? keyed.decode(String.self, forKey: CodingKeys.serialization))
                ?? ""
        }

        enum CodingKeys: String, CodingKey {
            case url
            case serialization
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(url, forKey: .url)
        }
    }

    struct MyNodeInfo: Codable {
        struct IPList: Codable {
            var publicIPv4: IPv4Addr?
            var interfaceIPv4s: [IPv4Addr]?
            var publicIPv6: IPv6Addr?
            var interfaceIPv6s: [IPv6Addr]?
            var listeners: [Url]?

            enum CodingKeys: String, CodingKey {
                case publicIPv4 = "public_ipv4"
                case interfaceIPv4s = "interface_ipv4s"
                case publicIPv6 = "public_ipv6"
                case interfaceIPv6s = "interface_ipv6s"
                case listeners
            }

            init(
                publicIPv4: IPv4Addr?,
                interfaceIPv4s: [IPv4Addr]?,
                publicIPv6: IPv6Addr?,
                interfaceIPv6s: [IPv6Addr]?,
                listeners: [Url]? = nil
            ) {
                self.publicIPv4 = publicIPv4
                self.interfaceIPv4s = interfaceIPv4s
                self.publicIPv6 = publicIPv6
                self.interfaceIPv6s = interfaceIPv6s
                self.listeners = listeners
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                publicIPv4 = try container.decodeIfPresent(IPv4Addr.self, forKey: .publicIPv4)
                interfaceIPv4s = container.decodeLossyArray(IPv4Addr.self, forKey: .interfaceIPv4s)
                publicIPv6 = try container.decodeIfPresent(IPv6Addr.self, forKey: .publicIPv6)
                interfaceIPv6s = container.decodeLossyArray(IPv6Addr.self, forKey: .interfaceIPv6s)
                let decodedListeners = container.decodeLossyArray(Url.self, forKey: .listeners)
                listeners = decodedListeners.isEmpty ? nil : decodedListeners
            }
        }
        var virtualIPv4: IPv4CIDR?
        var hostname: String
        var version: String
        var ips: IPList?
        var stunInfo: STUNInfo?
        var listeners: [Url]? = nil
        var vpnPortalCfg: String?
        var peerID: Int?

        enum CodingKeys: String, CodingKey {
            case virtualIPv4 = "virtual_ipv4"
            case hostname, version
            case ips
            case stunInfo = "stun_info"
            case listeners
            case vpnPortalCfg = "vpn_portal_cfg"
            case peerID = "peer_id"
        }

        init(
            virtualIPv4: IPv4CIDR?,
            hostname: String,
            version: String,
            ips: IPList?,
            stunInfo: STUNInfo?,
            listeners: [Url]? = nil,
            vpnPortalCfg: String?,
            peerID: Int?
        ) {
            self.virtualIPv4 = virtualIPv4
            self.hostname = hostname
            self.version = version
            self.ips = ips
            self.stunInfo = stunInfo
            self.listeners = listeners
            self.vpnPortalCfg = vpnPortalCfg
            self.peerID = peerID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            virtualIPv4 = try container.decodeIfPresent(IPv4CIDR.self, forKey: .virtualIPv4)
            hostname = try container.decodeIfPresent(String.self, forKey: .hostname) ?? ""
            version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
            ips = try container.decodeIfPresent(IPList.self, forKey: .ips)
            stunInfo = try container.decodeIfPresent(STUNInfo.self, forKey: .stunInfo)
            let decodedListeners = container.decodeLossyArray(Url.self, forKey: .listeners)
            listeners = decodedListeners.isEmpty ? nil : decodedListeners
            vpnPortalCfg = try container.decodeIfPresent(String.self, forKey: .vpnPortalCfg)
            peerID = try container.decodeIfPresent(Int.self, forKey: .peerID)
        }
    }

    struct STUNInfo: Codable, Hashable {
        var udpNATType: NATType
        var tcpNATType: NATType
        var lastUpdateTime: TimeInterval
        var publicIPs: [String] = []
        var minPort: Int? = nil
        var maxPort: Int? = nil

        enum CodingKeys: String, CodingKey {
            case udpNATType = "udp_nat_type"
            case tcpNATType = "tcp_nat_type"
            case lastUpdateTime = "last_update_time"
            case publicIPs = "public_ip"
            case minPort = "min_port"
            case maxPort = "max_port"
        }

        init(
            udpNATType: NATType,
            tcpNATType: NATType,
            lastUpdateTime: TimeInterval,
            publicIPs: [String] = [],
            minPort: Int? = nil,
            maxPort: Int? = nil
        ) {
            self.udpNATType = udpNATType
            self.tcpNATType = tcpNATType
            self.lastUpdateTime = lastUpdateTime
            self.publicIPs = publicIPs
            self.minPort = minPort
            self.maxPort = maxPort
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            udpNATType = try container.decodeIfPresent(NATType.self, forKey: .udpNATType) ?? .unknown
            tcpNATType = try container.decodeIfPresent(NATType.self, forKey: .tcpNATType) ?? .unknown
            if let value = try? container.decode(Double.self, forKey: .lastUpdateTime) {
                lastUpdateTime = value
            } else if let value = try? container.decode(Int.self, forKey: .lastUpdateTime) {
                lastUpdateTime = TimeInterval(value)
            } else if let value = try? container.decode(String.self, forKey: .lastUpdateTime),
                      let parsed = TimeInterval(value) {
                lastUpdateTime = parsed
            } else {
                lastUpdateTime = 0
            }
            publicIPs = try container.decodeIfPresent([String].self, forKey: .publicIPs) ?? []
            minPort = try container.decodeIfPresent(Int.self, forKey: .minPort)
            maxPort = try container.decodeIfPresent(Int.self, forKey: .maxPort)
        }
    }

    struct Route: Codable, Hashable, Identifiable {
        var id: Int { peerId }
        var peerId: Int
        var ipv4Addr: IPv4CIDR?
        var ipv6Addr: IPv6CIDR?
        var nextHopPeerId: Int
        var cost: Int
        var pathLatency: Int
        var proxyCIDRs: [String] = []
        var hostname: String
        var stunInfo: STUNInfo?
        var instId: String
        var version: String
        var nextHopPeerIdLatencyFirst: UInt?
        var costLatencyFirst: Int? = nil
        var pathLatencyLatencyFirst: Int? = nil
        var featureFlag: PeerFeatureFlag? = nil

        enum CodingKeys: String, CodingKey {
            case peerId = "peer_id"
            case ipv4Addr = "ipv4_addr"
            case ipv6Addr = "ipv6_addr"
            case nextHopPeerId = "next_hop_peer_id"
            case cost
            case pathLatency = "path_latency"
            case hostname, version
            case proxyCIDRs = "proxy_cidrs"
            case stunInfo = "stun_info"
            case instId = "inst_id"
            case nextHopPeerIdLatencyFirst = "next_hop_peer_id_latency_first"
            case costLatencyFirst = "cost_latency_first"
            case pathLatencyLatencyFirst = "path_latency_latency_first"
            case featureFlag = "feature_flag"
        }

        init(
            peerId: Int,
            ipv4Addr: IPv4CIDR? = nil,
            ipv6Addr: IPv6CIDR? = nil,
            nextHopPeerId: Int,
            cost: Int,
            pathLatency: Int,
            proxyCIDRs: [String] = [],
            hostname: String,
            stunInfo: STUNInfo? = nil,
            instId: String,
            version: String,
            nextHopPeerIdLatencyFirst: UInt? = nil,
            costLatencyFirst: Int? = nil,
            pathLatencyLatencyFirst: Int? = nil,
            featureFlag: PeerFeatureFlag? = nil
        ) {
            self.peerId = peerId
            self.ipv4Addr = ipv4Addr
            self.ipv6Addr = ipv6Addr
            self.nextHopPeerId = nextHopPeerId
            self.cost = cost
            self.pathLatency = pathLatency
            self.proxyCIDRs = proxyCIDRs
            self.hostname = hostname
            self.stunInfo = stunInfo
            self.instId = instId
            self.version = version
            self.nextHopPeerIdLatencyFirst = nextHopPeerIdLatencyFirst
            self.costLatencyFirst = costLatencyFirst
            self.pathLatencyLatencyFirst = pathLatencyLatencyFirst
            self.featureFlag = featureFlag
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            peerId = try container.decodeIfPresent(Int.self, forKey: .peerId) ?? 0
            ipv4Addr = try container.decodeIfPresent(IPv4CIDR.self, forKey: .ipv4Addr)
            ipv6Addr = try container.decodeIfPresent(IPv6CIDR.self, forKey: .ipv6Addr)
            nextHopPeerId = try container.decodeIfPresent(Int.self, forKey: .nextHopPeerId) ?? 0
            cost = try container.decodeIfPresent(Int.self, forKey: .cost) ?? 0
            pathLatency = try container.decodeIfPresent(Int.self, forKey: .pathLatency) ?? 0
            proxyCIDRs = try container.decodeIfPresent([String].self, forKey: .proxyCIDRs) ?? []
            hostname = try container.decodeIfPresent(String.self, forKey: .hostname) ?? ""
            stunInfo = try container.decodeIfPresent(STUNInfo.self, forKey: .stunInfo)
            instId = try container.decodeIfPresent(String.self, forKey: .instId) ?? ""
            version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
            nextHopPeerIdLatencyFirst = try container.decodeIfPresent(UInt.self, forKey: .nextHopPeerIdLatencyFirst)
            costLatencyFirst = try container.decodeIfPresent(Int.self, forKey: .costLatencyFirst)
            pathLatencyLatencyFirst = try container.decodeIfPresent(Int.self, forKey: .pathLatencyLatencyFirst)
            featureFlag = try container.decodeIfPresent(PeerFeatureFlag.self, forKey: .featureFlag)
        }
    }

    struct PeerInfo: Codable, Hashable, Identifiable {
        var id: Int { peerId }
        var peerId: Int
        var conns: [PeerConnInfo]
        var defaultConnId: UUID? = nil
        var directlyConnectedConns: [UUID] = []

        enum CodingKeys: String, CodingKey {
            case peerId = "peer_id"
            case conns
            case defaultConnId = "default_conn_id"
            case directlyConnectedConns = "directly_connected_conns"
        }

        init(peerId: Int, conns: [PeerConnInfo], defaultConnId: UUID? = nil, directlyConnectedConns: [UUID] = []) {
            self.peerId = peerId
            self.conns = conns
            self.defaultConnId = defaultConnId
            self.directlyConnectedConns = directlyConnectedConns
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            peerId = try container.decodeIfPresent(Int.self, forKey: .peerId) ?? 0
            conns = container.decodeLossyArray(PeerConnInfo.self, forKey: .conns)
            defaultConnId = try? container.decodeIfPresent(UUID.self, forKey: .defaultConnId)
            directlyConnectedConns = container.decodeLossyArray(UUID.self, forKey: .directlyConnectedConns)
        }
    }

    struct PeerConnInfo: Codable, Hashable {
        var connId: String
        var myPeerId: Int
        var isClient: Bool
        var peerId: Int
        var features: [String]
        var tunnel: TunnelInfo?
        var stats: PeerConnStats?
        var lossRate: Double
        var networkName: String? = nil
        var isClosed: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case connId = "conn_id"
            case myPeerId = "my_peer_id"
            case isClient = "is_client"
            case peerId = "peer_id"
            case features, tunnel, stats
            case lossRate = "loss_rate"
            case networkName = "network_name"
            case isClosed = "is_closed"
        }

        init(
            connId: String,
            myPeerId: Int,
            isClient: Bool,
            peerId: Int,
            features: [String],
            tunnel: TunnelInfo?,
            stats: PeerConnStats?,
            lossRate: Double,
            networkName: String? = nil,
            isClosed: Bool? = nil
        ) {
            self.connId = connId
            self.myPeerId = myPeerId
            self.isClient = isClient
            self.peerId = peerId
            self.features = features
            self.tunnel = tunnel
            self.stats = stats
            self.lossRate = lossRate
            self.networkName = networkName
            self.isClosed = isClosed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            connId = try container.decodeIfPresent(String.self, forKey: .connId) ?? ""
            myPeerId = try container.decodeIfPresent(Int.self, forKey: .myPeerId) ?? 0
            isClient = try container.decodeIfPresent(Bool.self, forKey: .isClient) ?? false
            peerId = try container.decodeIfPresent(Int.self, forKey: .peerId) ?? 0
            features = try container.decodeIfPresent([String].self, forKey: .features) ?? []
            tunnel = try? container.decodeIfPresent(TunnelInfo.self, forKey: .tunnel)
            stats = try? container.decodeIfPresent(PeerConnStats.self, forKey: .stats)
            lossRate = try container.decodeIfPresent(Double.self, forKey: .lossRate) ?? 0
            networkName = try container.decodeIfPresent(String.self, forKey: .networkName)
            isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed)
        }
    }

    struct PeerRoutePair: Codable, Hashable, Identifiable {
        var id: Int { route.id }
        var route: Route
        var peer: PeerInfo?
    }

    struct TunnelInfo: Codable, Hashable {
        var tunnelType: String
        var localAddr: Url
        var remoteAddr: Url

        init(tunnelType: String, localAddr: Url, remoteAddr: Url) {
            self.tunnelType = tunnelType
            self.localAddr = localAddr
            self.remoteAddr = remoteAddr
        }

        enum CodingKeys: String, CodingKey {
            case tunnelType = "tunnel_type"
            case localAddr = "local_addr"
            case remoteAddr = "remote_addr"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tunnelType = try container.decodeIfPresent(String.self, forKey: .tunnelType) ?? ""
            localAddr = (try? container.decodeIfPresent(Url.self, forKey: .localAddr)) ?? Url(url: "")
            remoteAddr = (try? container.decodeIfPresent(Url.self, forKey: .remoteAddr)) ?? Url(url: "")
        }
    }

    struct PeerConnStats: Codable, Hashable {
        var rxBytes: Int
        var txBytes: Int
        var rxPackets: Int
        var txPackets: Int
        var latencyUs: Int

        enum CodingKeys: String, CodingKey {
            case rxBytes = "rx_bytes"
            case txBytes = "tx_bytes"
            case rxPackets = "rx_packets"
            case txPackets = "tx_packets"
            case latencyUs = "latency_us"
        }

        init(rxBytes: Int, txBytes: Int, rxPackets: Int, txPackets: Int, latencyUs: Int) {
            self.rxBytes = rxBytes
            self.txBytes = txBytes
            self.rxPackets = rxPackets
            self.txPackets = txPackets
            self.latencyUs = latencyUs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rxBytes = try container.decodeIfPresent(Int.self, forKey: .rxBytes) ?? 0
            txBytes = try container.decodeIfPresent(Int.self, forKey: .txBytes) ?? 0
            rxPackets = try container.decodeIfPresent(Int.self, forKey: .rxPackets) ?? 0
            txPackets = try container.decodeIfPresent(Int.self, forKey: .txPackets) ?? 0
            latencyUs = try container.decodeIfPresent(Int.self, forKey: .latencyUs) ?? 0
        }
    }

    var devName: String
    var myNodeInfo: MyNodeInfo?
    var events: [String]
    var routes: [Route]
    var peers: [PeerInfo]
    var peerRoutePairs: [PeerRoutePair]
    var running: Bool
    var errorMsg: String?

    enum CodingKeys: String, CodingKey {
        case devName = "dev_name"
        case myNodeInfo = "my_node_info"
        case events, routes, peers, running
        case peerRoutePairs = "peer_route_pairs"
        case errorMsg = "error_msg"
    }

    init(
        devName: String,
        myNodeInfo: MyNodeInfo?,
        events: [String],
        routes: [Route],
        peers: [PeerInfo],
        peerRoutePairs: [PeerRoutePair],
        running: Bool,
        errorMsg: String?
    ) {
        self.devName = devName
        self.myNodeInfo = myNodeInfo
        self.events = events
        self.routes = routes
        self.peers = peers
        self.peerRoutePairs = peerRoutePairs
        self.running = running
        self.errorMsg = errorMsg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        devName = try container.decodeIfPresent(String.self, forKey: .devName) ?? ""
        myNodeInfo = try container.decodeIfPresent(MyNodeInfo.self, forKey: .myNodeInfo)
        events = try container.decodeIfPresent([String].self, forKey: .events) ?? []
        routes = container.decodeLossyArray(Route.self, forKey: .routes)
        peers = container.decodeLossyArray(PeerInfo.self, forKey: .peers)
        peerRoutePairs = container.decodeLossyArray(PeerRoutePair.self, forKey: .peerRoutePairs)
        running = try container.decodeIfPresent(Bool.self, forKey: .running) ?? false
        errorMsg = try container.decodeIfPresent(String.self, forKey: .errorMsg)
    }

    func sum(of keyPath: KeyPath<PeerConnStats, Int>) -> Int {
        peers
            .flatMap { $0.conns }
            .compactMap { $0.stats }
            .map { $0[keyPath: keyPath] }
            .reduce(0, +)
    }
}

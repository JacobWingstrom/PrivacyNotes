import Foundation

/// Small IPv4 toolkit for subnet math, all done on-device.
struct IPv4: Hashable, Comparable, CustomStringConvertible {
    let value: UInt32

    init(_ value: UInt32) { self.value = value }

    init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ".")
        guard parts.count == 4 else { return nil }
        var v: UInt32 = 0
        for p in parts {
            guard let n = UInt32(p), n <= 255 else { return nil }
            v = (v << 8) | n
        }
        value = v
    }

    var description: String {
        "\((value >> 24) & 255).\((value >> 16) & 255).\((value >> 8) & 255).\(value & 255)"
    }

    static func < (a: IPv4, b: IPv4) -> Bool { a.value < b.value }

    var isPrivate: Bool {
        let a = value >> 24, b = (value >> 16) & 255
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
    }
}

struct CIDR: Hashable {
    let network: IPv4
    let prefix: Int

    init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard let ip = IPv4(String(parts.first ?? "")) else { return nil }
        let p = parts.count > 1 ? Int(parts[1]) ?? -1 : 32
        guard (0...32).contains(p) else { return nil }
        prefix = p
        network = IPv4(ip.value & CIDR.mask(p))
    }

    static func mask(_ prefix: Int) -> UInt32 { prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix) }

    var mask: IPv4 { IPv4(CIDR.mask(prefix)) }
    var wildcard: IPv4 { IPv4(~CIDR.mask(prefix)) }
    var broadcast: IPv4 { IPv4(network.value | ~CIDR.mask(prefix)) }
    var size: UInt64 { UInt64(1) << UInt64(32 - prefix) }
    var usableCount: UInt64 { prefix >= 31 ? size : max(size, 2) - 2 }
    var firstHost: IPv4 { prefix >= 31 ? network : IPv4(network.value + 1) }
    var lastHost: IPv4 { prefix >= 31 ? broadcast : IPv4(broadcast.value - 1) }

    func contains(_ ip: IPv4) -> Bool { ip.value & CIDR.mask(prefix) == network.value }

    /// All usable host addresses (only for /20 or smaller, to keep it quick).
    var hosts: [IPv4] {
        guard prefix >= 20 else { return [] }
        return (firstHost.value...lastHost.value).map(IPv4.init)
    }

    var description: String { "\(network)/\(prefix)" }

    func overlaps(_ other: CIDR) -> Bool { contains(other.network) || other.contains(network) }
}

enum NetworkMath {
    /// Device IPs that are used more than once.
    static func duplicates(_ devices: [LabDevice]) -> [String: [LabDevice]] {
        Dictionary(grouping: devices.filter { IPv4($0.ip) != nil }) { IPv4($0.ip)!.description }
            .filter { $0.value.count > 1 }
    }

    static func nextFree(in subnet: LabSubnet, devices: [LabDevice]) -> IPv4? {
        guard let cidr = CIDR(subnet.cidr) else { return nil }
        let used = Set(devices.compactMap { IPv4($0.ip) }) .union([subnet.gateway, subnet.dns].compactMap { IPv4($0) })
        let dhcp: ClosedRange<UInt32>? = {
            guard let a = IPv4(subnet.dhcpStart), let b = IPv4(subnet.dhcpEnd), a <= b else { return nil }
            return a.value...b.value
        }()
        var v = cidr.firstHost.value
        while v <= cidr.lastHost.value {
            if !used.contains(IPv4(v)) && !(dhcp?.contains(v) ?? false) { return IPv4(v) }
            if v == UInt32.max { break }
            v += 1
        }
        return nil
    }
}

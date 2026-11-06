import Foundation

/// Reads the parts of a compose file that matter for documentation. It is deliberately
/// forgiving: unknown keys are ignored and nothing is ever executed or fetched.
enum ComposeParser {
    struct Service {
        var name: String
        var image = ""
        var containerName = ""
        var ports: [ServicePort] = []
        var volumes: [String] = []
        var networks: [String] = []
        var envKeys: [String] = []
        var restart = ""
        var dependsOn: [String] = []
    }

    static func parse(_ yaml: String) -> [Service] {
        let lines = yaml.replacingOccurrences(of: "\t", with: "  ").components(separatedBy: "\n")
        func indent(_ l: String) -> Int { l.prefix { $0 == " " }.count }
        func clean(_ s: String) -> String {
            var t = s
            if let hash = t.range(of: " #") { t = String(t[..<hash.lowerBound]) }
            t = t.trimmingCharacters(in: .whitespaces)
            if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")), t.count >= 2 { t = String(t.dropFirst().dropLast()) }
            return t
        }
        func flowList(_ s: String) -> [String]? {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("["), t.hasSuffix("]") else { return nil }
            return t.dropFirst().dropLast().split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty }
        }

        guard let start = lines.firstIndex(where: { $0.hasPrefix("services:") }) else { return [] }
        var services: [Service] = []
        var serviceIndent: Int?
        var keyIndent: Int?
        var current: Service?
        var currentKey = ""
        var longPort: [String: String] = [:]

        func flushPort() {
            guard !longPort.isEmpty else { return }
            let published = Int(longPort["published"]?.split(separator: "-").first ?? "") ?? Int(longPort["target"] ?? "")
            if let p = published {
                current?.ports.append(ServicePort(port: p, proto: (longPort["protocol"] ?? "tcp").uppercased(), purpose: CommonPorts.name(p) ?? ""))
            }
            longPort = [:]
        }
        func flushService() {
            flushPort()
            if let c = current { services.append(c) }
            current = nil
        }

        for raw in lines[(start + 1)...] {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let ind = indent(raw)
            if ind == 0 { break }   // next top-level key (networks:, volumes:, …)
            if serviceIndent == nil { serviceIndent = ind }
            if ind == serviceIndent, trimmed.hasSuffix(":") {
                flushService()
                current = Service(name: String(trimmed.dropLast()))
                keyIndent = nil
                continue
            }
            guard current != nil else { continue }
            if keyIndent == nil, ind > (serviceIndent ?? 0) { keyIndent = ind }
            if ind == keyIndent, !trimmed.hasPrefix("-"), let colon = trimmed.firstIndex(of: ":") {
                flushPort()
                currentKey = String(trimmed[..<colon])
                let value = String(trimmed[trimmed.index(after: colon)...])
                let v = clean(value)
                switch currentKey {
                case "image": current?.image = v
                case "container_name": current?.containerName = v
                case "restart": current?.restart = v
                case "ports": for p in flowList(value) ?? [] { if let sp = shortPort(p) { current?.ports.append(sp) } }
                case "volumes": current?.volumes += flowList(value) ?? []
                case "networks": current?.networks += flowList(value) ?? []
                case "depends_on": current?.dependsOn += flowList(value) ?? []
                case "network_mode": if !v.isEmpty { current?.networks.append(v) }
                default: break
                }
                continue
            }
            // Children of the current key.
            if trimmed.hasPrefix("-") {
                flushPort()
                let item = clean(String(trimmed.dropFirst()))
                switch currentKey {
                case "ports":
                    if item.contains(":") && (item.hasPrefix("target") || item.hasPrefix("published") || item.hasPrefix("protocol")) {
                        let kv = item.split(separator: ":", maxSplits: 1).map { clean(String($0)) }
                        if kv.count == 2 { longPort[kv[0]] = kv[1] }
                    } else if let sp = shortPort(item) { current?.ports.append(sp) }
                case "volumes": current?.volumes.append(item)
                case "networks": current?.networks.append(item)
                case "depends_on": current?.dependsOn.append(item)
                case "environment":
                    let key = item.split(separator: "=", maxSplits: 1).first.map(String.init) ?? item
                    if !key.isEmpty { current?.envKeys.append(key) }
                default: break
                }
            } else if let colon = trimmed.firstIndex(of: ":") {
                let k = String(trimmed[..<colon]), v = clean(String(trimmed[trimmed.index(after: colon)...]))
                switch currentKey {
                case "ports": longPort[k] = v
                case "environment": current?.envKeys.append(k)
                case "networks": current?.networks.append(k)
                case "depends_on": current?.dependsOn.append(k)
                default: break
                }
            }
        }
        flushService()
        return services
    }

    /// "8096:8096", "127.0.0.1:53:53/udp", "8000-8010:8000-8010", "443"
    static func shortPort(_ s: String) -> ServicePort? {
        var spec = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        var proto = "TCP"
        if let slash = spec.lastIndex(of: "/") {
            proto = spec[spec.index(after: slash)...].uppercased()
            spec = String(spec[..<slash])
        }
        let parts = spec.split(separator: ":").map(String.init)
        let host = parts.count >= 2 ? parts[parts.count - 2] : parts.last ?? ""
        guard let p = Int(host.split(separator: "-").first ?? ""), (1...65535).contains(p) else { return nil }
        return ServicePort(port: p, proto: proto, purpose: CommonPorts.name(p) ?? "")
    }

    /// Replaces values of secret-looking environment variables with ***.
    static func redactSecrets(_ yaml: String) -> String {
        let pattern = "(?im)^(\\s*-?\\s*[A-Z0-9_]*(PASSWORD|PASS|SECRET|TOKEN|API_?KEY|PRIVATE)[A-Z0-9_]*\\s*[:=]\\s*)(\\S.*)$"
        return yaml.replacingOccurrences(of: pattern, with: "$1***", options: .regularExpression)
    }

    /// Splits text holding several files marked with "### /path/to/compose.yaml" lines.
    static func splitFiles(_ text: String) -> [(path: String, yaml: String)] {
        var out: [(String, String)] = []
        var path = ""
        var buf: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("### ") {
                if !buf.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((path, buf.joined(separator: "\n"))) }
                path = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                buf = []
            } else {
                buf.append(line)
            }
        }
        if !buf.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((path, buf.joined(separator: "\n"))) }
        return out
    }

    /// A readable stack name from a path like /opt/stacks/media/compose.yaml → "media".
    static func stackName(fromPath path: String) -> String {
        let comps = path.split(separator: "/").map(String.init)
        guard comps.count >= 2 else { return "Stack" }
        return comps[comps.count - 2]
    }
}

/// Output of: docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
enum DockerPSParser {
    struct Row { var name: String; var image: String; var ports: [ServicePort] }

    static func parse(_ text: String) -> [Row] {
        text.components(separatedBy: "\n").compactMap { line in
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 2, !cols[0].isEmpty, cols[0] != "NAMES" else { return nil }
            var ports: [ServicePort] = []
            if cols.count >= 3 {
                for part in cols[2].components(separatedBy: ", ") {
                    // 0.0.0.0:8096->8096/tcp
                    guard let arrow = part.range(of: "->") else { continue }
                    let left = String(part[..<arrow.lowerBound])
                    let right = String(part[arrow.upperBound...])
                    let host = left.split(separator: ":").last.map(String.init) ?? ""
                    let proto = right.split(separator: "/").last.map { $0.uppercased() } ?? "TCP"
                    if let p = Int(host.split(separator: "-").first ?? ""), !ports.contains(where: { $0.port == p && $0.proto == proto }) {
                        ports.append(ServicePort(port: p, proto: proto, purpose: CommonPorts.name(p) ?? ""))
                    }
                }
            }
            return Row(name: cols[0].trimmingCharacters(in: .whitespaces), image: cols[1].trimmingCharacters(in: .whitespaces), ports: ports)
        }
    }
}

/// Proxmox command output → guests and nodes.
enum ProxmoxParser {
    struct Guest {
        var node: String
        var vmid: Int
        var name: String
        var isLXC: Bool
        var cores: Int
        var memoryMB: Int
        var diskGB: Double
        var running: Bool
        var template: Bool
    }

    /// pvesh get /cluster/resources --type vm --output-format json
    static func clusterResources(_ text: String) -> [Guest]? {
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return arr.compactMap { o in
            guard let type = o["type"] as? String, type == "qemu" || type == "lxc",
                  let vmid = (o["vmid"] as? Int) ?? Int("\(o["vmid"] ?? "")") else { return nil }
            func num(_ k: String) -> Double { (o[k] as? Double) ?? Double("\(o[k] ?? 0)") ?? 0 }
            return Guest(node: o["node"] as? String ?? "", vmid: vmid, name: o["name"] as? String ?? "\(type)-\(vmid)",
                         isLXC: type == "lxc", cores: Int(num("maxcpu")), memoryMB: Int(num("maxmem") / 1_048_576),
                         diskGB: (num("maxdisk") / 1_073_741_824 * 10).rounded() / 10,
                         running: (o["status"] as? String) == "running", template: num("template") == 1)
        }
    }

    struct Config {
        var name = ""
        var cores = 0
        var memoryMB = 0
        var diskGB = 0.0
        var storage = ""
        var bridge = ""
        var vlanTag = ""
        var mac = ""
        var ip = ""
        var ostype = ""
        var onBoot = false
        var isLXC = false
        var description = ""
    }

    /// qm config <vmid>  or  pct config <vmid>
    static func config(_ text: String) -> Config {
        var c = Config()
        for line in text.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "name": c.name = value
            case "hostname": c.name = value; c.isLXC = true
            case "cores": c.cores = Int(value) ?? 0
            case "memory": c.memoryMB = Int(value) ?? 0
            case "ostype": c.ostype = value
            case "onboot": c.onBoot = value == "1"
            case "description": c.description = value.removingPercentEncoding ?? value
            case "rootfs", "scsi0", "virtio0", "sata0", "ide0":
                if c.diskGB == 0 {
                    c.isLXC = c.isLXC || key == "rootfs"
                    c.storage = String(value.split(separator: ":").first ?? "")
                    if let size = value.components(separatedBy: ",").first(where: { $0.hasPrefix("size=") })?.dropFirst(5) {
                        let s = String(size)
                        let n = Double(s.dropLast()) ?? 0
                        c.diskGB = s.hasSuffix("T") ? n * 1024 : (s.hasSuffix("M") ? n / 1024 : n)
                    }
                }
            case "net0":
                for part in value.components(separatedBy: ",") {
                    let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                    guard kv.count == 2 else { continue }
                    switch kv[0] {
                    case "bridge": c.bridge = kv[1]
                    case "tag": c.vlanTag = kv[1]
                    case "hwaddr": c.mac = kv[1]
                    case "ip": c.ip = kv[1] == "dhcp" ? "" : String(kv[1].split(separator: "/").first ?? "")
                    case "virtio", "e1000", "vmxnet3", "rtl8139": c.mac = kv[1]
                    default: break
                    }
                }
            default: break
            }
        }
        return c
    }
}

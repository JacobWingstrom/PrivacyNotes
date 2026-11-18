import Foundation

/// Downloads the data for one widget. Each source talks only to the address you configured
/// (or, for weather, markets, news and releases, to the public service named in the gallery).
enum DashboardSources {
    static func fetch(_ w: HomeWidget, homelabURLs: [(String, String)]) async throws -> WidgetPayload {
        switch w.kind {
        case .server: return .server(try await server(w))
        case .containers: return .containers(try await containers(w))
        case .monitor: return .monitor(await monitor(w, homelab: homelabURLs))
        case .weather: return .weather(try await weather(w))
        case .markets: return .markets(try await markets(w.items.isEmpty ? ["AAPL"] : w.items))
        case .news: return .news(try await news(w))
        case .releases: return .releases(try await releases(w))
        case .dns: return .dns(try await dns(w))
        case .customAPI:
            let (fields, raw) = try await custom(w)
            return .custom(fields, raw: raw)
        default: throw DashboardError.setup("Nothing to load.")
        }
    }

    // MARK: Server stats

    static func server(_ w: HomeWidget) async throws -> ServerSnapshot {
        switch w.source {
        case "hush": return try await hushServer(w)
        case "netdata": return try await netdata(w)
        case "proxmox": return try await proxmoxNode(w)
        default: return try await glances(w)
        }
    }

    private static func hushServer(_ w: HomeWidget) async throws -> ServerSnapshot {
        let token = w.secret.isEmpty ? (SyncSettings.token ?? "") : w.secret
        let base = w.endpoint.isEmpty ? SyncSettings.serverURL : w.endpoint
        let j = try await DashboardNet.json(try DashboardNet.url(base, "/v1/system"), headers: ["Authorization": "Bearer \(token)"], selfSigned: w.allowSelfSigned)
        guard let d = j as? [String: Any] else { throw DashboardError.parse("hush-server") }
        var s = ServerSnapshot()
        s.hostname = JSONPath.string(d["hostname"])
        s.os = [JSONPath.string(d["os"]), d["kernel"] as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        s.uptime = JSONPath.double(d["uptime"]) ?? 0
        s.cpu = JSONPath.double(d["cpuPercent"]) ?? 0
        s.perCore = (d["perCore"] as? [Any])?.compactMap(JSONPath.double) ?? []
        s.cores = Int(JSONPath.double(d["cores"]) ?? 0)
        s.load = (d["load"] as? [Any])?.compactMap(JSONPath.double) ?? []
        s.memTotal = JSONPath.double(d["memTotal"]) ?? 0
        s.memUsed = JSONPath.double(d["memUsed"]) ?? 0
        s.swapTotal = JSONPath.double(d["swapTotal"]) ?? 0
        s.swapUsed = JSONPath.double(d["swapUsed"]) ?? 0
        s.disks = ((d["disks"] as? [[String: Any]]) ?? []).map {
            .init(name: JSONPath.string($0["mount"]), total: JSONPath.double($0["total"]) ?? 0, used: JSONPath.double($0["used"]) ?? 0)
        }
        s.temps = ((d["temps"] as? [[String: Any]]) ?? []).map { .init(name: JSONPath.string($0["name"]), celsius: JSONPath.double($0["celsius"]) ?? 0) }
        s.netRxTotal = JSONPath.double(d["netRx"])
        s.netTxTotal = JSONPath.double(d["netTx"])
        return s
    }

    /// Glances REST API (v4, falling back to v3).
    private static func glances(_ w: HomeWidget) async throws -> ServerSnapshot {
        var headers: [String: String] = [:]
        if !w.username.isEmpty { headers["Authorization"] = "Basic " + Data("\(w.username):\(w.secret)".utf8).base64EncodedString() }
        var version = "4"
        let probe = try? await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api/4/cpu"), headers: headers, selfSigned: w.allowSelfSigned)
        if probe == nil { version = "3" }
        func get(_ plugin: String) async -> Any? {
            guard let u = try? DashboardNet.url(w.endpoint, "/api/\(version)/\(plugin)") else { return nil }
            return try? await DashboardNet.json(u, headers: headers, selfSigned: w.allowSelfSigned)
        }
        async let cpuJ = get("cpu")
        async let perJ = get("percpu")
        async let memJ = get("mem")
        async let swapJ = get("memswap")
        async let loadJ = get("load")
        async let fsJ = get("fs")
        async let upJ = get("uptime")
        async let sensJ = get("sensors")
        async let netJ = get("network")
        async let sysJ = get("system")
        let (cpu, per, mem, swap, load, fs, up, sens, net, sys) = await (cpuJ, perJ, memJ, swapJ, loadJ, fsJ, upJ, sensJ, netJ, sysJ)
        guard let cpuD = cpu as? [String: Any] else { throw DashboardError.setup("Couldn't reach Glances at \(w.endpoint). Start it with `glances -w` (port 61208).") }
        var s = ServerSnapshot()
        s.cpu = JSONPath.double(cpuD["total"]) ?? 0
        s.cores = Int(JSONPath.double(cpuD["cpucore"]) ?? 0)
        s.perCore = ((per as? [[String: Any]]) ?? []).compactMap { JSONPath.double($0["total"]) }
        if s.cores == 0 { s.cores = s.perCore.count }
        if let m = mem as? [String: Any] { s.memTotal = JSONPath.double(m["total"]) ?? 0; s.memUsed = JSONPath.double(m["used"]) ?? 0 }
        if let m = swap as? [String: Any] { s.swapTotal = JSONPath.double(m["total"]) ?? 0; s.swapUsed = JSONPath.double(m["used"]) ?? 0 }
        if let l = load as? [String: Any] { s.load = ["min1", "min5", "min15"].compactMap { JSONPath.double(l[$0]) } }
        s.disks = ((fs as? [[String: Any]]) ?? []).map {
            .init(name: JSONPath.string($0["mnt_point"]), total: JSONPath.double($0["size"]) ?? 0, used: JSONPath.double($0["used"]) ?? 0)
        }.filter { $0.total > 0 && !$0.name.hasPrefix("/boot") && !$0.name.contains("/snap/") }
        if let u = up as? String { s.uptime = parseGlancesUptime(u) } else if let n = JSONPath.double(up) { s.uptime = n }
        s.temps = ((sens as? [[String: Any]]) ?? []).filter { ($0["type"] as? String ?? "").contains("temperature") }
            .compactMap { d in JSONPath.double(d["value"]).map { ServerSnapshot.Temp(name: JSONPath.string(d["label"]), celsius: $0) } }
        let nics = ((net as? [[String: Any]]) ?? []).filter {
            let n = ($0["interface_name"] as? String ?? "")
            return n != "lo" && !n.hasPrefix("veth") && !n.hasPrefix("docker") && !n.hasPrefix("br-")
        }
        let rx = nics.compactMap { JSONPath.double($0["bytes_recv_rate_per_sec"] ?? $0["rx"]) }
        let tx = nics.compactMap { JSONPath.double($0["bytes_sent_rate_per_sec"] ?? $0["tx"]) }
        if !rx.isEmpty { s.netRx = rx.reduce(0, +) }
        if !tx.isEmpty { s.netTx = tx.reduce(0, +) }
        if let d = sys as? [String: Any] {
            s.hostname = JSONPath.string(d["hostname"])
            s.os = [d["linux_distro"] as? String, d["os_name"] as? String].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        }
        return s
    }

    /// "3 days, 4:05:06" → seconds
    static func parseGlancesUptime(_ s: String) -> TimeInterval {
        var total: TimeInterval = 0
        var rest = s
        if let r = s.range(of: "(\\d+) days?, ", options: .regularExpression) {
            total += (Double(s[r].split(separator: " ").first ?? "") ?? 0) * 86400
            rest = String(s[r.upperBound...])
        }
        let parts = rest.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 { total += parts[0] * 3600 + parts[1] * 60 + parts[2] }
        return total
    }

    /// Netdata's v1 data API.
    private static func netdata(_ w: HomeWidget) async throws -> ServerSnapshot {
        func chart(_ name: String) async -> (labels: [String], values: [Double])? {
            guard let u = try? DashboardNet.url(w.endpoint, "/api/v1/data?chart=\(name)&after=-1&points=1&format=json"),
                  let j = try? await DashboardNet.json(u, selfSigned: w.allowSelfSigned) as? [String: Any],
                  let labels = j["labels"] as? [String], let rows = j["data"] as? [[Any]], let row = rows.first else { return nil }
            return (labels, row.compactMap(JSONPath.double))
        }
        func dim(_ c: (labels: [String], values: [Double])?, _ name: String) -> Double? {
            guard let c, let i = c.labels.firstIndex(of: name), i < c.values.count else { return nil }
            return c.values[i]
        }
        let info = try await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api/v1/info"), selfSigned: w.allowSelfSigned) as? [String: Any]
        async let cpuC = chart("system.cpu")
        async let ramC = chart("system.ram")
        async let loadC = chart("system.load")
        async let upC = chart("system.uptime")
        async let netC = chart("system.net")
        async let swapC = chart("mem.swap")
        async let diskC = chart("disk_space._")
        let (cpu, ram, load, up, net, swap, disk) = await (cpuC, ramC, loadC, upC, netC, swapC, diskC)
        var s = ServerSnapshot()
        s.hostname = JSONPath.string(JSONPath.value(info ?? [:], "mirrored_hosts.0"))
        s.os = JSONPath.string(info?["os_name"]) + " " + JSONPath.string(info?["os_version"])
        s.cores = Int(JSONPath.double(info?["cores_total"]) ?? 0)
        if let cpu { s.cpu = zip(cpu.labels, cpu.values).filter { $0.0 != "time" && $0.0 != "idle" }.map(\.1).reduce(0, +) }
        let mib = 1024.0 * 1024.0
        if ram != nil {
            let used = dim(ram, "used") ?? 0
            let total = ["used", "free", "cached", "buffers"].compactMap { dim(ram, $0) }.reduce(0, +)
            s.memUsed = used * mib; s.memTotal = total * mib
        }
        if swap != nil { let u = dim(swap, "used") ?? 0; s.swapUsed = u * mib; s.swapTotal = (u + (dim(swap, "free") ?? 0)) * mib }
        s.load = ["load1", "load5", "load15"].compactMap { dim(load, $0) }
        s.uptime = dim(up, "uptime") ?? 0
        // kilobits/s; "sent" is negative in Netdata
        if let r = dim(net, "received") { s.netRx = abs(r) * 125 }
        if let t = dim(net, "sent") { s.netTx = abs(t) * 125 }
        if disk != nil {
            let gib = 1024.0 * mib
            let used = dim(disk, "used") ?? 0, avail = dim(disk, "avail") ?? 0, reserved = dim(disk, "reserved for root") ?? 0
            s.disks = [.init(name: "/", total: (used + avail + reserved) * gib, used: used * gib)]
        }
        return s
    }

    private static func proxmoxHeaders(_ w: HomeWidget) throws -> [String: String] {
        guard !w.username.isEmpty, !w.secret.isEmpty else {
            throw DashboardError.setup("Add a Proxmox API token: Datacenter → Permissions → API Tokens. Token ID looks like root@pam!hush.")
        }
        return ["Authorization": "PVEAPIToken=\(w.username)=\(w.secret)"]
    }

    private static func proxmoxNodeName(_ w: HomeWidget, _ headers: [String: String]) async throws -> String {
        if !w.node.trimmed.isEmpty { return w.node.trimmed }
        let j = try await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api2/json/nodes"), headers: headers, selfSigned: w.allowSelfSigned)
        guard let name = JSONPath.value(j, "data.0.node") as? String else { throw DashboardError.parse("no Proxmox nodes") }
        return name
    }

    private static func proxmoxNode(_ w: HomeWidget) async throws -> ServerSnapshot {
        let h = try proxmoxHeaders(w)
        let node = try await proxmoxNodeName(w, h)
        let j = try await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api2/json/nodes/\(node)/status"), headers: h, selfSigned: w.allowSelfSigned)
        guard let d = (j as? [String: Any])?["data"] as? [String: Any] else { throw DashboardError.parse("Proxmox status") }
        var s = ServerSnapshot()
        s.hostname = node
        s.os = JSONPath.string(d["pveversion"])
        s.cpu = (JSONPath.double(d["cpu"]) ?? 0) * 100
        s.cores = Int(JSONPath.double(JSONPath.value(d, "cpuinfo.cpus")) ?? 0)
        s.uptime = JSONPath.double(d["uptime"]) ?? 0
        s.load = ((d["loadavg"] as? [Any]) ?? []).compactMap(JSONPath.double)
        s.memTotal = JSONPath.double(JSONPath.value(d, "memory.total")) ?? 0
        s.memUsed = JSONPath.double(JSONPath.value(d, "memory.used")) ?? 0
        s.swapTotal = JSONPath.double(JSONPath.value(d, "swap.total")) ?? 0
        s.swapUsed = JSONPath.double(JSONPath.value(d, "swap.used")) ?? 0
        s.disks = [.init(name: "root", total: JSONPath.double(JSONPath.value(d, "rootfs.total")) ?? 0, used: JSONPath.double(JSONPath.value(d, "rootfs.used")) ?? 0)]
        // Storage pools
        if let st = try? await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api2/json/nodes/\(node)/storage"), headers: h, selfSigned: w.allowSelfSigned),
           let pools = (st as? [String: Any])?["data"] as? [[String: Any]] {
            for p in pools where (p["active"] as? Int ?? 1) == 1 {
                let total = JSONPath.double(p["total"]) ?? 0
                if total > 0 { s.disks.append(.init(name: JSONPath.string(p["storage"]), total: total, used: JSONPath.double(p["used"]) ?? 0)) }
            }
        }
        return s
    }

    // MARK: Containers

    static func containers(_ w: HomeWidget) async throws -> [ContainerInfo] {
        if w.source == "proxmox" {
            let h = try proxmoxHeaders(w)
            let node = try await proxmoxNodeName(w, h)
            var out: [ContainerInfo] = []
            for kind in ["qemu", "lxc"] {
                let j = try await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api2/json/nodes/\(node)/\(kind)"), headers: h, selfSigned: w.allowSelfSigned)
                for d in ((j as? [String: Any])?["data"] as? [[String: Any]]) ?? [] {
                    let status = JSONPath.string(d["status"])
                    out.append(ContainerInfo(id: "\(kind)-\(JSONPath.string(d["vmid"]))", name: JSONPath.string(d["name"]), kind: kind == "qemu" ? "vm" : "lxc",
                                             status: status, running: status == "running", cpu: (JSONPath.double(d["cpu"]) ?? 0) * 100,
                                             memory: JSONPath.double(d["mem"]), memoryLimit: JSONPath.double(d["maxmem"]),
                                             image: "ID \(JSONPath.string(d["vmid"]))", uptime: JSONPath.double(d["uptime"])))
                }
            }
            return out
        }
        var headers: [String: String] = [:]
        if !w.username.isEmpty { headers["Authorization"] = "Basic " + Data("\(w.username):\(w.secret)".utf8).base64EncodedString() }
        var list: [[String: Any]] = []
        if let j = try? await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api/4/containers"), headers: headers, selfSigned: w.allowSelfSigned) {
            list = j as? [[String: Any]] ?? []
        } else {
            let j = try await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api/3/docker"), headers: headers, selfSigned: w.allowSelfSigned)
            list = (j as? [String: Any])?["containers"] as? [[String: Any]] ?? (j as? [[String: Any]] ?? [])
        }
        return list.map { d in
            let status = JSONPath.string(d["status"] ?? d["Status"])
            let mem = JSONPath.double(JSONPath.value(d, "memory.usage")) ?? JSONPath.double(d["memory_usage"])
            let limit = JSONPath.double(JSONPath.value(d, "memory.limit"))
            let cpu = JSONPath.double(JSONPath.value(d, "cpu.total")) ?? JSONPath.double(d["cpu_percent"])
            let image = (d["image"] as? [String])?.first ?? JSONPath.string(d["image"] ?? d["Image"])
            let name = JSONPath.string(d["name"] ?? d["Names"])
            return ContainerInfo(id: name, name: name, kind: "docker", status: status,
                                 running: status.lowercased().contains("running") || status.lowercased().hasPrefix("up"),
                                 cpu: cpu, memory: mem, memoryLimit: limit, image: image == "—" ? "" : image,
                                 uptime: JSONPath.double(d["uptime"]))
        }
    }

    // MARK: Uptime monitor

    static func monitor(_ w: HomeWidget, homelab: [(String, String)]) async -> [MonitorResult] {
        var targets: [(String, String)] = w.items.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map { String($0).trimmed }
            if parts.count == 2 { return (parts[0], parts[1]) }
            return parts.first.map { ($0.replacingOccurrences(of: "https://", with: ""), $0) }
        }
        if w.includeHomelab { targets += homelab.filter { h in !targets.contains { $0.1 == h.1 } } }
        return await withTaskGroup(of: (Int, MonitorResult).self) { group in
            for (i, t) in targets.enumerated() {
                group.addTask { (i, await check(name: t.0, url: t.1, selfSigned: w.allowSelfSigned)) }
            }
            var out: [(Int, MonitorResult)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func check(name: String, url raw: String, selfSigned: Bool) async -> MonitorResult {
        var s = raw.trimmed
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return MonitorResult(name: name, url: raw, up: false, status: 0, ms: 0, error: "Bad address") }
        let start = Date()
        do {
            let (_, http) = try await DashboardNet.data(url, selfSigned: selfSigned)
            let ms = Date().timeIntervalSince(start) * 1000
            return MonitorResult(name: name, url: s, up: http.statusCode < 400 || http.statusCode == 401, status: http.statusCode, ms: ms)
        } catch {
            return MonitorResult(name: name, url: s, up: false, status: 0, ms: Date().timeIntervalSince(start) * 1000,
                                 error: (error as NSError).localizedDescription)
        }
    }

    // MARK: Weather (Open-Meteo)

    static func geocode(_ place: String) async throws -> (name: String, lat: Double, lon: Double) {
        let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place
        let j = try await DashboardNet.json(URL(string: "https://geocoding-api.open-meteo.com/v1/search?count=1&name=\(q)")!)
        guard let r = JSONPath.value(j, "results.0") as? [String: Any], let lat = JSONPath.double(r["latitude"]), let lon = JSONPath.double(r["longitude"]) else {
            throw DashboardError.setup("Couldn't find “\(place)”.")
        }
        let name = [JSONPath.string(r["name"]), r["admin1"] as? String, r["country_code"] as? String].compactMap { $0 }.joined(separator: ", ")
        return (name, lat, lon)
    }

    static func weather(_ w: HomeWidget) async throws -> WeatherData {
        guard w.latitude != 0 || w.longitude != 0 else { throw DashboardError.setup("Choose a place in the widget's settings.") }
        var u = "https://api.open-meteo.com/v1/forecast?latitude=\(w.latitude)&longitude=\(w.longitude)"
        u += "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"
        u += "&hourly=temperature_2m,precipitation_probability,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
        u += "&timezone=auto&forecast_days=7&timeformat=unixtime"
        if w.imperial { u += "&temperature_unit=fahrenheit&wind_speed_unit=mph" }
        let j = try await DashboardNet.json(URL(string: u)!)
        var d = WeatherData()
        d.place = w.location
        d.imperial = w.imperial
        d.temperature = JSONPath.double(JSONPath.value(j, "current.temperature_2m")) ?? 0
        d.feelsLike = JSONPath.double(JSONPath.value(j, "current.apparent_temperature")) ?? d.temperature
        d.humidity = JSONPath.double(JSONPath.value(j, "current.relative_humidity_2m")) ?? 0
        d.wind = JSONPath.double(JSONPath.value(j, "current.wind_speed_10m")) ?? 0
        d.code = Int(JSONPath.double(JSONPath.value(j, "current.weather_code")) ?? 0)
        d.isDay = (JSONPath.double(JSONPath.value(j, "current.is_day")) ?? 1) == 1
        func arr(_ p: String) -> [Double] { ((JSONPath.value(j, p) as? [Any]) ?? []).map { JSONPath.double($0) ?? 0 } }
        let ht = arr("hourly.time"), htemp = arr("hourly.temperature_2m"), hrain = arr("hourly.precipitation_probability"), hcode = arr("hourly.weather_code")
        let now = Date().addingTimeInterval(-3600)
        for i in ht.indices where i < htemp.count {
            let t = Date(timeIntervalSince1970: ht[i])
            guard t >= now, d.hourly.count < 48 else { continue }
            d.hourly.append(.init(time: t, temp: htemp[i], rain: i < hrain.count ? hrain[i] : 0, code: Int(i < hcode.count ? hcode[i] : 0)))
        }
        let dt = arr("daily.time"), hi = arr("daily.temperature_2m_max"), lo = arr("daily.temperature_2m_min"), dr = arr("daily.precipitation_probability_max"),
            dc = arr("daily.weather_code"), sr = arr("daily.sunrise"), ss = arr("daily.sunset")
        for i in dt.indices where i < hi.count && i < lo.count {
            d.daily.append(.init(date: Date(timeIntervalSince1970: dt[i]), high: hi[i], low: lo[i], rain: i < dr.count ? dr[i] : 0,
                                 code: Int(i < dc.count ? dc[i] : 0),
                                 sunrise: i < sr.count ? Date(timeIntervalSince1970: sr[i]) : nil, sunset: i < ss.count ? Date(timeIntervalSince1970: ss[i]) : nil))
        }
        return d
    }

    static func weatherSymbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func weatherText(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77: "Snow"
        case 80...82: "Showers"
        case 85, 86: "Snow showers"
        case 95...99: "Thunderstorm"
        default: "—"
        }
    }

    // MARK: Markets (Yahoo Finance chart API)

    static func markets(_ symbols: [String]) async throws -> [Quote] {
        let list = symbols.map { $0.trimmed.uppercased() }.filter { !$0.isEmpty }
        let quotes = await withTaskGroup(of: (Int, Quote?).self) { group in
            for (i, s) in list.enumerated() { group.addTask { (i, try? await quote(s, range: "1d", interval: "15m")) } }
            var out: [(Int, Quote?)] = []
            for await q in group { out.append(q) }
            return out.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        if quotes.isEmpty && !list.isEmpty { throw DashboardError.setup("Couldn't load prices. Check the symbols (e.g. AAPL, VOO, BTC-USD).") }
        return quotes
    }

    static func quote(_ symbol: String, range: String, interval: String) async throws -> Quote {
        let s = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let j = try await DashboardNet.json(URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(s)?range=\(range)&interval=\(interval)")!)
        guard let r = JSONPath.value(j, "chart.result.0") as? [String: Any], let meta = r["meta"] as? [String: Any] else { throw DashboardError.parse(symbol) }
        let closes = ((JSONPath.value(r, "indicators.quote.0.close") as? [Any]) ?? []).compactMap(JSONPath.double)
        let price = JSONPath.double(meta["regularMarketPrice"]) ?? closes.last ?? 0
        let prev = range == "1d" ? (JSONPath.double(meta["chartPreviousClose"]) ?? JSONPath.double(meta["previousClose"]) ?? price) : (closes.first ?? price)
        let name = (meta["shortName"] as? String) ?? (meta["longName"] as? String) ?? symbol
        return Quote(symbol: symbol, name: name, price: price, previousClose: prev, currency: JSONPath.string(meta["currency"]), points: closes)
    }

    // MARK: News

    static func news(_ w: HomeWidget) async throws -> [NewsItem] {
        let count = max(1, min(w.limit, 30))
        if w.source == "lobsters" {
            let feed = w.sortMode == "new" ? "newest" : "hottest"
            let j = try await DashboardNet.json(URL(string: "https://lobste.rs/\(feed).json")!)
            let iso = ISO8601DateFormatter()
            return ((j as? [[String: Any]]) ?? []).prefix(count).map { d in
                let link = JSONPath.string(d["url"])
                let comments = JSONPath.string(d["comments_url"] ?? d["short_id_url"])
                let user = (d["submitter_user"] as? String) ?? JSONPath.string(JSONPath.value(d, "submitter_user.username"))
                return NewsItem(id: JSONPath.string(d["short_id"]), title: JSONPath.string(d["title"]), url: link.isEmpty || link == "—" ? comments : link,
                                commentsURL: comments, score: Int(JSONPath.double(d["score"]) ?? 0), comments: Int(JSONPath.double(d["comment_count"]) ?? 0),
                                author: user, date: iso.date(from: JSONPath.string(d["created_at"])) ?? Date())
            }
        }
        let list = w.sortMode == "new" ? "newstories" : (w.sortMode == "best" ? "beststories" : "topstories")
        let ids = ((try await DashboardNet.json(URL(string: "https://hacker-news.firebaseio.com/v0/\(list).json")!) as? [Any]) ?? []).compactMap(JSONPath.double).prefix(count)
        return await withTaskGroup(of: (Int, NewsItem?).self) { group in
            for (i, id) in ids.enumerated() {
                group.addTask {
                    let n = Int(id)
                    guard let d = try? await DashboardNet.json(URL(string: "https://hacker-news.firebaseio.com/v0/item/\(n).json")!) as? [String: Any] else { return (i, nil) }
                    let comments = "https://news.ycombinator.com/item?id=\(n)"
                    let link = d["url"] as? String ?? comments
                    return (i, NewsItem(id: String(n), title: JSONPath.string(d["title"]), url: link, commentsURL: comments,
                                        score: Int(JSONPath.double(d["score"]) ?? 0), comments: Int(JSONPath.double(d["descendants"]) ?? 0),
                                        author: JSONPath.string(d["by"]), date: Date(timeIntervalSince1970: JSONPath.double(d["time"]) ?? 0)))
                }
            }
            var out: [(Int, NewsItem?)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
    }

    // MARK: GitHub releases

    static func releases(_ w: HomeWidget) async throws -> [ReleaseInfo] {
        var headers = ["Accept": "application/vnd.github+json"]
        if !w.secret.isEmpty { headers["Authorization"] = "Bearer \(w.secret)" }
        let repos = w.items.map { $0.trimmed.replacingOccurrences(of: "https://github.com/", with: "") }.filter { $0.contains("/") }
        let iso = ISO8601DateFormatter()
        let out = await withTaskGroup(of: (Int, ReleaseInfo?).self) { group in
            for (i, repo) in repos.enumerated() {
                group.addTask {
                    if let j = try? await DashboardNet.json(URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, headers: headers) as? [String: Any] {
                        return (i, ReleaseInfo(repo: repo, tag: JSONPath.string(j["tag_name"]), name: JSONPath.string(j["name"]),
                                               date: iso.date(from: JSONPath.string(j["published_at"])), url: JSONPath.string(j["html_url"]),
                                               notes: String((j["body"] as? String ?? "").prefix(4000))))
                    }
                    // No releases: show the newest tag.
                    if let tags = try? await DashboardNet.json(URL(string: "https://api.github.com/repos/\(repo)/tags?per_page=1")!, headers: headers) as? [[String: Any]],
                       let t = tags.first {
                        let name = JSONPath.string(t["name"])
                        return (i, ReleaseInfo(repo: repo, tag: name, name: name, date: nil, url: "https://github.com/\(repo)/releases/tag/\(name)", notes: ""))
                    }
                    return (i, nil)
                }
            }
            var all: [(Int, ReleaseInfo?)] = []
            for await r in group { all.append(r) }
            return all.compactMap { r in r.1.map { (r.0, $0) } }
        }
        if out.isEmpty && !repos.isEmpty { throw DashboardError.setup("Couldn't load releases (GitHub allows 60 requests an hour without a token).") }
        return out.sorted { ($0.1.date ?? .distantPast) > ($1.1.date ?? .distantPast) }.map(\.1)
    }

    // MARK: DNS blocking

    static func dns(_ w: HomeWidget) async throws -> DNSStats {
        switch w.source {
        case "adguard": return try await adguard(w)
        case "pihole5": return try await pihole5(w)
        default: return try await pihole6(w)
        }
    }

    private static func pihole6(_ w: HomeWidget) async throws -> DNSStats {
        var sid = ""
        if !w.secret.isEmpty {
            let body = try JSONSerialization.data(withJSONObject: ["password": w.secret])
            let (data, http) = try await DashboardNet.data(try DashboardNet.url(w.endpoint, "/api/auth"), method: "POST", body: body, selfSigned: w.allowSelfSigned)
            guard (200..<300).contains(http.statusCode), let j = try? JSONSerialization.jsonObject(with: data),
                  let s = JSONPath.value(j, "session.sid") as? String else { throw DashboardError.http(http.statusCode == 200 ? 401 : http.statusCode, "Pi-hole") }
            sid = s
        }
        let headers = sid.isEmpty ? [:] : ["X-FTL-SID": sid]
        defer {
            // Pi-hole has a limited number of sessions: always log out.
            if !sid.isEmpty, let u = try? DashboardNet.url(w.endpoint, "/api/auth") {
                Task { _ = try? await DashboardNet.data(u, method: "DELETE", headers: headers, selfSigned: w.allowSelfSigned) }
            }
        }
        let summary = try await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api/stats/summary"), headers: headers, selfSigned: w.allowSelfSigned)
        var s = DNSStats()
        s.total = JSONPath.double(JSONPath.value(summary, "queries.total")) ?? 0
        s.blocked = JSONPath.double(JSONPath.value(summary, "queries.blocked")) ?? 0
        s.percent = JSONPath.double(JSONPath.value(summary, "queries.percent_blocked")) ?? (s.total > 0 ? s.blocked / s.total * 100 : 0)
        s.listSize = JSONPath.double(JSONPath.value(summary, "gravity.domains_being_blocked")) ?? 0
        s.clients = JSONPath.double(JSONPath.value(summary, "clients.active")) ?? 0
        if let h = try? await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api/history"), headers: headers, selfSigned: w.allowSelfSigned),
           let rows = (h as? [String: Any])?["history"] as? [[String: Any]] {
            s.history = rows.map { .init(time: Date(timeIntervalSince1970: JSONPath.double($0["timestamp"]) ?? 0),
                                          total: JSONPath.double($0["total"]) ?? 0, blocked: JSONPath.double($0["blocked"]) ?? 0) }
        }
        if let t = try? await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api/stats/top_domains?blocked=true&count=10"), headers: headers, selfSigned: w.allowSelfSigned),
           let rows = (t as? [String: Any])?["domains"] as? [[String: Any]] {
            s.topBlocked = rows.map { .init(domain: JSONPath.string($0["domain"]), count: JSONPath.double($0["count"]) ?? 0) }
        }
        if let b = try? await DashboardNet.json(try DashboardNet.url(w.endpoint, "/api/dns/blocking"), headers: headers, selfSigned: w.allowSelfSigned) {
            s.enabled = (JSONPath.value(b, "blocking") as? String).map { $0 == "enabled" }
        }
        return s
    }

    private static func pihole5(_ w: HomeWidget) async throws -> DNSStats {
        let token = w.secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let j = try await DashboardNet.json(try DashboardNet.url(w.endpoint, "/admin/api.php?summaryRaw&overTimeData10mins&topItems=10&auth=\(token)"), selfSigned: w.allowSelfSigned)
        guard let d = j as? [String: Any] else { throw DashboardError.parse("Pi-hole") }
        var s = DNSStats()
        s.total = JSONPath.double(d["dns_queries_today"]) ?? 0
        s.blocked = JSONPath.double(d["ads_blocked_today"]) ?? 0
        s.percent = JSONPath.double(d["ads_percentage_today"]) ?? 0
        s.listSize = JSONPath.double(d["domains_being_blocked"]) ?? 0
        s.clients = JSONPath.double(d["unique_clients"]) ?? 0
        s.enabled = (d["status"] as? String).map { $0 == "enabled" }
        if let total = d["domains_over_time"] as? [String: Any], let ads = d["ads_over_time"] as? [String: Any] {
            s.history = total.keys.compactMap { k in
                Double(k).map { DNSStats.Point(time: Date(timeIntervalSince1970: $0), total: JSONPath.double(total[k]) ?? 0, blocked: JSONPath.double(ads[k]) ?? 0) }
            }.sorted { $0.time < $1.time }
        }
        if let top = d["top_ads"] as? [String: Any] {
            s.topBlocked = top.map { .init(domain: $0.key, count: JSONPath.double($0.value) ?? 0) }.sorted { $0.count > $1.count }
        }
        return s
    }

    private static func adguard(_ w: HomeWidget) async throws -> DNSStats {
        var headers: [String: String] = [:]
        if !w.username.isEmpty { headers["Authorization"] = "Basic " + Data("\(w.username):\(w.secret)".utf8).base64EncodedString() }
        let j = try await DashboardNet.json(try DashboardNet.url(w.endpoint, "/control/stats"), headers: headers, selfSigned: w.allowSelfSigned)
        guard let d = j as? [String: Any] else { throw DashboardError.parse("AdGuard Home") }
        var s = DNSStats()
        s.total = JSONPath.double(d["num_dns_queries"]) ?? 0
        s.blocked = (JSONPath.double(d["num_blocked_filtering"]) ?? 0) + (JSONPath.double(d["num_replaced_safebrowsing"]) ?? 0) + (JSONPath.double(d["num_replaced_parental"]) ?? 0)
        s.percent = s.total > 0 ? s.blocked / s.total * 100 : 0
        let totals = ((d["dns_queries"] as? [Any]) ?? []).compactMap(JSONPath.double)
        let blocked = ((d["blocked_filtering"] as? [Any]) ?? []).compactMap(JSONPath.double)
        let hourly = (d["time_units"] as? String ?? "hours") == "hours"
        let now = Date()
        s.history = totals.enumerated().map { i, t in
            let back = Double(totals.count - 1 - i) * (hourly ? 3600 : 86400)
            return .init(time: now.addingTimeInterval(-back), total: t, blocked: i < blocked.count ? blocked[i] : 0)
        }
        s.topBlocked = ((d["top_blocked_domains"] as? [[String: Any]]) ?? []).compactMap { $0.first.map { DNSStats.Domain(domain: $0.key, count: JSONPath.double($0.value) ?? 0) } }
        if let st = try? await DashboardNet.json(try DashboardNet.url(w.endpoint, "/control/status"), headers: headers, selfSigned: w.allowSelfSigned) {
            s.enabled = JSONPath.value(st, "protection_enabled") as? Bool
            s.listSize = 0
        }
        if let f = try? await DashboardNet.json(try DashboardNet.url(w.endpoint, "/control/filtering/status"), headers: headers, selfSigned: w.allowSelfSigned),
           let filters = (f as? [String: Any])?["filters"] as? [[String: Any]] {
            s.listSize = filters.filter { ($0["enabled"] as? Bool) ?? false }.compactMap { JSONPath.double($0["rules_count"]) }.reduce(0, +)
        }
        return s
    }

    // MARK: Custom API

    static func custom(_ w: HomeWidget) async throws -> ([CustomField], String) {
        var headers: [String: String] = ["Accept": "application/json"]
        if !w.secret.isEmpty { headers[w.username.trimmed.isEmpty ? "Authorization" : w.username.trimmed] = w.secret }
        guard let url = URL(string: w.endpoint.trimmed), url.scheme != nil else { throw DashboardError.setup("Add the API address (https://…) in the widget's settings.") }
        let (data, http) = try await DashboardNet.data(url, headers: headers, selfSigned: w.allowSelfSigned)
        guard (200..<300).contains(http.statusCode) else { throw DashboardError.http(http.statusCode, url.host() ?? "") }
        let raw: String
        let root: Any
        if let j = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            root = j
            let pretty = (try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])) ?? data
            raw = String(decoding: pretty.prefix(30_000), as: UTF8.self)
        } else {
            throw DashboardError.parse("the address didn't return JSON")
        }
        let specs = w.items.isEmpty ? defaultFields(root) : w.items
        let fields: [CustomField] = specs.filter { !$0.trimmed.isEmpty && !$0.trimmed.hasPrefix("=") }.compactMap { spec in
            let main = spec.split(separator: "|", maxSplits: 1).map(String.init)
            guard !main.isEmpty else { return nil }
            let unit = main.count > 1 ? main[1].trimmed : ""
            let lr = main[0].split(separator: "=", maxSplits: 1).map { String($0).trimmed }
            guard !lr.isEmpty else { return nil }
            let label = lr[0], path = lr.count > 1 ? lr[1] : lr[0]
            guard !path.isEmpty else { return nil }
            let v = JSONPath.value(root, path)
            return CustomField(label: label, value: JSONPath.string(v), number: v is String ? nil : JSONPath.double(v), unit: unit)
        }
        return (fields, raw)
    }

    /// When no fields are chosen yet: the first few simple values at the top level.
    private static func defaultFields(_ root: Any) -> [String] {
        guard let d = root as? [String: Any] else { return [] }
        return d.keys.sorted().filter { !(d[$0] is [Any]) && !(d[$0] is [String: Any]) }.prefix(6).map { "\($0)=\($0)" }
    }
}

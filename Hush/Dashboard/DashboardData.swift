import Foundation

// MARK: - Results

struct ServerSnapshot: Codable {
    var hostname = ""
    var os = ""
    var uptime: TimeInterval = 0
    var cpu: Double = 0
    var perCore: [Double] = []
    var cores = 0
    var load: [Double] = []
    var memTotal: Double = 0
    var memUsed: Double = 0
    var swapTotal: Double = 0
    var swapUsed: Double = 0
    var disks: [Disk] = []
    var temps: [Temp] = []
    /// Bytes per second, when known.
    var netRx: Double?
    var netTx: Double?
    /// Raw counters (converted to rates using the previous sample).
    var netRxTotal: Double?
    var netTxTotal: Double?

    struct Disk: Codable, Hashable { var name: String; var total: Double; var used: Double }
    struct Temp: Codable, Hashable { var name: String; var celsius: Double }

    var memPercent: Double { memTotal > 0 ? memUsed / memTotal * 100 : 0 }
    var swapPercent: Double { swapTotal > 0 ? swapUsed / swapTotal * 100 : 0 }
    var hottest: Double? { temps.map(\.celsius).max() }
    var fullestDisk: Disk? { disks.max { ($0.total > 0 ? $0.used / $0.total : 0) < ($1.total > 0 ? $1.used / $1.total : 0) } }
}

struct ContainerInfo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: String // docker, vm, lxc
    var status: String
    var running: Bool
    var cpu: Double?
    var memory: Double?
    var memoryLimit: Double?
    var image = ""
    var uptime: TimeInterval?
}

struct MonitorResult: Codable, Identifiable, Hashable {
    var id: String { name + url }
    var name: String
    var url: String
    var up: Bool
    var status: Int
    var ms: Double
    var error = ""
}

struct WeatherData: Codable {
    var place = ""
    var temperature: Double = 0
    var feelsLike: Double = 0
    var humidity: Double = 0
    var wind: Double = 0
    var code = 0
    var isDay = true
    var hourly: [Hour] = []
    var daily: [Day] = []
    var imperial = false

    struct Hour: Codable, Hashable { var time: Date; var temp: Double; var rain: Double; var code: Int }
    struct Day: Codable, Hashable { var date: Date; var high: Double; var low: Double; var rain: Double; var code: Int; var sunrise: Date?; var sunset: Date? }
}

struct Quote: Codable, Identifiable, Hashable {
    var id: String { symbol }
    var symbol: String
    var name: String
    var price: Double
    var previousClose: Double
    var currency: String
    var points: [Double]

    var change: Double { price - previousClose }
    var changePercent: Double { previousClose > 0 ? change / previousClose * 100 : 0 }
}

struct NewsItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var url: String
    var commentsURL: String
    var score: Int
    var comments: Int
    var author: String
    var date: Date
    var domain: String { URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? "" }
}

struct ReleaseInfo: Codable, Identifiable, Hashable {
    var id: String { repo }
    var repo: String
    var tag: String
    var name: String
    var date: Date?
    var url: String
    var notes: String
    var isNew: Bool { date.map { Date().timeIntervalSince($0) < 7 * 86400 } ?? false }
}

struct DNSStats: Codable {
    var total: Double = 0
    var blocked: Double = 0
    var percent: Double = 0
    var listSize: Double = 0
    var clients: Double = 0
    var enabled: Bool?
    var history: [Point] = []
    var topBlocked: [Domain] = []

    struct Point: Codable, Hashable { var time: Date; var total: Double; var blocked: Double }
    struct Domain: Codable, Hashable { var domain: String; var count: Double }
}

struct CustomField: Codable, Hashable, Identifiable {
    var id: String { label }
    var label: String
    var value: String
    var number: Double?
    var unit: String
}

enum WidgetPayload {
    case server(ServerSnapshot)
    case containers([ContainerInfo])
    case monitor([MonitorResult])
    case weather(WeatherData)
    case markets([Quote])
    case news([NewsItem])
    case releases([ReleaseInfo])
    case dns(DNSStats)
    case custom([CustomField], raw: String)
}

/// One point of history for a widget's charts.
struct HistorySample: Codable, Hashable {
    var t: Date
    var v: [String: Double]
}

enum DashboardError: LocalizedError {
    case setup(String)
    case http(Int, String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .setup(let s): s
        case .http(401, _), .http(403, _): "The server refused the login. Check the token or password in the widget's settings."
        case .http(let c, let host): "\(host) answered \(c)."
        case .parse(let s): "Unexpected answer: \(s)"
        }
    }
}

// MARK: - Networking

/// Requests for dashboard widgets. Self-signed certificates (common on Proxmox and homelab boxes)
/// are accepted only for widgets where you turned that on.
final class DashboardNet: NSObject, URLSessionDelegate {
    static let strict = DashboardNet(allowSelfSigned: false)
    static let lenient = DashboardNet(allowSelfSigned: true)

    private let allowSelfSigned: Bool
    private(set) lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Hush"]
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    private init(allowSelfSigned: Bool) { self.allowSelfSigned = allowSelfSigned }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowSelfSigned, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    static func data(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil,
                     selfSigned: Bool = false) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if body != nil && headers["Content-Type"] == nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await (selfSigned ? lenient : strict).session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DashboardError.parse("no HTTP response") }
        return (data, http)
    }

    /// GET and parse JSON, throwing on non-2xx answers.
    static func json(_ url: URL, headers: [String: String] = [:], selfSigned: Bool = false) async throws -> Any {
        let (data, http) = try await self.data(url, headers: headers, selfSigned: selfSigned)
        guard (200..<300).contains(http.statusCode) else { throw DashboardError.http(http.statusCode, url.host() ?? url.absoluteString) }
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) } catch {
            throw DashboardError.parse("not JSON from \(url.host() ?? "")")
        }
    }

    static func url(_ base: String, _ path: String) throws -> URL {
        var b = base.trimmed
        guard !b.isEmpty else { throw DashboardError.setup("Add the server address in the widget's settings.") }
        if !b.contains("://") { b = "http://" + b }
        while b.hasSuffix("/") { b.removeLast() }
        guard let u = URL(string: b + path) else { throw DashboardError.setup("“\(base)” isn't a valid address.") }
        return u
    }
}

/// Reads values out of parsed JSON with paths like "main.temp" or "items.0.name".
enum JSONPath {
    static func value(_ root: Any, _ path: String) -> Any? {
        var cur: Any? = root
        for part in path.split(separator: ".").map(String.init) where !part.isEmpty {
            if let d = cur as? [String: Any] { cur = d[part] }
            else if let a = cur as? [Any], let i = Int(part) { cur = i >= 0 && i < a.count ? a[i] : (i < 0 && -i <= a.count ? a[a.count + i] : nil) }
            else { return nil }
        }
        return cur
    }

    static func double(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func string(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "Yes" : "No" }
            let d = n.doubleValue
            return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(format: "%.2f", d)
        case let a as [Any]: return "\(a.count) items"
        case is [String: Any]: return "{…}"
        case nil: return "—"
        default: return "\(v!)"
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ b: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(b, 0)), countStyle: .binary)
    }
    static func rate(_ b: Double?) -> String {
        guard let b else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(max(b, 0)), countStyle: .decimal) + "/s"
    }
    static func percent(_ p: Double) -> String { String(format: p < 10 ? "%.1f%%" : "%.0f%%", p) }
    static func uptime(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = t >= 86400 ? [.day, .hour] : [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: t) ?? "—"
    }
    static func compact(_ n: Double) -> String {
        n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
    static func price(_ p: Double, _ currency: String) -> String {
        p.formatted(.currency(code: currency.isEmpty ? "USD" : currency).precision(.fractionLength(p < 1 ? 4 : 2)))
    }
}

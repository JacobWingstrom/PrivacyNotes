import Foundation

enum DAVError: LocalizedError {
    case http(Int, String)
    case conflict
    case badURL(String)

    var errorDescription: String? {
        switch self {
        case .http(401, _): "The calendar server didn't accept your password."
        case .http(let code, let url): "The calendar server answered \(code) for \(URL(string: url)?.path ?? url)."
        case .conflict: "The item was changed on the server at the same time."
        case .badURL(let s): "“\(s)” isn't a valid server address."
        }
    }
}

struct DAVResponse {
    var href: String
    var status: Int?
    var props: [String: String] = [:]
    var resourceTypes: Set<String> = []
    var components: Set<String> = []
}

/// Minimal WebDAV / CalDAV / CardDAV over HTTPS with Basic auth.
final class DAVClient: NSObject, URLSessionTaskDelegate {
    private let authHeader: String
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    init(username: String, password: String) {
        authHeader = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    deinit { session.invalidateAndCancel() }

    func request(_ url: URL, method: String, depth: String? = nil, body: String? = nil,
                 contentType: String = "application/xml; charset=utf-8", headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard url.scheme?.lowercased() == "https" else { throw DAVError.badURL(url.absoluteString + " (HTTPS is required)") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("Hush", forHTTPHeaderField: "User-Agent")
        if let depth { req.setValue(depth, forHTTPHeaderField: "Depth") }
        if let body {
            req.httpBody = Data(body.utf8)
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DAVError.http(0, url.absoluteString) }
        return (data, http)
    }

    /// Keeps method, body and auth when the server redirects (e.g. /.well-known/caldav).
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest, let url = request.url, url.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            return
        }
        var r = original
        r.url = url
        completionHandler(r)
    }

    func propfind(_ url: URL, depth: String, props: String) async throws -> [DAVResponse] {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:cs="http://calendarserver.org/ns/" xmlns:ic="http://apple.com/ns/ical/">
        <d:prop>\(props)</d:prop></d:propfind>
        """
        let (data, http) = try await request(url, method: "PROPFIND", depth: depth, body: body)
        guard http.statusCode == 207 || http.statusCode == 200 else { throw DAVError.http(http.statusCode, url.absoluteString) }
        return DAVXMLParser.parse(data)
    }

    func report(_ url: URL, body: String, depth: String = "1") async throws -> [DAVResponse] {
        let (data, http) = try await request(url, method: "REPORT", depth: depth, body: body)
        guard http.statusCode == 207 || http.statusCode == 200 else { throw DAVError.http(http.statusCode, url.absoluteString) }
        return DAVXMLParser.parse(data)
    }

    /// Creates or replaces a resource. Returns the new ETag if the server sends one.
    func put(_ url: URL, body: String, contentType: String, ifMatch: String?, create: Bool) async throws -> String? {
        var headers: [String: String] = [:]
        if create { headers["If-None-Match"] = "*" } else if let ifMatch, !ifMatch.isEmpty { headers["If-Match"] = ifMatch }
        let (_, http) = try await request(url, method: "PUT", body: body, contentType: contentType, headers: headers)
        if http.statusCode == 412 { throw DAVError.conflict }
        guard (200..<300).contains(http.statusCode) else { throw DAVError.http(http.statusCode, url.absoluteString) }
        return http.value(forHTTPHeaderField: "ETag")
    }

    func delete(_ url: URL, ifMatch: String?) async throws {
        var headers: [String: String] = [:]
        if let ifMatch, !ifMatch.isEmpty { headers["If-Match"] = ifMatch }
        let (_, http) = try await request(url, method: "DELETE", headers: headers)
        if http.statusCode == 412 { throw DAVError.conflict }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 404 else { throw DAVError.http(http.statusCode, url.absoluteString) }
    }

    func get(_ url: URL) async throws -> (String, String?) {
        let (data, http) = try await request(url, method: "GET")
        guard (200..<300).contains(http.statusCode) else { throw DAVError.http(http.statusCode, url.absoluteString) }
        return (String(decoding: data, as: UTF8.self), http.value(forHTTPHeaderField: "ETag"))
    }
}

/// Reads a WebDAV multistatus answer.
final class DAVXMLParser: NSObject, XMLParserDelegate {
    private var responses: [DAVResponse] = []
    private var current: DAVResponse?
    private var propstatProps: [String: String] = [:]
    private var propstatTypes: Set<String> = []
    private var propstatComps: Set<String> = []
    private var propstatStatus = 200
    private var stack: [String] = []
    private var text = ""
    private var propName: String?
    private var propText = ""

    static func parse(_ data: Data) -> [DAVResponse] {
        let p = XMLParser(data: data)
        p.shouldProcessNamespaces = true
        let d = DAVXMLParser()
        p.delegate = d
        p.parse()
        return d.responses
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        stack.append(name)
        text = ""
        switch name {
        case "response": current = DAVResponse(href: "")
        case "propstat":
            propstatProps = [:]; propstatTypes = []; propstatComps = []; propstatStatus = 200
        default: break
        }
        if propName == nil, stack.count >= 2, stack[stack.count - 2] == "prop" {
            propName = name
            propText = ""
        }
        if stack.contains("resourcetype") && name != "resourcetype" { propstatTypes.insert(name) }
        if name == "comp", let n = attributes["name"] { propstatComps.insert(n.uppercased()) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
        if propName != nil { propText += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        let s = String(decoding: CDATABlock, as: UTF8.self)
        text += s
        if propName != nil { propText += s }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { if !stack.isEmpty { stack.removeLast() } }
        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
        if name == "href" && parent == "response" { current?.href = text.trimmed }
        if name == "status" {
            let code = Int(text.split(separator: " ").dropFirst().first ?? "") ?? 200
            if parent == "propstat" { propstatStatus = code } else if parent == "response" { current?.status = code }
        }
        if let p = propName, p == name, parent == "prop" {
            propstatProps[p] = propText.trimmingCharacters(in: .whitespacesAndNewlines)
            propName = nil
        }
        if name == "propstat", (200..<300).contains(propstatStatus) {
            for (k, v) in propstatProps { current?.props[k] = v }
            current?.resourceTypes.formUnion(propstatTypes)
            current?.components.formUnion(propstatComps)
        }
        if name == "response", let r = current {
            responses.append(r)
            current = nil
        }
    }
}

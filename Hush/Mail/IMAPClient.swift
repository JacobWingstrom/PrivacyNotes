import Foundation

struct IMAPFolder: Codable, Hashable, Identifiable {
    /// Path exactly as the server names it (modified UTF-7).
    var path: String
    var delimiter: String
    var attributes: [String]
    var unread = 0
    var total = 0

    var id: String { path }
    var displayPath: String { ModifiedUTF7.decode(path) }
    var name: String {
        let decoded = displayPath
        guard !delimiter.isEmpty, let last = decoded.components(separatedBy: delimiter).last, !last.isEmpty else { return decoded }
        return decoded.uppercased() == "INBOX" ? "Inbox" : last
    }
    var depth: Int { delimiter.isEmpty ? 0 : max(displayPath.components(separatedBy: delimiter).count - 1, 0) }
    var isSelectable: Bool { !attributes.contains { $0.caseInsensitiveCompare("\\Noselect") == .orderedSame || $0.caseInsensitiveCompare("\\NonExistent") == .orderedSame } }

    /// \Sent, \Trash, \Drafts, \Junk, \Archive, \Flagged … or "inbox".
    var role: String? {
        if path.uppercased() == "INBOX" { return "inbox" }
        let known = ["\\Sent", "\\Trash", "\\Drafts", "\\Junk", "\\Archive", "\\All", "\\Flagged"]
        if let a = attributes.first(where: { attr in known.contains { $0.caseInsensitiveCompare(attr) == .orderedSame } }) {
            return a.dropFirst().lowercased()
        }
        // Common names when the server doesn't mark them.
        let n = name.lowercased()
        if ["sent", "sent items", "sent messages", "gesendet", "gesendete objekte", "gesendete elemente"].contains(n) { return "sent" }
        if ["trash", "deleted items", "deleted messages", "papierkorb", "bin"].contains(n) { return "trash" }
        if ["drafts", "entwürfe", "draft"].contains(n) { return "drafts" }
        if ["junk", "spam", "junk e-mail", "junk email"].contains(n) { return "junk" }
        if ["archive", "archiv", "archives"].contains(n) { return "archive" }
        return nil
    }

    var symbol: String {
        switch role {
        case "inbox": "tray"
        case "sent": "paperplane"
        case "trash": "trash"
        case "drafts": "doc"
        case "junk": "xmark.bin"
        case "archive": "archivebox"
        case "flagged": "flag"
        default: "folder"
        }
    }

    var sortRank: Int {
        switch role {
        case "inbox": 0
        case "drafts": 1
        case "sent": 2
        case "archive": 3
        case "junk": 4
        case "trash": 5
        default: 10
        }
    }
}

struct IMAPSelectInfo {
    var exists = 0
    var uidValidity = 0
    var uidNext = 0
}

struct IMAPFetched {
    var uid = 0
    var flags: [String] = []
    var internalDate: Date?
    var size = 0
    var header: Data?
    var body: Data?
}

/// A small IMAP4rev1 client: enough to list, read, flag, move, delete and append messages.
final class IMAPClient {
    private let conn: StreamConnection
    private var tagCounter = 0
    private(set) var capabilities: Set<String> = []
    private(set) var selected: String?
    private(set) var selectInfo = IMAPSelectInfo()
    var lastUsed = Date()

    init(host: String, port: Int) {
        conn = StreamConnection(host: host, port: port)
    }

    func connect(security: MailSecurity, username: String, password: String) async throws {
        conn.open(implicitTLS: security == .tls)
        let greeting = try await readResponse()
        if greeting.status == "BYE" { throw MailError.server(greeting.text) }
        if let code = greeting.responseCode, code.uppercased().hasPrefix("CAPABILITY") { parseCapabilities(code) }
        if security == .starttls {
            _ = try await command("STARTTLS")
            conn.startTLS()
            capabilities = []
        }
        if capabilities.isEmpty { try await refreshCapabilities() }
        guard conn.isSecure else { throw MailError.connection("The connection isn't encrypted.") }
        do {
            if capabilities.contains("AUTH=PLAIN") && capabilities.contains("SASL-IR") {
                let token = Data("\0\(username)\0\(password)".utf8).base64EncodedString()
                _ = try await command("AUTHENTICATE PLAIN \(token)", sensitive: true)
            } else {
                _ = try await command("LOGIN", args: [.string(username), .string(password)], sensitive: true)
            }
        } catch MailError.server(let msg) {
            throw MailError.auth(msg)
        }
        try await refreshCapabilities()
    }

    func logout() async {
        _ = try? await command("LOGOUT")
        conn.close()
    }

    func close() { conn.close() }

    // MARK: Commands

    func refreshCapabilities() async throws {
        let r = try await command("CAPABILITY")
        for line in r.untagged where line.text.uppercased().hasPrefix("* CAPABILITY") {
            parseCapabilities(String(line.text.dropFirst(2)))
        }
    }

    private func parseCapabilities(_ s: String) {
        capabilities = Set(s.split(separator: " ").dropFirst().map { $0.uppercased() })
    }

    func listFolders() async throws -> [IMAPFolder] {
        let r = try await command("LIST \"\" \"*\"")
        var out: [IMAPFolder] = []
        for line in r.untagged {
            let v = line.values
            guard v.count >= 4, v[0].text?.uppercased() == "LIST" else { continue }
            let attrs = v[1].items.compactMap(\.text)
            let delim = v[2].text ?? ""
            guard let path = v[3].text else { continue }
            out.append(IMAPFolder(path: path, delimiter: delim, attributes: attrs))
        }
        return out
    }

    func status(_ folder: String) async throws -> (total: Int, unread: Int, uidNext: Int, uidValidity: Int) {
        let r = try await command("STATUS", args: [.mailbox(folder), .raw("(MESSAGES UNSEEN UIDNEXT UIDVALIDITY)")])
        var total = 0, unread = 0, next = 0, validity = 0
        for line in r.untagged {
            let v = line.values
            guard v.count >= 3, v[0].text?.uppercased() == "STATUS" else { continue }
            let items = v[2].items
            var i = 0
            while i + 1 < items.count {
                let key = items[i].text?.uppercased() ?? ""
                let value = items[i + 1].int ?? 0
                switch key {
                case "MESSAGES": total = value
                case "UNSEEN": unread = value
                case "UIDNEXT": next = value
                case "UIDVALIDITY": validity = value
                default: break
                }
                i += 2
            }
        }
        return (total, unread, next, validity)
    }

    @discardableResult
    func select(_ folder: String, readOnly: Bool = false) async throws -> IMAPSelectInfo {
        let r = try await command(readOnly ? "EXAMINE" : "SELECT", args: [.mailbox(folder)])
        var info = IMAPSelectInfo()
        for line in r.untagged {
            let t = line.text
            let v = line.values
            if v.count >= 2, v[1].text?.uppercased() == "EXISTS" { info.exists = v[0].int ?? 0 }
            if let code = line.responseCode {
                let parts = code.split(separator: " ")
                if parts.count == 2 {
                    if parts[0].uppercased() == "UIDVALIDITY" { info.uidValidity = Int(parts[1]) ?? 0 }
                    if parts[0].uppercased() == "UIDNEXT" { info.uidNext = Int(parts[1]) ?? 0 }
                }
            }
            _ = t
        }
        selected = folder
        selectInfo = info
        return info
    }

    func searchUIDs(_ criteria: String) async throws -> [Int] {
        let r = try await command("UID SEARCH \(criteria)")
        var out: [Int] = []
        for line in r.untagged {
            let v = line.values
            guard v.first?.text?.uppercased() == "SEARCH" else { continue }
            out += v.dropFirst().compactMap(\.int)
        }
        return out
    }

    /// Fetches by UID set (e.g. "1:*", "5,7,9").
    func fetch(uids: String, items: String) async throws -> [IMAPFetched] {
        let r = try await command("UID FETCH \(uids) (\(items))")
        return parseFetch(r.untagged)
    }

    /// Fetches by sequence number range (e.g. "1:50").
    func fetch(sequence: String, items: String) async throws -> [IMAPFetched] {
        let r = try await command("FETCH \(sequence) (\(items))")
        return parseFetch(r.untagged)
    }

    private func parseFetch(_ lines: [IMAPResponse]) -> [IMAPFetched] {
        var out: [IMAPFetched] = []
        for line in lines {
            let v = line.values
            guard v.count >= 3, v[1].text?.uppercased() == "FETCH" else { continue }
            let items = v[2].items
            var f = IMAPFetched()
            var i = 0
            while i + 1 < items.count {
                let key = (items[i].text ?? "").uppercased()
                let value = items[i + 1]
                if key == "UID" { f.uid = value.int ?? 0 }
                else if key == "FLAGS" { f.flags = value.items.compactMap(\.text) }
                else if key == "RFC822.SIZE" { f.size = value.int ?? 0 }
                else if key == "INTERNALDATE" { f.internalDate = value.text.flatMap(Self.parseInternalDate) }
                else if key.hasPrefix("BODY[HEADER") || key == "RFC822.HEADER" { f.header = value.data }
                else if key.hasPrefix("BODY[") || key == "RFC822" { f.body = value.data }
                i += 2
            }
            if f.uid > 0 { out.append(f) }
        }
        return out
    }

    func store(uids: [Int], add: Bool, flags: [String]) async throws {
        guard !uids.isEmpty else { return }
        _ = try await command("UID STORE \(Self.set(uids)) \(add ? "+" : "-")FLAGS.SILENT (\(flags.joined(separator: " ")))")
    }

    func move(uids: [Int], to folder: String) async throws {
        guard !uids.isEmpty else { return }
        if capabilities.contains("MOVE") {
            _ = try await command("UID MOVE \(Self.set(uids))", args: [.mailbox(folder)])
        } else {
            _ = try await command("UID COPY \(Self.set(uids))", args: [.mailbox(folder)])
            try await store(uids: uids, add: true, flags: ["\\Deleted"])
            try await expunge(uids: uids)
        }
    }

    func expunge(uids: [Int]) async throws {
        if capabilities.contains("UIDPLUS") {
            _ = try await command("UID EXPUNGE \(Self.set(uids))")
        } else {
            _ = try await command("EXPUNGE")
        }
    }

    func append(folder: String, message: Data, flags: [String]) async throws {
        _ = try await command("APPEND", args: [.mailbox(folder), .raw("(\(flags.joined(separator: " ")))"), .literal(message)])
    }

    func noop() async throws { _ = try await command("NOOP") }

    // MARK: Plumbing

    enum Arg {
        case raw(String)
        case string(String)
        case mailbox(String)
        case literal(Data)
    }

    struct Result {
        var untagged: [IMAPResponse]
        var tagged: IMAPResponse
    }

    @discardableResult
    func command(_ name: String, args: [Arg] = [], sensitive: Bool = false) async throws -> Result {
        tagCounter += 1
        lastUsed = Date()
        let tag = String(format: "H%03d", tagCounter)
        // Build the command; literals need the server's "+" before their bytes are sent.
        var pieces: [(Data, Bool)] = [] // (data, waitForContinuationAfter)
        var current = Data("\(tag) \(name)".utf8)
        for arg in args {
            current.append(0x20)
            switch arg {
            case .raw(let s):
                current.append(contentsOf: Array(s.utf8))
            case .mailbox(let s):
                current.append(contentsOf: Array(Self.quote(s).utf8))
            case .string(let s):
                if s.utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) {
                    current.append(contentsOf: Array(Self.quote(s).utf8))
                } else {
                    let d = Data(s.utf8)
                    current.append(contentsOf: Array("{\(d.count)}\r\n".utf8))
                    pieces.append((current, true))
                    current = d
                }
            case .literal(let d):
                current.append(contentsOf: Array("{\(d.count)}\r\n".utf8))
                pieces.append((current, true))
                current = d
            }
        }
        current.append(contentsOf: [0x0D, 0x0A])
        pieces.append((current, false))

        var untagged: [IMAPResponse] = []
        for (data, wait) in pieces {
            try await conn.write(data)
            if wait {
                while true {
                    let r = try await readResponse()
                    if case .continuation = r.kind { break }
                    if case .tagged = r.kind { throw MailError.server(r.text) }
                    untagged.append(r)
                }
            }
        }
        while true {
            let r = try await readResponse()
            switch r.kind {
            case .untagged:
                if r.status == "BYE", !name.hasPrefix("LOGOUT") { throw MailError.closed }
                untagged.append(r)
            case .continuation:
                // Unexpected (e.g. AUTHENTICATE without SASL-IR); cancel it.
                try await conn.write("*\r\n")
            case .tagged(let t):
                guard t == tag else { continue }
                let words = r.text.split(separator: " ", maxSplits: 2)
                let status = words.count > 1 ? words[1].uppercased() : ""
                if status != "OK" {
                    let msg = words.count > 2 ? String(words[2]) : r.text
                    throw MailError.server(sensitive ? "The server said: \(msg)" : "\(name.split(separator: " ").first ?? ""): \(msg)")
                }
                return Result(untagged: untagged, tagged: r)
            }
        }
    }

    /// Reads one response, pulling in any literals it announces.
    private func readResponse() async throws -> IMAPResponse {
        var raw = Data()
        while true {
            let line = try await conn.readLine()
            raw.append(line)
            if let n = Self.trailingLiteralSize(line) {
                raw.append(contentsOf: [0x0D, 0x0A])
                raw.append(try await conn.read(count: n))
                continue
            }
            break
        }
        let kind: IMAPResponse.Kind
        if raw.first == UInt8(ascii: "*") { kind = .untagged }
        else if raw.first == UInt8(ascii: "+") { kind = .continuation }
        else {
            let tag = raw.prefix { $0 != 0x20 }
            kind = .tagged(String(decoding: tag, as: UTF8.self))
        }
        return IMAPResponse(kind: kind, raw: raw)
    }

    private static func trailingLiteralSize(_ line: Data) -> Int? {
        guard line.last == UInt8(ascii: "}") else { return nil }
        guard let open = line.lastIndex(of: UInt8(ascii: "{")) else { return nil }
        var digits = line[line.index(after: open)..<line.index(before: line.endIndex)]
        if digits.last == UInt8(ascii: "+") { digits = digits.dropLast() }
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return Int(String(decoding: digits, as: UTF8.self))
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Compact UID set: [1,2,3,7] → "1:3,7".
    static func set(_ uids: [Int]) -> String {
        let sorted = Array(Set(uids)).sorted()
        var parts: [String] = []
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count && sorted[j + 1] == sorted[j] + 1 { j += 1 }
            parts.append(i == j ? "\(sorted[i])" : "\(sorted[i]):\(sorted[j])")
            i = j + 1
        }
        return parts.joined(separator: ",")
    }

    private static let internalDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        return f
    }()

    static func parseInternalDate(_ s: String) -> Date? {
        internalDateFormatter.date(from: s.trimmingCharacters(in: .whitespaces))
    }

    static func searchDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d-MMM-yyyy"
        return f.string(from: d)
    }
}

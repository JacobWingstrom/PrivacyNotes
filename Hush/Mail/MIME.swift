import Foundation

struct MailAddress: Hashable, Codable, Identifiable {
    var name: String
    var email: String
    var id: String { email.lowercased() }

    var display: String { name.isEmpty ? email : name }
    /// "Name <email>" for headers (name encoded if needed).
    var header: String {
        guard !name.isEmpty else { return email }
        let needsQuotes = name.contains { ",;:<>@\"()[]\\.".contains($0) }
        let encoded = MIME.encodeWord(name)
        if encoded != name { return "\(encoded) <\(email)>" }
        return needsQuotes ? "\"\(name.replacingOccurrences(of: "\"", with: "\\\""))\" <\(email)>" : "\(name) <\(email)>"
    }
    var full: String { name.isEmpty ? email : "\(name) <\(email)>" }
}

struct MIMEHeaders {
    var fields: [(name: String, value: String)] = []

    /// Raw (unfolded, undecoded) value of the first header with this name.
    func raw(_ name: String) -> String? {
        fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
    func all(_ name: String) -> [String] {
        fields.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }
    /// Value with =?charset?…?= words decoded.
    subscript(_ name: String) -> String? { raw(name).map(MIME.decodeWords) }
}

struct MIMEPart {
    var headers = MIMEHeaders()
    /// Body bytes as transmitted (still transfer-encoded).
    var rawBody = Data()
    var children: [MIMEPart] = []

    var contentType: String { MIME.mainValue(headers.raw("Content-Type") ?? "text/plain").lowercased() }
    var contentTypeParams: [String: String] { MIME.params(headers.raw("Content-Type") ?? "") }
    var dispositionParams: [String: String] { MIME.params(headers.raw("Content-Disposition") ?? "") }
    var disposition: String { MIME.mainValue(headers.raw("Content-Disposition") ?? "").lowercased() }
    var charset: String? { contentTypeParams["charset"] }
    var contentID: String? {
        headers.raw("Content-ID").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t")) }
    }
    var filename: String? {
        let n = dispositionParams["filename"] ?? contentTypeParams["name"]
        return n.map(MIME.decodeWords).flatMap { $0.isEmpty ? nil : $0 }
    }
    var isMultipart: Bool { contentType.hasPrefix("multipart/") }

    /// Body with base64 / quoted-printable undone.
    var decodedData: Data {
        switch (headers.raw("Content-Transfer-Encoding") ?? "").lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64": return MIME.decodeBase64(rawBody)
        case "quoted-printable": return MIME.decodeQuotedPrintable(rawBody, underscoreIsSpace: false)
        default: return rawBody
        }
    }

    var text: String { MIME.string(decodedData, charset: charset) }
}

struct MailAttachment: Identifiable {
    let id = UUID()
    var filename: String
    var mimeType: String
    var data: Data
    var contentID: String?
    var isInline: Bool
}

/// A message taken apart for reading.
struct ParsedMessage {
    var headers = MIMEHeaders()
    var from: MailAddress?
    var to: [MailAddress] = []
    var cc: [MailAddress] = []
    var replyTo: [MailAddress] = []
    var subject = ""
    var date: Date?
    var messageID = ""
    var inReplyTo = ""
    var references: [String] = []
    var textBody: String?
    var htmlBody: String?
    var attachments: [MailAttachment] = []
    /// text/calendar parts (invites), as text.
    var calendarParts: [String] = []
    /// text/vcard parts and .vcf attachments, as text.
    var vcardParts: [String] = []
    var isPGPEncrypted = false
    var isPGPSigned = false

    /// Newsletters, notifications and other mass mail.
    var isBulk: Bool {
        if headers.raw("List-Unsubscribe") != nil || headers.raw("List-Id") != nil { return true }
        let p = (headers.raw("Precedence") ?? "").lowercased()
        if p.contains("bulk") || p.contains("list") || p.contains("junk") { return true }
        if headers.raw("Auto-Submitted").map({ !$0.lowercased().hasPrefix("no") }) ?? false { return true }
        let e = (from?.email ?? "").lowercased()
        return ["noreply", "no-reply", "donotreply", "do-not-reply", "notifications@", "newsletter", "mailer-daemon"].contains { e.contains($0) }
    }

    /// Plain text for previews, scanning and quoting.
    var plainText: String {
        if let t = textBody, !t.trimmed.isEmpty { return t }
        return MIME.htmlToText(htmlBody ?? "")
    }

    var snippet: String {
        let flat = plainText
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix(">") }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return String(flat.prefix(220))
    }
}

enum MIME {
    // MARK: Parsing

    static func parse(_ data: Data) -> MIMEPart {
        let (headerData, body) = splitHeader(data)
        var part = MIMEPart(headers: parseHeaders(headerData), rawBody: body)
        if part.isMultipart, let boundary = part.contentTypeParams["boundary"], !boundary.isEmpty {
            part.children = splitMultipart(body, boundary: boundary).map(parse)
        } else if part.contentType == "message/rfc822" && !(part.disposition == "attachment") {
            part.children = [parse(part.decodedData)]
        }
        return part
    }

    static func parseMessage(_ data: Data) -> ParsedMessage {
        let root = parse(data)
        var m = ParsedMessage()
        m.headers = root.headers
        m.from = root.headers.raw("From").flatMap { parseAddresses($0).first }
        m.to = root.headers.raw("To").map(parseAddresses) ?? []
        m.cc = root.headers.raw("Cc").map(parseAddresses) ?? []
        m.replyTo = root.headers.raw("Reply-To").map(parseAddresses) ?? []
        m.subject = root.headers["Subject"]?.trimmed ?? ""
        m.date = root.headers.raw("Date").flatMap(parseDate)
        m.messageID = root.headers.raw("Message-ID")?.trimmed ?? ""
        m.inReplyTo = root.headers.raw("In-Reply-To")?.trimmed ?? ""
        m.references = (root.headers.raw("References") ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        collect(root, into: &m, inAlternative: false)
        if root.contentType == "multipart/encrypted" || (m.textBody ?? "").contains("-----BEGIN PGP MESSAGE-----") { m.isPGPEncrypted = true }
        if root.contentType == "multipart/signed" || (m.textBody ?? "").contains("-----BEGIN PGP SIGNED MESSAGE-----") { m.isPGPSigned = true }
        return m
    }

    private static func collect(_ part: MIMEPart, into m: inout ParsedMessage, inAlternative: Bool) {
        if part.isMultipart {
            for child in part.children { collect(child, into: &m, inAlternative: part.contentType == "multipart/alternative") }
            return
        }
        if part.contentType == "message/rfc822" && !part.children.isEmpty && part.disposition != "attachment" {
            // Forwarded inline: treat as attachment so the main text stays clear.
            m.attachments.append(MailAttachment(filename: (part.children[0].headers["Subject"] ?? "Forwarded message") + ".eml",
                                                mimeType: "message/rfc822", data: part.decodedData, contentID: nil, isInline: false))
            return
        }
        let type = part.contentType
        let isAttachment = part.disposition == "attachment" || (part.filename != nil && !type.hasPrefix("text/plain") && !type.hasPrefix("text/html"))
        if type == "text/calendar" || type == "application/ics" || (part.filename?.lowercased().hasSuffix(".ics") ?? false) {
            m.calendarParts.append(part.text)
        }
        if type == "text/vcard" || type == "text/x-vcard" || (part.filename?.lowercased().hasSuffix(".vcf") ?? false) {
            m.vcardParts.append(part.text)
        }
        if !isAttachment && type == "text/plain" && m.textBody == nil { m.textBody = part.text; return }
        if !isAttachment && type == "text/html" && m.htmlBody == nil { m.htmlBody = part.text; return }
        if !isAttachment && (type == "text/plain" || type == "text/html") { return }
        if type == "application/pgp-encrypted" { m.isPGPEncrypted = true; return }
        if type == "application/pgp-signature" { m.isPGPSigned = true; return }
        let name = part.filename ?? defaultName(for: type)
        let inline = part.disposition == "inline" || (part.contentID != nil && part.disposition != "attachment")
        m.attachments.append(MailAttachment(filename: name, mimeType: type, data: part.decodedData, contentID: part.contentID, isInline: inline && type.hasPrefix("image/")))
    }

    private static func defaultName(for type: String) -> String {
        switch type {
        case "text/calendar": return "invite.ics"
        case "image/png": return "image.png"
        case "image/jpeg": return "image.jpg"
        case "application/pdf": return "document.pdf"
        default: return "attachment"
        }
    }

    static func splitHeader(_ data: Data) -> (Data, Data) {
        if let r = data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
            let n = data.range(of: Data([0x0A, 0x0A]))
            if let n, n.lowerBound < r.lowerBound { return (data[..<n.lowerBound], data[n.upperBound...]) }
            return (data[..<r.lowerBound], data[r.upperBound...])
        }
        if let n = data.range(of: Data([0x0A, 0x0A])) { return (data[..<n.lowerBound], data[n.upperBound...]) }
        // Only headers, or a body without headers.
        if data.first == 0x0D || data.first == 0x0A { return (Data(), data) }
        return (data, Data())
    }

    static func parseHeaders(_ data: Data) -> MIMEHeaders {
        // Headers should be ASCII; decode leniently so 8-bit names still show.
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        var fields: [(String, String)] = []
        for line in text.components(separatedBy: "\n") {
            let l = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if let first = l.first, first == " " || first == "\t" {
                if !fields.isEmpty { fields[fields.count - 1].1 += " " + l.trimmingCharacters(in: .whitespaces) }
                continue
            }
            guard let colon = l.firstIndex(of: ":") else { continue }
            let name = String(l[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(l[l.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields.append((name, value))
        }
        return MIMEHeaders(fields: fields.map { (name: $0.0, value: $0.1) })
    }

    static func splitMultipart(_ body: Data, boundary: String) -> [Data] {
        let delimiter = Data("--\(boundary)".utf8)
        var parts: [Data] = []
        var searchFrom = body.startIndex
        var starts: [(Data.Index, Data.Index)] = [] // (delimiter start, content start)
        while let r = body.range(of: delimiter, in: searchFrom..<body.endIndex) {
            // Must be at the start of a line.
            let atLineStart = r.lowerBound == body.startIndex || body[body.index(before: r.lowerBound)] == 0x0A
            if atLineStart {
                var after = r.upperBound
                let isClose = body.count >= 2 && after < body.endIndex - 1 && body[after] == 0x2D && body[body.index(after: after)] == 0x2D
                // Skip to the end of the delimiter line.
                while after < body.endIndex && body[after] != 0x0A { after = body.index(after: after) }
                if after < body.endIndex { after = body.index(after: after) }
                starts.append((r.lowerBound, after))
                if isClose { break }
            }
            searchFrom = r.upperBound
        }
        for i in 0..<starts.count {
            let contentStart = starts[i].1
            let contentEnd: Data.Index
            if i + 1 < starts.count {
                var e = starts[i + 1].0
                // Drop the line break that belongs to the next delimiter.
                if e > contentStart && body[body.index(before: e)] == 0x0A { e = body.index(before: e) }
                if e > contentStart && body[body.index(before: e)] == 0x0D { e = body.index(before: e) }
                contentEnd = e
            } else {
                break // after the closing delimiter: epilogue
            }
            if contentEnd >= contentStart { parts.append(Data(body[contentStart..<contentEnd])) }
        }
        return parts
    }

    /// "text/plain; charset=utf-8" → "text/plain"
    static func mainValue(_ header: String) -> String {
        String(header.split(separator: ";", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// Header parameters, including RFC 2231 continuations and charset'lang'%XX values.
    static func params(_ header: String) -> [String: String] {
        var out: [String: String] = [:]
        var continued: [String: [(Int, String, Bool)]] = [:]
        for raw in splitParams(header).dropFirst() {
            guard let eq = raw.firstIndex(of: "=") else { continue }
            var key = raw[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = raw[raw.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
            }
            let extended = key.hasSuffix("*")
            if extended { key.removeLast() }
            if let star = key.firstIndex(of: "*"), let n = Int(key[key.index(after: star)...]) {
                continued[String(key[..<star]), default: []].append((n, value, extended))
            } else if extended {
                out[key] = decode2231(value, first: true)
            } else {
                out[key] = value
            }
        }
        for (key, pieces) in continued {
            let joined = pieces.sorted { $0.0 < $1.0 }.enumerated().map { i, p in p.2 ? decode2231(p.1, first: i == 0) : p.1 }.joined()
            out[key] = joined
        }
        return out
    }

    private static func splitParams(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        for c in s {
            if c == "\"" { inQuotes.toggle() }
            if c == ";" && !inQuotes { parts.append(current); current = ""; continue }
            current.append(c)
        }
        parts.append(current)
        return parts
    }

    private static func decode2231(_ v: String, first: Bool) -> String {
        var charset = "utf-8"
        var value = v
        if first {
            let parts = v.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 { charset = String(parts[0]); value = String(parts[2]) }
        }
        var bytes: [UInt8] = []
        var i = value.utf8.startIndex
        let u = value.utf8
        while i < u.endIndex {
            let c = u[i]
            if c == UInt8(ascii: "%"), let a = u.index(i, offsetBy: 1, limitedBy: u.endIndex), let b = u.index(i, offsetBy: 2, limitedBy: u.endIndex), b < u.endIndex,
               let byte = UInt8(String(decoding: [u[a], u[b]], as: UTF8.self), radix: 16) {
                bytes.append(byte)
                i = u.index(after: b)
            } else {
                bytes.append(c)
                i = u.index(after: i)
            }
        }
        return string(Data(bytes), charset: charset.isEmpty ? "utf-8" : charset)
    }

    // MARK: Encodings

    static func decodeBase64(_ data: Data) -> Data {
        let cleaned = data.filter { b in
            (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || b == 0x2B || b == 0x2F || b == 0x3D
        }
        var s = String(decoding: cleaned, as: UTF8.self)
        if let firstPad = s.firstIndex(of: "=") { s = String(s[..<firstPad]) }
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s) ?? Data()
    }

    static func decodeQuotedPrintable(_ data: Data, underscoreIsSpace: Bool) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        let bytes = [UInt8](data)
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b {
            case 0x30...0x39: return b - 0x30
            case 0x41...0x46: return b - 0x41 + 10
            case 0x61...0x66: return b - 0x61 + 10
            default: return nil
            }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "=") {
                if i + 1 < bytes.count && bytes[i + 1] == 0x0A { i += 2; continue }
                if i + 2 < bytes.count && bytes[i + 1] == 0x0D && bytes[i + 2] == 0x0A { i += 3; continue }
                if i + 2 < bytes.count, let h = hex(bytes[i + 1]), let l = hex(bytes[i + 2]) {
                    out.append(h << 4 | l)
                    i += 3
                    continue
                }
                // Trailing "=" with spaces before the line break.
                var j = i + 1
                while j < bytes.count && (bytes[j] == 0x20 || bytes[j] == 0x09) { j += 1 }
                if j < bytes.count && (bytes[j] == 0x0D || bytes[j] == 0x0A) {
                    i = j + (bytes[j] == 0x0D && j + 1 < bytes.count && bytes[j + 1] == 0x0A ? 2 : 1)
                    continue
                }
                out.append(b)
                i += 1
            } else if underscoreIsSpace && b == UInt8(ascii: "_") {
                out.append(0x20)
                i += 1
            } else {
                out.append(b)
                i += 1
            }
        }
        return out
    }

    static func encoding(for charset: String?) -> String.Encoding? {
        guard var name = charset?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).lowercased(), !name.isEmpty else { return nil }
        if name == "utf8" { name = "utf-8" }
        if name == "ks_c_5601-1987" { name = "euc-kr" }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    static func string(_ data: Data, charset: String?) -> String {
        if let enc = encoding(for: charset), let s = String(data: data, encoding: enc) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    /// Decodes RFC 2047 encoded words; spaces between adjacent encoded words are dropped.
    static func decodeWords(_ s: String) -> String {
        guard s.contains("=?") else { return s }
        let pattern = "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?="
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        var previousWasWord = false
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            if !(previousWasWord && between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { out += between }
            let charset = ns.substring(with: m.range(at: 1)).split(separator: "*").first.map(String.init) ?? "utf-8"
            let mode = ns.substring(with: m.range(at: 2)).uppercased()
            let text = ns.substring(with: m.range(at: 3))
            let data = mode == "B" ? decodeBase64(Data(text.utf8)) : decodeQuotedPrintable(Data(text.utf8), underscoreIsSpace: true)
            out += string(data, charset: charset)
            last = m.range.location + m.range.length
            previousWasWord = true
        }
        out += ns.substring(from: last)
        return out
    }

    /// Encodes a header value as UTF-8 base64 words when it isn't plain ASCII.
    static func encodeWord(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0.value > 0x7E || $0.value < 0x20 }) else { return s }
        // Split into chunks so each encoded word stays under 75 characters.
        var words: [String] = []
        var chunk = ""
        for ch in s {
            if (chunk + String(ch)).utf8.count > 45 {
                words.append("=?UTF-8?B?\(Data(chunk.utf8).base64EncodedString())?=")
                chunk = ""
            }
            chunk.append(ch)
        }
        if !chunk.isEmpty { words.append("=?UTF-8?B?\(Data(chunk.utf8).base64EncodedString())?=") }
        return words.joined(separator: "\r\n ")
    }

    static func encodeQuotedPrintable(_ text: String) -> String {
        var out = ""
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var current = ""
            let bytes = Array(line.utf8)
            for (i, b) in bytes.enumerated() {
                let isLast = i == bytes.count - 1
                var piece: String
                if (b >= 33 && b <= 126 && b != 61) || (b == 32 && !isLast) || (b == 9 && !isLast) {
                    piece = String(UnicodeScalar(b))
                } else {
                    piece = String(format: "=%02X", b)
                }
                if current.count + piece.count > 75 {
                    out += current + "=\r\n"
                    current = ""
                }
                current += piece
            }
            out += current + "\r\n"
        }
        return out
    }

    // MARK: Addresses & dates

    static func parseAddresses(_ raw: String) -> [MailAddress] {
        let s = decodeWords(raw)
        var items: [String] = []
        var current = ""
        var inQuotes = false, angle = 0, paren = 0
        for c in s {
            switch c {
            case "\"": inQuotes.toggle()
            case "<" where !inQuotes: angle += 1
            case ">" where !inQuotes: angle = max(angle - 1, 0)
            case "(" where !inQuotes: paren += 1
            case ")" where !inQuotes: paren = max(paren - 1, 0)
            default: break
            }
            if (c == "," || c == ";") && !inQuotes && angle == 0 && paren == 0 {
                items.append(current); current = ""
                continue
            }
            current.append(c)
        }
        items.append(current)
        return items.compactMap { item -> MailAddress? in
            var t = item.trimmed
            // Group syntax "Team: a@b, c@d;" – drop the group name.
            if let colon = t.firstIndex(of: ":"), !t.contains("<"), !t[..<colon].contains("@") { t = String(t[t.index(after: colon)...]).trimmed }
            guard !t.isEmpty else { return nil }
            if let lt = t.lastIndex(of: "<"), let gt = t.lastIndex(of: ">"), lt < gt {
                let email = String(t[t.index(after: lt)..<gt]).trimmed
                var name = String(t[..<lt]).trimmed
                if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 { name = String(name.dropFirst().dropLast()) }
                name = name.replacingOccurrences(of: "\\\"", with: "\"")
                guard email.contains("@") else { return nil }
                return MailAddress(name: name == email ? "" : name, email: email)
            }
            var email = t
            var name = ""
            if let p = t.firstIndex(of: "("), let q = t.lastIndex(of: ")"), p < q {
                name = String(t[t.index(after: p)..<q]).trimmed
                email = String(t[..<p]).trimmed
            }
            guard email.contains("@") else { return nil }
            return MailAddress(name: name, email: email)
        }
    }

    private static let dateFormatters: [DateFormatter] = [
        "EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z",
        "EEE, d MMM yy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss zzz",
    ].map { fmt in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = fmt
        return f
    }

    static func parseDate(_ raw: String) -> Date? {
        var s = raw.trimmed
        if let p = s.firstIndex(of: "(") { s = String(s[..<p]).trimmed }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        for f in dateFormatters { if let d = f.date(from: s) { return d } }
        return nil
    }

    static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return f.string(from: d)
    }

    // MARK: HTML

    /// Rough HTML → text for previews, quoting and scanning.
    static func htmlToText(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        var s = html
        let rules: [(String, String)] = [
            ("(?is)<(script|style|head|title)[^>]*>.*?</\\1>", ""),
            ("(?is)<!--.*?-->", ""),
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|tr|li|h[1-6]|table|blockquote)>", "\n"),
            ("(?i)<li[^>]*>", "• "),
            ("(?s)<[^>]+>", ""),
        ]
        for (p, r) in rules { s = s.replacingOccurrences(of: p, with: r, options: .regularExpression) }
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        return s.trimmed
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&hellip;": "…", "&mdash;": "—", "&ndash;": "–", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“",
                     "&euro;": "€", "&copy;": "©", "&reg;": "®", "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä",
                     "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß", "&eacute;": "é", "&zwnj;": "", "&shy;": ""]
        for (k, v) in named where k != "&amp;" { out = out.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                let num = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10) ?? 0x20
                result += String(UnicodeScalar(num).map(Character.init) ?? " ")
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Building messages to send

struct OutgoingMessage {
    var from: MailAddress
    var to: [MailAddress] = []
    var cc: [MailAddress] = []
    var bcc: [MailAddress] = []
    var subject = ""
    var body = ""
    var inReplyTo = ""
    var references: [String] = []
    var attachments: [(name: String, mimeType: String, data: Data)] = []

    var recipients: [MailAddress] { to + cc + bcc }

    /// RFC 5322 message (CRLF line endings). Bcc is never written into the headers.
    func render(messageID: String, date: Date = .now) -> Data {
        var h: [String] = []
        h.append("From: \(from.header)")
        if !to.isEmpty { h.append("To: " + to.map(\.header).joined(separator: ",\r\n ")) }
        if !cc.isEmpty { h.append("Cc: " + cc.map(\.header).joined(separator: ",\r\n ")) }
        h.append("Subject: " + MIME.encodeWord(subject))
        h.append("Date: " + MIME.formatDate(date))
        h.append("Message-ID: \(messageID)")
        if !inReplyTo.isEmpty { h.append("In-Reply-To: \(inReplyTo)") }
        if !references.isEmpty { h.append("References: " + references.joined(separator: "\r\n ")) }
        h.append("MIME-Version: 1.0")

        let textPart = "Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n" + MIME.encodeQuotedPrintable(body)
        var out = h.joined(separator: "\r\n") + "\r\n"
        if attachments.isEmpty {
            out += textPart
        } else {
            let boundary = "hush-" + UUID().uuidString
            out += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n"
            out += "--\(boundary)\r\n" + textPart
            for a in attachments {
                let name = MIME.encodeWord(a.name).replacingOccurrences(of: "\r\n ", with: " ").replacingOccurrences(of: "\"", with: "")
                out += "--\(boundary)\r\n"
                out += "Content-Type: \(a.mimeType); name=\"\(name)\"\r\n"
                out += "Content-Disposition: attachment; filename=\"\(name)\"\r\n"
                out += "Content-Transfer-Encoding: base64\r\n\r\n"
                out += a.data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) + "\r\n"
            }
            out += "--\(boundary)--\r\n"
        }
        return Data(out.utf8)
    }

    static func newMessageID(for email: String) -> String {
        let domain = email.split(separator: "@").last.map(String.init) ?? "hush.local"
        return "<\(UUID().uuidString.lowercased())@\(domain)>"
    }
}

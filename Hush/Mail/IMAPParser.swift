import Foundation

/// A parsed piece of an IMAP response.
indirect enum IMAPValue: CustomStringConvertible {
    case atom(String)
    case string(Data)
    case list([IMAPValue])
    case nil_

    var text: String? {
        switch self {
        case .atom(let s): s
        case .string(let d): String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)
        case .nil_: nil
        case .list: nil
        }
    }
    var data: Data? {
        switch self {
        case .string(let d): d
        case .atom(let s): Data(s.utf8)
        default: nil
        }
    }
    var items: [IMAPValue] {
        if case .list(let l) = self { return l }
        return []
    }
    var int: Int? { text.flatMap { Int($0) } }

    var description: String {
        switch self {
        case .atom(let s): s
        case .string(let d): "\"\(String(decoding: d.prefix(60), as: UTF8.self))\""
        case .list(let l): "(" + l.map(\.description).joined(separator: " ") + ")"
        case .nil_: "NIL"
        }
    }
}

/// Reads IMAP response text where literals ({n}CRLF + n bytes) are already inline.
struct IMAPScanner {
    private let bytes: [UInt8]
    private(set) var pos = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    var atEnd: Bool { pos >= bytes.count }

    mutating func skipSpaces() {
        while pos < bytes.count, bytes[pos] == 0x20 { pos += 1 }
    }

    mutating func readAll() -> [IMAPValue] {
        var out: [IMAPValue] = []
        while true {
            skipSpaces()
            guard pos < bytes.count else { break }
            if bytes[pos] == 0x0D || bytes[pos] == 0x0A { pos += 1; continue }
            if bytes[pos] == UInt8(ascii: ")") { pos += 1; continue }
            out.append(readValue())
        }
        return out
    }

    /// The remaining raw text (e.g. the human-readable part of "OK ...").
    mutating func rest() -> String {
        let s = String(decoding: bytes[min(pos, bytes.count)...], as: UTF8.self)
        pos = bytes.count
        return s
    }

    mutating func readValue() -> IMAPValue {
        skipSpaces()
        guard pos < bytes.count else { return .nil_ }
        let c = bytes[pos]
        switch c {
        case UInt8(ascii: "("):
            pos += 1
            var items: [IMAPValue] = []
            while true {
                skipSpaces()
                guard pos < bytes.count else { break }
                if bytes[pos] == UInt8(ascii: ")") { pos += 1; break }
                if bytes[pos] == 0x0D || bytes[pos] == 0x0A { pos += 1; continue }
                items.append(readValue())
            }
            return .list(items)
        case UInt8(ascii: "\""):
            pos += 1
            var out: [UInt8] = []
            while pos < bytes.count {
                let b = bytes[pos]
                if b == UInt8(ascii: "\\"), pos + 1 < bytes.count { out.append(bytes[pos + 1]); pos += 2; continue }
                if b == UInt8(ascii: "\"") { pos += 1; break }
                out.append(b)
                pos += 1
            }
            return .string(Data(out))
        case UInt8(ascii: "{"):
            let save = pos
            pos += 1
            var n = 0
            var digits = 0
            while pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x39 {
                n = n * 10 + Int(bytes[pos] - 0x30)
                pos += 1
                digits += 1
            }
            if pos < bytes.count, bytes[pos] == UInt8(ascii: "+") { pos += 1 }
            guard digits > 0, pos < bytes.count, bytes[pos] == UInt8(ascii: "}") else {
                pos = save
                return readAtom()
            }
            pos += 1
            if pos < bytes.count, bytes[pos] == 0x0D { pos += 1 }
            if pos < bytes.count, bytes[pos] == 0x0A { pos += 1 }
            let end = min(pos + n, bytes.count)
            let d = Data(bytes[pos..<end])
            pos = end
            return .string(d)
        default:
            return readAtom()
        }
    }

    private mutating func readAtom() -> IMAPValue {
        var out: [UInt8] = []
        var depth = 0
        while pos < bytes.count {
            let b = bytes[pos]
            if b == UInt8(ascii: "[") { depth += 1 }
            if b == UInt8(ascii: "]") { depth = max(depth - 1, 0) }
            if depth == 0 && (b == 0x20 || b == UInt8(ascii: "(") || b == UInt8(ascii: ")") || b == 0x0D || b == 0x0A) {
                // "BODY[...]" keeps its section; "(" right after "]" starts the next value.
                break
            }
            out.append(b)
            pos += 1
        }
        if out.isEmpty, pos < bytes.count { pos += 1 }
        let s = String(decoding: out, as: UTF8.self)
        return s.uppercased() == "NIL" ? .nil_ : .atom(s)
    }
}

/// One complete server response line (with any literals inlined).
struct IMAPResponse {
    enum Kind { case untagged, continuation, tagged(String) }
    let kind: Kind
    let raw: Data

    var text: String { String(decoding: raw, as: UTF8.self) }

    /// For tagged and untagged status responses: "OK", "NO", "BAD", "BYE", "PREAUTH".
    var status: String? {
        let words = text.split(separator: " ", maxSplits: 3)
        let index: Int
        switch kind {
        case .untagged, .tagged: index = 1
        case .continuation: return nil
        }
        guard words.count > index else { return nil }
        let w = words[index].uppercased()
        return ["OK", "NO", "BAD", "BYE", "PREAUTH"].contains(w) ? w : nil
    }

    /// Values after "* " (untagged) — e.g. ["12", "FETCH", (...)] or ["LIST", (...), "/", "INBOX"].
    var values: [IMAPValue] {
        var s = IMAPScanner(raw)
        _ = s.readValue() // "*" or tag
        return s.readAll()
    }

    /// "[CODE args]" response code text, if any.
    var responseCode: String? {
        guard let open = text.firstIndex(of: "["), let close = text[open...].firstIndex(of: "]") else { return nil }
        return String(text[text.index(after: open)..<close])
    }
}

/// IMAP's modified UTF-7 for folder names (RFC 3501 §5.1.3).
enum ModifiedUTF7 {
    static func decode(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&" {
                guard let end = s[i...].firstIndex(of: "-") else { out.append(contentsOf: s[i...]); break }
                let chunk = s[s.index(after: i)..<end]
                if chunk.isEmpty {
                    out.append("&")
                } else {
                    var b64 = chunk.replacingOccurrences(of: ",", with: "/")
                    while b64.count % 4 != 0 { b64 += "=" }
                    if let data = Data(base64Encoded: b64), let decoded = String(data: data, encoding: .utf16BigEndian) {
                        out += decoded
                    } else {
                        out += "&" + chunk + "-"
                    }
                }
                i = s.index(after: end)
            } else {
                out.append(c)
                i = s.index(after: i)
            }
        }
        return out
    }

    static func encode(_ s: String) -> String {
        var out = ""
        var pending: [UInt16] = []
        func flush() {
            guard !pending.isEmpty else { return }
            var data = Data()
            for u in pending { data.append(UInt8(u >> 8)); data.append(UInt8(u & 0xFF)) }
            let b64 = data.base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "/", with: ",")
            out += "&" + b64 + "-"
            pending.removeAll()
        }
        for scalar in s.unicodeScalars {
            if scalar.value >= 0x20 && scalar.value <= 0x7E {
                flush()
                out += scalar == "&" ? "&-" : String(scalar)
            } else {
                pending.append(contentsOf: Array(String(scalar).utf16))
            }
        }
        flush()
        return out
    }
}

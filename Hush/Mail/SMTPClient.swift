import Foundation

/// Sends one message over SMTP submission (TLS on 465, or STARTTLS on 587).
final class SMTPClient {
    private let conn: StreamConnection
    private var extensions: [String] = []

    init(host: String, port: Int) {
        conn = StreamConnection(host: host, port: port)
    }

    func connect(security: MailSecurity, username: String, password: String) async throws {
        conn.open(implicitTLS: security == .tls)
        _ = try await expect(220)
        try await ehlo()
        if security == .starttls {
            guard extensions.contains(where: { $0.uppercased().hasPrefix("STARTTLS") }) else {
                throw MailError.connection("The server doesn't offer STARTTLS.")
            }
            try await conn.write("STARTTLS\r\n")
            _ = try await expect(220)
            conn.startTLS()
            try await ehlo()
        }
        guard conn.isSecure else { throw MailError.connection("The connection isn't encrypted.") }
        let auth = extensions.first { $0.uppercased().hasPrefix("AUTH") }?.uppercased() ?? "AUTH PLAIN LOGIN"
        do {
            if auth.contains("PLAIN") {
                let token = Data("\0\(username)\0\(password)".utf8).base64EncodedString()
                try await conn.write("AUTH PLAIN \(token)\r\n")
                _ = try await expect(235)
            } else {
                try await conn.write("AUTH LOGIN\r\n")
                _ = try await expect(334)
                try await conn.write(Data(username.utf8).base64EncodedString() + "\r\n")
                _ = try await expect(334)
                try await conn.write(Data(password.utf8).base64EncodedString() + "\r\n")
                _ = try await expect(235)
            }
        } catch MailError.server(let msg) {
            throw MailError.auth(msg)
        }
    }

    func send(from: String, to recipients: [String], data: Data) async throws {
        try await conn.write("MAIL FROM:<\(from)>\r\n")
        _ = try await expect(250)
        for r in recipients {
            try await conn.write("RCPT TO:<\(r)>\r\n")
            _ = try await expect([250, 251])
        }
        try await conn.write("DATA\r\n")
        _ = try await expect(354)
        try await conn.write(Self.dotStuff(data))
        try await conn.write(".\r\n")
        _ = try await expect(250)
    }

    func quit() async {
        try? await conn.write("QUIT\r\n")
        conn.close()
    }

    private func ehlo() async throws {
        try await conn.write("EHLO [127.0.0.1]\r\n")
        let lines = try await expect(250)
        extensions = Array(lines.dropFirst())
    }

    @discardableResult
    private func expect(_ code: Int) async throws -> [String] { try await expect([code]) }

    /// Reads a (possibly multi-line) reply and checks its code.
    @discardableResult
    private func expect(_ codes: [Int]) async throws -> [String] {
        var lines: [String] = []
        var code = 0
        while true {
            let line = try await conn.readLineString()
            guard line.count >= 3, let c = Int(line.prefix(3)) else { throw MailError.protocolError(line) }
            code = c
            lines.append(String(line.dropFirst(4)))
            if line.count < 4 || line[line.index(line.startIndex, offsetBy: 3)] != "-" { break }
        }
        guard codes.contains(code) else { throw MailError.server("Sending failed (\(code)): \(lines.joined(separator: " "))") }
        return lines
    }

    /// Normalizes line endings and doubles leading dots (RFC 5321 §4.5.2).
    static func dotStuff(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count + 64)
        var atLineStart = true
        var previous: UInt8 = 0
        for b in data {
            if b == 0x0A && previous != 0x0D { out.append(0x0D) }
            if atLineStart && b == UInt8(ascii: ".") { out.append(UInt8(ascii: ".")) }
            out.append(b)
            atLineStart = b == 0x0A
            previous = b
        }
        if !(out.suffix(2) == Data([0x0D, 0x0A])) { out.append(contentsOf: [0x0D, 0x0A]) }
        return out
    }
}

import Foundation

enum MailSecurity: String, Codable, CaseIterable, Identifiable {
    /// Encrypted from the first byte (IMAP 993, SMTP 465).
    case tls
    /// Plain connection upgraded with STARTTLS (IMAP 143, SMTP 587).
    case starttls
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tls: "SSL/TLS"
        case .starttls: "STARTTLS"
        }
    }
}

enum MailError: LocalizedError {
    case connection(String)
    case timeout
    case closed
    case protocolError(String)
    case auth(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .connection(let s): "Couldn't connect: \(s)"
        case .timeout: "The server took too long to answer."
        case .closed: "The server closed the connection."
        case .protocolError(let s): "Unexpected answer from the server: \(s)"
        case .auth(let s): "Sign-in failed. Check your email and (app) password. \(s)"
        case .server(let s): s
        }
    }
}

/// A TCP connection (always TLS-encrypted before any password is sent) with line-based reads.
/// Built on URLSessionStreamTask so STARTTLS can upgrade the same connection, and the system's
/// certificate checks apply.
final class StreamConnection {
    private let session: URLSession
    private let task: URLSessionStreamTask
    private var buffer = Data()
    private(set) var isSecure = false
    var timeout: TimeInterval = 45

    init(host: String, port: Int) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
        task = session.streamTask(withHostName: host, port: port)
    }

    deinit { close() }

    func open(implicitTLS: Bool) {
        task.resume()
        if implicitTLS { startTLS() }
    }

    /// Upgrades to TLS. Call only when no unread data is pending.
    func startTLS() {
        buffer.removeAll()
        task.startSecureConnection()
        isSecure = true
    }

    func close() {
        task.cancel()
        session.invalidateAndCancel()
    }

    func write(_ string: String) async throws {
        try await write(Data(string.utf8))
    }

    func write(_ data: Data) async throws {
        let t = task, timeout = self.timeout
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            t.write(data, timeout: timeout) { error in
                if let error { cont.resume(throwing: Self.map(error)) } else { cont.resume() }
            }
        }
    }

    /// One line without its CRLF.
    func readLine() async throws -> Data {
        while true {
            if let i = buffer.firstIndex(of: 0x0A) {
                var line = buffer[buffer.startIndex..<i]
                if line.last == 0x0D { line = line.dropLast() }
                let out = Data(line)
                buffer.removeSubrange(buffer.startIndex...i)
                return out
            }
            try await fill()
        }
    }

    func readLineString() async throws -> String {
        let d = try await readLine()
        return String(decoding: d, as: UTF8.self)
    }

    func read(count: Int) async throws -> Data {
        while buffer.count < count { try await fill() }
        let out = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return out
    }

    private func fill() async throws {
        let t = task, timeout = self.timeout
        let chunk: Data = try await withCheckedThrowingContinuation { cont in
            t.readData(ofMinLength: 1, maxLength: 256 * 1024, timeout: timeout) { data, atEOF, error in
                if let error { cont.resume(throwing: Self.map(error)); return }
                if let data, !data.isEmpty { cont.resume(returning: data); return }
                if atEOF { cont.resume(throwing: MailError.closed); return }
                cont.resume(returning: Data())
            }
        }
        buffer.append(chunk)
    }

    private static func map(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut { return MailError.timeout }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 60 { return MailError.timeout }
        return MailError.connection(ns.localizedDescription)
    }
}

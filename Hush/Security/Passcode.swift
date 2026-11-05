import Foundation
import CommonCrypto

/// The passcode itself is never stored: only a salted PBKDF2-SHA256 hash, in the Keychain.
enum Passcode {
    private static let key = "app.passcode"
    private static let rounds: UInt32 = 150_000

    static var isSet: Bool { Keychain.load(key) != nil }

    static func set(_ code: String) {
        let salt = randomBytes(16)
        Keychain.save(salt + derive(code, salt: salt), for: key)
    }

    static func verify(_ code: String) -> Bool {
        guard let stored = Keychain.load(key), stored.count == 48 else { return false }
        let salt = stored.prefix(16)
        let expected = stored.suffix(32)
        let actual = derive(code, salt: Data(salt))
        // constant-time comparison
        var diff: UInt8 = 0
        for (a, b) in zip(actual, expected) { diff |= a ^ b }
        return diff == 0
    }

    static func clear() { Keychain.delete(key) }

    private static func derive(_ code: String, salt: Data) -> Data {
        let password = Array(code.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        _ = password.withUnsafeBufferPointer { pw in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                UnsafeRawPointer(pw.baseAddress)?.assumingMemoryBound(to: CChar.self), password.count,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                &out, out.count)
        }
        return Data(out)
    }

    private static func randomBytes(_ n: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes)
    }
}

import Foundation
import CommonCrypto

/// A passcode is never stored: only a salted PBKDF2-SHA256 hash, in the Keychain.
struct PasscodeStore {
    let key: String

    var isSet: Bool { Keychain.load(key) != nil }

    /// Number of digits, so the keypad can unlock as soon as the last one is typed (like iPhone).
    var length: Int { UserDefaults.standard.integer(forKey: key + ".length") }
    func rememberLength(_ n: Int) { UserDefaults.standard.set(n, forKey: key + ".length") }

    func set(_ code: String) {
        let salt = Passcode.randomBytes(16)
        Keychain.save(salt + Passcode.pbkdf2(code, salt: salt), for: key)
        rememberLength(code.count)
    }

    func verify(_ code: String) -> Bool {
        guard let stored = Keychain.load(key), stored.count == 48 else { return false }
        let salt = Data(stored.prefix(16))
        let expected = Data(stored.suffix(32))
        let actual = Passcode.pbkdf2(code, salt: salt)
        var diff: UInt8 = 0
        for (a, b) in zip(actual, expected) { diff |= a ^ b }
        return diff == 0
    }

    func clear() {
        Keychain.delete(key)
        UserDefaults.standard.removeObject(forKey: key + ".length")
    }
}

enum Passcode {
    static let app = PasscodeStore(key: "app.passcode")
    static let vault = PasscodeStore(key: "vault.passcode")

    static func pbkdf2(_ password: String, salt: Data, rounds: UInt32 = 150_000) -> Data {
        let pw = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        _ = pw.withUnsafeBufferPointer { buf in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                UnsafeRawPointer(buf.baseAddress)?.assumingMemoryBound(to: CChar.self), pw.count,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                &out, out.count)
        }
        return Data(out)
    }

    static func randomBytes(_ n: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes)
    }
}

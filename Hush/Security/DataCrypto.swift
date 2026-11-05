import Foundation
import CryptoKit

/// AES-256-GCM encryption for Vault and Files. The key is random, created on first use,
/// and kept in this iPhone's Keychain (never synced, never leaves the device).
enum DataCrypto {
    private static let keyName = "data.key"
    private static var cached: SymmetricKey?

    static var key: SymmetricKey {
        if let cached { return cached }
        if let stored = Keychain.load(keyName), stored.count == 32 {
            let k = SymmetricKey(data: stored)
            cached = k
            return k
        }
        let k = SymmetricKey(size: .bits256)
        Keychain.save(k.withUnsafeBytes { Data($0) }, for: keyName)
        cached = k
        return k
    }

    static func seal(_ data: Data) -> Data { seal(data, key: key) }
    static func open(_ data: Data) -> Data? { open(data, key: key) }

    static func seal(_ data: Data, key: SymmetricKey) -> Data {
        guard let box = try? AES.GCM.seal(data, using: key), let combined = box.combined else { return Data() }
        return combined
    }

    static func open(_ data: Data, key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

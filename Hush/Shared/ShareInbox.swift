import Foundation
import SwiftData
import UniformTypeIdentifiers

/// The share extension can't reach Hush's encryption key, so photos and files it receives wait here,
/// in the private App Group folder, until Hush opens and stores them encrypted.
enum ShareInbox {
    static var folder: URL? {
        AppGroup.containerURL?.appendingPathComponent("Inbox", isDirectory: true)
    }

    static func save(_ data: Data, name: String) {
        guard let dir = folder else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        try? data.write(to: dir.appendingPathComponent(UUID().uuidString + "__" + safe), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    #if !SHARE_EXTENSION
    @MainActor
    static func importPending(into ctx: ModelContext) {
        guard let dir = folder, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil), !files.isEmpty else { return }
        for url in files {
            guard let data = try? Data(contentsOf: url) else { continue }
            let name = url.lastPathComponent.components(separatedBy: "__").dropFirst().joined(separator: "__")
            let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
            ctx.insert(StoredFile(name: name.isEmpty ? url.lastPathComponent : name, typeIdentifier: type, data: data))
            try? FileManager.default.removeItem(at: url)
        }
        try? ctx.save()
    }
    #endif
}

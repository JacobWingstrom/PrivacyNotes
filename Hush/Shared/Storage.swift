import Foundation
import SwiftData

/// The shared App Group lets widgets read Hush's data. AltStore may rename the group when it
/// re-signs the app, so the real name is read from Info.plist ("ALTAppGroups") when present.
enum AppGroup {
    static let baseID = "group.com.jacobwingstrom.hush"

    static let id: String? = {
        var candidates: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { candidates += alt }
        candidates.append(baseID)
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    static var containerURL: URL? { id.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) } }
    static var defaults: UserDefaults { id.flatMap { UserDefaults(suiteName: $0) } ?? .standard }
}

enum Storage {
    static let shared: ModelContainer = makeContainer()

    /// Everything lives in a private folder on this iPhone. iOS encrypts it with your device passcode;
    /// nothing ever leaves the phone, and it's excluded from iCloud backups.
    static func makeContainer() -> ModelContainer {
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Store", isDirectory: true)
        var dir = legacy
        if let group = AppGroup.containerURL {
            let groupDir = group.appendingPathComponent("Library/Application Support/Store", isDirectory: true)
            // One-time move of existing data into the shared container.
            if !fm.fileExists(atPath: groupDir.path), fm.fileExists(atPath: legacy.path) {
                try? fm.createDirectory(at: groupDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.moveItem(at: legacy, to: groupDir)
            }
            dir = groupDir
        }
        let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: protection)
        try? fm.setAttributes(protection, ofItemAtPath: dir.path)

        var excluded = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)

        let config = ModelConfiguration(url: dir.appendingPathComponent("hush.store"), cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: Schema(Models.all), configurations: config)
        } catch {
            fatalError("Hush could not open its storage: \(error)")
        }
    }
}

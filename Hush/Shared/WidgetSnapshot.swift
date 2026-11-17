import Foundation

/// What the Mail, To Review and Headlines widgets show. Written by the app into the shared
/// App Group (file-protected like the rest of Hush's store) because widgets can't download or decrypt mail.
struct WidgetSnapshot: Codable {
    struct Line: Codable, Hashable {
        var title: String
        var detail: String
    }

    var updated: Date
    var unreadMail: Int
    var mail: [Line]
    var reviewCount: Int
    var review: [Line]
    var unreadArticles: Int
    var headlines: [Line]
    var hasMail: Bool
    var hasFeeds: Bool

    static let empty = WidgetSnapshot(updated: .distantPast, unreadMail: 0, mail: [], reviewCount: 0, review: [], unreadArticles: 0,
                                      headlines: [], hasMail: false, hasFeeds: false)

    private static var url: URL? { AppGroup.containerURL?.appendingPathComponent("Library/Application Support/widget-online.json") }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() -> WidgetSnapshot {
        guard let url, let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snap
    }
}

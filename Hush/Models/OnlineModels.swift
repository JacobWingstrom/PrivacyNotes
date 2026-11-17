import Foundation
import SwiftData

// Data that comes from the internet: cached emails and feed articles.
// These stay out of Hush Sync and backups; they can always be downloaded again.

enum OnlineModels {
    static let all: [any PersistentModel.Type] = [MailMessage.self, Feed.self, FeedArticle.self]
}

/// What the message list needs, kept encrypted with this device's key.
struct MailSummary: Codable, Hashable {
    var fromName = ""
    var fromEmail = ""
    var to: [String] = []
    var cc: [String] = []
    var subject = ""
    var snippet = ""
    var inReplyTo = ""
    var references: [String] = []
    var isBulk = false
    var replyTo = ""
}

/// One email cached from an IMAP folder. The full message source is AES-GCM sealed.
@Model
final class MailMessage {
    var id: UUID = UUID()
    var accountID: String = ""
    /// IMAP mailbox path as the server names it.
    var folder: String = ""
    var uid: Int = 0
    var uidValidity: Int = 0
    var date: Date = Date()
    /// IMAP flags separated by spaces, e.g. "\\Seen \\Flagged".
    var flagsRaw: String = ""
    var size: Int = 0
    var messageID: String = ""
    var sealedSummary: Data = Data()
    @Attribute(.externalStorage) var sealedSource: Data? = nil
    var hasAttachments: Bool = false
    var scannedAt: Date? = nil
    var fetchedAt: Date = Date()

    init(accountID: String, folder: String, uid: Int, uidValidity: Int) {
        self.accountID = accountID
        self.folder = folder
        self.uid = uid
        self.uidValidity = uidValidity
    }

    var flags: Set<String> {
        get { Set(flagsRaw.split(separator: " ").map { String($0) }) }
        set { flagsRaw = newValue.sorted().joined(separator: " ") }
    }
    var isSeen: Bool { flags.contains("\\Seen") }
    var isFlagged: Bool { flags.contains("\\Flagged") }
    var isAnswered: Bool { flags.contains("\\Answered") }
    var isDeleted: Bool { flags.contains("\\Deleted") }

    /// "account|folder|uid|message-id" — used to link found items back to this email.
    var reference: String { [accountID, folder, String(uid), messageID].joined(separator: "|") }

    private static var summaryCache: [UUID: (Data, MailSummary)] = [:]

    var summary: MailSummary {
        get {
            if let hit = Self.summaryCache[id], hit.0 == sealedSummary { return hit.1 }
            let value = DataCrypto.open(sealedSummary).flatMap { try? JSONDecoder().decode(MailSummary.self, from: $0) } ?? MailSummary()
            Self.summaryCache[id] = (sealedSummary, value)
            return value
        }
        set {
            sealedSummary = DataCrypto.seal((try? JSONEncoder().encode(newValue)) ?? Data())
        }
    }

    var source: Data? {
        get { sealedSource.flatMap(DataCrypto.open) }
        set { sealedSource = newValue.map(DataCrypto.seal) }
    }

    var senderLabel: String {
        let s = summary
        return s.fromName.isEmpty ? (s.fromEmail.isEmpty ? "Unknown sender" : s.fromEmail) : s.fromName
    }
}

/// An RSS, Atom or Reddit feed you follow.
@Model
final class Feed {
    var id: UUID = UUID()
    var title: String = ""
    var urlString: String = ""
    var siteURL: String = ""
    var folder: String = ""
    /// "rss" or "reddit".
    var kindRaw: String = "rss"
    var lastFetched: Date? = nil
    var etag: String = ""
    var lastModified: String = ""
    var errorText: String = ""
    var loadImages: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    init(url: String) { urlString = url }

    var isReddit: Bool { kindRaw == "reddit" }
    var displayTitle: String {
        if !title.isEmpty { return title }
        return URL(string: urlString)?.host() ?? urlString
    }
}

@Model
final class FeedArticle {
    var id: UUID = UUID()
    var feedID: UUID = UUID()
    var guid: String = ""
    var title: String = ""
    var link: String = ""
    var author: String = ""
    var published: Date = Date()
    var summaryHTML: String = ""
    var contentHTML: String = ""
    var imageURL: String = ""
    var isRead: Bool = false
    var isStarred: Bool = false
    /// Clean article text saved for reading offline.
    var savedHTML: String = ""
    var fetchedAt: Date = Date()

    init(feedID: UUID, guid: String) {
        self.feedID = feedID
        self.guid = guid
    }

    var bodyHTML: String {
        if !savedHTML.isEmpty { return savedHTML }
        return contentHTML.count >= summaryHTML.count ? contentHTML : summaryHTML
    }
}

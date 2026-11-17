import Foundation

/// An email account. Settings live in UserDefaults; the password lives only in the Keychain.
struct MailAccount: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name = ""
    var displayName = ""
    var email = ""
    var username = ""
    var preset = "mailboxorg"

    var imapHost = "imap.mailbox.org"
    var imapPort = 993
    var imapSecurity = MailSecurity.tls
    var smtpHost = "smtp.mailbox.org"
    var smtpPort = 465
    var smtpSecurity = MailSecurity.tls

    var signature = ""
    var notify = true
    var scanEnabled = true
    /// Space that found and synced items go into ("" = Personal).
    var spaceID = ""
    var connectedAt = Date()

    // Calendars, contacts and tasks (CalDAV / CardDAV)
    var davEnabled = true
    var caldavURL = "https://dav.mailbox.org/caldav/"
    var carddavURL = "https://dav.mailbox.org/carddav/"
    /// Hush items created after this date are uploaded to the account's default calendar, task list or address book.
    var davUploadFrom = Date()
    var davDefaultCalendar = ""
    var davDefaultTaskList = ""
    var davDefaultAddressBook = ""
    var davDisabledCollections: [String] = []

    /// How many recent messages per folder to keep on the device.
    var keepRecent = 300

    init() {}

    var label: String { name.isEmpty ? email : name }
    var fromAddress: MailAddress { MailAddress(name: displayName, email: email) }
    var targetSpace: String { spaceID.isEmpty ? Spaces.defaultID : spaceID }

    static func mailboxOrg(email: String) -> MailAccount {
        var a = MailAccount()
        a.preset = "mailboxorg"
        a.name = "mailbox.org"
        a.email = email
        a.username = email
        return a
    }

    static func custom(email: String) -> MailAccount {
        var a = MailAccount()
        a.preset = "custom"
        a.email = email
        a.username = email
        let domain = email.split(separator: "@").last.map(String.init) ?? ""
        a.name = domain
        a.imapHost = domain.isEmpty ? "" : "imap.\(domain)"
        a.smtpHost = domain.isEmpty ? "" : "smtp.\(domain)"
        a.smtpPort = 465
        a.caldavURL = domain.isEmpty ? "" : "https://\(domain)/.well-known/caldav"
        a.carddavURL = domain.isEmpty ? "" : "https://\(domain)/.well-known/carddav"
        a.davEnabled = false
        return a
    }

    // Tolerant decoding: settings added in later versions fall back to their defaults.
    enum CodingKeys: String, CodingKey {
        case id, name, displayName, email, username, preset, imapHost, imapPort, imapSecurity, smtpHost, smtpPort, smtpSecurity
        case signature, notify, scanEnabled, spaceID, connectedAt, davEnabled, caldavURL, carddavURL, davUploadFrom
        case davDefaultCalendar, davDefaultTaskList, davDefaultAddressBook, davDisabledCollections, keepRecent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MailAccount()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil ?? fallback }
        id = v(.id, d.id); name = v(.name, d.name); displayName = v(.displayName, d.displayName)
        email = v(.email, d.email); username = v(.username, d.username); preset = v(.preset, d.preset)
        imapHost = v(.imapHost, d.imapHost); imapPort = v(.imapPort, d.imapPort); imapSecurity = v(.imapSecurity, d.imapSecurity)
        smtpHost = v(.smtpHost, d.smtpHost); smtpPort = v(.smtpPort, d.smtpPort); smtpSecurity = v(.smtpSecurity, d.smtpSecurity)
        signature = v(.signature, d.signature); notify = v(.notify, d.notify); scanEnabled = v(.scanEnabled, d.scanEnabled)
        spaceID = v(.spaceID, d.spaceID); connectedAt = v(.connectedAt, d.connectedAt)
        davEnabled = v(.davEnabled, d.davEnabled); caldavURL = v(.caldavURL, d.caldavURL); carddavURL = v(.carddavURL, d.carddavURL)
        davUploadFrom = v(.davUploadFrom, d.davUploadFrom)
        davDefaultCalendar = v(.davDefaultCalendar, d.davDefaultCalendar); davDefaultTaskList = v(.davDefaultTaskList, d.davDefaultTaskList)
        davDefaultAddressBook = v(.davDefaultAddressBook, d.davDefaultAddressBook)
        davDisabledCollections = v(.davDisabledCollections, d.davDisabledCollections)
        keepRecent = v(.keepRecent, d.keepRecent)
    }
}

enum MailAccounts {
    private static let key = "mailAccounts"

    static func load() -> [MailAccount] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MailAccount].self, from: data)) ?? []
    }

    static func save(_ accounts: [MailAccount]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: key)
    }

    static func password(for id: String) -> String? {
        Keychain.load("mail.\(id)").flatMap { String(data: $0, encoding: .utf8) }
    }

    static func setPassword(_ password: String, for id: String) {
        Keychain.save(Data(password.utf8), for: "mail.\(id)")
    }

    static func deletePassword(for id: String) { Keychain.delete("mail.\(id)") }

    static var anyConfigured: Bool { !load().isEmpty }
}

/// Folders and sync bookmarks per account, kept between launches.
struct MailFolderState: Codable {
    var folders: [IMAPFolder] = []
    /// path → UIDVALIDITY seen last time
    var uidValidity: [String: Int] = [:]
    /// path → highest UID downloaded
    var highestUID: [String: Int] = [:]
    /// path → how many messages to keep (grows when you load older mail)
    var keepCount: [String: Int] = [:]
    var lastSync: Date?
    var lastError: String?

    private static func key(_ id: String) -> String { "mailState.\(id)" }

    static func load(_ id: String) -> MailFolderState {
        guard let d = UserDefaults.standard.data(forKey: key(id)) else { return MailFolderState() }
        return (try? JSONDecoder().decode(MailFolderState.self, from: d)) ?? MailFolderState()
    }

    func save(_ id: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key(id))
    }

    static func remove(_ id: String) { UserDefaults.standard.removeObject(forKey: key(id)) }

    func folder(role: String) -> IMAPFolder? { folders.first { $0.role == role } }
}

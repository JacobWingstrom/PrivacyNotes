import Foundation

/// Your own rule: "emails from school@… become tasks in the School list".
struct ScanRule: Codable, Identifiable, Hashable {
    enum Field: String, Codable, CaseIterable { case from, subject, body, any }
    enum Action: String, Codable, CaseIterable { case task, event, contact, trust, ignore }

    var id = UUID()
    var enabled = true
    var field = Field.from
    var contains = ""
    var action = Action.task
    var taskList = ""
    /// For tasks without a date in the email: due this many days after it arrives (-1 = no due date).
    var dueInDays = -1
    var autoConfirm = false

    var summary: String {
        let what: String
        switch field {
        case .from: what = "From contains “\(contains)”"
        case .subject: what = "Subject contains “\(contains)”"
        case .body: what = "Text contains “\(contains)”"
        case .any: what = "Email contains “\(contains)”"
        }
        let action: String
        switch self.action {
        case .task: action = "make a task" + (taskList.isEmpty ? "" : " in \(taskList)")
        case .event: action = "make an event"
        case .contact: action = "suggest the sender as a contact"
        case .trust: action = "add found items without asking"
        case .ignore: action = "ignore"
        }
        return "\(what) → \(action)"
    }

    func matches(from: String, subject: String, body: String) -> Bool {
        let needle = contains.trimmed
        guard enabled, !needle.isEmpty else { return false }
        switch field {
        case .from: return from.localizedCaseInsensitiveContains(needle)
        case .subject: return subject.localizedCaseInsensitiveContains(needle)
        case .body: return body.localizedCaseInsensitiveContains(needle)
        case .any: return from.localizedCaseInsensitiveContains(needle) || subject.localizedCaseInsensitiveContains(needle) || body.localizedCaseInsensitiveContains(needle)
        }
    }
}

enum ScanPrefs {
    static let autoInvitesKey = "scanAutoInvites"
    static let autoReservationsKey = "scanAutoReservations"
    static let detectKey = "scanDetectDates"
    static let contactsKey = "scanSuggestContacts"
    static let recipientsKey = "scanContactsFromSent"
    static let lookbackKey = "scanLookbackDays"
    private static let trustedKey = "scanTrustedSenders"
    private static let rulesKey = "scanRules"
    private static let dismissedKey = "scanDismissed"

    private static var d: UserDefaults { .standard }
    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }

    static var autoConfirmInvites: Bool { bool(autoInvitesKey, true) }
    static var autoConfirmReservations: Bool { bool(autoReservationsKey, true) }
    static var detectDates: Bool { bool(detectKey, true) }
    static var suggestContacts: Bool { bool(contactsKey, true) }
    static var contactsFromSent: Bool { bool(recipientsKey, true) }
    static var lookbackDays: Int { d.object(forKey: lookbackKey) as? Int ?? 14 }

    static var trustedSenders: [String] {
        get { d.stringArray(forKey: trustedKey) ?? [] }
        set { d.set(newValue.map { $0.lowercased().trimmed }.filter { !$0.isEmpty }, forKey: trustedKey) }
    }

    static func isTrusted(_ email: String) -> Bool {
        let e = email.lowercased()
        guard let domain = e.split(separator: "@").last else { return false }
        return trustedSenders.contains { t in t == e || t == "@" + domain || t == String(domain) }
    }

    static func trust(_ email: String) {
        var list = trustedSenders
        if !list.contains(email.lowercased()) { list.append(email.lowercased()) }
        trustedSenders = list
    }

    static var rules: [ScanRule] {
        get { d.data(forKey: rulesKey).flatMap { try? JSONDecoder().decode([ScanRule].self, from: $0) } ?? [] }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: rulesKey) }
    }

    /// Suggestions you dismissed, so they aren't suggested again.
    static func isDismissed(_ key: String) -> Bool { (d.stringArray(forKey: dismissedKey) ?? []).contains(key) }
    static func dismiss(_ key: String) {
        var list = d.stringArray(forKey: dismissedKey) ?? []
        list.append(key)
        if list.count > 4000 { list.removeFirst(list.count - 4000) }
        d.set(list, forKey: dismissedKey)
    }
}

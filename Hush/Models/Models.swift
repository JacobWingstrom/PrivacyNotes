import SwiftUI
import SwiftData

// MARK: - Shared value types

struct Subtask: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var done = false
}

struct LabeledValue: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var value: String
}

enum RepeatRule: String, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Never"
        case .daily: "Every Day"
        case .weekdays: "Weekdays"
        case .weekly: "Every Week"
        case .monthly: "Every Month"
        case .yearly: "Every Year"
        }
    }
    func next(after date: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .none: return nil
        case .daily: return cal.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var d = cal.date(byAdding: .day, value: 1, to: date) ?? date
            while cal.isDateInWeekend(d) { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return d
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        case .yearly: return cal.date(byAdding: .year, value: 1, to: date)
        }
    }
}

enum Priority: Int, CaseIterable, Identifiable {
    case none = 0, low, medium, high
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
    var color: Color? {
        switch self {
        case .none: nil
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}

enum Mood: Int, CaseIterable, Identifiable {
    case none = 0, awful, low, okay, good, great
    var id: Int { rawValue }
    var emoji: String {
        switch self {
        case .none: ""
        case .awful: "😞"
        case .low: "😕"
        case .okay: "😐"
        case .good: "🙂"
        case .great: "😄"
        }
    }
    var label: String {
        switch self {
        case .none: "None"
        case .awful: "Awful"
        case .low: "Low"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }
}

enum JSONField {
    static func decode<T: Decodable>(_ data: Data, as type: T.Type) -> T? {
        data.isEmpty ? nil : try? JSONDecoder().decode(T.self, from: data)
    }
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}

// MARK: - Tasks

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var isDone: Bool = false
    var dueDate: Date? = nil
    var hasDueTime: Bool = false
    var remind: Bool = false
    var priorityRaw: Int = 0
    var repeatRaw: String = "none"
    var subtasksData: Data = Data()
    var list: String = ""
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    init(title: String = "") { self.title = title }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRaw) ?? .none }
        set { repeatRaw = newValue.rawValue }
    }
    var subtasks: [Subtask] {
        get { JSONField.decode(subtasksData, as: [Subtask].self) ?? [] }
        set { subtasksData = JSONField.encode(newValue) }
    }

    var isOverdue: Bool {
        guard !isDone, let d = dueDate else { return false }
        return hasDueTime ? d < .now : d < Calendar.current.startOfDay(for: .now)
    }

    func reminderDate(defaultMinutes: Int) -> Date? {
        guard remind, !isDone, let d = dueDate else { return nil }
        if hasDueTime { return d }
        return Calendar.current.startOfDay(for: d).addingTimeInterval(Double(defaultMinutes * 60))
    }

    static func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            if a.priorityRaw != b.priorityRaw { return a.priorityRaw > b.priorityRaw }
            return a.createdAt > b.createdAt
        }
    }
}

// MARK: - Calendar events

@Model
final class CalendarEvent {
    var id: UUID = UUID()
    var title: String = ""
    var start: Date = Date()
    var end: Date = Date().addingTimeInterval(3600)
    var isAllDay: Bool = false
    var location: String = ""
    var notes: String = ""
    var colorName: String = "none"
    /// Minutes before the start to remind; -1 means no reminder.
    var alertMinutes: Int = -1
    var createdAt: Date = Date()

    init(start: Date = Date()) {
        self.start = start
        self.end = start.addingTimeInterval(3600)
    }

    var color: Color? { NoteColor(rawValue: colorName)?.color }

    func occurs(on day: Date) -> Bool {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = dayStart.addingTimeInterval(86400)
        return start < dayEnd && max(end, start.addingTimeInterval(1)) > dayStart
    }
}

// MARK: - Journal

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var body: String = ""
    var moodRaw: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(date: Date = Date()) { self.date = date }

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .none }
        set { moodRaw = newValue.rawValue }
    }
    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && moodRaw == 0
    }
}

// MARK: - Drawings

@Model
final class Drawing {
    var id: UUID = UUID()
    var title: String = "Untitled Drawing"
    @Attribute(.externalStorage) var data: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

// MARK: - Vault (contents are AES-GCM encrypted)

struct VaultMeta: Codable, Hashable {
    var title: String = ""
    var body: String = ""
    var username: String = ""
    var password: String = ""
    var url: String = ""
}

enum VaultKind: String, CaseIterable, Identifiable {
    case note, login, photo
    var id: String { rawValue }
    var label: String {
        switch self {
        case .note: "Secure Note"
        case .login: "Login"
        case .photo: "Photo"
        }
    }
    var symbol: String {
        switch self {
        case .note: "doc.text"
        case .login: "key"
        case .photo: "photo"
        }
    }
}

@Model
final class VaultItem {
    var id: UUID = UUID()
    var kindRaw: String = "note"
    var sealedMeta: Data = Data()
    @Attribute(.externalStorage) var sealedImage: Data? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(kind: VaultKind) { kindRaw = kind.rawValue }

    var kind: VaultKind { VaultKind(rawValue: kindRaw) ?? .note }

    var meta: VaultMeta {
        get { DataCrypto.open(sealedMeta).flatMap { JSONField.decode($0, as: VaultMeta.self) } ?? VaultMeta() }
        set { sealedMeta = DataCrypto.seal(JSONField.encode(newValue)); updatedAt = .now }
    }

    var imageData: Data? {
        get { sealedImage.flatMap(DataCrypto.open) }
        set { sealedImage = newValue.map(DataCrypto.seal) }
    }
}

// MARK: - Files (contents are AES-GCM encrypted)

@Model
final class StoredFile {
    var id: UUID = UUID()
    var name: String = ""
    var typeIdentifier: String = ""
    var size: Int = 0
    @Attribute(.externalStorage) var sealedData: Data = Data()
    var createdAt: Date = Date()

    init(name: String, typeIdentifier: String, data: Data) {
        self.name = name
        self.typeIdentifier = typeIdentifier
        self.size = data.count
        self.sealedData = DataCrypto.seal(data)
    }
}

// MARK: - Contacts

@Model
final class Contact {
    var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var company: String = ""
    var phonesData: Data = Data()
    var emailsData: Data = Data()
    var address: String = ""
    var birthday: Date? = nil
    var birthdayReminder: Bool = false
    var notes: String = ""
    var emoji: String = ""
    var isFavorite: Bool = false
    var createdAt: Date = Date()

    init() {}

    var phones: [LabeledValue] {
        get { JSONField.decode(phonesData, as: [LabeledValue].self) ?? [] }
        set { phonesData = JSONField.encode(newValue) }
    }
    var emails: [LabeledValue] {
        get { JSONField.decode(emailsData, as: [LabeledValue].self) ?? [] }
        set { emailsData = JSONField.encode(newValue) }
    }

    var displayName: String {
        let n = [firstName, lastName].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        if !n.isEmpty { return n }
        return company.isEmpty ? "No Name" : company
    }
    var initials: String {
        let parts = [firstName, lastName].compactMap { $0.trimmingCharacters(in: .whitespaces).first }
        if !parts.isEmpty { return String(parts) .uppercased() }
        return String(displayName.prefix(1)).uppercased()
    }
    var sortKey: String { (lastName.isEmpty ? displayName : lastName + " " + firstName).lowercased() }
    var isEmpty: Bool { firstName.isEmpty && lastName.isEmpty && company.isEmpty && phones.isEmpty && emails.isEmpty }
}

// MARK: - Bookmarks

@Model
final class Bookmark {
    var id: UUID = UUID()
    var title: String = ""
    var urlString: String = ""
    var notes: String = ""
    var tags: [String] = []
    var isFavorite: Bool = false
    var createdAt: Date = Date()

    init() {}

    var url: URL? { URL(string: urlString) }
    var host: String { url?.host() ?? urlString }
    var displayTitle: String { title.isEmpty ? host : title }

    static func normalize(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }
        return s.contains("://") ? s : "https://" + s
    }
}

enum Models {
    static let all: [any PersistentModel.Type] = [
        Note.self, TaskItem.self, CalendarEvent.self, JournalEntry.self, Drawing.self,
        VaultItem.self, StoredFile.self, Contact.self, Bookmark.self,
    ]
}

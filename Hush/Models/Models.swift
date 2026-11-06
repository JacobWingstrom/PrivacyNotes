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

    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(title: String = "") { self.title = title; spaceID = Spaces.newItemSpace }

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

    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(start: Date = Date()) {
        self.start = start
        self.end = start.addingTimeInterval(3600)
        spaceID = Spaces.newItemSpace
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

    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(date: Date = Date()) { self.date = date; spaceID = Spaces.newItemSpace }

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
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init() { spaceID = Spaces.newItemSpace }
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
    /// Set when the file is attached to a note.
    var noteID: UUID? = nil
    /// Text recognized in scans, used for search.
    var searchText: String = ""
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(name: String, typeIdentifier: String, data: Data, noteID: UUID? = nil) {
        self.name = name
        self.typeIdentifier = typeIdentifier
        self.size = data.count
        self.sealedData = DataCrypto.seal(data)
        self.noteID = noteID
        spaceID = Spaces.newItemSpace
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
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init() { spaceID = Spaces.newItemSpace }

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
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init() { spaceID = Spaces.newItemSpace }

    var url: URL? { URL(string: urlString) }
    var host: String { url?.host() ?? urlString }
    var displayTitle: String { title.isEmpty ? host : title }

    static func normalize(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }
        return s.contains("://") ? s : "https://" + s
    }
}

// MARK: - Folders (nested, for notes)

@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var parentID: UUID? = nil
    var emoji: String = ""
    var createdAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(name: String, parentID: UUID? = nil) {
        self.name = name
        self.parentID = parentID
        spaceID = Spaces.newItemSpace
    }
}

// MARK: - Note history

@Model
final class NoteVersion {
    var id: UUID = UUID()
    var noteID: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var savedAt: Date = Date()

    init(noteID: UUID, title: String, body: String) {
        self.noteID = noteID
        self.title = title
        self.body = body
    }
}

// MARK: - Your own note templates

@Model
final class NoteTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = ""
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date()

    init(name: String, emoji: String, title: String, body: String) {
        self.name = name
        self.emoji = emoji
        self.title = title
        self.body = body
    }
}

// MARK: - Habits

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "checkmark.circle"
    var colorName: String = "none"
    var target: Int = 1
    /// Weekdays (1 = Sunday … 7 = Saturday). Empty means every day.
    var daysData: Data = Data()
    var remind: Bool = false
    var reminderMinutes: Int = 540
    /// Completions per day, keyed "yyyy-MM-dd".
    var logData: Data = Data()
    var archived: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(name: String = "") {
        self.name = name
        spaceID = Spaces.newItemSpace
    }

    var days: [Int] {
        get { JSONField.decode(daysData, as: [Int].self) ?? [] }
        set { daysData = JSONField.encode(newValue.sorted()) }
    }
    var log: [String: Int] {
        get { JSONField.decode(logData, as: [String: Int].self) ?? [:] }
        set { logData = JSONField.encode(newValue) }
    }
    var color: Color? { NoteColor(rawValue: colorName)?.color }

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func count(on date: Date) -> Int { log[Self.key(date)] ?? 0 }
    func isDone(on date: Date) -> Bool { count(on: date) >= max(target, 1) }
    func isScheduled(on date: Date) -> Bool {
        days.isEmpty || days.contains(Calendar.current.component(.weekday, from: date))
    }

    /// One more completion; wraps back to zero once the target is reached.
    func tap(on date: Date) {
        var l = log
        let k = Self.key(date)
        let c = l[k] ?? 0
        l[k] = c >= max(target, 1) ? 0 : c + 1
        if l[k] == 0 { l.removeValue(forKey: k) }
        log = l
    }

    func setDone(_ done: Bool, on date: Date) {
        var l = log
        l[Self.key(date)] = done ? max(target, 1) : nil
        log = l
    }

    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if !isDone(on: day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        let earliest = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: createdAt)) ?? createdAt
        var n = 0
        var steps = 0
        while steps < 3660 && day >= earliest {
            if isScheduled(on: day) {
                if isDone(on: day) { n += 1 } else { break }
            }
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
            steps += 1
        }
        return n
    }

    var bestStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: createdAt)
        let today = cal.startOfDay(for: .now)
        var best = 0, run = 0, steps = 0
        while day <= today && steps < 3660 {
            if isScheduled(on: day) {
                if isDone(on: day) { run += 1; best = max(best, run) } else if day < today { run = 0 }
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? today.addingTimeInterval(1)
            steps += 1
        }
        return best
    }

    /// Share of scheduled days completed over the last `n` days.
    func completionRate(lastDays n: Int) -> Double {
        let cal = Calendar.current
        var scheduled = 0, done = 0
        for i in 0..<n {
            guard let d = cal.date(byAdding: .day, value: -i, to: .now), d >= cal.startOfDay(for: createdAt) else { continue }
            if isScheduled(on: d) {
                scheduled += 1
                if isDone(on: d) { done += 1 }
            }
        }
        return scheduled == 0 ? 0 : Double(done) / Double(scheduled)
    }
}

// MARK: - Spaces & Trash

enum Spaces {
    static let defaultID = "personal"
    static let currentKey = "currentSpace"
    /// New items go into the space you're viewing (or Personal when viewing all spaces).
    static var newItemSpace: String {
        let current = UserDefaults.standard.string(forKey: currentKey) ?? "all"
        return current == "all" ? defaultID : current
    }
}

/// Everything that can live in a Space and go to the Trash.
protocol HushItem: AnyObject {
    var spaceID: String { get set }
    var deletedAt: Date? { get set }
}

extension HushItem {
    var isTrashed: Bool { deletedAt != nil }
    var spaceKey: String { spaceID.isEmpty ? Spaces.defaultID : spaceID }
    func inSpace(_ space: String?) -> Bool { space == nil || spaceKey == space }
}

extension Array where Element: HushItem {
    /// Items not in the Trash and in the given space (nil = all spaces).
    func live(_ space: String?) -> [Element] { filter { $0.deletedAt == nil && $0.inSpace(space) } }
    var trashed: [Element] { filter { $0.deletedAt != nil } }
}

extension Note: HushItem {}
extension TaskItem: HushItem {}
extension CalendarEvent: HushItem {}
extension JournalEntry: HushItem {}
extension Drawing: HushItem {}
extension StoredFile: HushItem {}
extension Contact: HushItem {}
extension Bookmark: HushItem {}
extension Folder: HushItem {}
extension Habit: HushItem {}

/// Strips Markdown symbols for previews and widgets.
enum Markdown {
    static func plain(_ s: String) -> String {
        var t = s
        for (pattern, template) in [
            ("(?m)^#{1,6}\\s+", ""), ("\\*\\*(.+?)\\*\\*", "$1"), ("~~(.+?)~~", "$1"),
            ("(?<![\\w*])\\*(?!\\s)(.+?)\\*", "$1"), ("`([^`]+)`", "$1"),
            ("\\[\\[([^\\]]+)\\]\\]", "$1"), ("\\[([^\\]]+)\\]\\([^)]+\\)", "$1"),
            ("(?m)^\\s*[-*+]\\s\\[[ xX]\\]\\s", "☐ "), ("(?m)^>\\s?", ""),
        ] {
            t = t.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return t
    }
}

enum Models {
    static let all: [any PersistentModel.Type] = [
        Note.self, TaskItem.self, CalendarEvent.self, JournalEntry.self, Drawing.self,
        VaultItem.self, StoredFile.self, Contact.self, Bookmark.self,
        Folder.self, NoteVersion.self, NoteTemplate.self, Habit.self,
    ] + HomelabModels.all + BoardModels.all
}

/// Item icons are SF Symbol names. Older emoji values fall back to a default symbol.
enum SymbolName {
    static func isValid(_ name: String) -> Bool { !name.isEmpty && UIImage(systemName: name) != nil }
    static func resolve(_ name: String, fallback: String) -> String { isValid(name) ? name : fallback }
}

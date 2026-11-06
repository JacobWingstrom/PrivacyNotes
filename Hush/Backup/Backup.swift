import SwiftUI
import SwiftData
import CryptoKit
import UniformTypeIdentifiers

/// Backup file: "HUSHBK1" + 16-byte salt + AES-256-GCM(JSON), key = PBKDF2(password, salt).
enum Backup {
    private static let magic = Data("HUSHBK1".utf8)
    private static let rounds: UInt32 = 300_000

    struct Payload: Codable {
        var version = 1
        var createdAt = Date()
        var notes: [NoteDTO] = []
        var tasks: [TaskDTO] = []
        var events: [EventDTO] = []
        var journals: [JournalDTO] = []
        var drawings: [DrawingDTO] = []
        var contacts: [ContactDTO] = []
        var bookmarks: [BookmarkDTO] = []
        var files: [FileDTO] = []
        var vault: [VaultDTO] = []

        var count: Int {
            notes.count + tasks.count + events.count + journals.count + drawings.count
                + contacts.count + bookmarks.count + files.count + vault.count
        }
    }

    struct NoteDTO: Codable {
        var id: UUID, title: String, body: String, isPinned: Bool, colorName: String, emoji: String, tags: [String], createdAt: Date, updatedAt: Date
        var isLocked: Bool? = nil
        var lockedText: String? = nil
        var wordGoal: Int? = nil
        var folderID: UUID? = nil
    }
    struct TaskDTO: Codable {
        var id: UUID, title: String, notes: String, isDone: Bool, dueDate: Date?, hasDueTime: Bool, remind: Bool
        var priorityRaw: Int, repeatRaw: String, subtasks: [Subtask], list: String, createdAt: Date, completedAt: Date?
    }
    struct EventDTO: Codable {
        var id: UUID, title: String, start: Date, end: Date, isAllDay: Bool, location: String, notes: String, colorName: String, alertMinutes: Int, createdAt: Date
    }
    struct JournalDTO: Codable {
        var id: UUID, date: Date, title: String, body: String, moodRaw: Int, createdAt: Date, updatedAt: Date
    }
    struct DrawingDTO: Codable {
        var id: UUID, title: String, data: Data, createdAt: Date, updatedAt: Date
    }
    struct ContactDTO: Codable {
        var id: UUID, firstName: String, lastName: String, company: String, phones: [LabeledValue], emails: [LabeledValue]
        var address: String, birthday: Date?, birthdayReminder: Bool, notes: String, emoji: String, isFavorite: Bool, createdAt: Date
    }
    struct BookmarkDTO: Codable {
        var id: UUID, title: String, urlString: String, notes: String, tags: [String], isFavorite: Bool, createdAt: Date
    }
    struct FileDTO: Codable {
        var id: UUID, name: String, typeIdentifier: String, data: Data, createdAt: Date
    }
    struct VaultDTO: Codable {
        var id: UUID, kindRaw: String, meta: VaultMeta, image: Data?, createdAt: Date, updatedAt: Date
    }

    enum BackupError: LocalizedError {
        case notABackup, wrongPassword
        var errorDescription: String? {
            switch self {
            case .notABackup: "This file isn't a Hush backup."
            case .wrongPassword: "Wrong password, or the file is damaged."
            }
        }
    }

    // MARK: Export

    static func makePayload(_ ctx: ModelContext, includeVault: Bool) throws -> Payload {
        var p = Payload()
        p.notes = try ctx.fetch(FetchDescriptor<Note>()).map {
            NoteDTO(id: $0.id, title: $0.title, body: $0.body, isPinned: $0.isPinned, colorName: $0.colorName, emoji: $0.emoji, tags: $0.tags, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                    isLocked: $0.isLocked, lockedText: $0.isLocked ? NoteLock.read($0) : nil, wordGoal: $0.wordGoal, folderID: $0.folderID)
        }
        p.tasks = try ctx.fetch(FetchDescriptor<TaskItem>()).map {
            TaskDTO(id: $0.id, title: $0.title, notes: $0.notes, isDone: $0.isDone, dueDate: $0.dueDate, hasDueTime: $0.hasDueTime, remind: $0.remind,
                    priorityRaw: $0.priorityRaw, repeatRaw: $0.repeatRaw, subtasks: $0.subtasks, list: $0.list, createdAt: $0.createdAt, completedAt: $0.completedAt)
        }
        p.events = try ctx.fetch(FetchDescriptor<CalendarEvent>()).map {
            EventDTO(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay, location: $0.location, notes: $0.notes, colorName: $0.colorName, alertMinutes: $0.alertMinutes, createdAt: $0.createdAt)
        }
        p.journals = try ctx.fetch(FetchDescriptor<JournalEntry>()).map {
            JournalDTO(id: $0.id, date: $0.date, title: $0.title, body: $0.body, moodRaw: $0.moodRaw, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
        p.drawings = try ctx.fetch(FetchDescriptor<Drawing>()).map {
            DrawingDTO(id: $0.id, title: $0.title, data: $0.data, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
        p.contacts = try ctx.fetch(FetchDescriptor<Contact>()).map {
            ContactDTO(id: $0.id, firstName: $0.firstName, lastName: $0.lastName, company: $0.company, phones: $0.phones, emails: $0.emails,
                       address: $0.address, birthday: $0.birthday, birthdayReminder: $0.birthdayReminder, notes: $0.notes, emoji: $0.emoji, isFavorite: $0.isFavorite, createdAt: $0.createdAt)
        }
        p.bookmarks = try ctx.fetch(FetchDescriptor<Bookmark>()).map {
            BookmarkDTO(id: $0.id, title: $0.title, urlString: $0.urlString, notes: $0.notes, tags: $0.tags, isFavorite: $0.isFavorite, createdAt: $0.createdAt)
        }
        p.files = try ctx.fetch(FetchDescriptor<StoredFile>()).compactMap { f in
            DataCrypto.open(f.sealedData).map { FileDTO(id: f.id, name: f.name, typeIdentifier: f.typeIdentifier, data: $0, createdAt: f.createdAt) }
        }
        if includeVault {
            p.vault = try ctx.fetch(FetchDescriptor<VaultItem>()).map {
                VaultDTO(id: $0.id, kindRaw: $0.kindRaw, meta: $0.meta, image: $0.imageData, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            }
        }
        return p
    }

    static func export(_ ctx: ModelContext, password: String, includeVault: Bool) throws -> URL {
        let json = try JSONEncoder().encode(makePayload(ctx, includeVault: includeVault))
        let salt = Passcode.randomBytes(16)
        let key = SymmetricKey(data: Passcode.pbkdf2(password, salt: salt, rounds: rounds))
        let sealed = DataCrypto.seal(json, key: key)
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Hush Backup \(stamp).hushbackup")
        try (magic + salt + sealed).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    // MARK: Import

    static func read(_ data: Data, password: String) throws -> Payload {
        guard data.count > magic.count + 16, data.prefix(magic.count) == magic else { throw BackupError.notABackup }
        let salt = data.subdata(in: magic.count..<(magic.count + 16))
        let body = data.subdata(in: (magic.count + 16)..<data.count)
        let key = SymmetricKey(data: Passcode.pbkdf2(password, salt: salt, rounds: rounds))
        guard let json = DataCrypto.open(body, key: key) else { throw BackupError.wrongPassword }
        return try JSONDecoder().decode(Payload.self, from: json)
    }

    /// Adds everything from the backup that isn't already here (matched by ID). Returns the number of items added.
    static func restore(_ p: Payload, into ctx: ModelContext) throws -> Int {
        var added = 0
        let noteIDs = Set(try ctx.fetch(FetchDescriptor<Note>()).map(\.id))
        for d in p.notes where !noteIDs.contains(d.id) {
            let n = Note()
            n.id = d.id; n.title = d.title; n.body = d.body; n.isPinned = d.isPinned; n.colorName = d.colorName
            n.emoji = d.emoji; n.tags = d.tags; n.createdAt = d.createdAt; n.updatedAt = d.updatedAt
            n.wordGoal = d.wordGoal ?? 0; n.folderID = d.folderID
            if d.isLocked == true, let text = d.lockedText { NoteLock.lock(n, text: text) }
            ctx.insert(n); added += 1
        }
        let taskIDs = Set(try ctx.fetch(FetchDescriptor<TaskItem>()).map(\.id))
        for d in p.tasks where !taskIDs.contains(d.id) {
            let t = TaskItem(title: d.title)
            t.id = d.id; t.notes = d.notes; t.isDone = d.isDone; t.dueDate = d.dueDate; t.hasDueTime = d.hasDueTime
            t.remind = d.remind; t.priorityRaw = d.priorityRaw; t.repeatRaw = d.repeatRaw; t.subtasks = d.subtasks
            t.list = d.list; t.createdAt = d.createdAt; t.completedAt = d.completedAt
            ctx.insert(t); Reminders.sync(t); added += 1
        }
        let eventIDs = Set(try ctx.fetch(FetchDescriptor<CalendarEvent>()).map(\.id))
        for d in p.events where !eventIDs.contains(d.id) {
            let e = CalendarEvent(start: d.start)
            e.id = d.id; e.title = d.title; e.end = d.end; e.isAllDay = d.isAllDay; e.location = d.location
            e.notes = d.notes; e.colorName = d.colorName; e.alertMinutes = d.alertMinutes; e.createdAt = d.createdAt
            ctx.insert(e); Reminders.sync(e); added += 1
        }
        let journalIDs = Set(try ctx.fetch(FetchDescriptor<JournalEntry>()).map(\.id))
        for d in p.journals where !journalIDs.contains(d.id) {
            let j = JournalEntry(date: d.date)
            j.id = d.id; j.title = d.title; j.body = d.body; j.moodRaw = d.moodRaw; j.createdAt = d.createdAt; j.updatedAt = d.updatedAt
            ctx.insert(j); added += 1
        }
        let drawingIDs = Set(try ctx.fetch(FetchDescriptor<Drawing>()).map(\.id))
        for d in p.drawings where !drawingIDs.contains(d.id) {
            let x = Drawing()
            x.id = d.id; x.title = d.title; x.data = d.data; x.createdAt = d.createdAt; x.updatedAt = d.updatedAt
            ctx.insert(x); added += 1
        }
        let contactIDs = Set(try ctx.fetch(FetchDescriptor<Contact>()).map(\.id))
        for d in p.contacts where !contactIDs.contains(d.id) {
            let c = Contact()
            c.id = d.id; c.firstName = d.firstName; c.lastName = d.lastName; c.company = d.company; c.phones = d.phones
            c.emails = d.emails; c.address = d.address; c.birthday = d.birthday; c.birthdayReminder = d.birthdayReminder
            c.notes = d.notes; c.emoji = d.emoji; c.isFavorite = d.isFavorite; c.createdAt = d.createdAt
            ctx.insert(c); Reminders.sync(c); added += 1
        }
        let bookmarkIDs = Set(try ctx.fetch(FetchDescriptor<Bookmark>()).map(\.id))
        for d in p.bookmarks where !bookmarkIDs.contains(d.id) {
            let b = Bookmark()
            b.id = d.id; b.title = d.title; b.urlString = d.urlString; b.notes = d.notes; b.tags = d.tags
            b.isFavorite = d.isFavorite; b.createdAt = d.createdAt
            ctx.insert(b); added += 1
        }
        let fileIDs = Set(try ctx.fetch(FetchDescriptor<StoredFile>()).map(\.id))
        for d in p.files where !fileIDs.contains(d.id) {
            let f = StoredFile(name: d.name, typeIdentifier: d.typeIdentifier, data: d.data)
            f.id = d.id; f.createdAt = d.createdAt
            ctx.insert(f); added += 1
        }
        let vaultIDs = Set(try ctx.fetch(FetchDescriptor<VaultItem>()).map(\.id))
        for d in p.vault where !vaultIDs.contains(d.id) {
            let v = VaultItem(kind: VaultKind(rawValue: d.kindRaw) ?? .note)
            v.id = d.id; v.meta = d.meta; v.imageData = d.image; v.createdAt = d.createdAt; v.updatedAt = d.updatedAt
            ctx.insert(v); added += 1
        }
        try ctx.save()
        return added
    }
}

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @State private var password = ""
    @State private var confirm = ""
    @State private var includeVault = true
    @State private var exportURL: URL?
    @State private var working = false
    @State private var importing = false
    @State private var importData: Data?
    @State private var importPassword = ""
    @State private var message: String?

    var body: some View {
        HushForm {
            Section {
                SecureField("Backup password (8+ characters)", text: $password)
                SecureField("Confirm password", text: $confirm)
                Toggle("Include Vault", isOn: $includeVault)
                Button {
                    makeBackup()
                } label: {
                    HStack { Text("Create Backup"); if working { Spacer(); ProgressView() } }
                }
                .disabled(password.count < 8 || password != confirm || working)
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Save Backup File…", systemImage: "square.and.arrow.up") }
                }
            } header: {
                Text("Back Up")
            } footer: {
                Text("Creates one encrypted file of everything in Hush. Save it to the Files app, a USB drive or your computer. Without the password it can't be opened — not even by you.")
            }

            Section {
                Button("Restore from Backup…") { importing = true }
            } header: {
                Text("Restore")
            } footer: {
                Text("Adds items from a backup that aren't already here. Nothing is deleted.")
            }
        }
        .hushBackground()
        .navigationTitle("Backup & Restore")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importData = try? Data(contentsOf: url)
            importPassword = ""
            if importData == nil { message = "Couldn't read that file." }
        }
        .alert("Backup Password", isPresented: Binding(get: { importData != nil }, set: { if !$0 { importData = nil } })) {
            SecureField("Password", text: $importPassword)
            Button("Restore") { restore() }
            Button("Cancel", role: .cancel) { importData = nil }
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
        .onDisappear { if let exportURL { try? FileManager.default.removeItem(at: exportURL) } }
    }

    private func makeBackup() {
        working = true
        let pw = password
        let vault = includeVault
        DispatchQueue.main.async {
            do {
                exportURL = try Backup.export(context, password: pw, includeVault: vault)
            } catch {
                message = "Backup failed: \(error.localizedDescription)"
            }
            working = false
        }
    }

    private func restore() {
        guard let data = importData else { return }
        importData = nil
        do {
            let payload = try Backup.read(data, password: importPassword)
            let added = try Backup.restore(payload, into: context)
            message = "Restored \(added) item\(added == 1 ? "" : "s") from a backup made \(payload.createdAt.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            message = error.localizedDescription
        }
    }
}

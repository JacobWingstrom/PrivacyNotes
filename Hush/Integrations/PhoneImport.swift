import SwiftUI
import SwiftData
import Contacts
import EventKit
import UniformTypeIdentifiers

/// One-time imports from the iPhone into Hush. Everything happens on-device.
enum PhoneImport {
    struct ContactData {
        var first, last, company, address: String
        var phones, emails: [LabeledValue]
        var birthday: Date?
    }

    // MARK: Contacts

    static func fetchPhoneContacts() async throws -> [ContactData] {
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else { throw ImportError.denied("Contacts") }
        return try await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey, CNContactBirthdayKey,
            ].map { $0 as CNKeyDescriptor }
            var out: [ContactData] = []
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
                out.append(convert(c))
            }
            return out
        }.value
    }

    static func convert(_ c: CNContact) -> ContactData {
        func label(_ raw: String?) -> String {
            guard let raw, !raw.isEmpty else { return "other" }
            return CNLabeledValue<NSString>.localizedString(forLabel: raw).lowercased()
        }
        let phones = c.phoneNumbers.map { LabeledValue(label: label($0.label), value: $0.value.stringValue) }
        let emails = c.emailAddresses.map { LabeledValue(label: label($0.label), value: $0.value as String) }
        let address = c.postalAddresses.first.map { CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress) } ?? ""
        var birthday: Date?
        if var comps = c.birthday {
            if comps.year == nil { comps.year = 2000 }
            birthday = Calendar.current.date(from: comps)
        }
        return ContactData(first: c.givenName, last: c.familyName, company: c.organizationName, address: address,
                           phones: phones, emails: emails, birthday: birthday)
    }

    /// Inserts contacts that aren't already in Hush (matched by name + first phone/email).
    @MainActor
    static func insert(_ list: [ContactData], into ctx: ModelContext) -> Int {
        let existing = (try? ctx.fetch(FetchDescriptor<Contact>())) ?? []
        var keys = Set(existing.map { key($0.firstName, $0.lastName, $0.company, $0.phones.first?.value ?? $0.emails.first?.value) })
        var added = 0
        for d in list {
            let k = key(d.first, d.last, d.company, d.phones.first?.value ?? d.emails.first?.value)
            guard !keys.contains(k), !(d.first + d.last + d.company).trimmed.isEmpty || !d.phones.isEmpty else { continue }
            let c = Contact()
            c.firstName = d.first; c.lastName = d.last; c.company = d.company; c.address = d.address
            c.phones = d.phones; c.emails = d.emails; c.birthday = d.birthday
            ctx.insert(c)
            keys.insert(k)
            added += 1
        }
        try? ctx.save()
        return added
    }

    private static func key(_ a: String, _ b: String, _ c: String, _ d: String?) -> String {
        [a, b, c, (d ?? "").filter { $0.isLetter || $0.isNumber }].map { $0.lowercased() }.joined(separator: "|")
    }

    // MARK: Reminders → Tasks

    @MainActor
    static func importReminders(includeCompleted: Bool, into ctx: ModelContext) async throws -> Int {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else { throw ImportError.denied("Reminders") }
        let predicate = includeCompleted
            ? store.predicateForReminders(in: nil)
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        let existing = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        var keys = Set(existing.map { "\($0.title.lowercased())|\($0.list.lowercased())" })
        var added = 0
        for r in reminders {
            let title = (r.title ?? "").trimmed
            let list = r.calendar?.title ?? ""
            let k = "\(title.lowercased())|\(list.lowercased())"
            guard !title.isEmpty, !keys.contains(k) else { continue }
            let t = TaskItem(title: title)
            t.notes = r.notes ?? ""
            t.list = list
            if let comps = r.dueDateComponents, let due = Calendar.current.date(from: comps) {
                t.dueDate = due
                t.hasDueTime = comps.hour != nil
            }
            switch r.priority {
            case 1...4: t.priority = .high
            case 5: t.priority = .medium
            case 6...9: t.priority = .low
            default: t.priority = .none
            }
            t.isDone = r.isCompleted
            t.completedAt = r.completionDate
            t.createdAt = r.creationDate ?? .now
            ctx.insert(t)
            keys.insert(k)
            added += 1
        }
        try? ctx.save()
        return added
    }

    // MARK: Calendar events → Hush events

    @MainActor
    static func copyEvents(store: EKEventStore, monthsBack: Int, monthsAhead: Int, into ctx: ModelContext) async throws -> Int {
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            guard try await store.requestFullAccessToEvents() else { throw ImportError.denied("Calendars") }
        }
        let cal = Calendar.current
        let start = cal.date(byAdding: .month, value: -monthsBack, to: .now) ?? .now
        let end = cal.date(byAdding: .month, value: monthsAhead, to: .now) ?? .now
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        return insertEvents(events.map { ($0.title ?? "", $0.startDate, $0.endDate, $0.isAllDay, $0.location ?? "", $0.notes ?? "") }, into: ctx)
    }

    @MainActor
    static func insertEvents(_ list: [(String, Date, Date, Bool, String, String)], into ctx: ModelContext) -> Int {
        let existing = (try? ctx.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        var keys = Set(existing.map { "\($0.title.lowercased())|\(Int($0.start.timeIntervalSince1970))" })
        var added = 0
        for (title, start, end, allDay, location, notes) in list {
            let k = "\(title.lowercased())|\(Int(start.timeIntervalSince1970))"
            guard !keys.contains(k) else { continue }
            let e = CalendarEvent(start: start)
            e.title = title; e.end = max(end, start); e.isAllDay = allDay; e.location = location; e.notes = notes
            ctx.insert(e)
            keys.insert(k)
            added += 1
        }
        try? ctx.save()
        return added
    }

    // MARK: Files (.txt / .md → Notes, .vcf → Contacts, .ics → Events)

    @MainActor
    static func importFiles(_ urls: [URL], into ctx: ModelContext) -> String {
        var notes = 0, contacts = 0, events = 0, skipped = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { skipped += 1; continue }
            let ext = url.pathExtension.lowercased()
            if ext == "vcf" || ext == "vcard" {
                let list = (try? CNContactVCardSerialization.contacts(with: data)) ?? []
                contacts += insert(list.map(convert), into: ctx)
            } else if ext == "ics" {
                events += insertEvents(ICSParser.parse(String(decoding: data, as: UTF8.self)), into: ctx)
            } else if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let n = Note()
                n.title = url.deletingPathExtension().lastPathComponent
                n.body = text
                if let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    n.createdAt = mod; n.updatedAt = mod
                }
                ctx.insert(n)
                notes += 1
            } else {
                skipped += 1
            }
        }
        try? ctx.save()
        var parts: [String] = []
        if notes > 0 { parts.append("\(notes) note\(notes == 1 ? "" : "s")") }
        if contacts > 0 { parts.append("\(contacts) contact\(contacts == 1 ? "" : "s")") }
        if events > 0 { parts.append("\(events) event\(events == 1 ? "" : "s")") }
        var msg = parts.isEmpty ? "Nothing new to import." : "Imported " + parts.joined(separator: ", ") + "."
        if skipped > 0 { msg += " \(skipped) file\(skipped == 1 ? "" : "s") couldn't be read." }
        return msg
    }

    enum ImportError: LocalizedError {
        case denied(String)
        var errorDescription: String? {
            switch self {
            case .denied(let what): "Hush needs permission to read your \(what). You can allow it in iPhone Settings → Apps → Hush."
            }
        }
    }
}

/// Minimal iCalendar (.ics) reader: SUMMARY, DTSTART, DTEND, LOCATION, DESCRIPTION.
enum ICSParser {
    static func parse(_ text: String) -> [(String, Date, Date, Bool, String, String)] {
        // Unfold continuation lines (lines starting with a space or tab).
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if let first = raw.first, (first == " " || first == "\t"), !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(raw)
            }
        }
        var out: [(String, Date, Date, Bool, String, String)] = []
        var fields: [String: (params: String, value: String)]?
        for line in lines {
            if line == "BEGIN:VEVENT" { fields = [:]; continue }
            if line == "END:VEVENT", let f = fields {
                if let s = f["DTSTART"], let start = date(s.value, params: s.params) {
                    let allDay = s.params.contains("VALUE=DATE") || s.value.count == 8
                    let end = f["DTEND"].flatMap { date($0.value, params: $0.params) } ?? start.addingTimeInterval(allDay ? 86399 : 3600)
                    out.append((unescape(f["SUMMARY"]?.value ?? ""), start, allDay ? end.addingTimeInterval(-1) : end, allDay,
                                unescape(f["LOCATION"]?.value ?? ""), unescape(f["DESCRIPTION"]?.value ?? "")))
                }
                fields = nil
                continue
            }
            guard fields != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";", maxSplits: 1)
            let name = String(parts.first ?? "").uppercased()
            fields?[name] = (parts.count > 1 ? String(parts[1]).uppercased() : "", value)
        }
        return out
    }

    private static func date(_ value: String, params: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if value.hasSuffix("Z") {
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else if value.count == 8 {
            f.timeZone = .current
            f.dateFormat = "yyyyMMdd"
        } else {
            f.timeZone = .current
            f.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return f.date(from: value)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(PhoneCalendar.self) private var phone
    @State private var includeCompleted = false
    @State private var monthsBack = 1
    @State private var monthsAhead = 12
    @State private var working: String?
    @State private var message: String?
    @State private var importingFiles = false

    var body: some View {
        HushForm {
            Section {
                Button { run("contacts") { let list = try await PhoneImport.fetchPhoneContacts(); return "Imported \(PhoneImport.insert(list, into: context)) new contacts." } } label: {
                    row("Import iPhone Contacts", "person.crop.circle.badge.plus", "contacts")
                }
            } header: {
                Text("Contacts")
            } footer: {
                Text("Copies your iPhone contacts into Hush's private Contacts. People already in Hush are skipped.")
            }

            Section {
                Toggle("Include Completed", isOn: $includeCompleted)
                Button { run("reminders") { "Imported \(try await PhoneImport.importReminders(includeCompleted: includeCompleted, into: context)) reminders as tasks." } } label: {
                    row("Import Reminders as Tasks", "checklist", "reminders")
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Due dates, priorities and lists are kept. Reminders already imported are skipped.")
            }

            Section {
                Stepper("From \(monthsBack) month\(monthsBack == 1 ? "" : "s") ago", value: $monthsBack, in: 0...24)
                Stepper("To \(monthsAhead) month\(monthsAhead == 1 ? "" : "s") ahead", value: $monthsAhead, in: 1...36)
                Button { run("events") { "Copied \(try await PhoneImport.copyEvents(store: phone.store, monthsBack: monthsBack, monthsAhead: monthsAhead, into: context)) events into Hush." } } label: {
                    row("Copy Calendar Events into Hush", "calendar.badge.plus", "events")
                }
                NavigationLink("Show iPhone calendars live instead") { ConnectedCalendarsView() }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Copies make private Hush events that no longer follow changes on your iPhone. To keep Outlook or Apple Calendar in sync, connect them live instead.")
            }

            Section {
                Button { importingFiles = true } label: {
                    row("Import Files…", "doc.badge.plus", "files")
                }
            } header: {
                Text("Files")
            } footer: {
                Text("Text and Markdown files become notes, .vcf contact cards become contacts, and .ics calendar files become events. To bring over Apple Notes, share or export each note as a text or Markdown file to the Files app, then import it here. Photos and documents go in the Files section.")
            }
        }
        .navigationTitle("Import from iPhone")
        .fileImporter(isPresented: $importingFiles,
                      allowedContentTypes: [.plainText, .text, .vCard, .calendarEvent, UTType(filenameExtension: "md") ?? .text, UTType(filenameExtension: "ics") ?? .data],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { message = PhoneImport.importFiles(urls, into: context) }
        }
        .alert("Import", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }

    private func row(_ title: String, _ symbol: String, _ key: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if working == key { ProgressView() }
        }
    }

    private func run(_ key: String, _ job: @escaping () async throws -> String) {
        guard working == nil else { return }
        working = key
        Task { @MainActor in
            do { message = try await job() } catch { message = error.localizedDescription }
            working = nil
        }
    }
}

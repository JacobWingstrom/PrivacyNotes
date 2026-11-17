import Foundation
import SwiftData
import CryptoKit

struct DAVCollection: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case calendar, tasks, addressBook
        var symbol: String {
            switch self {
            case .calendar: "calendar"
            case .tasks: "checklist"
            case .addressBook: "person.crop.rectangle.stack"
            }
        }
    }
    var href: String
    var name: String
    var kind: Kind
    var components: [String] = []
    var ctag = ""
    var color = ""
    var id: String { href }
    var url: URL? { URL(string: href) }
    var holdsEvents: Bool { kind == .calendar && (components.isEmpty || components.contains("VEVENT")) }
    var holdsTasks: Bool { kind == .tasks || components.contains("VTODO") }
}

/// What Hush knows about one synced item: where it lives on the server, its version, and the
/// last synced content (so unknown fields survive a round trip and local edits can be spotted).
struct DAVEntry: Codable {
    var href: String
    var etag: String
    var localID: UUID
    var hash: String
    var raw: String
    var collection: String
    var kind: String // "event", "task", "contact"
}

struct DAVState: Codable {
    var collections: [DAVCollection] = []
    var entries: [String: DAVEntry] = [:]
    var lastSync: Date?
    var lastDiscovery: Date?
}

enum DAVStore {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DAV", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excluded = base
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? excluded.setResourceValues(v)
        return base
    }

    private static func file(_ id: String) -> URL { dir.appendingPathComponent("\(id).json") }

    static func load(_ id: String) -> DAVState {
        guard let sealed = try? Data(contentsOf: file(id)), let data = DataCrypto.open(sealed) else { return DAVState() }
        return (try? JSONDecoder().decode(DAVState.self, from: data)) ?? DAVState()
    }

    static func save(_ state: DAVState, _ id: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? DataCrypto.seal(data).write(to: file(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(accountID: String) { try? FileManager.default.removeItem(at: file(accountID)) }
}

/// Two-way sync of calendars, tasks and contacts with CalDAV / CardDAV (mailbox.org and others).
@MainActor
@Observable
final class DAVSync {
    static let shared = DAVSync()

    private(set) var states: [String: DAVState] = [:]
    private(set) var syncing: Set<String> = []
    var errors: [String: String] = [:]

    private var context: ModelContext { Storage.shared.mainContext }

    /// Doesn't cache, so views can call it while drawing.
    func state(_ id: String) -> DAVState {
        states[id] ?? DAVStore.load(id)
    }

    func syncIfDue(_ account: MailAccount) async {
        let last = state(account.id).lastSync ?? .distantPast
        if Date().timeIntervalSince(last) > 600 { await sync(account, force: false) }
    }

    /// Syncs every DAV account (used after local edits and in the background).
    func syncAll(force: Bool = false) async {
        for a in MailEngine.shared.accounts where a.davEnabled {
            if force { await sync(a, force: true) } else { await syncIfDue(a) }
        }
    }

    func sync(_ account: MailAccount, force: Bool) async {
        guard account.davEnabled, !syncing.contains(account.id) else { return }
        guard let password = MailAccounts.password(for: account.id) else { return }
        syncing.insert(account.id)
        defer { syncing.remove(account.id) }
        let client = DAVClient(username: account.username, password: password)
        var st = state(account.id)
        do {
            if st.collections.isEmpty || force || Date().timeIntervalSince(st.lastDiscovery ?? .distantPast) > 86400 {
                var found: [DAVCollection] = []
                if let u = URL(string: account.caldavURL.trimmed), !account.caldavURL.trimmed.isEmpty {
                    found += try await discover(client, start: u, card: false)
                }
                if let u = URL(string: account.carddavURL.trimmed), !account.carddavURL.trimmed.isEmpty {
                    found += (try? await discover(client, start: u, card: true)) ?? []
                }
                // Keep sync tokens for collections we already knew.
                for i in found.indices { found[i].ctag = st.collections.first { $0.href == found[i].href }?.ctag ?? "" }
                // Forget items of collections that disappeared.
                let hrefs = Set(found.map(\.href))
                st.entries = st.entries.filter { hrefs.contains($0.value.collection) }
                st.collections = found
                st.lastDiscovery = Date()
            }
            for i in st.collections.indices where !account.davDisabledCollections.contains(st.collections[i].href) {
                try await syncCollection(client, account: account, state: &st, index: i, force: force)
            }
            try await uploadNew(client, account: account, state: &st)
            st.lastSync = Date()
            errors[account.id] = nil
        } catch {
            errors[account.id] = error.localizedDescription
        }
        try? context.save()
        states[account.id] = st
        DAVStore.save(st, account.id)
        OnlineCenter.reloadWidgets()
    }

    // MARK: Discovery

    private func resolve(_ href: String, base: URL) -> URL? {
        URL(string: href, relativeTo: base)?.absoluteURL
    }

    private func discover(_ client: DAVClient, start: URL, card: Bool) async throws -> [DAVCollection] {
        let homeProp = card ? "<card:addressbook-home-set/>" : "<c:calendar-home-set/>"
        let homeKey = card ? "addressbook-home-set" : "calendar-home-set"
        var home = start
        if let principalHref = try? await client.propfind(start, depth: "0", props: "<d:current-user-principal/>").first?.props["current-user-principal"],
           !principalHref.isEmpty, let principal = resolve(principalHref, base: start) {
            if let h = try? await client.propfind(principal, depth: "0", props: homeProp).first?.props[homeKey], !h.isEmpty,
               let u = resolve(h, base: principal) {
                home = u
            }
        }
        let props = "<d:resourcetype/><d:displayname/><cs:getctag/><d:sync-token/><c:supported-calendar-component-set/><ic:calendar-color/>"
        let listed = try await client.propfind(home, depth: "1", props: props)
        var out: [DAVCollection] = []
        for r in listed {
            guard let url = resolve(r.href, base: home) else { continue }
            let isCal = r.resourceTypes.contains("calendar")
            let isBook = r.resourceTypes.contains("addressbook")
            guard card ? isBook : isCal else { continue }
            let name = r.props["displayname"].flatMap { $0.isEmpty ? nil : $0 } ?? url.lastPathComponent
            var kind: DAVCollection.Kind = card ? .addressBook : .calendar
            if !card && r.components.contains("VTODO") && !r.components.contains("VEVENT") { kind = .tasks }
            out.append(DAVCollection(href: url.absoluteString, name: name, kind: kind, components: Array(r.components).sorted(),
                                     color: r.props["calendar-color"] ?? ""))
        }
        return out
    }

    // MARK: One collection

    private static let window = (past: -366, future: 3 * 366)

    private func syncCollection(_ client: DAVClient, account: MailAccount, state st: inout DAVState, index: Int, force: Bool) async throws {
        let coll = st.collections[index]
        guard let url = coll.url else { return }
        let info = try await client.propfind(url, depth: "0", props: "<cs:getctag/><d:sync-token/>").first
        let ctag = info?.props["getctag"] ?? info?.props["sync-token"] ?? ""
        let mine = st.entries.values.filter { $0.collection == coll.href }
        let items = LocalItems(context)
        let dirty = mine.contains { localHash(for: $0, items) != $0.hash }
        if !force && !ctag.isEmpty && ctag == coll.ctag && !dirty { return }

        // 1. What's on the server (href → etag).
        var remote: [String: String] = [:]
        if coll.kind == .addressBook {
            for r in try await client.propfind(url, depth: "1", props: "<d:getetag/><d:resourcetype/>") {
                guard let u = resolve(r.href, base: url), u.absoluteString != coll.href, !r.resourceTypes.contains("collection") else { continue }
                remote[u.absoluteString] = r.props["getetag"] ?? ""
            }
        } else {
            var queries: [String] = []
            if coll.holdsEvents {
                let start = ICal.utc(Calendar.current.date(byAdding: .day, value: Self.window.past, to: .now) ?? .now)
                let end = ICal.utc(Calendar.current.date(byAdding: .day, value: Self.window.future, to: .now) ?? .now)
                queries.append("<c:comp-filter name=\"VEVENT\"><c:time-range start=\"\(start)\" end=\"\(end)\"/></c:comp-filter>")
            }
            if coll.holdsTasks { queries.append("<c:comp-filter name=\"VTODO\"/>") }
            for q in queries {
                let body = """
                <?xml version="1.0" encoding="utf-8"?>
                <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
                <d:prop><d:getetag/></d:prop>
                <c:filter><c:comp-filter name="VCALENDAR">\(q)</c:comp-filter></c:filter>
                </c:calendar-query>
                """
                for r in try await client.report(url, body: body) {
                    guard let u = resolve(r.href, base: url), u.absoluteString != coll.href else { continue }
                    remote[u.absoluteString] = r.props["getetag"] ?? ""
                }
            }
        }

        // 2. Local edits and deletions go up first (unless the server copy changed too: then the server wins).
        for entry in mine {
            guard let u = URL(string: entry.href) else { continue }
            let serverEtag = remote[entry.href]
            let local = items.item(entry)
            let localGone = local == nil || local?.deletedAt != nil
            if localGone {
                if serverEtag != nil && serverEtag == entry.etag || serverEtag == nil {
                    try? await client.delete(u, ifMatch: entry.etag)
                    st.entries[entry.href] = nil
                    remote[entry.href] = nil
                }
                continue
            }
            guard let local, localHash(for: entry, items) != entry.hash, serverEtag == entry.etag || entry.etag.isEmpty else { continue }
            if let pending = local as? any Reviewable, pending.isPendingReview { continue }
            let body = render(local, entry: entry)
            do {
                let etag = try await client.put(u, body: body, contentType: entry.kind == "contact" ? "text/vcard; charset=utf-8" : "text/calendar; charset=utf-8",
                                                ifMatch: entry.etag, create: false)
                var e = entry
                e.etag = etag ?? ""
                e.hash = localHash(for: entry, items)
                e.raw = body
                st.entries[entry.href] = e
                remote[entry.href] = e.etag.isEmpty ? "changed" : e.etag
                if e.etag.isEmpty { st.entries[entry.href]?.etag = "changed" }
            } catch DAVError.conflict {
                st.entries[entry.href]?.etag = "" // pull the server's version below
            }
        }

        // 3. Server changes come down.
        let changed = remote.filter { href, etag in
            guard let e = st.entries[href] else { return true }
            return e.etag != etag || etag.isEmpty
        }.map(\.key)
        for chunk in changed.chunked(40) {
            let hrefs = chunk.compactMap { URL(string: $0)?.path }.map { "<d:href>\(MIME.escapeHTML($0))</d:href>" }.joined()
            let body: String
            if coll.kind == .addressBook {
                body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><card:addressbook-multiget xmlns:d=\"DAV:\" xmlns:card=\"urn:ietf:params:xml:ns:carddav\"><d:prop><d:getetag/><card:address-data/></d:prop>\(hrefs)</card:addressbook-multiget>"
            } else {
                body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><c:calendar-multiget xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop><d:getetag/><c:calendar-data/></d:prop>\(hrefs)</c:calendar-multiget>"
            }
            for r in try await client.report(url, body: body) {
                guard let u = resolve(r.href, base: url) else { continue }
                let data = r.props["calendar-data"] ?? r.props["address-data"] ?? ""
                guard !data.isEmpty else { continue }
                apply(remoteData: data, href: u.absoluteString, etag: r.props["getetag"] ?? remote[u.absoluteString] ?? "",
                      collection: coll, account: account, state: &st, items: items)
            }
        }

        // 4. Gone from the server: remove here too (events that just aged out of the window stay).
        let windowStart = Calendar.current.date(byAdding: .day, value: Self.window.past, to: .now) ?? .distantPast
        for entry in st.entries.values where entry.collection == coll.href && remote[entry.href] == nil {
            if let ev = items.item(entry) as? CalendarEvent, max(ev.end, ev.start) < windowStart, ev.recurrenceRule.isEmpty {
                st.entries[entry.href] = nil
                continue
            }
            if let local = items.item(entry) { items.remove(local) }
            st.entries[entry.href] = nil
        }
        st.collections[index].ctag = ctag
    }

    // MARK: Server → Hush

    private func apply(remoteData: String, href: String, etag: String, collection: DAVCollection, account: MailAccount,
                       state st: inout DAVState, items: LocalItems) {
        let roots = ICal.parse(remoteData)
        if collection.kind == .addressBook {
            guard let card = roots.first(where: { $0.name == "VCARD" }) else { return }
            let found = ICal.contact(from: card)
            let c: Contact
            if let entry = st.entries[href], let existing = items.item(entry) as? Contact { c = existing } else {
                c = Contact()
                c.spaceID = account.targetSpace
                c.originRaw = "dav"
                context.insert(c)
            }
            c.firstName = found.first; c.lastName = found.last; c.company = found.company
            c.emails = found.emails; c.phones = found.phones; c.address = found.address
            c.birthday = found.birthday; c.notes = found.notes
            st.entries[href] = DAVEntry(href: href, etag: etag, localID: c.id, hash: Self.hash(c), raw: remoteData, collection: collection.href, kind: "contact")
            return
        }
        guard let cal = roots.first(where: { $0.name == "VCALENDAR" }) else { return }
        if let v = cal.children.first(where: { $0.name == "VEVENT" && $0.prop("RECURRENCE-ID") == nil }) ?? cal.children.first(where: { $0.name == "VEVENT" }),
           let found = ICal.event(from: v) {
            var ev: CalendarEvent?
            if let entry = st.entries[href] { ev = items.item(entry) as? CalendarEvent }
            if ev == nil, !found.uid.isEmpty {
                // An invite Hush already picked up from email: link it instead of duplicating.
                let uid = found.uid
                let linked = Set(st.entries.values.map(\.localID))
                ev = ((try? context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.icalUID == uid }))) ?? [])
                    .first { $0.deletedAt == nil && !linked.contains($0.id) }
            }
            let e = ev ?? {
                let n = CalendarEvent(start: found.start)
                n.spaceID = account.targetSpace
                n.originRaw = "dav"
                self.context.insert(n)
                return n
            }()
            e.title = found.title
            e.start = found.start
            e.end = found.end
            e.isAllDay = found.allDay
            e.location = found.location
            e.notes = found.notes
            e.recurrenceRule = found.rrule
            e.alertMinutes = found.alertMinutes
            e.icalUID = found.uid
            if e.reviewRaw == "pending" { e.reviewRaw = "" } // it's on your calendar, so it's confirmed
            Reminders.sync(e)
            st.entries[href] = DAVEntry(href: href, etag: etag, localID: e.id, hash: Self.hash(e), raw: remoteData, collection: collection.href, kind: "event")
        } else if let v = cal.children.first(where: { $0.name == "VTODO" }) {
            let found = ICal.task(from: v)
            var t: TaskItem
            if let entry = st.entries[href], let existing = items.item(entry) as? TaskItem { t = existing } else {
                t = TaskItem(title: found.title)
                t.spaceID = account.targetSpace
                t.originRaw = "dav"
                context.insert(t)
            }
            t.title = found.title
            t.notes = found.notes
            t.dueDate = found.due
            t.hasDueTime = found.hasTime
            t.isDone = found.done
            t.completedAt = found.completedAt
            t.priority = Priority(rawValue: found.priority) ?? Priority.none
            t.list = collection.name
            Reminders.sync(t)
            st.entries[href] = DAVEntry(href: href, etag: etag, localID: t.id, hash: Self.hash(t), raw: remoteData, collection: collection.href, kind: "task")
        }
    }

    // MARK: Hush → server (new items)

    private func uploadNew(_ client: DAVClient, account: MailAccount, state st: inout DAVState) async throws {
        // Only one account uploads for a given space.
        guard MailEngine.shared.accounts.first(where: { $0.davEnabled && $0.targetSpace == account.targetSpace })?.id == account.id else { return }
        let enabled = st.collections.filter { !account.davDisabledCollections.contains($0.href) }
        var linked = Set<UUID>()
        for other in MailEngine.shared.accounts { for e in state(other.id).entries.values { linked.insert(e.localID) } }
        for e in st.entries.values { linked.insert(e.localID) }
        let since = account.davUploadFrom
        let space = account.targetSpace

        func eligible(_ createdAt: Date, _ id: UUID, _ spaceKey: String, _ review: String, _ deleted: Date?) -> Bool {
            deleted == nil && review != "pending" && spaceKey == space && createdAt >= since && !linked.contains(id)
        }

        let calendars = enabled.filter(\.holdsEvents)
        if let target = calendars.first(where: { $0.href == account.davDefaultCalendar }) ?? calendars.first {
            let events = ((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []).filter {
                eligible($0.createdAt, $0.id, $0.spaceKey, $0.reviewRaw, $0.deletedAt) && !$0.title.trimmed.isEmpty
            }
            for e in events.prefix(200) {
                let uid = e.icalUID.isEmpty ? e.id.uuidString : e.icalUID
                let body = ICal.calendar(for: e, uid: uid, original: nil)
                let href = target.href.hasSuffix("/") ? target.href + "\(e.id.uuidString).ics" : target.href + "/\(e.id.uuidString).ics"
                guard let u = URL(string: href) else { continue }
                let etag = try await client.put(u, body: body, contentType: "text/calendar; charset=utf-8", ifMatch: nil, create: true)
                e.icalUID = uid
                st.entries[href] = DAVEntry(href: href, etag: etag ?? "", localID: e.id, hash: Self.hash(e), raw: body, collection: target.href, kind: "event")
            }
        }

        let taskLists = enabled.filter(\.holdsTasks)
        if !taskLists.isEmpty {
            let fallback = taskLists.first { $0.href == account.davDefaultTaskList } ?? taskLists.first { $0.kind == .tasks } ?? taskLists[0]
            let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter {
                eligible($0.createdAt, $0.id, $0.spaceKey, $0.reviewRaw, $0.deletedAt) && !$0.title.trimmed.isEmpty
            }
            for t in tasks.prefix(200) {
                let target = taskLists.first { !t.list.isEmpty && $0.name.caseInsensitiveCompare(t.list) == .orderedSame } ?? fallback
                let body = ICal.calendar(for: t, uid: t.id.uuidString, original: nil)
                let href = target.href.hasSuffix("/") ? target.href + "\(t.id.uuidString).ics" : target.href + "/\(t.id.uuidString).ics"
                guard let u = URL(string: href) else { continue }
                let etag = try await client.put(u, body: body, contentType: "text/calendar; charset=utf-8", ifMatch: nil, create: true)
                st.entries[href] = DAVEntry(href: href, etag: etag ?? "", localID: t.id, hash: Self.hash(t), raw: body, collection: target.href, kind: "task")
            }
        }

        let books = enabled.filter { $0.kind == .addressBook }
        if let target = books.first(where: { $0.href == account.davDefaultAddressBook }) ?? books.first {
            let contacts = ((try? context.fetch(FetchDescriptor<Contact>())) ?? []).filter {
                eligible($0.createdAt, $0.id, $0.spaceKey, $0.reviewRaw, $0.deletedAt) && !$0.isEmpty
            }
            for c in contacts.prefix(300) {
                let body = ICal.vcard(for: c, uid: c.id.uuidString, original: nil)
                let href = target.href.hasSuffix("/") ? target.href + "\(c.id.uuidString).vcf" : target.href + "/\(c.id.uuidString).vcf"
                guard let u = URL(string: href) else { continue }
                let etag = try await client.put(u, body: body, contentType: "text/vcard; charset=utf-8", ifMatch: nil, create: true)
                st.entries[href] = DAVEntry(href: href, etag: etag ?? "", localID: c.id, hash: Self.hash(c), raw: body, collection: target.href, kind: "contact")
            }
        }
    }

    // MARK: Helpers

    private func render(_ item: any HushItem, entry: DAVEntry) -> String {
        if let e = item as? CalendarEvent {
            let uid = e.icalUID.isEmpty ? (ICal.parse(entry.raw).first?.child("VEVENT")?.text("UID") ?? e.id.uuidString) : e.icalUID
            return ICal.calendar(for: e, uid: uid, original: entry.raw)
        }
        if let t = item as? TaskItem {
            let uid = ICal.parse(entry.raw).first?.child("VTODO")?.text("UID") ?? t.id.uuidString
            return ICal.calendar(for: t, uid: uid, original: entry.raw)
        }
        if let c = item as? Contact {
            let uid = ICal.parse(entry.raw).first?.text("UID") ?? c.id.uuidString
            return ICal.vcard(for: c, uid: uid, original: entry.raw)
        }
        return entry.raw
    }

    private func localHash(for entry: DAVEntry, _ items: LocalItems) -> String {
        switch items.item(entry) {
        case let e as CalendarEvent: return Self.hash(e)
        case let t as TaskItem: return Self.hash(t)
        case let c as Contact: return Self.hash(c)
        default: return ""
        }
    }

    private static func digest(_ parts: [String]) -> String {
        SHA256.hash(data: Data(parts.joined(separator: "\u{1}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ e: CalendarEvent) -> String {
        digest([e.title, "\(e.start.timeIntervalSince1970)", "\(e.end.timeIntervalSince1970)", "\(e.isAllDay)", e.location, e.notes,
                e.recurrenceRule, "\(e.alertMinutes)"])
    }

    static func hash(_ t: TaskItem) -> String {
        digest([t.title, t.notes, "\(t.dueDate?.timeIntervalSince1970 ?? 0)", "\(t.hasDueTime)", "\(t.isDone)", "\(t.priorityRaw)"])
    }

    static func hash(_ c: Contact) -> String {
        digest([c.firstName, c.lastName, c.company, c.emails.map(\.value).joined(separator: ","), c.phones.map(\.value).joined(separator: ","),
                c.address, "\(c.birthday?.timeIntervalSince1970 ?? 0)", c.notes])
    }
}

/// Looks up Hush items by id for one sync run.
@MainActor
private final class LocalItems {
    let context: ModelContext
    private lazy var events: [UUID: CalendarEvent] = Dictionary(((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private lazy var tasks: [UUID: TaskItem] = Dictionary(((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private lazy var contacts: [UUID: Contact] = Dictionary(((try? context.fetch(FetchDescriptor<Contact>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    init(_ context: ModelContext) { self.context = context }

    func item(_ entry: DAVEntry) -> (any HushItem)? {
        switch entry.kind {
        case "event": return events[entry.localID]
        case "task": return tasks[entry.localID]
        default: return contacts[entry.localID]
        }
    }

    func remove(_ item: any HushItem) {
        if let e = item as? CalendarEvent { Reminders.cancel("event.\(e.id.uuidString)"); events[e.id] = nil; context.delete(e) }
        if let t = item as? TaskItem { Reminders.cancel("task.\(t.id.uuidString)"); tasks[t.id] = nil; context.delete(t) }
        if let c = item as? Contact { contacts[c.id] = nil; context.delete(c) }
    }
}

import Foundation
import SwiftData

/// Finds events, tasks and contacts in email, entirely on this device.
/// Found items are added right away but marked "pending" (shown faded) until you confirm them,
/// or "auto" when they come from a source you trust.
@MainActor
enum MailScanner {
    enum Confidence { case structured, rule, detected }

    // MARK: Entry points

    /// Scans downloaded messages that haven't been looked at yet.
    static func scanPending(context: ModelContext) async {
        let engine = MailEngine.shared
        let d = FetchDescriptor<MailMessage>(predicate: #Predicate { $0.scannedAt == nil })
        let pending = (try? context.fetch(d)) ?? []
        guard !pending.isEmpty else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -ScanPrefs.lookbackDays, to: .now) ?? .now
        var changed = 0
        for m in pending {
            guard let account = engine.account(m.accountID) else { m.scannedAt = Date(); continue }
            let role = engine.states[m.accountID]?.folders.first { $0.path == m.folder }?.role
            // Skip old mail, mail you sent and junk.
            if !account.scanEnabled || m.date < cutoff || ["sent", "trash", "junk", "drafts"].contains(role ?? "") {
                m.scannedAt = Date()
                continue
            }
            guard let source = m.source else { continue }
            let parsed = MIME.parseMessage(source)
            changed += scan(m, parsed: parsed, account: account, context: context, force: false)
            m.scannedAt = Date()
        }
        try? context.save()
        if changed > 0 { OnlineCenter.reloadWidgets() }
    }

    /// Scans one message again on request (ignores earlier dismissals).
    static func rescan(_ m: MailMessage, parsed: ParsedMessage) async {
        guard let account = MailEngine.shared.account(m.accountID) else { return }
        let ctx = Storage.shared.mainContext
        _ = scan(m, parsed: parsed, account: account, context: ctx, force: true)
        m.scannedAt = Date()
        try? ctx.save()
    }

    /// Returns how many items were added or updated.
    @discardableResult
    static func scan(_ m: MailMessage, parsed p: ParsedMessage, account: MailAccount, context ctx: ModelContext, force: Bool) -> Int {
        let fromEmail = p.from?.email ?? ""
        let subject = p.subject
        let text = mainText(p)
        let ref = m.reference + "|" + fromEmail.lowercased()
        let note = "\(p.from?.display ?? fromEmail) · \(subject.isEmpty ? "(No subject)" : subject)"
        let senderTrusted = ScanPrefs.isTrusted(fromEmail)
        let matching = ScanPrefs.rules.filter { $0.matches(from: (p.from?.full ?? fromEmail), subject: subject, body: text) }
        if matching.contains(where: { $0.action == .ignore }) { return 0 }
        let ruleTrust = matching.contains { $0.action == .trust || $0.autoConfirm }
        var ctxInfo = Context(ref: ref, note: note, account: account, force: force, context: ctx, message: m)
        var count = 0

        // 1. Calendar invites and attached .ics files.
        for part in p.calendarParts {
            count += applyCalendar(part, trusted: senderTrusted || ruleTrust || ScanPrefs.autoConfirmInvites, info: &ctxInfo)
        }
        // 2. Contact cards.
        for card in p.vcardParts {
            for v in ICal.parse(card) where v.name == "VCARD" {
                if addContact(ICal.contact(from: v), trusted: senderTrusted || ruleTrust, info: ctxInfo) { count += 1 }
            }
        }
        // 3. Booking, delivery and invoice data that shops and airlines embed (schema.org).
        if let html = p.htmlBody {
            for item in SchemaOrg.extract(html) {
                let trusted = senderTrusted || ruleTrust || ScanPrefs.autoConfirmReservations
                switch item {
                case .event(let e): if addEvent(e, trusted: trusted, info: ctxInfo) { count += 1 }
                case .task(let t): if addTask(t, trusted: trusted, info: ctxInfo) { count += 1 }
                }
            }
        }
        // 4. Your rules.
        let detectedDate = DateFinder.find(subject: subject, text: text, received: m.date)
        for r in matching {
            switch r.action {
            case .task:
                var t = FoundTask()
                t.title = cleanSubject(subject)
                t.list = r.taskList
                if let d = detectedDate {
                    t.due = d.date
                    t.hasTime = d.hasTime
                } else if r.dueInDays >= 0 {
                    t.due = Calendar.current.date(byAdding: .day, value: r.dueInDays, to: Calendar.current.startOfDay(for: m.date))
                }
                t.notes = "From \(p.from?.display ?? fromEmail)"
                if addTask(t, trusted: senderTrusted || r.autoConfirm, info: ctxInfo) { count += 1 }
            case .event:
                if let d = detectedDate {
                    var e = FoundEvent()
                    e.title = cleanSubject(subject)
                    e.start = d.date
                    e.allDay = !d.hasTime
                    e.end = d.hasTime ? d.date.addingTimeInterval(d.duration ?? 3600) : d.date.addingTimeInterval(86399)
                    e.location = d.location
                    if addEvent(e, trusted: senderTrusted || r.autoConfirm, info: ctxInfo) { count += 1 }
                }
            case .contact:
                if let from = p.from, addContact(signatureContact(from, text: p.plainText), trusted: senderTrusted || r.autoConfirm, info: ctxInfo) { count += 1 }
            case .trust, .ignore:
                break
            }
        }
        let ruleMade = matching.contains { [.task, .event].contains($0.action) }

        // 5. Dates in ordinary personal mail ("Lunch on Friday at 12:30", "please send it by June 3").
        if ScanPrefs.detectDates, !ruleMade, count == 0, !p.isBulk || senderTrusted, let d = detectedDate {
            let trusted = senderTrusted || ruleTrust
            switch d.kind {
            case .event:
                var e = FoundEvent()
                e.title = cleanSubject(subject)
                e.start = d.date
                e.allDay = !d.hasTime
                e.end = d.hasTime ? d.date.addingTimeInterval(d.duration ?? 3600) : d.date.addingTimeInterval(86399)
                e.location = d.location
                e.notes = d.sentence
                if addEvent(e, trusted: trusted, info: ctxInfo) { count += 1 }
            case .task:
                var t = FoundTask()
                t.title = cleanSubject(subject)
                t.due = d.date
                t.hasTime = d.hasTime
                t.notes = d.sentence
                if addTask(t, trusted: trusted, info: ctxInfo) { count += 1 }
            }
        }

        // 6. New people with a signature (phone number) become contact suggestions.
        if ScanPrefs.suggestContacts, !p.isBulk, let from = p.from, !matching.contains(where: { $0.action == .contact }) {
            let c = signatureContact(from, text: p.plainText)
            if !c.phones.isEmpty, addContact(c, trusted: senderTrusted, info: ctxInfo) { count += 1 }
        }
        return count
    }

    // MARK: Manual imports (from the message's attachment menu)

    static func importCalendar(_ text: String, from m: MailMessage) -> String {
        guard let account = MailEngine.shared.account(m.accountID) else { return "This account was removed." }
        var info = Context(ref: m.reference + "|" + m.summary.fromEmail.lowercased(), note: "\(m.senderLabel) · \(m.summary.subject)",
                           account: account, force: true, context: Storage.shared.mainContext, message: m)
        let n = applyCalendar(text, trusted: true, info: &info)
        try? info.context.save()
        return n == 0 ? "Nothing new in this file." : "Added \(n) item\(n == 1 ? "" : "s") to Hush."
    }

    static func importVCards(_ text: String, from m: MailMessage) -> String {
        guard let account = MailEngine.shared.account(m.accountID) else { return "This account was removed." }
        let info = Context(ref: m.reference + "|" + m.summary.fromEmail.lowercased(), note: "\(m.senderLabel) · \(m.summary.subject)",
                           account: account, force: true, context: Storage.shared.mainContext, message: m)
        var n = 0
        for v in ICal.parse(text) where v.name == "VCARD" { if addContact(ICal.contact(from: v), trusted: true, info: info) { n += 1 } }
        try? info.context.save()
        return n == 0 ? "These contacts are already in Hush." : "Added \(n) contact\(n == 1 ? "" : "s")."
    }

    static func addContact(_ addr: MailAddress, signature: String, from m: MailMessage, confirmed: Bool) -> String {
        guard let account = MailEngine.shared.account(m.accountID) else { return "This account was removed." }
        let info = Context(ref: m.reference + "|" + addr.email.lowercased(), note: "\(m.senderLabel) · \(m.summary.subject)",
                           account: account, force: true, context: Storage.shared.mainContext, message: m)
        let ok = addContact(signatureContact(addr, text: signature), trusted: confirmed, info: info, reviewState: confirmed ? "" : nil)
        try? info.context.save()
        return ok ? "Added \(addr.display) to Contacts." : "\(addr.display) is already in your contacts."
    }

    /// People you write to become contact suggestions (if they aren't contacts yet).
    static func noteRecipients(_ recipients: [MailAddress], account: MailAccount, context: ModelContext) {
        guard ScanPrefs.contactsFromSent else { return }
        for r in recipients {
            let info = Context(ref: "sent|" + r.email.lowercased(), note: "You emailed \(r.display)", account: account, force: false, context: context, message: nil)
            var c = FoundContact()
            let words = r.name.split(separator: " ").map(String.init)
            c.first = words.dropLast().joined(separator: " ")
            c.last = words.last ?? ""
            if c.first.isEmpty { c.first = c.last; c.last = "" }
            c.emails = [LabeledValue(label: "other", value: r.email)]
            _ = addContact(c, trusted: false, info: info)
        }
        try? context.save()
    }

    // MARK: Review actions

    static func confirm(_ item: any Reviewable) {
        item.reviewRaw = ""
        if let t = item as? TaskItem { Reminders.sync(t) }
        if let e = item as? CalendarEvent { Reminders.sync(e) }
        if let c = item as? Contact { Reminders.sync(c) }
        try? Storage.shared.mainContext.save()
        OnlineCenter.reloadWidgets()
    }

    static func dismiss(_ item: any Reviewable) {
        let ctx = Storage.shared.mainContext
        if let t = item as? TaskItem {
            ScanPrefs.dismiss(key(t.originRef, "task", t.title))
            Reminders.cancel("task.\(t.id.uuidString)")
            ctx.delete(t)
        } else if let e = item as? CalendarEvent {
            ScanPrefs.dismiss(key(e.originRef, "event", e.title))
            if !e.icalUID.isEmpty { ScanPrefs.dismiss("uid|" + e.icalUID) }
            Reminders.cancel("event.\(e.id.uuidString)")
            ctx.delete(e)
        } else if let c = item as? Contact {
            for e in c.emails { ScanPrefs.dismiss("contact|" + e.value.lowercased()) }
            ctx.delete(c)
        }
        try? ctx.save()
        OnlineCenter.reloadWidgets()
    }

    /// The sender's email, from an item's origin reference.
    static func senderEmail(_ ref: String) -> String? {
        let parts = ref.components(separatedBy: "|")
        guard let last = parts.last, last.contains("@") else { return nil }
        return last
    }

    /// Trust the sender and confirm everything waiting from them.
    static func trustSender(of item: any Reviewable) {
        guard let email = senderEmail(item.originRef) else { confirm(item); return }
        ScanPrefs.trust(email)
        let ctx = Storage.shared.mainContext
        let suffix = "|" + email
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.reviewRaw == "pending" }))) ?? []
        let events = (try? ctx.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.reviewRaw == "pending" }))) ?? []
        let contacts = (try? ctx.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.reviewRaw == "pending" }))) ?? []
        let all: [any Reviewable] = tasks.map { $0 as any Reviewable } + events.map { $0 as any Reviewable } + contacts.map { $0 as any Reviewable }
        for i in all where i.originRef.hasSuffix(suffix) { confirm(i) }
        confirm(item)
    }

    // MARK: Creating items

    struct Context {
        var ref: String
        var note: String
        var account: MailAccount
        var force: Bool
        var context: ModelContext
        var message: MailMessage?
    }

    static func key(_ ref: String, _ kind: String, _ title: String) -> String {
        "\(ref)|\(kind)|\(title.lowercased().trimmed)"
    }

    private static func applyCalendar(_ text: String, trusted: Bool, info: inout Context) -> Int {
        var n = 0
        for cal in ICal.parse(text) where cal.name == "VCALENDAR" {
            let method = cal.text("METHOD") ?? ""
            for v in cal.children where v.name == "VEVENT" && v.prop("RECURRENCE-ID") == nil {
                if let e = ICal.event(from: v, method: method), addEvent(e, trusted: trusted, info: info) { n += 1 }
            }
            for v in cal.children where v.name == "VTODO" {
                if addTask(ICal.task(from: v), trusted: trusted, info: info) { n += 1 }
            }
        }
        return n
    }

    @discardableResult
    static func addEvent(_ e: FoundEvent, trusted: Bool, info: Context) -> Bool {
        let ctx = info.context
        let title = e.title.trimmed.isEmpty ? "Event" : e.title.trimmed
        // Updates and cancellations of an invite we already have.
        if !e.uid.isEmpty {
            let uid = e.uid
            let existing = (try? ctx.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.icalUID == uid }))) ?? []
            if let ev = existing.first(where: { $0.deletedAt == nil }) ?? existing.first {
                if ev.deletedAt != nil && !info.force { return false }
                if e.cancelled {
                    if ev.deletedAt != nil { return false }
                    if ev.reviewRaw == "pending" && ev.originRaw == "email" {
                        Reminders.cancel("event.\(ev.id.uuidString)")
                        ctx.delete(ev)
                        return true
                    }
                    ev.originNote = "Canceled by the organizer. Dismiss to remove it. · " + info.note
                    ev.reviewRaw = "pending"
                    if !ev.title.hasPrefix("Canceled: ") { ev.title = "Canceled: " + ev.title }
                    return true
                }
                let changed = ev.start != e.start || ev.end != e.end || ev.location != e.location || ev.title != title
                guard changed || info.force else { return false }
                ev.title = title
                ev.start = e.start
                ev.end = e.end
                ev.isAllDay = e.allDay
                ev.location = e.location
                ev.recurrenceRule = e.rrule
                if ev.originRaw == "email" {
                    ev.originNote = "Updated · " + info.note
                    ev.reviewRaw = trusted ? "auto" : "pending"
                }
                Reminders.sync(ev)
                return true
            }
            if !info.force && ScanPrefs.isDismissed("uid|" + uid) { return false }
        }
        if e.cancelled { return false }
        // Skip things that are already over.
        if !info.force && max(e.end, e.start) < Calendar.current.startOfDay(for: .now) && e.rrule.isEmpty { return false }
        let k = key(info.ref, "event", title)
        if !info.force && ScanPrefs.isDismissed(k) { return false }
        let ref = info.ref
        let dupes = (try? ctx.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.originRef == ref }))) ?? []
        if dupes.contains(where: { $0.title.lowercased() == title.lowercased() }) { return false }

        let ev = CalendarEvent(start: e.start)
        ev.title = title
        ev.end = max(e.end, e.start)
        ev.isAllDay = e.allDay
        ev.location = e.location
        ev.notes = e.notes
        ev.recurrenceRule = e.rrule
        ev.alertMinutes = e.alertMinutes
        ev.icalUID = e.uid
        ev.spaceID = info.account.targetSpace
        ev.originRaw = "email"
        ev.originRef = info.ref
        ev.originNote = info.note
        ev.reviewRaw = trusted ? "auto" : "pending"
        ctx.insert(ev)
        if trusted { Reminders.sync(ev) }
        return true
    }

    @discardableResult
    static func addTask(_ t: FoundTask, trusted: Bool, info: Context) -> Bool {
        let ctx = info.context
        let title = t.title.trimmed.isEmpty ? "Follow up" : t.title.trimmed
        if t.done { return false }
        if !info.force, let due = t.due, due < Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now { return false }
        let k = key(info.ref, "task", title)
        if !info.force && ScanPrefs.isDismissed(k) { return false }
        let ref = info.ref
        let dupes = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.originRef == ref }))) ?? []
        if dupes.contains(where: { $0.title.lowercased() == title.lowercased() }) { return false }
        let task = TaskItem(title: title)
        task.notes = t.notes
        task.dueDate = t.due
        task.hasDueTime = t.hasTime
        task.remind = t.due != nil
        task.list = t.list
        task.priority = Priority(rawValue: t.priority) ?? .none
        task.spaceID = info.account.targetSpace
        task.originRaw = "email"
        task.originRef = info.ref
        task.originNote = info.note
        task.reviewRaw = trusted ? "auto" : "pending"
        ctx.insert(task)
        if trusted { Reminders.sync(task) }
        return true
    }

    @discardableResult
    static func addContact(_ c: FoundContact, trusted: Bool, info: Context, reviewState: String? = nil) -> Bool {
        let ctx = info.context
        let emails = c.emails.map { $0.value.lowercased().trimmed }.filter { !$0.isEmpty }
        guard !emails.isEmpty || !(c.first + c.last + c.company).trimmed.isEmpty else { return false }
        if emails.contains(where: { $0.contains("noreply") || $0.contains("no-reply") }) { return false }
        if !info.force && emails.contains(where: { ScanPrefs.isDismissed("contact|" + $0) }) { return false }
        // Already known? (Your own addresses count as known.)
        let mine = Set(MailEngine.shared.accounts.map { $0.email.lowercased() })
        if emails.contains(where: { mine.contains($0) }) { return false }
        let existing = (try? ctx.fetch(FetchDescriptor<Contact>())) ?? []
        for other in existing where other.emails.contains(where: { emails.contains($0.value.lowercased().trimmed) }) {
            // Fill in a phone number we didn't have.
            if other.phones.isEmpty && !c.phones.isEmpty && other.deletedAt == nil { other.phones = c.phones }
            return false
        }
        if emails.isEmpty {
            let name = (c.first + " " + c.last).trimmed.lowercased()
            if existing.contains(where: { ($0.firstName + " " + $0.lastName).trimmed.lowercased() == name }) { return false }
        }
        let contact = Contact()
        contact.firstName = c.first
        contact.lastName = c.last
        contact.company = c.company
        contact.emails = c.emails
        contact.phones = c.phones
        contact.address = c.address
        contact.birthday = c.birthday
        contact.notes = c.notes
        contact.spaceID = info.account.targetSpace
        contact.originRaw = "email"
        contact.originRef = info.ref
        contact.originNote = info.note
        contact.reviewRaw = reviewState ?? (trusted ? "auto" : "pending")
        ctx.insert(contact)
        return true
    }

    // MARK: Text helpers

    /// The message's own words: no quoted replies, no long footers.
    static func mainText(_ p: ParsedMessage) -> String {
        var out: [String] = []
        for line in p.plainText.components(separatedBy: "\n") {
            let t = line.trimmed
            if t.hasPrefix(">") { continue }
            if t.range(of: "^(On|Am) .{4,120}(wrote|schrieb):?$", options: .regularExpression) != nil { break }
            if t.hasPrefix("-----Original Message-----") || t.hasPrefix("---------- Forwarded") { break }
            out.append(line)
        }
        return String(out.joined(separator: "\n").prefix(6000))
    }

    static func cleanSubject(_ s: String) -> String {
        var t = s.trimmed
        while let r = t.range(of: "^(re|fw|fwd|aw|wg|antw)(\\[\\d+\\])?\\s*:\\s*", options: [.regularExpression, .caseInsensitive]) {
            t.removeSubrange(r)
        }
        return t.isEmpty ? "Email follow-up" : t
    }

    /// Name, phone and address from the sender's signature.
    static func signatureContact(_ from: MailAddress, text: String) -> FoundContact {
        var c = FoundContact()
        var name = from.name.trimmed
        if name.contains(","), !name.contains(" ") || name.split(separator: ",").count == 2 {
            // "Doe, Jane"
            let parts = name.split(separator: ",").map { $0.trimmed }
            if parts.count == 2 { name = parts[1] + " " + parts[0] }
        }
        let words = name.split(separator: " ").map(String.init)
        c.first = words.dropLast().joined(separator: " ")
        c.last = words.last ?? ""
        if c.first.isEmpty { c.first = c.last; c.last = "" }
        c.emails = [LabeledValue(label: "other", value: from.email)]
        // Signatures live in the last lines before any quote.
        let own = text.components(separatedBy: "\n").prefix { !$0.hasPrefix(">") && $0.range(of: "(wrote|schrieb):\\s*$", options: .regularExpression) == nil }
        let tail = own.suffix(14).joined(separator: "\n")
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {
            for m in detector.matches(in: tail, range: NSRange(tail.startIndex..., in: tail)) {
                if m.resultType == .phoneNumber, let phone = m.phoneNumber, c.phones.count < 2 {
                    let lineRange = (tail as NSString).lineRange(for: m.range)
                    let line = (tail as NSString).substring(with: lineRange).lowercased()
                    let label = line.contains("mob") || line.contains("cell") || line.contains("handy") ? "mobile" : (line.contains("fax") ? "other" : "work")
                    if !line.contains("fax") { c.phones.append(LabeledValue(label: label, value: phone)) }
                }
                if m.resultType == .address, c.address.isEmpty, let comps = m.addressComponents {
                    c.address = [comps[.street], [comps[.zip], comps[.city]].compactMap { $0 }.joined(separator: " "), comps[.country]]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
                }
            }
        }
        return c
    }
}

/// Spots a date in an email and decides whether it reads like an event or a deadline.
enum DateFinder {
    struct Hit {
        enum Kind { case event, task }
        var kind: Kind
        var date: Date
        var hasTime: Bool
        var duration: TimeInterval?
        var location: String
        var sentence: String
    }

    static let eventWords = ["meeting", "meet ", "call", "appointment", "interview", "dinner", "lunch", "breakfast", "coffee", "party",
                             "webinar", "zoom", "teams", "google meet", "conference", "session", "visit", "concert", "game", "class",
                             "lecture", "seminar", "workshop", "training", "termin", "besprechung", "treffen", "verabredung", "abendessen",
                             "mittagessen", "invite", "invitation", "einladung", "event", "reservation", "booking", "check-in"]
    static let taskWords = ["due", "deadline", "by ", "until", "no later than", "expires", "expiry", "expiration", "renew", "payment",
                            "invoice", "bill", "rsvp", "submit", "send me", "please send", "reminder", "remind", "fällig", "frist",
                            "bis zum", "bis spätestens", "rechnung", "zahlung", "abgabe", "läuft ab"]

    static func find(subject: String, text: String, received: Date) -> Hit? {
        let all = subject + "\n" + text
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue | NSTextCheckingResult.CheckingType.address.rawValue | NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let ns = all as NSString
        let matches = detector.matches(in: all, range: NSRange(location: 0, length: ns.length))
        let lowerSubject = subject.lowercased()
        var location = ""
        for m in matches {
            if m.resultType == .address, location.isEmpty {
                location = ns.substring(with: m.range).replacingOccurrences(of: "\n", with: ", ")
            }
            if m.resultType == .link, location.isEmpty, let url = m.url?.absoluteString.lowercased(),
               url.contains("zoom.us/j") || url.contains("teams.microsoft.com") || url.contains("meet.google.com") || url.contains("meet.jit.si") {
                location = m.url?.absoluteString ?? ""
            }
        }
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 400, to: now) ?? now
        for m in matches where m.resultType == .date {
            guard let date = m.date, date > now.addingTimeInterval(-3600), date < horizon else { continue }
            let matched = ns.substring(with: m.range)
            // "today" in an old email isn't today.
            if Calendar.current.dateComponents([.day], from: received, to: now).day ?? 0 > 2,
               matched.lowercased().contains("today") || matched.lowercased().contains("tomorrow") || matched.lowercased().contains("heute") { continue }
            let hasTime = matched.range(of: "\\d{1,2}[:.]\\d{2}|\\d\\s?(am|pm)|uhr|noon|midnight|o'clock", options: [.regularExpression, .caseInsensitive]) != nil
            let start = max(0, m.range.location - 90)
            let end = min(ns.length, m.range.location + m.range.length + 90)
            let around = ns.substring(with: NSRange(location: start, length: end - start)).lowercased()
            let sentence = sentenceAround(ns, m.range)
            let isEvent = eventWords.contains { around.contains($0) || lowerSubject.contains($0) }
            let isTask = taskWords.contains { around.contains($0) }
            if hasTime && isEvent {
                return Hit(kind: .event, date: date, hasTime: true, duration: m.duration > 0 ? m.duration : nil, location: location, sentence: sentence)
            }
            if isTask {
                return Hit(kind: .task, date: date, hasTime: hasTime, duration: nil, location: location, sentence: sentence)
            }
            if eventWords.contains(where: { lowerSubject.contains($0) }) {
                return Hit(kind: .event, date: Calendar.current.startOfDay(for: date), hasTime: false, duration: nil, location: location, sentence: sentence)
            }
        }
        return nil
    }

    private static func sentenceAround(_ ns: NSString, _ range: NSRange) -> String {
        var start = range.location
        while start > 0 {
            let c = ns.character(at: start - 1)
            if c == 0x2E || c == 0x0A || c == 0x21 || c == 0x3F { break }
            start -= 1
        }
        var end = range.location + range.length
        while end < ns.length {
            let c = ns.character(at: end)
            end += 1
            if c == 0x2E || c == 0x0A || c == 0x21 || c == 0x3F { break }
        }
        return ns.substring(with: NSRange(location: start, length: end - start)).trimmed
    }
}

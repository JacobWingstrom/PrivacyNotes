import Foundation

/// One "NAME;PARAM=x:value" line of an iCalendar or vCard file.
struct ICalProperty {
    var name: String
    var params: [String: String] = [:]
    var value: String

    func param(_ key: String) -> String? { params[key.uppercased()] }
    var text: String { ICal.unescape(value) }

    var line: String {
        var s = name
        for (k, v) in params.sorted(by: { $0.key < $1.key }) {
            let needsQuotes = v.contains(":") || v.contains(";") || v.contains(",")
            s += ";\(k)=" + (needsQuotes ? "\"\(v)\"" : v)
        }
        return s + ":" + value
    }
}

/// BEGIN:X … END:X with its properties and nested components.
final class ICalComponent {
    var name: String
    var properties: [ICalProperty] = []
    var children: [ICalComponent] = []

    init(name: String) { self.name = name }

    func prop(_ n: String) -> ICalProperty? { properties.first { $0.name == n.uppercased() } }
    func props(_ n: String) -> [ICalProperty] { properties.filter { $0.name == n.uppercased() } }
    func text(_ n: String) -> String? { prop(n)?.text }
    func child(_ n: String) -> ICalComponent? { children.first { $0.name == n.uppercased() } }
    func all(_ n: String) -> [ICalComponent] {
        var out: [ICalComponent] = []
        for c in children {
            if c.name == n.uppercased() { out.append(c) }
            out += c.all(n)
        }
        return out
    }

    func remove(_ names: Set<String>) { properties.removeAll { names.contains($0.name) } }
    func set(_ name: String, _ value: String, params: [String: String] = [:]) {
        properties.removeAll { $0.name == name }
        properties.append(ICalProperty(name: name, params: params, value: value))
    }

    func serialize() -> String {
        var lines = ["BEGIN:\(name)"]
        lines += properties.map { ICal.fold($0.line) }
        for c in children { lines.append(c.serialize()) }
        lines.append("END:\(name)")
        return lines.joined(separator: "\r\n")
    }
}

enum ICal {
    static func parse(_ text: String) -> [ICalComponent] {
        var roots: [ICalComponent] = []
        var stack: [ICalComponent] = []
        for line in unfold(text) {
            guard let p = parseLine(line) else { continue }
            if p.name == "BEGIN" {
                let c = ICalComponent(name: p.value.uppercased().trimmingCharacters(in: .whitespaces))
                if let parent = stack.last { parent.children.append(c) } else { roots.append(c) }
                stack.append(c)
            } else if p.name == "END" {
                if !stack.isEmpty { stack.removeLast() }
            } else {
                stack.last?.properties.append(p)
            }
        }
        return roots
    }

    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }
        return lines
    }

    static func parseLine(_ line: String) -> ICalProperty? {
        // Find the first ":" that isn't inside a quoted parameter value.
        var inQuotes = false
        var colon: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            if c == ":" && !inQuotes { colon = i; break }
        }
        guard let colon else { return nil }
        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])
        var parts: [String] = []
        var current = ""
        inQuotes = false
        for c in head {
            if c == "\"" { inQuotes.toggle(); continue }
            if c == ";" && !inQuotes { parts.append(current); current = ""; continue }
            current.append(c)
        }
        parts.append(current)
        var name = parts.removeFirst().uppercased()
        // vCard groups: "item1.EMAIL" → "EMAIL"
        if let dot = name.lastIndex(of: ".") { name = String(name[name.index(after: dot)...]) }
        var params: [String: String] = [:]
        for p in parts {
            let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                let key = kv[0].uppercased()
                params[key] = params[key].map { $0 + "," + kv[1] } ?? kv[1]
            } else if kv.count == 1 {
                // vCard 2.1 bare types: "TEL;CELL:…"
                params["TYPE"] = params["TYPE"].map { $0 + "," + kv[0] } ?? kv[0]
            }
        }
        return ICalProperty(name: name, params: params, value: value)
    }

    static func fold(_ line: String) -> String {
        var out = ""
        var count = 0
        for ch in line {
            let n = String(ch).utf8.count
            if count + n > 74 {
                out += "\r\n "
                count = 1
            }
            out.append(ch)
            count += n
        }
        return out
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var escaped = false
        for c in s {
            if escaped {
                switch c {
                case "n", "N": out.append("\n")
                default: out.append(c)
                }
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: Dates

    /// Windows time zone names used by Outlook/Exchange invites.
    static let windowsZones: [String: String] = [
        "W. Europe Standard Time": "Europe/Berlin", "Romance Standard Time": "Europe/Paris", "Central Europe Standard Time": "Europe/Budapest",
        "Central European Standard Time": "Europe/Warsaw", "GMT Standard Time": "Europe/London", "Greenwich Standard Time": "Atlantic/Reykjavik",
        "E. Europe Standard Time": "Europe/Chisinau", "FLE Standard Time": "Europe/Kiev", "GTB Standard Time": "Europe/Bucharest",
        "Russian Standard Time": "Europe/Moscow", "Eastern Standard Time": "America/New_York", "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver", "US Mountain Standard Time": "America/Phoenix", "Pacific Standard Time": "America/Los_Angeles",
        "Alaskan Standard Time": "America/Anchorage", "Hawaiian Standard Time": "Pacific/Honolulu", "Atlantic Standard Time": "America/Halifax",
        "India Standard Time": "Asia/Kolkata", "China Standard Time": "Asia/Shanghai", "Tokyo Standard Time": "Asia/Tokyo",
        "AUS Eastern Standard Time": "Australia/Sydney", "Singapore Standard Time": "Asia/Singapore", "UTC": "UTC",
        "Coordinated Universal Time": "UTC", "Arabian Standard Time": "Asia/Dubai", "Israel Standard Time": "Asia/Jerusalem",
        "South Africa Standard Time": "Africa/Johannesburg", "E. South America Standard Time": "America/Sao_Paulo",
        "New Zealand Standard Time": "Pacific/Auckland", "Korea Standard Time": "Asia/Seoul",
    ]

    static func timeZone(_ tzid: String?) -> TimeZone {
        guard var id = tzid?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")), !id.isEmpty else { return .current }
        if let tz = TimeZone(identifier: id) { return tz }
        if let mapped = windowsZones[id], let tz = TimeZone(identifier: mapped) { return tz }
        // "/mozilla.org/20050126_1/Europe/Berlin" and similar prefixes
        while let slash = id.firstIndex(of: "/") {
            id = String(id[id.index(after: slash)...])
            if let tz = TimeZone(identifier: id) { return tz }
        }
        return .current
    }

    /// (date, isAllDay) for DTSTART / DTEND / DUE / EXDATE-style properties.
    static func date(_ p: ICalProperty) -> (Date, Bool)? {
        date(p.value.trimmingCharacters(in: .whitespaces), tzid: p.param("TZID"), dateOnly: p.param("VALUE") == "DATE")
    }

    static func date(_ value: String, tzid: String?, dateOnly: Bool = false) -> (Date, Bool)? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        if dateOnly || value.count == 8 {
            f.timeZone = .current
            f.dateFormat = "yyyyMMdd"
            return f.date(from: String(value.prefix(8))).map { ($0, true) }
        }
        if value.hasSuffix("Z") {
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else {
            f.timeZone = timeZone(tzid)
            f.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return f.date(from: value).map { ($0, false) }
    }

    static func utc(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    static func dateOnly(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    /// "-PT15M", "-P1D", "PT0S" → minutes before (positive).
    static func minutesBefore(_ trigger: String) -> Int? {
        var s = trigger.uppercased()
        let negative = s.hasPrefix("-")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard s.hasPrefix("P") else { return nil }
        var total = 0
        var number = ""
        var inTime = false
        for c in s.dropFirst() {
            if c.isNumber { number.append(c); continue }
            let n = Int(number) ?? 0
            number = ""
            switch c {
            case "T": inTime = true
            case "W": total += n * 7 * 1440
            case "D": total += n * 1440
            case "H": total += n * 60
            case "M": total += inTime ? n : n * 43200
            case "S": total += n / 60
            default: break
            }
        }
        return negative || total == 0 ? total : -total
    }
}

// MARK: - Mapping to Hush items

struct FoundEvent {
    var uid = ""
    var title = ""
    var start = Date()
    var end = Date()
    var allDay = false
    var location = ""
    var notes = ""
    var rrule = ""
    var alertMinutes = -1
    var cancelled = false
    var sequence = 0
}

struct FoundTask {
    var uid = ""
    var title = ""
    var due: Date?
    var hasTime = false
    var done = false
    var completedAt: Date?
    var priority = 0
    var notes = ""
    var list = ""
}

struct FoundContact {
    var uid = ""
    var first = ""
    var last = ""
    var company = ""
    var emails: [LabeledValue] = []
    var phones: [LabeledValue] = []
    var address = ""
    var birthday: Date?
    var notes = ""
}

extension ICal {
    static func event(from v: ICalComponent, method: String = "") -> FoundEvent? {
        guard let startProp = v.prop("DTSTART"), let parsedStart = date(startProp) else { return nil }
        let (start, allDay) = parsedStart
        var e = FoundEvent()
        e.uid = v.text("UID") ?? ""
        e.title = v.text("SUMMARY") ?? ""
        e.start = start
        e.allDay = allDay
        if let endProp = v.prop("DTEND"), let end = date(endProp)?.0 {
            e.end = allDay ? end.addingTimeInterval(-1) : end
        } else if let dur = v.text("DURATION"), let mins = minutesBefore("-" + dur) {
            e.end = start.addingTimeInterval(Double(mins * 60) - (allDay ? 1 : 0))
        } else {
            e.end = allDay ? start.addingTimeInterval(86399) : start.addingTimeInterval(3600)
        }
        if e.end < e.start { e.end = e.start }
        e.location = v.text("LOCATION") ?? ""
        e.notes = v.text("DESCRIPTION") ?? ""
        if let rr = v.prop("RRULE")?.value {
            var rule = rr
            let ex = v.props("EXDATE").flatMap { p in
                p.value.split(separator: ",").compactMap { date(String($0), tzid: p.param("TZID"), dateOnly: p.param("VALUE") == "DATE")?.0 }
            }
            if !ex.isEmpty { rule += "|EX=" + ex.map { Recurrence.dayKey($0) }.joined(separator: ",") }
            e.rrule = rule
        }
        if let alarm = v.children.first(where: { $0.name == "VALARM" }), let trig = alarm.prop("TRIGGER"), trig.param("VALUE") != "DATE-TIME" {
            e.alertMinutes = max(minutesBefore(trig.value) ?? -1, -1)
        }
        e.cancelled = method.uppercased() == "CANCEL" || (v.text("STATUS") ?? "").uppercased() == "CANCELLED"
        e.sequence = Int(v.text("SEQUENCE") ?? "") ?? 0
        return e
    }

    static func task(from v: ICalComponent) -> FoundTask {
        var t = FoundTask()
        t.uid = v.text("UID") ?? ""
        t.title = v.text("SUMMARY") ?? ""
        if let p = v.prop("DUE") ?? v.prop("DTSTART"), let r = date(p) {
            t.due = r.0
            t.hasTime = !r.1
        }
        let status = (v.text("STATUS") ?? "").uppercased()
        t.done = status == "COMPLETED" || v.prop("COMPLETED") != nil
        if let p = v.prop("COMPLETED"), let d = date(p)?.0 { t.completedAt = d }
        let pr = Int(v.text("PRIORITY") ?? "") ?? 0
        t.priority = pr == 0 ? 0 : (pr <= 4 ? 3 : (pr == 5 ? 2 : 1))
        t.notes = v.text("DESCRIPTION") ?? ""
        return t
    }

    static func contact(from v: ICalComponent) -> FoundContact {
        var c = FoundContact()
        c.uid = v.text("UID") ?? ""
        if let n = v.prop("N")?.value {
            let parts = n.components(separatedBy: ";").map(ICal.unescape)
            c.last = parts.first ?? ""
            c.first = parts.count > 1 ? parts[1] : ""
        }
        if c.first.isEmpty && c.last.isEmpty, let fn = v.text("FN") {
            let words = fn.split(separator: " ")
            c.first = words.dropLast().joined(separator: " ")
            c.last = words.last.map(String.init) ?? ""
            if c.first.isEmpty { c.first = c.last; c.last = "" }
        }
        c.company = (v.prop("ORG")?.value.components(separatedBy: ";").first).map(ICal.unescape) ?? ""
        func label(_ p: ICalProperty, _ fallback: String) -> String {
            let types = (p.param("TYPE") ?? "").lowercased()
            if types.contains("cell") || types.contains("mobile") { return "mobile" }
            if types.contains("work") { return "work" }
            if types.contains("home") { return p.name == "EMAIL" ? "personal" : "home" }
            return fallback
        }
        c.emails = v.props("EMAIL").map { LabeledValue(label: label($0, "other"), value: $0.text) }
        c.phones = v.props("TEL").map { LabeledValue(label: label($0, "mobile"), value: $0.text.replacingOccurrences(of: "tel:", with: "")) }
        if let adr = v.prop("ADR")?.value {
            let parts = adr.components(separatedBy: ";").map(ICal.unescape)
            // PO box; extended; street; city; region; postal code; country
            let street = parts.count > 2 ? parts[2] : ""
            let city = [parts.count > 5 ? parts[5] : "", parts.count > 3 ? parts[3] : ""].filter { !$0.isEmpty }.joined(separator: " ")
            let country = parts.count > 6 ? parts[6] : ""
            c.address = [street, city, country].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if let b = v.text("BDAY") {
            let digits = b.replacingOccurrences(of: "-", with: "")
            if digits.hasPrefix("--") || b.hasPrefix("--") {
                c.birthday = date("2000" + b.replacingOccurrences(of: "-", with: "").suffix(4), tzid: nil, dateOnly: true)?.0
            } else {
                c.birthday = date(String(digits.prefix(8)), tzid: nil, dateOnly: true)?.0
            }
        }
        c.notes = v.text("NOTE") ?? ""
        return c
    }

    // MARK: Writing

    static let managedEventProps: Set<String> = ["DTSTART", "DTEND", "DURATION", "SUMMARY", "LOCATION", "DESCRIPTION", "DTSTAMP", "LAST-MODIFIED", "RRULE", "EXDATE", "UID", "SEQUENCE"]

    /// A VCALENDAR for the event; keeps unknown properties and exceptions from `original`.
    static func calendar(for e: CalendarEvent, uid: String, original: String?) -> String {
        let roots = original.map(parse) ?? []
        let cal = roots.first { $0.name == "VCALENDAR" } ?? ICalComponent(name: "VCALENDAR")
        if cal.prop("VERSION") == nil { cal.set("VERSION", "2.0") }
        if cal.prop("PRODID") == nil { cal.set("PRODID", "-//Hush//Hush Notes//EN") }
        cal.remove(["METHOD"])
        let master = cal.children.first { $0.name == "VEVENT" && $0.prop("RECURRENCE-ID") == nil } ?? {
            let v = ICalComponent(name: "VEVENT")
            cal.children.append(v)
            return v
        }()
        var sequence = Int(master.text("SEQUENCE") ?? "") ?? 0
        if original != nil { sequence += 1 }
        master.remove(managedEventProps)
        master.set("UID", uid)
        master.set("DTSTAMP", utc(Date()))
        master.set("LAST-MODIFIED", utc(Date()))
        master.set("SEQUENCE", String(sequence))
        if e.isAllDay {
            master.set("DTSTART", dateOnly(e.start), params: ["VALUE": "DATE"])
            let endDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(e.end, e.start))) ?? e.end
            master.set("DTEND", dateOnly(endDay), params: ["VALUE": "DATE"])
        } else {
            master.set("DTSTART", utc(e.start))
            master.set("DTEND", utc(max(e.end, e.start)))
        }
        master.set("SUMMARY", escape(e.title))
        if !e.location.isEmpty { master.set("LOCATION", escape(e.location)) }
        if !e.notes.isEmpty { master.set("DESCRIPTION", escape(e.notes)) }
        if let rule = Recurrence(e.recurrenceRule) {
            master.set("RRULE", rule.rruleString)
            if !rule.exceptions.isEmpty {
                if e.isAllDay {
                    master.properties.append(ICalProperty(name: "EXDATE", params: ["VALUE": "DATE"], value: rule.exceptions.sorted().joined(separator: ",")))
                } else {
                    let time = Calendar.current.dateComponents([.hour, .minute, .second], from: e.start)
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "yyyyMMdd"
                    let values = rule.exceptions.sorted().compactMap { key -> String? in
                        guard let day = f.date(from: key),
                              let d = Calendar.current.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) else { return nil }
                        return utc(d)
                    }
                    master.properties.append(ICalProperty(name: "EXDATE", value: values.joined(separator: ",")))
                }
            }
        }
        // Alarm: replace with Hush's single alert.
        master.children.removeAll { $0.name == "VALARM" }
        if e.alertMinutes >= 0 {
            let alarm = ICalComponent(name: "VALARM")
            alarm.set("ACTION", "DISPLAY")
            alarm.set("DESCRIPTION", escape(e.title.isEmpty ? "Reminder" : e.title))
            alarm.set("TRIGGER", e.alertMinutes == 0 ? "PT0S" : "-PT\(e.alertMinutes)M")
            master.children.append(alarm)
        }
        return cal.serialize() + "\r\n"
    }

    static let managedTodoProps: Set<String> = ["SUMMARY", "DESCRIPTION", "DUE", "STATUS", "COMPLETED", "PRIORITY", "DTSTAMP", "LAST-MODIFIED", "UID", "PERCENT-COMPLETE"]

    static func calendar(for t: TaskItem, uid: String, original: String?) -> String {
        let roots = original.map(parse) ?? []
        let cal = roots.first { $0.name == "VCALENDAR" } ?? ICalComponent(name: "VCALENDAR")
        if cal.prop("VERSION") == nil { cal.set("VERSION", "2.0") }
        if cal.prop("PRODID") == nil { cal.set("PRODID", "-//Hush//Hush Notes//EN") }
        let todo = cal.children.first { $0.name == "VTODO" } ?? {
            let v = ICalComponent(name: "VTODO")
            cal.children.append(v)
            return v
        }()
        todo.remove(managedTodoProps)
        todo.set("UID", uid)
        todo.set("DTSTAMP", utc(Date()))
        todo.set("LAST-MODIFIED", utc(Date()))
        todo.set("SUMMARY", escape(t.title))
        if !t.notes.isEmpty { todo.set("DESCRIPTION", escape(t.notes)) }
        if let due = t.dueDate {
            if t.hasDueTime { todo.set("DUE", utc(due)) } else { todo.set("DUE", dateOnly(due), params: ["VALUE": "DATE"]) }
            // A DTSTART after the new DUE makes the item invalid.
            if let s = todo.prop("DTSTART"), let start = date(s)?.0, start > due { todo.remove(["DTSTART"]) }
        }
        if t.isDone {
            todo.set("STATUS", "COMPLETED")
            todo.set("PERCENT-COMPLETE", "100")
            todo.set("COMPLETED", utc(t.completedAt ?? Date()))
        } else {
            todo.set("STATUS", "NEEDS-ACTION")
        }
        switch t.priority {
        case .high: todo.set("PRIORITY", "1")
        case .medium: todo.set("PRIORITY", "5")
        case .low: todo.set("PRIORITY", "9")
        case .none: break
        }
        return cal.serialize() + "\r\n"
    }

    static let managedCardProps: Set<String> = ["N", "FN", "ORG", "EMAIL", "TEL", "ADR", "BDAY", "NOTE", "UID", "REV"]

    static func vcard(for c: Contact, uid: String, original: String?) -> String {
        let card = (original.map(parse) ?? []).first { $0.name == "VCARD" } ?? ICalComponent(name: "VCARD")
        if card.prop("VERSION") == nil { card.set("VERSION", "3.0") }
        let version = card.prop("VERSION")?.value ?? "3.0"
        card.remove(managedCardProps)
        card.set("UID", uid)
        card.set("N", [escape(c.lastName), escape(c.firstName), "", "", ""].joined(separator: ";"))
        card.set("FN", escape(c.displayName == "No Name" ? c.company : c.displayName))
        if !c.company.isEmpty { card.set("ORG", escape(c.company)) }
        func typ(_ label: String, phone: Bool) -> String {
            switch label.lowercased() {
            case "mobile": return "CELL"
            case "work": return "WORK"
            case "home", "personal": return "HOME"
            default: return phone ? "VOICE" : "INTERNET"
            }
        }
        for e in c.emails where !e.value.trimmed.isEmpty {
            card.properties.append(ICalProperty(name: "EMAIL", params: ["TYPE": typ(e.label, phone: false)], value: escape(e.value.trimmed)))
        }
        for p in c.phones where !p.value.trimmed.isEmpty {
            card.properties.append(ICalProperty(name: "TEL", params: ["TYPE": typ(p.label, phone: true)], value: escape(p.value.trimmed)))
        }
        if !c.address.trimmed.isEmpty {
            let lines = c.address.components(separatedBy: "\n").map { $0.trimmed }.filter { !$0.isEmpty }
            // Street on the first line, the rest as locality; good enough for a round trip.
            let street = lines.first ?? ""
            let rest = lines.dropFirst().joined(separator: ", ")
            card.properties.append(ICalProperty(name: "ADR", params: ["TYPE": "HOME"], value: ["", "", escape(street), escape(rest), "", "", ""].joined(separator: ";")))
        }
        if let b = c.birthday {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = version.hasPrefix("4") ? "yyyyMMdd" : "yyyy-MM-dd"
            card.set("BDAY", f.string(from: b))
        }
        if !c.notes.isEmpty { card.set("NOTE", escape(c.notes)) }
        card.set("REV", utc(Date()))
        return card.serialize() + "\r\n"
    }
}

import Foundation

/// The parts of an iCalendar RRULE that Hush shows in its calendar:
/// FREQ (daily, weekly, monthly, yearly), INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY and BYMONTH,
/// plus skipped days stored after "|EX=".
struct Recurrence: Equatable {
    enum Freq: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

    var freq: Freq
    var interval = 1
    var count: Int?
    var until: Date?
    /// Weekdays (1 = Sunday … 7 = Saturday) with an optional position (2 = second, -1 = last).
    var byDay: [(ordinal: Int, weekday: Int)] = []
    var byMonthDay: [Int] = []
    var byMonth: [Int] = []
    /// Skipped days as "yyyyMMdd".
    var exceptions: Set<String> = []

    static func == (a: Recurrence, b: Recurrence) -> Bool { a.rruleString == b.rruleString && a.exceptions == b.exceptions }

    private static let dayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    init(freq: Freq) { self.freq = freq }

    init?(_ stored: String) {
        let halves = stored.components(separatedBy: "|EX=")
        var freq: Freq?
        for part in halves[0].split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let key = kv[0].uppercased(), value = kv[1].uppercased()
            switch key {
            case "FREQ": freq = Freq(rawValue: value)
            case "INTERVAL": interval = max(Int(value) ?? 1, 1)
            case "COUNT": count = Int(value)
            case "UNTIL": until = Self.parseUntil(value)
            case "BYDAY":
                byDay = value.split(separator: ",").compactMap { token in
                    let t = String(token)
                    guard t.count >= 2, let idx = Self.dayCodes.firstIndex(of: String(t.suffix(2))) else { return nil }
                    return (Int(t.dropLast(2)) ?? 0, idx + 1)
                }
            case "BYMONTHDAY": byMonthDay = value.split(separator: ",").compactMap { Int($0) }
            case "BYMONTH": byMonth = value.split(separator: ",").compactMap { Int($0) }
            default: break
            }
        }
        guard let freq else { return nil }
        self.freq = freq
        if halves.count > 1 { exceptions = Set(halves[1].split(separator: ",").map(String.init)) }
    }

    /// The RRULE value without the exceptions.
    var rruleString: String {
        var parts = ["FREQ=\(freq.rawValue)"]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if let count { parts.append("COUNT=\(count)") }
        if let until { parts.append("UNTIL=\(Self.untilFormatter.string(from: until))") }
        if !byDay.isEmpty {
            parts.append("BYDAY=" + byDay.map { ($0.ordinal == 0 ? "" : "\($0.ordinal)") + Self.dayCodes[$0.weekday - 1] }.joined(separator: ","))
        }
        if !byMonthDay.isEmpty { parts.append("BYMONTHDAY=" + byMonthDay.map(String.init).joined(separator: ",")) }
        if !byMonth.isEmpty { parts.append("BYMONTH=" + byMonth.map(String.init).joined(separator: ",")) }
        return parts.joined(separator: ";")
    }

    var stored: String {
        exceptions.isEmpty ? rruleString : rruleString + "|EX=" + exceptions.sorted().joined(separator: ",")
    }

    /// "Every week", "Every 2 months" …
    var summary: String {
        let unit: String
        switch freq {
        case .daily: unit = "day"
        case .weekly: unit = "week"
        case .monthly: unit = "month"
        case .yearly: unit = "year"
        }
        var s = interval == 1 ? "Every \(unit)" : "Every \(interval) \(unit)s"
        if freq == .weekly && !byDay.isEmpty {
            let names = Calendar.current.shortWeekdaySymbols
            s += " on " + byDay.map { names[$0.weekday - 1] }.joined(separator: ", ")
        }
        if let count { s += ", \(count) times" }
        if let until { s += ", until \(until.formatted(date: .abbreviated, time: .omitted))" }
        return s
    }

    private static let untilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    private static func parseUntil(_ v: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if v.count == 8 {
            f.timeZone = .current
            f.dateFormat = "yyyyMMdd"
            return f.date(from: v).map { $0.addingTimeInterval(86399) }
        }
        f.timeZone = v.hasSuffix("Z") ? TimeZone(identifier: "UTC") : .current
        f.dateFormat = v.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        return f.date(from: v)
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// If the series has an occurrence starting on `day`, its start time.
    func occurrenceStart(on day: Date, seriesStart: Date, calendar cal: Calendar) -> Date? {
        let first = cal.startOfDay(for: seriesStart)
        let d = cal.startOfDay(for: day)
        guard d >= first else { return nil }
        guard matches(d, first: first, seriesStart: seriesStart, cal: cal) else { return nil }
        guard !exceptions.contains(Self.dayKey(d, calendar: cal)) else { return nil }
        let time = cal.dateComponents([.hour, .minute, .second], from: seriesStart)
        guard let start = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: d) else { return nil }
        if let until, start > until { return nil }
        if let count {
            // Count every occurrence up to this one (bounded, so huge series stay cheap enough).
            var n = 0
            var cursor = first
            var steps = 0
            while cursor <= d && steps < 3700 {
                if matches(cursor, first: first, seriesStart: seriesStart, cal: cal) { n += 1 }
                if n > count { return nil }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? d.addingTimeInterval(86400)
                steps += 1
            }
            if n > count { return nil }
        }
        return start
    }

    private func matches(_ d: Date, first: Date, seriesStart: Date, cal: Calendar) -> Bool {
        let comps = cal.dateComponents([.year, .month, .day, .weekday], from: d)
        let startComps = cal.dateComponents([.year, .month, .day, .weekday], from: seriesStart)
        if !byMonth.isEmpty && !byMonth.contains(comps.month ?? 0) { return false }
        switch freq {
        case .daily:
            let days = cal.dateComponents([.day], from: first, to: d).day ?? 0
            guard days % interval == 0 else { return false }
            if !byDay.isEmpty && !byDay.contains(where: { $0.weekday == comps.weekday }) { return false }
            return true
        case .weekly:
            let weekdays = byDay.isEmpty ? [startComps.weekday ?? 1] : byDay.map(\.weekday)
            guard weekdays.contains(comps.weekday ?? 0) else { return false }
            var c = cal
            c.firstWeekday = 2
            let a = c.dateInterval(of: .weekOfYear, for: first)?.start ?? first
            let b = c.dateInterval(of: .weekOfYear, for: d)?.start ?? d
            let weeks = (c.dateComponents([.day], from: a, to: b).day ?? 0) / 7
            return weeks % interval == 0
        case .monthly:
            let months = ((comps.year ?? 0) - (startComps.year ?? 0)) * 12 + (comps.month ?? 0) - (startComps.month ?? 0)
            guard months >= 0, months % interval == 0 else { return false }
            return dayMatchesInMonth(d, comps: comps, startDay: startComps.day ?? 1, cal: cal)
        case .yearly:
            let years = (comps.year ?? 0) - (startComps.year ?? 0)
            guard years >= 0, years % interval == 0 else { return false }
            if byMonth.isEmpty && comps.month != startComps.month { return false }
            return dayMatchesInMonth(d, comps: comps, startDay: startComps.day ?? 1, cal: cal)
        }
    }

    private func dayMatchesInMonth(_ d: Date, comps: DateComponents, startDay: Int, cal: Calendar) -> Bool {
        let day = comps.day ?? 0
        let daysInMonth = cal.range(of: .day, in: .month, for: d)?.count ?? 31
        if !byMonthDay.isEmpty {
            return byMonthDay.contains { $0 > 0 ? $0 == day : daysInMonth + $0 + 1 == day }
        }
        if !byDay.isEmpty {
            return byDay.contains { rule in
                guard rule.weekday == comps.weekday else { return false }
                if rule.ordinal == 0 { return true }
                if rule.ordinal > 0 { return (day - 1) / 7 + 1 == rule.ordinal }
                return (daysInMonth - day) / 7 + 1 == -rule.ordinal
            }
        }
        return day == startDay
    }
}

import Foundation

/// Turns "Call mom tomorrow 5pm !high #family every week" into a task.
/// Everything is parsed on the device with Apple's built-in date detector.
struct ParsedTask: Equatable {
    var title: String
    var dueDate: Date?
    var hasTime = false
    var priority: Priority = .none
    var list = ""
    var repeatRule: RepeatRule = .none
    var remind = false
    var minutes: Int?

    var hasExtras: Bool { dueDate != nil || priority != .none || !list.isEmpty || repeatRule != .none || minutes != nil }
}

enum TaskParser {
    static func parse(_ input: String, now: Date = .now) -> ParsedTask {
        var text = " " + input + " "
        var result = ParsedTask(title: input)

        func take(_ pattern: String, _ body: (NSTextCheckingResult, NSString) -> Void) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                body(m, ns)
                text = ns.replacingCharacters(in: m.range, with: " ")
            }
        }

        // Priority: !high !med !low, !!!, !1–!3
        take("(?<=\\s)!(high|h|3|!!)(?=\\s)|(?<=\\s)!!!(?=\\s)") { _, _ in result.priority = .high }
        if result.priority == .none { take("(?<=\\s)!(medium|med|m|2)(?=\\s)|(?<=\\s)!!(?=\\s)") { _, _ in result.priority = .medium } }
        if result.priority == .none { take("(?<=\\s)!(low|l|1)?(?=\\s)") { _, _ in result.priority = .low } }

        // List: #list or #multi-word-list
        take("(?<=\\s)#([\\w-]+)(?=\\s)") { m, ns in
            result.list = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "-", with: " ")
        }

        // Repeat
        let repeats: [(String, RepeatRule)] = [
            ("every\\s+weekday|weekdays", .weekdays), ("every\\s+day|daily", .daily), ("every\\s+week|weekly", .weekly),
            ("every\\s+month|monthly", .monthly), ("every\\s+year|yearly|annually", .yearly),
        ]
        for (p, rule) in repeats where result.repeatRule == .none {
            take("(?<=\\s)(\(p))(?=\\s)") { _, _ in result.repeatRule = rule }
        }
        // "every monday" → weekly starting next Monday
        if let re = try? NSRegularExpression(pattern: "(?<=\\s)every\\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?=\\s)", options: [.caseInsensitive]) {
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                result.repeatRule = .weekly
                text = ns.replacingCharacters(in: m.range, with: " next \(ns.substring(with: m.range(at: 1))) ")
            }
        }

        // Duration: "for 30m", "for 1h", "45min"
        take("(?<=\\s)(for\\s+)?(\\d{1,3})\\s?(m|min|mins|minutes|h|hr|hrs|hour|hours)(?=\\s)") { m, ns in
            let n = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let unit = ns.substring(with: m.range(at: 3)).lowercased()
            result.minutes = unit.hasPrefix("h") ? n * 60 : n
        }

        // Words the date detector misses
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        take("(?<=\\s)(tonight)(?=\\s)") { _, _ in
            result.dueDate = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now); result.hasTime = true
        }
        take("(?<=\\s)(this\\s+weekend|weekend)(?=\\s)") { _, _ in
            let wd = cal.component(.weekday, from: today)
            result.dueDate = cal.date(byAdding: .day, value: (7 - wd + 7) % 7, to: today)
        }
        take("(?<=\\s)(someday|later)(?=\\s)") { _, _ in result.dueDate = nil }

        // Dates and times via NSDataDetector
        if result.dueDate == nil, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let ns = text as NSString
            if let m = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), let date = m.date {
                let phrase = ns.substring(with: m.range).lowercased()
                let mentionsTime = phrase.range(of: "\\d\\s?(am|pm)|\\d:\\d\\d|noon|midnight|morning|afternoon|evening|at \\d", options: .regularExpression) != nil
                result.hasTime = mentionsTime
                result.dueDate = mentionsTime ? date : cal.startOfDay(for: date)
                if !mentionsTime, phrase.contains("morning") { result.dueDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date); result.hasTime = true }
                text = ns.replacingCharacters(in: m.range, with: " ")
            }
        }
        if result.hasTime { result.remind = true }

        // Leftover words like "at", "on", "by", "due" at the ends
        var title = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        for _ in 0..<2 {
            title = title.replacingOccurrences(of: "\\s+(at|on|by|due|in|for|this)$", with: "", options: [.regularExpression, .caseInsensitive])
        }
        result.title = title.isEmpty ? input.trimmingCharacters(in: .whitespaces) : title
        return result
    }

    static func apply(_ p: ParsedTask, to t: TaskItem) {
        t.title = p.title
        if let d = p.dueDate { t.dueDate = d; t.hasDueTime = p.hasTime }
        if p.priority != .none { t.priority = p.priority }
        if !p.list.isEmpty { t.list = p.list }
        if p.repeatRule != .none { t.repeatRule = p.repeatRule; if t.dueDate == nil { t.dueDate = Calendar.current.startOfDay(for: .now) } }
        if let m = p.minutes { t.durationMinutes = m }
        if p.remind { t.remind = true }
    }
}

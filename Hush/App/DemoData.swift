import Foundation
import SwiftData

/// Sample content used only when Hush is launched with `-demoSeed YES`
/// (the automated screenshot run). Never runs in normal use.
enum DemoData {
    static func seedIfRequested(_ ctx: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "demoSeed"),
              ((try? ctx.fetchCount(FetchDescriptor<Note>())) ?? 0) == 0 else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ n: Int, _ hour: Int = 9) -> Date {
            cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: n, to: today) ?? today) ?? today
        }

        let notes: [(String, String, [String], Bool, String)] = [
            ("Trip ideas", "Coast drive in spring\n☐ Book cabin\n☐ Check tide tables", ["travel"], true, "🧭"),
            ("Book list", "• The quiet hours\n• Field notes on rivers", ["reading"], true, ""),
            ("Meeting notes", "Agreed on the new schedule. Follow up Friday.", ["work"], false, ""),
            ("Recipe: lentil soup", "Onion, carrot, lentils, cumin, lemon.", ["cooking"], false, "🥣"),
        ]
        for (i, n) in notes.enumerated() {
            let note = Note()
            note.title = n.0; note.body = n.1; note.tags = n.2; note.isPinned = n.3; note.emoji = n.4
            note.updatedAt = day(-i, 10)
            ctx.insert(note)
        }

        let tasks: [(String, Int?, Int)] = [("Vitamins", 0, 0), ("Call the dentist", 0, 3), ("Water plants", 1, 1), ("Renew library card", 3, 2)]
        for t in tasks {
            let task = TaskItem(title: t.0)
            task.dueDate = t.1.map { day($0, 0) }
            task.priorityRaw = t.2
            ctx.insert(task)
        }

        let e1 = CalendarEvent(start: day(0, 15)); e1.title = "Coffee with Sam"; e1.location = "Corner café"
        let e2 = CalendarEvent(start: day(2, 18)); e2.title = "Yoga class"
        ctx.insert(e1); ctx.insert(e2)

        let j = JournalEntry(date: day(-1, 21)); j.title = "Quiet evening"; j.body = "Long walk, early night."; j.moodRaw = 4
        ctx.insert(j)

        for (title, url, tags) in [("Example", "https://example.com", ["reference"]), ("Weather", "https://example.org/weather", ["daily"])] {
            let b = Bookmark(); b.title = title; b.urlString = url; b.tags = tags
            ctx.insert(b)
        }

        let c = Contact(); c.firstName = "Alex"; c.lastName = "Rivera"; c.company = "Studio North"; c.isFavorite = true
        c.phones = [LabeledValue(label: "mobile", value: "555-0100")]
        ctx.insert(c)
        let c2 = Contact(); c2.firstName = "Jordan"; c2.lastName = "Lee"
        ctx.insert(c2)
        try? ctx.save()
    }
}

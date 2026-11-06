import AppIntents
import SwiftData
import WidgetKit

// Siri and Shortcuts. These only add things — nothing private is ever read aloud.

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Adds a task to Hush.")

    @Parameter(title: "Task", requestValueDialog: "What's the task?") var name: String
    @Parameter(title: "Due Today", default: false) var dueToday: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Storage.shared.mainContext
        let t = TaskItem(title: name.trimmed)
        if dueToday { t.dueDate = Calendar.current.startOfDay(for: .now) }
        ctx.insert(t)
        try ctx.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Added “\(name)” to Hush.")
    }
}

struct AddNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Note"
    static var description = IntentDescription("Saves a quick note in Hush.")

    @Parameter(title: "Note", requestValueDialog: "What should the note say?") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Storage.shared.mainContext
        let n = Note()
        let lines = text.trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        n.title = String(lines.first ?? "").trimmed
        n.body = lines.count > 1 ? String(lines[1]) : ""
        ctx.insert(n)
        try ctx.save()
        return .result(dialog: "Saved your note.")
    }
}

struct LogHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Habit"
    static var description = IntentDescription("Checks off a habit for today.")

    @Parameter(title: "Habit", requestValueDialog: "Which habit?") var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Storage.shared.mainContext
        let habits = try ctx.fetch(FetchDescriptor<Habit>()).filter { $0.deletedAt == nil && !$0.archived }
        let wanted = name.trimmed.lowercased()
        guard let h = habits.first(where: { $0.name.lowercased() == wanted })
                ?? habits.first(where: { $0.name.lowercased().contains(wanted) || wanted.contains($0.name.lowercased()) }) else {
            return .result(dialog: "I couldn't find a habit called “\(name)”.")
        }
        if !h.isDone(on: .now) { h.tap(on: .now) }
        try ctx.save()
        WidgetCenter.shared.reloadAllTimelines()
        let streak = h.streak
        return .result(dialog: streak > 1 ? "Logged \(h.name). That's a \(streak)-day streak!" : "Logged \(h.name).")
    }
}

struct AddJournalIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Journal Entry"
    static var description = IntentDescription("Writes a journal entry in Hush.")

    @Parameter(title: "Entry", requestValueDialog: "What would you like to write?") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Storage.shared.mainContext
        let e = JournalEntry()
        e.body = text.trimmed
        ctx.insert(e)
        try ctx.save()
        return .result(dialog: "Added to your journal.")
    }
}

struct HushShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(), phrases: [
            "Add a task in \(.applicationName)", "New \(.applicationName) task", "Remind me in \(.applicationName)",
        ], shortTitle: "Add Task", systemImageName: "checkmark.circle")
        AppShortcut(intent: AddNoteIntent(), phrases: [
            "Add a note in \(.applicationName)", "New \(.applicationName) note", "Take a note in \(.applicationName)",
        ], shortTitle: "Add Note", systemImageName: "square.and.pencil")
        AppShortcut(intent: LogHabitIntent(), phrases: [
            "Log a habit in \(.applicationName)", "Check off a habit in \(.applicationName)",
        ], shortTitle: "Log Habit", systemImageName: "flame")
        AppShortcut(intent: AddJournalIntent(), phrases: [
            "Add a journal entry in \(.applicationName)", "Journal in \(.applicationName)",
        ], shortTitle: "Journal", systemImageName: "book.closed")
    }
}

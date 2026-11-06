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
        let parsed = TaskParser.parse(name.trimmed)
        let t = TaskItem(title: parsed.title)
        if dueToday { t.dueDate = Calendar.current.startOfDay(for: .now) }
        TaskParser.apply(parsed, to: t)
        ctx.insert(t)
        Reminders.sync(t)
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
        if streak > 1 {
            return .result(dialog: "Logged \(h.name). That's a \(streak)-day streak!")
        }
        return .result(dialog: "Logged \(h.name).")
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

/// Opens Hush at a specific place — great on the Action Button or Back Tap.
struct OpenHushIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Hush"
    static var description = IntentDescription("Opens Hush straight to a new note, task, today's note, a voice memo or the focus timer.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Open") var destination: HushDestination

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: destination.url) { Router.shared?.handle(url) }
        return .result()
    }
}

enum HushDestination: String, AppEnum {
    case newNote, newTask, todaysNote, voiceMemo, focusTimer, newJournal, home

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    static var caseDisplayRepresentations: [HushDestination: DisplayRepresentation] = [
        .newNote: "New Note", .newTask: "New Task", .todaysNote: "Today's Note", .voiceMemo: "Voice Memo",
        .focusTimer: "Focus Timer", .newJournal: "Journal Entry", .home: "Home",
    ]

    var url: String {
        switch self {
        case .newNote: "hush://new/notes"
        case .newTask: "hush://new/tasks"
        case .todaysNote: "hush://daily"
        case .voiceMemo: "hush://memo"
        case .focusTimer: "hush://focus"
        case .newJournal: "hush://new/journals"
        case .home: "hush://open/home"
        }
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
        AppShortcut(intent: OpenHushIntent(), phrases: [
            "Open \(.applicationName)", "Open \(\.$destination) in \(.applicationName)",
        ], shortTitle: "Open Hush", systemImageName: "arrow.up.forward.app")
        AppShortcut(intent: AddJournalIntent(), phrases: [
            "Add a journal entry in \(.applicationName)", "Journal in \(.applicationName)",
        ], shortTitle: "Journal", systemImageName: "book.closed")
    }
}

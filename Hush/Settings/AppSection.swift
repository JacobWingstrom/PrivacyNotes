import Foundation

enum AppSection: String, CaseIterable, Identifiable, Codable, Hashable {
    case home, all, notes, tasks, drawings, vault, files, journals, calendar, contacts, bookmarks

    var id: String { rawValue }

    var defaultTitle: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .home: "house"
        case .all: "square.grid.2x2"
        case .notes: "square.and.pencil"
        case .tasks: "checkmark.circle"
        case .drawings: "scribble.variable"
        case .vault: "lock.shield"
        case .files: "folder"
        case .journals: "book.closed"
        case .calendar: "calendar"
        case .contacts: "person.crop.rectangle"
        case .bookmarks: "bookmark"
        }
    }

    /// Sections that are built so far. The rest show a "coming soon" page.
    var isReady: Bool { self == .notes || self == .all }

    var comingSoonBlurb: String {
        switch self {
        case .home: "A dashboard you arrange yourself: pinned items, today's tasks and upcoming reminders."
        case .tasks: "Due dates, priorities, subtasks, repeats and real reminder notifications."
        case .drawings: "A sketch pad with pens, markers and colors."
        case .vault: "A separately locked, extra-encrypted space for your most private things."
        case .files: "Import photos, PDFs and documents, kept encrypted inside Hush."
        case .journals: "Dated entries with mood, streaks and a daily reminder."
        case .calendar: "Month and agenda views of your tasks, journals and events."
        case .contacts: "Private contacts kept apart from your iPhone address book."
        case .bookmarks: "Saved links with notes and tags."
        default: ""
        }
    }
}

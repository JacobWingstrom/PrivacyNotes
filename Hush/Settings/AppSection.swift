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
}

enum HomeBlock: String, CaseIterable, Identifiable, Codable, Hashable {
    case quickAdd, today, upcoming, pinned, recentNotes, journal, stats

    var id: String { rawValue }
    var title: String {
        switch self {
        case .quickAdd: "Quick Add"
        case .today: "Today"
        case .upcoming: "Next 7 Days"
        case .pinned: "Pinned Notes"
        case .recentNotes: "Recent Notes"
        case .journal: "Journal"
        case .stats: "At a Glance"
        }
    }
    var symbol: String {
        switch self {
        case .quickAdd: "plus.circle"
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .pinned: "pin"
        case .recentNotes: "clock"
        case .journal: "book.closed"
        case .stats: "chart.bar"
        }
    }
}

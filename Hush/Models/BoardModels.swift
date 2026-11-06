import SwiftUI
import SwiftData

struct BoardColumn: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var colorName: String = "none"
    var symbol: String = ""
    /// Maximum cards before the column is marked as over its limit. 0 = no limit.
    var wipLimit: Int = 0
    var collapsed = false
    /// Cards moved here count as finished.
    var isDone = false
    var sort = "manual"   // manual, due, priority, created, title
}

struct BoardLabel: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var colorName: String = "blue"
}

@Model
final class Board {
    var id: UUID = UUID()
    var title: String = "Board"
    var symbol: String = "rectangle.split.3x1"
    var colorName: String = "none"
    var columnsData: Data = Data()
    var labelsData: Data = Data()
    var showDueDates: Bool = true
    var showLabels: Bool = true
    var showChecklist: Bool = true
    var showNotes: Bool = true
    var compactCards: Bool = false
    var tintedCards: Bool = true
    var columnWidthRaw: String = "regular"   // narrow, regular, wide
    var sortIndex: Int = 0
    var archived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(title: String = "Board") {
        self.title = title
        spaceID = Spaces.newItemSpace
    }

    var columns: [BoardColumn] {
        get { JSONField.decode(columnsData, as: [BoardColumn].self) ?? [] }
        set { columnsData = JSONField.encode(newValue); updatedAt = .now }
    }
    var labels: [BoardLabel] {
        get { JSONField.decode(labelsData, as: [BoardLabel].self) ?? [] }
        set { labelsData = JSONField.encode(newValue) }
    }
    var color: Color? { NoteColor(rawValue: colorName)?.color }
    var columnWidth: CGFloat {
        switch columnWidthRaw {
        case "narrow": 230
        case "wide": 330
        default: 280
        }
    }
}

@Model
final class BoardCard {
    var id: UUID = UUID()
    var boardID: UUID = UUID()
    var columnID: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var order: Double = 0
    var colorName: String = "none"
    var symbol: String = ""
    var labelIDs: [UUID] = []
    var dueDate: Date? = nil
    var remind: Bool = false
    var priorityRaw: Int = 0
    var checklistData: Data = Data()
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    var spaceID: String = ""
    var deletedAt: Date? = nil

    init(boardID: UUID, columnID: UUID, title: String = "") {
        self.boardID = boardID
        self.columnID = columnID
        self.title = title
        spaceID = Spaces.newItemSpace
    }

    var checklist: [Subtask] {
        get { JSONField.decode(checklistData, as: [Subtask].self) ?? [] }
        set { checklistData = JSONField.encode(newValue) }
    }
    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
    var color: Color? { NoteColor(rawValue: colorName)?.color }
    var isOverdue: Bool { completedAt == nil && (dueDate.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false) }
}

extension Board: HushItem {}
extension BoardCard: HushItem {}

enum BoardModels {
    static let all: [any PersistentModel.Type] = [Board.self, BoardCard.self]
}

enum BoardTemplates {
    struct Template: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let columns: [(String, String, String, Bool)]   // name, color, symbol, isDone
        let labels: [(String, String)]
    }

    static let all: [Template] = [
        Template(id: "simple", name: "Simple", symbol: "rectangle.split.3x1",
                 columns: [("To Do", "none", "circle", false), ("Doing", "blue", "circle.lefthalf.filled", false), ("Done", "green", "checkmark.circle", true)],
                 labels: [("Urgent", "red"), ("Quick win", "green")]),
        Template(id: "homelab", name: "Homelab Projects", symbol: "server.rack",
                 columns: [("Ideas", "purple", "lightbulb", false), ("Planning", "blue", "pencil.and.list.clipboard", false),
                           ("Building", "orange", "hammer", false), ("Testing", "yellow", "testtube.2", false), ("Done", "green", "checkmark.seal", true)],
                 labels: [("Networking", "blue"), ("Storage", "teal"), ("Docker", "purple"), ("Hardware", "orange"), ("Security", "red")]),
        Template(id: "dev", name: "Software / Bugs", symbol: "ladybug",
                 columns: [("Backlog", "none", "tray", false), ("To Do", "blue", "circle", false), ("In Progress", "orange", "arrow.triangle.2.circlepath", false),
                           ("Review", "purple", "eye", false), ("Done", "green", "checkmark.circle", true)],
                 labels: [("Bug", "red"), ("Feature", "blue"), ("Chore", "teal")]),
        Template(id: "content", name: "Writing & Content", symbol: "doc.richtext",
                 columns: [("Ideas", "yellow", "lightbulb", false), ("Drafting", "blue", "pencil", false), ("Editing", "purple", "text.magnifyingglass", false),
                           ("Published", "green", "paperplane", true)],
                 labels: [("Blog", "blue"), ("Video", "red"), ("Social", "pink")]),
        Template(id: "week", name: "Weekly Planner", symbol: "calendar",
                 columns: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Weekend"].map { ($0, "none", "", false) } + [("Done", "green", "checkmark.circle", true)],
                 labels: [("Work", "blue"), ("Home", "green"), ("Errand", "orange")]),
        Template(id: "goals", name: "Goals", symbol: "target",
                 columns: [("Someday", "none", "sparkles", false), ("This Year", "blue", "calendar", false), ("This Month", "orange", "flag", false),
                           ("Achieved", "green", "trophy", true)],
                 labels: [("Health", "green"), ("Money", "yellow"), ("Learning", "purple")]),
        Template(id: "blank", name: "Blank", symbol: "rectangle.dashed", columns: [("Column", "none", "", false)], labels: []),
    ]

    static func apply(_ t: Template, to board: Board) {
        board.columns = t.columns.map { BoardColumn(name: $0.0, colorName: $0.1, symbol: $0.2, isDone: $0.3) }
        board.labels = t.labels.map { BoardLabel(name: $0.0, colorName: $0.1) }
        board.symbol = t.symbol
    }
}

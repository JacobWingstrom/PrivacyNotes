import SwiftUI
import SwiftData

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var isPinned: Bool = false
    var colorName: String = NoteColor.none.rawValue
    var emoji: String = ""
    var tags: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "New Note" : firstLine
    }

    var preview: String {
        var lines = body.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if title.trimmingCharacters(in: .whitespaces).isEmpty, !lines.isEmpty { lines.removeFirst() }
        return lines.joined(separator: " ")
    }

    var color: Color? { NoteColor(rawValue: colorName)?.color }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || body.localizedCaseInsensitiveContains(query)
            || tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

enum NoteColor: String, CaseIterable, Identifiable {
    case none, red, orange, yellow, green, teal, blue, purple, pink
    var id: String { rawValue }
    var label: String { self == .none ? "No Color" : rawValue.capitalized }
    var color: Color? {
        switch self {
        case .none: nil
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

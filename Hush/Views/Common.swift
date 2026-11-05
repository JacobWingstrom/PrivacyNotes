import SwiftUI

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CheckButton: View {
    let done: Bool
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(tint ?? Color.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .accessibilityLabel(done ? "Mark not done" : "Mark done")
    }
}

struct Avatar: View {
    let text: String
    let emoji: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(.tint.opacity(0.18))
            if emoji.isEmpty {
                Text(text).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.tint)
            } else {
                Text(emoji).font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
    }
}

struct FilterChips<T: Hashable>: View {
    let options: [(T?, String)]
    @Binding var selection: T?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    TagChip(text: option.1, selected: selection == option.0) { selection = option.0 }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

extension View {
    /// A list row that holds chips or other edge-to-edge content.
    func chipRow() -> some View {
        self.listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

enum DateText {
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: .now)
        return date.formatted(sameYear ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                                       : .dateTime.month(.abbreviated).day().year())
    }

    static func due(_ task: TaskItem) -> String? {
        guard let d = task.dueDate else { return nil }
        let day = relativeDay(d)
        return task.hasDueTime ? "\(day), \(d.formatted(date: .omitted, time: .shortened))" : day
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Array where Element == String {
    /// Parses "a, b, #c" into unique tags.
    static func tags(from text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }
}

import SwiftUI

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.hush(.subheadline).weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.border))
    }
}

struct CheckButton: View {
    let done: Bool
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.hush(.title3))
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

// MARK: - Section chrome

/// Search field with an optional filter button, pinned under the top bar.
struct SearchHeader<Filter: View>: View {
    @Binding var text: String
    let prompt: String
    @ViewBuilder var filter: Filter
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(prompt, text: $text)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.background)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }
}

extension SearchHeader where Filter == EmptyView {
    init(text: Binding<String>, prompt: String) {
        self.init(text: text, prompt: prompt) { EmptyView() }
    }
}

/// Square filter button that opens a menu of sort and filter options.
struct FilterButton<Options: View>: View {
    var active = false
    @ViewBuilder var options: Options
    @Environment(\.palette) private var palette

    var body: some View {
        Menu { options } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.hush(.body).weight(.medium))
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(active ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.border)))
        }
        .accessibilityLabel("Sort and filter")
    }
}

/// Inline "add" field shown at the top of a list.
struct QuickAddField: View {
    let prompt: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    let onSubmit: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.square").font(.hush(.title3)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .URL)
                .submitLabel(.done)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border))
    }
}

/// Small uppercase section label.
struct ListHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.hush(.caption).weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct EmptyMessage: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension View {
    /// A full-width row for headers, fields and chips inside a list.
    func plainRow(top: CGFloat = 10, bottom: CGFloat = 10) -> some View {
        self.listRowInsets(EdgeInsets(top: top, leading: 14, bottom: bottom, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

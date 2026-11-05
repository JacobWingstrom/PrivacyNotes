import SwiftUI
import SwiftData

struct JournalView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var search = ""
    @State private var newEntry: JournalEntry?

    private var filtered: [JournalEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }
    }

    private var groups: [(Date, [JournalEntry])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    HStack {
                        stat("\(JournalStats.streak(entries))", "Day streak", "flame.fill")
                        Divider()
                        stat("\(entries.count)", "Entries", "book.closed.fill")
                        Divider()
                        stat(JournalStats.averageMood(entries), "Avg. mood", "face.smiling")
                    }
                    .padding(.vertical, 4)
                }
            }
            ForEach(groups, id: \.0) { month, items in
                Section(month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(items) { entry in
                        NavigationLink { JournalEditorView(entry: entry) } label: { JournalRow(entry: entry, compact: settings.compactLists) }
                    }
                    .onDelete { offsets in offsets.map { items[$0] }.forEach(context.delete) }
                }
            }
        }
        .hushBackground()
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Start your journal", systemImage: "book.closed",
                                       description: Text("Tap + to write about today."))
            }
        }
        .searchable(text: $search, prompt: "Search journal")
        .navigationTitle(title)
        .navigationDestination(item: $newEntry) { JournalEditorView(entry: $0, isNew: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let e = JournalEntry()
                    context.insert(e)
                    newEntry = e
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("New entry")
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Label(value, systemImage: symbol).font(.title3.bold()).foregroundStyle(.tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

enum JournalStats {
    /// Consecutive days with an entry, ending today (or yesterday, so the streak survives until you write today).
    static func streak(_ entries: [JournalEntry]) -> Int {
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: .now)
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    static func averageMood(_ entries: [JournalEntry]) -> String {
        let moods = entries.prefix(30).map(\.moodRaw).filter { $0 > 0 }
        guard !moods.isEmpty else { return "–" }
        let avg = Int((Double(moods.reduce(0, +)) / Double(moods.count)).rounded())
        return Mood(rawValue: avg)?.emoji ?? "–"
    }
}

struct JournalRow: View {
    let entry: JournalEntry
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(entry.date.formatted(.dateTime.day())).font(.title2.bold())
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.title.isEmpty ? (entry.body.split(separator: "\n").first.map(String.init) ?? "Untitled") : entry.title)
                        .font(.headline).lineLimit(1)
                    Spacer()
                    Text(entry.mood.emoji)
                }
                if !compact && !entry.body.isEmpty && !entry.title.isEmpty {
                    Text(entry.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}

struct JournalEditorView: View {
    @Bindable var entry: JournalEntry
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var deleting = false
    @FocusState private var focus: Field?
    private enum Field { case title, body }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DatePicker("Date", selection: $entry.date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(Mood.allCases.filter { $0 != .none }) { mood in
                    Button {
                        entry.mood = entry.mood == mood ? .none : mood
                    } label: {
                        Text(mood.emoji)
                            .font(.title2)
                            .padding(6)
                            .background(entry.mood == mood ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear), in: Circle())
                            .opacity(entry.mood == .none || entry.mood == mood ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mood: \(mood.label)")
                }
            }
            TextField("Title", text: $entry.title)
                .font(.title2.bold())
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onSubmit { focus = .body }
            TextEditor(text: $entry.body)
                .focused($focus, equals: .body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background((settings.theme == .black ? Color.black : Color(.systemBackground)).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: "\(entry.title)\n\n\(entry.body)") { Label("Share…", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        deleting = true
                        dismiss()
                    } label: { Label("Delete Entry", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .onChange(of: entry.body) { entry.updatedAt = .now }
        .onChange(of: entry.title) { entry.updatedAt = .now }
        .onAppear { if isNew { focus = .body } }
        .onDisappear { if deleting || entry.isEmpty { context.delete(entry) } }
    }
}

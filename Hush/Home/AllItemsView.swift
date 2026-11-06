import SwiftUI
import SwiftData

/// One searchable timeline of everything except the Vault and Files.
struct AllItemsView: View {
    let title: String
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @State private var choosing = false
    @Query private var notes: [Note]
    @Query private var tasks: [TaskItem]
    @Query private var events: [CalendarEvent]
    @Query private var journals: [JournalEntry]
    @Query private var drawings: [Drawing]
    @Query private var contacts: [Contact]
    @Query private var bookmarks: [Bookmark]
    @State private var search = ""
    @State private var kind: AppSection?

    private struct Item: Identifiable {
        let id: String
        let kind: AppSection
        let title: String
        let subtitle: String
        let date: Date
        let destination: () -> AnyView
    }

    private var items: [Item] {
        var out: [Item] = []
        out += notes.map { n in Item(id: "n\(n.id)", kind: .notes, title: n.displayTitle, subtitle: n.preview, date: n.updatedAt) { AnyView(NoteEditorView(note: n)) } }
        out += tasks.filter { settings.showCompletedInAll || !$0.isDone }.map { t in
            Item(id: "t\(t.id)", kind: .tasks, title: t.title, subtitle: DateText.due(t) ?? (t.isDone ? "Done" : ""), date: t.createdAt) { AnyView(TaskEditorView(task: t)) }
        }
        out += events.map { e in Item(id: "e\(e.id)", kind: .calendar, title: e.title, subtitle: e.start.formatted(date: .abbreviated, time: e.isAllDay ? .omitted : .shortened), date: e.start) { AnyView(EventEditorView(event: e)) } }
        out += journals.map { j in Item(id: "j\(j.id)", kind: .journals, title: j.title.isEmpty ? "Journal entry" : j.title, subtitle: String(j.body.prefix(80)), date: j.date) { AnyView(JournalEditorView(entry: j)) } }
        out += drawings.map { d in Item(id: "d\(d.id)", kind: .drawings, title: d.title, subtitle: "Drawing", date: d.updatedAt) { AnyView(DrawingEditorView(drawing: d)) } }
        out += contacts.map { c in Item(id: "c\(c.id)", kind: .contacts, title: c.displayName, subtitle: c.company, date: c.createdAt) { AnyView(ContactEditorView(contact: c)) } }
        out += bookmarks.map { b in Item(id: "b\(b.id)", kind: .bookmarks, title: b.displayTitle, subtitle: b.host, date: b.createdAt) { AnyView(BookmarkForm(bookmark: b)) } }
        return out
            .filter { kind == nil || $0.kind == kind }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let kinds: [AppSection] = [.notes, .tasks, .calendar, .journals, .drawings, .contacts, .bookmarks]
        let list = items
        List {
            FilterChips(options: [(nil, "Everything")] + kinds.map { ($0, settings.title(for: $0)) }, selection: $kind)
                .plainRow(top: 12, bottom: 6)
            ForEach(list) { item in
                NavigationLink { item.destination() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.kind.symbol)
                            .frame(width: 30, height: 30)
                            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title.isEmpty ? "Untitled" : item.title).lineLimit(1)
                            if !settings.compactLists && !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .hushRow()
            }
            if list.isEmpty { EmptyMessage(text: search.isEmpty ? "Nothing here yet. Tap + to add something." : "Nothing matches.") }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchHeader(text: $search, prompt: "Search everything…") {
                FilterButton(active: kind != nil) {
                    Picker("Show", selection: $kind) {
                        Text("Everything").tag(AppSection?.none)
                        ForEach(kinds) { Text(settings.title(for: $0)).tag(Optional($0)) }
                    }
                }
            }
        }
        .navigationTitle(title)
        .onCreate(.all) { choosing = true }
        .newItemDialog(isPresented: $choosing)
    }
}

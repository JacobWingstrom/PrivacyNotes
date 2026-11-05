import SwiftUI
import SwiftData

struct NotesListView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var newNote: Note?

    private var sorted: [Note] {
        let base = notes.filter { $0.matches(search) && (tagFilter.map { t in $0.tags.contains(t) } ?? true) }
        switch settings.noteSort {
        case .edited: return base
        case .created: return base.sorted { $0.createdAt > $1.createdAt }
        case .title: return base.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }

    private var allTags: [String] {
        Array(Set(notes.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        @Bindable var s = settings
        let pinned = sorted.filter(\.isPinned)
        let others = sorted.filter { !$0.isPinned }

        List {
            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TagChip(text: "All", selected: tagFilter == nil) { tagFilter = nil }
                        ForEach(allTags, id: \.self) { tag in
                            TagChip(text: "#\(tag)", selected: tagFilter == tag) {
                                tagFilter = tagFilter == tag ? nil : tag
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            if !pinned.isEmpty {
                Section("Pinned") { rows(pinned) }
            }
            Section(pinned.isEmpty ? "" : "Notes") { rows(others) }
        }
        .listStyle(.plain)
        .hushBackground()
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView("No notes yet", systemImage: "square.and.pencil",
                                       description: Text("Tap the pencil to write your first note."))
            } else if sorted.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search notes and tags")
        .navigationTitle(title)
        .navigationDestination(for: Note.self) { NoteEditorView(note: $0) }
        .navigationDestination(item: $newNote) { NoteEditorView(note: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $s.noteSort) {
                        ForEach(NoteSort.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Compact list", isOn: $s.compactLists)
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: create) { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New note")
            }
        }
    }

    @ViewBuilder
    private func rows(_ items: [Note]) -> some View {
        ForEach(items) { note in
            NavigationLink(value: note) {
                NoteRow(note: note, compact: settings.compactLists, previewLines: settings.previewLines)
            }
            .swipeActions(edge: .leading) {
                Button { note.isPinned.toggle() } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { context.delete(note) } label: { Label("Delete", systemImage: "trash") }
            }
            .listRowBackground(settings.theme == .black ? Color.black : nil)
        }
    }

    private func create() {
        let note = Note()
        if let tagFilter { note.tags = [tagFilter] }
        context.insert(note)
        newNote = note
    }
}

struct NoteRow: View {
    let note: Note
    let compact: Bool
    let previewLines: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !note.emoji.isEmpty {
                Text(note.emoji).font(.title3)
            } else if let c = note.color {
                Circle().fill(c).frame(width: 10, height: 10).padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.displayTitle).font(.headline).lineLimit(1)
                    if note.isPinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                    }
                }
                if !compact, previewLines > 0, !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(previewLines)
                }
                if !compact {
                    HStack(spacing: 6) {
                        Text(note.updatedAt, format: .relative(presentation: .named))
                        if !note.tags.isEmpty {
                            Text(note.tags.map { "#\($0)" }.joined(separator: " ")).lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, compact ? 0 : 4)
    }
}

struct TagChip: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }
}

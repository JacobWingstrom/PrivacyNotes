import SwiftUI
import SwiftData

struct NotesListView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var newNote: Note?

    private var sorted: [Note] {
        let base = notes.filter { note in
            note.matches(search) && (tagFilter.map { note.tags.contains($0) } ?? true)
        }
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
                }
                .plainRow(top: 12, bottom: 4)
            }
            if !pinned.isEmpty {
                Section { rows(pinned) } header: { ListHeader(title: "Pinned") }
            }
            Section {
                rows(others)
            } header: {
                if !pinned.isEmpty { ListHeader(title: "Notes") }
            }
            if notes.isEmpty {
                EmptyMessage(text: "No notes yet. Tap + to write one.")
            } else if sorted.isEmpty {
                EmptyMessage(text: "No notes match.")
            }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchHeader(text: $search, prompt: "Search notes…") {
                FilterButton(active: tagFilter != nil) {
                    Picker("Sort by", selection: $s.noteSort) {
                        ForEach(NoteSort.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Compact list", isOn: $s.compactLists)
                    if !allTags.isEmpty {
                        Picker("Tag", selection: $tagFilter) {
                            Text("All notes").tag(String?.none)
                            ForEach(allTags, id: \.self) { Text("#\($0)").tag(Optional($0)) }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(for: Note.self) { NoteEditorView(note: $0) }
        .navigationDestination(item: $newNote) { NoteEditorView(note: $0) }
        .onCreate(.notes) { create() }
        .onAppear {
            if let t = router.noteTag { tagFilter = t; router.noteTag = nil }
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
            .hushRow()
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
                        Text("Modified \(note.updatedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))")
                        if !note.tags.isEmpty {
                            Text(note.tags.map { "#\($0)" }.joined(separator: " ")).lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, compact ? 2 : 8)
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
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: Capsule())
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI
import SwiftData

struct NotesListView: View {
    let title: String
    var folder: Folder? = nil
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \Note.updatedAt, order: .reverse) private var notesStored: [Note]
    @Query private var foldersStored: [Folder]
    @AppStorage("notesShowAll") private var showAllNotes = false
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var untaggedOnly = false
    @State private var newNote: Note?
    @State private var pickingTemplate = false
    @State private var creatingFolder = false
    @State private var renaming: Folder?
    @State private var folderName = ""
    @State private var movingFolder: Folder?
    @State private var moveTarget: UUID?
    @State private var openFolder: Folder?
    @State private var showGraph = false

    private var notes: [Note] { notesStored.live(settings.spaceFilter) }
    private var folders: [Folder] { foldersStored.live(settings.spaceFilter) }

    /// Searching or filtering looks through every folder.
    private var flatMode: Bool { !search.isEmpty || tagFilter != nil || untaggedOnly || (folder == nil && showAllNotes) }

    private var sorted: [Note] {
        let base = notes.filter { note in
            note.matches(search)
                && (tagFilter.map { note.tags.contains($0) } ?? true)
                && (!untaggedOnly || note.tags.isEmpty)
                && (flatMode || note.folderID == folder?.id)
        }
        switch settings.noteSort {
        case .edited: return base
        case .created: return base.sorted { $0.createdAt > $1.createdAt }
        case .title: return base.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }

    private var subfolders: [Folder] {
        folders.filter { $0.parentID == folder?.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func count(in f: Folder) -> Int {
        let ids = FolderPath.descendants(of: f.id, in: folders)
        return notes.filter { $0.folderID.map(ids.contains) ?? false }.count
    }

    private var allTags: [String] {
        Array(Set(notes.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        @Bindable var s = settings
        let pinned = sorted.filter(\.isPinned)
        let others = sorted.filter { !$0.isPinned }

        List {
            if !allTags.isEmpty && folder == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TagChip(text: "All", selected: tagFilter == nil && !untaggedOnly) { tagFilter = nil; untaggedOnly = false }
                        ForEach(allTags, id: \.self) { tag in
                            TagChip(text: "#\(tag)", selected: tagFilter == tag) {
                                untaggedOnly = false
                                tagFilter = tagFilter == tag ? nil : tag
                            }
                        }
                        TagChip(text: "Untagged", selected: untaggedOnly) { tagFilter = nil; untaggedOnly.toggle() }
                    }
                }
                .plainRow(top: 12, bottom: 4)
            }
            if !flatMode && !subfolders.isEmpty {
                Section {
                    ForEach(subfolders) { f in
                        NavigationLink { NotesListView(title: f.name, folder: f) } label: { FolderRow(folder: f, count: count(in: f)) }
                            .contextMenu {
                                Button { folderName = f.name; renaming = f } label: { Label("Rename", systemImage: "pencil") }
                                Button { moveTarget = f.parentID; movingFolder = f } label: { Label("Move", systemImage: "folder") }
                                Button(role: .destructive) { FolderPath.delete(f, in: context) } label: { Label("Delete Folder (keeps notes)", systemImage: "trash") }
                            }
                            .hushRow()
                    }
                } header: { ListHeader(title: "Folders") }
            }
            if !pinned.isEmpty {
                Section { rows(pinned) } header: { ListHeader(title: "Pinned") }
            }
            Section {
                rows(others)
            } header: {
                if !pinned.isEmpty || (!flatMode && !subfolders.isEmpty) { ListHeader(title: "Notes") }
            }
            if notes.isEmpty && folders.isEmpty {
                EmptyMessage(text: "No notes yet. Tap + to write one.")
            } else if sorted.isEmpty && (flatMode || subfolders.isEmpty) {
                EmptyMessage(text: folder != nil && search.isEmpty ? "This folder is empty." : "No notes match.")
            }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchHeader(text: $search, prompt: folder.map { "Search \($0.name)…" } ?? "Search notes…") {
                FilterButton(active: tagFilter != nil || untaggedOnly || showAllNotes) {
                    Picker("Sort by", selection: $s.noteSort) {
                        ForEach(NoteSort.allCases) { Text($0.label).tag($0) }
                    }
                    if folder == nil {
                        Toggle("Show notes from all folders", isOn: $showAllNotes)
                    }
                    Toggle("Untagged only", isOn: $untaggedOnly)
                    Toggle("Compact list", isOn: $s.compactLists)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            if folder != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: create) { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New note in folder")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { newNote = DailyNote.open(in: context) } label: { Label("Today's Note", systemImage: "sun.max") }
                    Button { showGraph = true } label: { Label("Graph View", systemImage: "point.3.filled.connected.trianglepath.dotted") }
                    Divider()
                    Button { pickingTemplate = true } label: { Label("New from Template", systemImage: "doc.on.doc") }
                    Button { folderName = ""; creatingFolder = true } label: { Label(folder == nil ? "New Folder" : "New Subfolder", systemImage: "folder.badge.plus") }
                } label: { Image(systemName: "doc.badge.plus") }
                .accessibilityLabel("New from template or folder")
            }
        }
        .navigationDestination(for: Note.self) { NoteEditorView(note: $0) }
        .navigationDestination(item: $newNote) { NoteEditorView(note: $0) }
        .navigationDestination(item: $openFolder) { NotesListView(title: $0.name, folder: $0) }
        .navigationDestination(isPresented: $showGraph) { NotesGraphView() }
        .sheet(isPresented: $pickingTemplate) {
            TemplatePicker { title, body, emoji in
                let n = makeNote()
                n.title = title; n.body = body; n.emoji = emoji
                newNote = n
            }
        }
        .sheet(item: $movingFolder) { f in
            NavigationStack {
                FolderPicker(selection: Binding(get: { moveTarget }, set: { moveTarget = $0; f.parentID = $0 }), excluding: f.id, title: "Move “\(f.name)”")
            }
        }
        .alert(folder == nil ? "New Folder" : "New Subfolder", isPresented: $creatingFolder) {
            TextField("Name", text: $folderName)
            Button("Create") { if !folderName.trimmed.isEmpty { context.insert(Folder(name: folderName.trimmed, parentID: folder?.id)) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Folder", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $folderName)
            Button("Save") { if !folderName.trimmed.isEmpty { renaming?.name = folderName.trimmed } }
            Button("Cancel", role: .cancel) {}
        }
        .onCreate(.notes) { if folder == nil { create() } }
        .onChange(of: router.dailyRequest) { if folder == nil, router.consumeDaily() { newNote = DailyNote.open(in: context) } }
        .onAppear {
            if let t = router.noteTag { tagFilter = t; router.noteTag = nil }
            if UserDefaults.standard.bool(forKey: "demoGraph"), folder == nil { showGraph = true }
            if folder == nil, router.dailyRequest > 0, newNote == nil, router.consumeDaily() { newNote = DailyNote.open(in: context) }
            if folder == nil, let fid = router.noteFolder {
                router.noteFolder = nil
                openFolder = folders.first { $0.id == fid }
            }
            if UserDefaults.standard.bool(forKey: "demoOpenNote"), folder == nil, newNote == nil {
                newNote = notes.first { $0.title == "Homelab notes" }
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
                Button(role: .destructive) { TrashActions.trash(note) } label: { Label("Delete", systemImage: "trash") }
            }
            .hushRow()
        }
    }

    private func makeNote() -> Note {
        let note = Note()
        if let tagFilter { note.tags = [tagFilter] }
        note.folderID = folder?.id
        context.insert(note)
        return note
    }

    private func create() { newNote = makeNote() }
}

struct NoteRow: View {
    let note: Note
    let compact: Bool
    let previewLines: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if SymbolName.isValid(note.emoji) {
                Image(systemName: note.emoji).font(.system(size: 18)).foregroundStyle(note.color ?? Color.accentColor).frame(width: 24)
            } else if let c = note.color {
                Circle().fill(c).frame(width: 10, height: 10).padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.displayTitle).font(.hush(.headline)).lineLimit(1)
                    if note.isPinned {
                        Image(systemName: "pin.fill").font(.hush(.caption2)).foregroundStyle(.orange)
                    }
                }
                if !compact, previewLines > 0, !note.plainPreview.isEmpty {
                    Text(note.plainPreview)
                        .font(.hush(.subheadline))
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
                    .font(.hush(.caption))
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
                .font(.hush(.subheadline).weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: Capsule())
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }
}

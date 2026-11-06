import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @FocusState private var titleFocused: Bool
    @State private var deleting = false
    @State private var original: (String, String)?
    @State private var editingTags = false
    @State private var tagText = ""
    @State private var editingEmoji = false
    @State private var emojiText = ""
    @State private var pendingInsert: String?
    @State private var zen = false
    @State private var showInfo = false
    @State private var showHistory = false
    @State private var choosingFolder = false
    @State private var pickingLink = false
    @State private var pickingTemplate = false
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var choosingAttachment = false
    @State private var attachment: AttachmentKind?
    @State private var linkedNote: Note?
    @State private var share: ShareItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $note.title)
                .font(.title2.bold())
                .focused($titleFocused)
                .submitLabel(.next)
                .padding(.horizontal)
                .padding(.top, 10)

            if !note.tags.isEmpty || note.folderID != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let path = FolderPath.string(for: note.folderID, in: context) {
                            Label(path, systemImage: "folder").font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                                .onTapGesture { choosingFolder = true }
                        }
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)").font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 6)
            }

            if note.isEmpty {
                Button { pickingTemplate = true } label: {
                    Label("Start from a template", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            MarkdownEditor(text: $note.body, pendingInsert: $pendingInsert,
                           fontDesign: settings.fontStyle, accent: UIColor(settings.accentColor),
                           horizontalInset: 16,
                           onOpenNoteLink: openLink,
                           onLinkPicker: { pickingLink = true },
                           onAttach: { choosingAttachment = true })

            AttachmentStrip(noteID: note.id) { text in pendingInsert = "\n> " + text.replacingOccurrences(of: "\n", with: "\n> ") + "\n" }
        }
        .background {
            ZStack {
                palette.background
                if let c = note.color { c.opacity(0.07) }
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { zen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .accessibilityLabel("Zen mode")
            }
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .onChange(of: note.title) { note.updatedAt = .now }
        .onChange(of: note.body) { note.updatedAt = .now }
        .onAppear {
            if original == nil { original = (note.title, note.body) }
            if note.isEmpty { titleFocused = true }
        }
        .onDisappear(perform: finish)
        .fullScreenCover(isPresented: $zen) { ZenEditor(note: note) }
        .sheet(isPresented: $showInfo) { NavigationStack { NoteInfoView(note: note) { openLink($0) } } }
        .sheet(isPresented: $showHistory) { NavigationStack { NoteHistoryView(note: note) } }
        .sheet(isPresented: $choosingFolder) { NavigationStack { FolderPicker(selection: $note.folderID) } }
        .sheet(isPresented: $pickingLink) {
            NavigationStack { NoteLinkPicker(excluding: note.id) { title in pendingInsert = "[[\(title)]]" } }
        }
        .sheet(isPresented: $pickingTemplate) {
            TemplatePicker { title, body, emoji in
                if note.title.isEmpty { note.title = title }
                note.body = body
                if note.emoji.isEmpty { note.emoji = emoji }
            }
        }
        .sheet(item: $share) { item in ActivityView(items: item.urls).ignoresSafeArea() }
        .navigationDestination(item: $linkedNote) { NoteEditorView(note: $0) }
        .attachmentChooser(isPresented: $choosingAttachment) { attachment = $0 }
        .attachmentPresenter($attachment, noteID: note.id)
        .alert("Tags", isPresented: $editingTags) {
            TextField("work, ideas, personal", text: $tagText).textInputAutocapitalization(.never)
            Button("Save") { note.tags = .tags(from: tagText) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Separate tags with commas.") }
        .alert("Note Icon", isPresented: $editingEmoji) {
            TextField("Type an emoji", text: $emojiText)
            Button("Save") { note.emoji = String(emojiText.trimmed.prefix(1)) }
            Button("Remove", role: .destructive) { note.emoji = "" }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save as Template", isPresented: $savingTemplate) {
            TextField("Template name", text: $templateName)
            Button("Save") {
                let name = templateName.trimmed.isEmpty ? note.displayTitle : templateName.trimmed
                context.insert(NoteTemplate(name: name, emoji: note.emoji, title: note.title, body: note.body))
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var menu: some View {
        Menu {
            Section {
                Button { note.isPinned.toggle() } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                Button { choosingFolder = true } label: { Label("Move to Folder", systemImage: "folder") }
                Button { tagText = note.tags.joined(separator: ", "); editingTags = true } label: { Label("Tags", systemImage: "tag") }
                Picker(selection: $note.colorName) {
                    ForEach(NoteColor.allCases) { Text($0.label).tag($0.rawValue) }
                } label: { Label("Color", systemImage: "paintpalette") }
                .pickerStyle(.menu)
                Button { emojiText = note.emoji; editingEmoji = true } label: { Label("Icon", systemImage: "face.smiling") }
            }
            Section {
                Button { choosingAttachment = true } label: { Label("Attach…", systemImage: "paperclip") }
                Button { pickingTemplate = true } label: { Label("Apply Template…", systemImage: "doc.on.doc") }
                Button { templateName = note.displayTitle; savingTemplate = true } label: { Label("Save as Template", systemImage: "square.and.arrow.down.on.square") }
            }
            Section {
                Button { showInfo = true } label: { Label("Info & Backlinks", systemImage: "info.circle") }
                Button { showHistory = true } label: { Label("Version History", systemImage: "clock.arrow.circlepath") }
                Menu {
                    Button { share = ShareItem(urls: [Exporter.markdownFile(for: note)].compactMap { $0 }) } label: { Label("Markdown (.md)", systemImage: "doc.plaintext") }
                    Button { share = ShareItem(urls: [Exporter.pdfFile(for: note)].compactMap { $0 }) } label: { Label("PDF", systemImage: "doc.richtext") }
                    Button { share = ShareItem(urls: [Exporter.textFile(for: note)].compactMap { $0 }) } label: { Label("Plain Text", systemImage: "doc.text") }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
            }
            Section {
                Button(role: .destructive) {
                    deleting = true
                    dismiss()
                } label: { Label("Move to Trash", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func finish() {
        if note.isEmpty && !hasAttachments {
            context.delete(note)
            return
        }
        if deleting {
            TrashActions.trash(note)
            return
        }
        // Keep the previous version when something changed.
        if let (t, b) = original, (t != note.title || b != note.body), !(t.isEmpty && b.isEmpty) {
            NoteHistory.save(noteID: note.id, title: t, body: b, in: context)
        }
        original = (note.title, note.body)
    }

    private var hasAttachments: Bool {
        let id = note.id
        return ((try? context.fetch(FetchDescriptor<StoredFile>()))?.contains { $0.noteID == id }) ?? false
    }

    private func openLink(_ name: String) {
        let notes = ((try? context.fetch(FetchDescriptor<Note>())) ?? []).filter { $0.deletedAt == nil }
        if let found = notes.first(where: { $0.displayTitle.caseInsensitiveCompare(name.trimmed) == .orderedSame }) {
            linkedNote = found
        } else {
            let n = Note()
            n.title = name.trimmed
            n.folderID = note.folderID
            context.insert(n)
            linkedNote = n
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Zen mode

struct ZenEditor: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @State private var pending: String?
    @State private var showChrome = true

    var body: some View {
        ZStack(alignment: .top) {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                MarkdownEditor(text: $note.body, pendingInsert: $pending, fontDesign: settings.fontStyle,
                               fontScale: 1.15, accent: UIColor(settings.accentColor), horizontalInset: 28, focusOnAppear: true)
                    .frame(maxWidth: 700)
                    .padding(.top, 54)
            }
            HStack {
                Text(note.displayTitle).font(.headline).lineLimit(1)
                Spacer()
                Text("\(note.wordCount) words").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button("Done") { dismiss() }.font(.headline).padding(.leading, 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .opacity(showChrome ? 1 : 0.15)
            .animation(.easeInOut(duration: 0.6), value: showChrome)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: note.body) {
            note.updatedAt = .now
            showChrome = false
        }
        .onTapGesture(count: 2) { showChrome = true }
    }
}

// MARK: - History

enum NoteHistory {
    static let maxVersions = 50

    static func save(noteID: UUID, title: String, body: String, in ctx: ModelContext) {
        ctx.insert(NoteVersion(noteID: noteID, title: title, body: body))
        let all = ((try? ctx.fetch(FetchDescriptor<NoteVersion>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)]))) ?? [])
            .filter { $0.noteID == noteID }
        for old in all.dropFirst(maxVersions) { ctx.delete(old) }
    }
}

struct NoteHistoryView: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \NoteVersion.savedAt, order: .reverse) private var allVersions: [NoteVersion]

    var body: some View {
        let versions = allVersions.filter { $0.noteID == note.id }
        List {
            Text("A version is saved each time you finish editing. Up to \(NoteHistory.maxVersions) are kept per note.")
                .font(.footnote).foregroundStyle(.secondary)
                .plainRow(top: 12, bottom: 6)
            ForEach(versions) { v in
                NavigationLink {
                    VersionDetail(version: v) {
                        NoteHistory.save(noteID: note.id, title: note.title, body: note.body, in: context)
                        note.title = v.title
                        note.body = v.body
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(v.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text(Markdown.plain(v.body).replacingOccurrences(of: "\n", with: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .hushRow()
            }
            if versions.isEmpty { EmptyMessage(text: "No earlier versions yet.") }
        }
        .hushList()
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

private struct VersionDetail: View {
    let version: NoteVersion
    let restore: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(version.title.isEmpty ? "Untitled" : version.title).font(.title2.bold())
                Text(version.body).font(.body).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(palette.background)
        .navigationTitle(version.savedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Restore", action: restore) } }
    }
}

// MARK: - Info & backlinks

struct NoteInfoView: View {
    let note: Note
    var openLink: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var notes: [Note]

    var body: some View {
        let words = note.wordCount
        let needle = "[[\(note.displayTitle.lowercased())]]"
        let backlinks = notes.filter { $0.id != note.id && $0.deletedAt == nil && $0.body.lowercased().contains(needle) }
        let outgoing = Self.links(in: note.body)
        HushForm {
            Section {
                LabeledContent("Words", value: "\(words)")
                LabeledContent("Characters", value: "\(note.body.count)")
                LabeledContent("Reading time", value: "\(max(1, Int((Double(words) / 220).rounded(.up)))) min")
                LabeledContent("Created", value: note.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                if let path = FolderPath.string(for: note.folderID, in: context) { LabeledContent("Folder", value: path) }
            }
            Section("Linked from (\(backlinks.count))") {
                if backlinks.isEmpty { Text("No notes link here yet. Type [[\(note.displayTitle)]] in another note.").foregroundStyle(.secondary) }
                ForEach(backlinks) { n in
                    Button(n.displayTitle) { dismiss(); openLink(n.displayTitle) }
                }
            }
            if !outgoing.isEmpty {
                Section("Links to (\(outgoing.count))") {
                    ForEach(outgoing, id: \.self) { name in
                        Button(name) { dismiss(); openLink(name) }
                    }
                }
            }
        }
        .navigationTitle("Note Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    static func links(in body: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "\\[\\[([^\\]\\n]+)\\]\\]") else { return [] }
        let ns = body as NSString
        var seen = Set<String>()
        return re.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let s = ns.substring(with: m.range(at: 1))
            return seen.insert(s.lowercased()).inserted ? s : nil
        }
    }
}

struct NoteLinkPicker: View {
    let excluding: UUID
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.updatedAt, order: .reverse) private var notesStored: [Note]
    @Environment(AppSettings.self) private var settings
    @State private var search = ""

    var body: some View {
        let notes = notesStored.live(settings.spaceFilter).filter { $0.id != excluding && (search.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(search)) }
        List {
            if !search.trimmed.isEmpty {
                Button { onPick(search.trimmed); dismiss() } label: {
                    Label("Link to “\(search.trimmed)”", systemImage: "plus")
                }
                .hushRow()
            }
            ForEach(notes) { n in
                Button { onPick(n.displayTitle); dismiss() } label: {
                    Label(n.displayTitle, systemImage: "doc.text").foregroundStyle(.primary)
                }
                .hushRow()
            }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Find or name a note…") }
        .navigationTitle("Link to Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

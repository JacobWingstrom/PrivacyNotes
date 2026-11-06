import SwiftUI
import SwiftData
import LocalAuthentication

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
    @State private var pickingIcon = false
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
    @State private var unlocked = false
    @State private var lockedText = ""
    @State private var finding = false
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var matchIndex = 0
    @State private var selectRequest: NSRange?
    @State private var makingTable = false
    @State private var showOutline = false
    @State private var settingGoal = false
    @State private var goalText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $note.title)
                .font(.hush(.title2).bold())
                .focused($titleFocused)
                .submitLabel(.next)
                .padding(.horizontal)
                .padding(.top, 10)

            if !note.tags.isEmpty || note.folderID != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let path = FolderPath.string(for: note.folderID, in: context) {
                            Label(path, systemImage: "folder").font(.hush(.caption).weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                                .onTapGesture { choosingFolder = true }
                        }
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)").font(.hush(.caption).weight(.medium))
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
                        .font(.hush(.subheadline))
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if finding { findBar }

            if note.isLocked && !unlocked {
                LockedNoteView { unlock() }
            } else {
                MarkdownEditor(text: bodyBinding, pendingInsert: $pendingInsert,
                               fontDesign: settings.fontStyle, accent: UIColor(settings.accentColor),
                               horizontalInset: 16, palette: palette,
                               onOpenNoteLink: openLink,
                               onLinkPicker: { pickingLink = true },
                               onAttach: { choosingAttachment = true },
                               onTable: { makingTable = true },
                               highlight: finding ? findText : "",
                               selectRequest: $selectRequest)

                wordBar

                AttachmentStrip(noteID: note.id) { text in pendingInsert = "\n> " + text.replacingOccurrences(of: "\n", with: "\n> ") + "\n" }
            }
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
        .onChange(of: lockedText) { if unlocked { note.updatedAt = .now } }
        .onAppear {
            if original == nil { original = (note.title, note.body) }
            if note.isEmpty { titleFocused = true }
        }
        .onDisappear(perform: finish)
        .fullScreenCover(isPresented: $zen) { ZenEditor(note: note) }
        .sheet(isPresented: $makingTable) { TableMaker { pendingInsert = $0 } }
        .sheet(isPresented: $showOutline) {
            OutlineSheet(text: bodyBinding.wrappedValue) { range in selectRequest = range }
        }
        .alert("Word Goal", isPresented: $settingGoal) {
            TextField("Words (0 for none)", text: $goalText).keyboardType(.numberPad)
            Button("Save") { note.wordGoal = max(Int(goalText) ?? 0, 0) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Show progress toward a word count for this note.") }
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
        .sheet(isPresented: $pickingIcon) { SymbolPicker(selection: $note.emoji) }
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
                Button { pickingIcon = true } label: { Label("Icon", systemImage: "star.square") }
            }
            Section {
                Button { withAnimation { finding = true } } label: { Label("Find & Replace", systemImage: "magnifyingglass") }
                Button { showOutline = true } label: { Label("Outline", systemImage: "list.bullet.indent") }
                Button { makingTable = true } label: { Label("Insert Table", systemImage: "tablecells") }
                Button { tidyTables() } label: { Label("Tidy Tables", systemImage: "tablecells.badge.ellipsis") }
                Button { goalText = note.wordGoal > 0 ? "\(note.wordGoal)" : ""; settingGoal = true } label: { Label("Word Goal…", systemImage: "target") }
            }
            Section {
                Button { toggleLock() } label: {
                    Label(note.isLocked ? "Remove Lock" : "Lock Note", systemImage: note.isLocked ? "lock.open" : "lock")
                }
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
        if note.isLocked {
            if unlocked { NoteLock.save(note, text: lockedText) }
            if deleting { TrashActions.trash(note) }
            return
        }
        if note.isEmpty && !hasAttachments {
            context.delete(note)
            return
        }
        if deleting {
            TrashActions.trash(note)
            return
        }
        // Keep the previous version when something changed.
        if !note.isLocked, let (t, b) = original, (t != note.title || b != note.body), !(t.isEmpty && b.isEmpty) {
            NoteHistory.save(noteID: note.id, title: t, body: b, in: context)
        }
        original = (note.title, note.body)
    }

    // MARK: Locking, find, tables

    /// The text the editor works on: the decrypted copy for locked notes (never written to disk in plain text).
    private var bodyBinding: Binding<String> {
        note.isLocked ? $lockedText : $note.body
    }

    private func unlock() {
        NoteLock.authenticate("Unlock “\(note.displayTitle)”") { ok in
            guard ok else { return }
            lockedText = NoteLock.read(note)
            unlocked = true
        }
    }

    private func toggleLock() {
        if note.isLocked {
            NoteLock.authenticate("Remove the lock from this note") { ok in
                guard ok else { return }
                if unlocked { NoteLock.save(note, text: lockedText) }
                NoteLock.remove(note)
                unlocked = false
            }
        } else {
            NoteLock.authenticate("Lock this note") { ok in
                guard ok else { return }
                let text = note.body
                NoteLock.lock(note, text: text)
                NoteHistory.deleteAll(noteID: note.id, in: context)
                lockedText = text
                unlocked = true
            }
        }
    }

    private var matches: [NSRange] {
        let text = bodyBinding.wrappedValue as NSString
        guard !findText.isEmpty else { return [] }
        var out: [NSRange] = []
        var search = NSRange(location: 0, length: text.length)
        while search.length > 0 {
            let r = text.range(of: findText, options: [.caseInsensitive], range: search)
            guard r.location != NSNotFound else { break }
            out.append(r)
            search = NSRange(location: r.upperBound, length: text.length - r.upperBound)
        }
        return out
    }

    private var findBar: some View {
        let m = matches
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find", text: $findText).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onChange(of: findText) { matchIndex = 0 }
                Text(m.isEmpty ? (findText.isEmpty ? "" : "0") : "\(min(matchIndex + 1, m.count))/\(m.count)")
                    .font(.hush(.caption).monospacedDigit()).foregroundStyle(.secondary)
                Button { step(-1, m) } label: { Image(systemName: "chevron.up") }.disabled(m.isEmpty)
                Button { step(1, m) } label: { Image(systemName: "chevron.down") }.disabled(m.isEmpty)
                Button("Done") { withAnimation { finding = false; findText = "" } }.font(.hush(.subheadline).weight(.semibold))
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.2.squarepath").foregroundStyle(.secondary)
                TextField("Replace with", text: $replaceText).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("Replace") { replaceCurrent(m) }.disabled(m.isEmpty)
                Button("All") { replaceAll() }.disabled(m.isEmpty)
            }
        }
        .buttonStyle(.borderless)
        .padding(10)
        .background(palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func step(_ d: Int, _ m: [NSRange]) {
        guard !m.isEmpty else { return }
        matchIndex = (matchIndex + d + m.count) % m.count
        selectRequest = m[matchIndex]
    }

    private func replaceCurrent(_ m: [NSRange]) {
        guard !m.isEmpty else { return }
        let i = min(matchIndex, m.count - 1)
        let ns = bodyBinding.wrappedValue as NSString
        bodyBinding.wrappedValue = ns.replacingCharacters(in: m[i], with: replaceText)
    }

    private func replaceAll() {
        bodyBinding.wrappedValue = bodyBinding.wrappedValue.replacingOccurrences(of: findText, with: replaceText, options: .caseInsensitive)
    }

    private func tidyTables() {
        bodyBinding.wrappedValue = TableTidy.tidy(bodyBinding.wrappedValue)
    }

    private var wordBar: some View {
        let words = bodyBinding.wrappedValue.split { $0.isWhitespace || $0.isNewline }.count
        return HStack(spacing: 10) {
            Text("\(words) word\(words == 1 ? "" : "s")").monospacedDigit()
            if note.wordGoal > 0 {
                ProgressView(value: min(Double(words), Double(note.wordGoal)), total: Double(note.wordGoal))
                    .frame(maxWidth: 140)
                Text("\(Int(min(Double(words) / Double(note.wordGoal), 1) * 100))% of \(note.wordGoal)").monospacedDigit()
                if words >= note.wordGoal { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
            }
            Spacer()
            if note.isLocked { Label("Locked", systemImage: "lock.fill").labelStyle(.iconOnly).foregroundStyle(.tint) }
        }
        .font(.hush(.caption))
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
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
                               fontScale: 1.15, accent: UIColor(settings.accentColor), horizontalInset: 28, palette: palette, focusOnAppear: true)
                    .frame(maxWidth: 700)
                    .padding(.top, 54)
            }
            HStack {
                Text(note.displayTitle).font(.hush(.headline)).lineLimit(1)
                Spacer()
                Text("\(note.wordCount) words").font(.hush(.caption)).foregroundStyle(.secondary).monospacedDigit()
                Button("Done") { dismiss() }.font(.hush(.headline)).padding(.leading, 12)
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

    static func deleteAll(noteID: UUID, in ctx: ModelContext) {
        for v in (try? ctx.fetch(FetchDescriptor<NoteVersion>())) ?? [] where v.noteID == noteID { ctx.delete(v) }
    }

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
                .font(.hush(.footnote)).foregroundStyle(.secondary)
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
                        Text(v.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.hush(.headline))
                        Text(Markdown.plain(v.body).replacingOccurrences(of: "\n", with: " ")).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(2)
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
                Text(version.title.isEmpty ? "Untitled" : version.title).font(.hush(.title2).bold())
                Text(version.body).font(.hush(.body)).textSelection(.enabled)
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


// MARK: - Note lock

enum NoteLock {
    static func lock(_ n: Note, text: String) {
        n.lockedBody = DataCrypto.seal(Data(text.utf8))
        n.body = ""
        n.isLocked = true
    }

    static func read(_ n: Note) -> String {
        DataCrypto.open(n.lockedBody).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static func save(_ n: Note, text: String) {
        n.lockedBody = DataCrypto.seal(Data(text.utf8))
    }

    static func remove(_ n: Note) {
        n.body = read(n)
        n.lockedBody = Data()
        n.isLocked = false
    }

    /// Face ID or Touch ID, falling back to the iPhone passcode.
    static func authenticate(_ reason: String, done: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { done(true); return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

private struct LockedNoteView: View {
    var unlock: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "lock.doc.fill").font(.system(size: 46)).foregroundStyle(.tint)
            Text("This note is locked").font(.hush(.headline))
            Text("Its text is encrypted. Unlock with Face ID to read or edit it.").font(.hush(.subheadline))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Unlock", action: unlock).buttonStyle(.borderedProminent)
            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { unlock() } }
    }
}

// MARK: - Tables

struct TableMaker: View {
    var onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var columns = 3
    @State private var rows = 3
    @State private var headers = "Name, Value, Notes"

    var body: some View {
        NavigationStack {
            HushForm {
                Section {
                    Stepper("Columns: \(columns)", value: $columns, in: 1...8)
                    Stepper("Rows: \(rows)", value: $rows, in: 1...30)
                    TextField("Headers, comma separated", text: $headers)
                }
                Section("Preview") {
                    Text(markdown).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            .navigationTitle("Insert Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Insert") { onInsert("\n" + markdown + "\n"); dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var markdown: String {
        var names = headers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        while names.count < columns { names.append("Column \(names.count + 1)") }
        names = Array(names.prefix(columns))
        let header = "| " + names.joined(separator: " | ") + " |"
        let rule = "|" + Array(repeating: "---|", count: columns).joined()
        let row = "|" + Array(repeating: "  |", count: columns).joined()
        return ([header, rule] + Array(repeating: row, count: rows)).joined(separator: "\n")
    }
}

/// Pads Markdown table cells so the pipes line up.
enum TableTidy {
    static func tidy(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            guard lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") else { i += 1; continue }
            var j = i
            while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("|") { j += 1 }
            let rows = lines[i..<j].map { line -> [String] in
                var t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("|") { t.removeFirst() }
                if t.hasSuffix("|") { t.removeLast() }
                return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            let cols = rows.map(\.count).max() ?? 0
            let isRule: ([String]) -> Bool = { $0.allSatisfy { c in !c.isEmpty && c.allSatisfy { "-:".contains($0) } } }
            var widths = Array(repeating: 3, count: cols)
            for r in rows where !isRule(r) { for (k, c) in r.enumerated() { widths[k] = max(widths[k], c.count) } }
            let formatted = rows.map { r -> String in
                let cells = (0..<cols).map { k -> String in
                    let c = k < r.count ? r[k] : ""
                    if isRule(r) { return String(repeating: "-", count: widths[k]) }
                    return c + String(repeating: " ", count: widths[k] - c.count)
                }
                return "| " + cells.joined(separator: " | ") + " |"
            }
            lines.replaceSubrange(i..<j, with: formatted)
            i = j
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Outline

private struct OutlineSheet: View {
    let text: String
    var jump: (NSRange) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let ns = text as NSString
        let re = try? NSRegularExpression(pattern: "^(#{1,6})[ \\t]+(.+)$", options: .anchorsMatchLines)
        let items: [(level: Int, title: String, range: NSRange)] = (re?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []).map {
            ($0.range(at: 1).length, ns.substring(with: $0.range(at: 2)), $0.range)
        }
        NavigationStack {
            List {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    Button {
                        jump(NSRange(location: item.range.location, length: 0))
                        dismiss()
                    } label: {
                        Text(item.title)
                            .font(.hush(item.level == 1 ? .headline : (item.level == 2 ? .subheadline : .footnote)))
                            .foregroundStyle(.primary)
                            .padding(.leading, CGFloat(item.level - 1) * 16)
                    }
                    .hushRow()
                }
                if items.isEmpty { EmptyMessage(text: "No headings yet. Start a line with # to make one.") }
            }
            .hushList()
            .navigationTitle("Outline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

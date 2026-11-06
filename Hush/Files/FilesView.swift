import SwiftUI
import SwiftData
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

struct FilesView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @Query(sort: \StoredFile.createdAt, order: .reverse) private var filesStored: [StoredFile]
    @Environment(AppSettings.self) private var filesSpace
    private var files: [StoredFile] { filesStored.live(filesSpace.spaceFilter) }
    @State private var kind: FileKind?
    @State private var choosingSource = false
    @State private var attachKind: AttachmentKind?
    @AppStorage("filesShowAttachments") private var showAttachments = true
    @State private var search = ""
    @State private var importingFiles = false
    @State private var pickingPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var previewURL: URL?
    @State private var renaming: StoredFile?
    @State private var renameText = ""
    @State private var sort: FileSort = .newest
    @State private var errorMessage: String?

    enum FileSort: String, CaseIterable, Identifiable {
        case newest, name, size
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum FileKind: String, CaseIterable, Identifiable {
        case images, video, audio, documents
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        func matches(_ f: StoredFile) -> Bool {
            let t = UTType(f.typeIdentifier) ?? .data
            switch self {
            case .images: return t.conforms(to: .image)
            case .video: return t.conforms(to: .movie)
            case .audio: return t.conforms(to: .audio)
            case .documents: return !t.conforms(to: .image) && !t.conforms(to: .movie) && !t.conforms(to: .audio)
            }
        }
    }

    private var filtered: [StoredFile] {
        let base = files.filter {
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.searchText.localizedCaseInsensitiveContains(search))
                && (kind?.matches($0) ?? true) && (showAttachments || $0.noteID == nil)
        }
        switch sort {
        case .newest: return base
        case .name: return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size: return base.sorted { $0.size > $1.size }
        }
    }

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Encrypted storage", systemImage: "lock.doc")
                    Spacer()
                    Text("\(files.count) file\(files.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(files.reduce(0) { $0 + $1.size }), countStyle: .file))")
                        .monospacedDigit()
                }
                .font(.hush(.subheadline))
                .foregroundStyle(.secondary)
                Text("No size limits — files are only limited by your iPhone's free space.")
                    .font(.hush(.caption)).foregroundStyle(.tertiary)
            }
            .plainRow(top: 12, bottom: 6)
            FilterChips(options: [(nil, "All")] + FileKind.allCases.map { ($0, $0.label) }, selection: $kind)
                .plainRow(top: 4, bottom: 6)
            ForEach(filtered) { file in
                Button { open(file) } label: { FileRow(file: file) }
                    .foregroundStyle(.primary)
                    .hushRow()
                    .swipeActions {
                        Button(role: .destructive) { TrashActions.trash(file) } label: { Label("Delete", systemImage: "trash") }
                        Button { renameText = file.name; renaming = file } label: { Label("Rename", systemImage: "pencil") }
                    }
                    .contextMenu {
                        Button { open(file) } label: { Label("Open", systemImage: "eye") }
                        Button { renameText = file.name; renaming = file } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { TrashActions.trash(file) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .hushList()
        .overlay {
            if filtered.isEmpty {
                EmptyMessage(text: files.isEmpty ? "No files yet. Tap + to import photos, PDFs and documents." : "No files match.")
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchHeader(text: $search, prompt: "Search files…") {
                FilterButton(active: sort != .newest || !showAttachments) {
                    Picker("Sort", selection: $sort) { ForEach(FileSort.allCases) { Text($0.label).tag($0) } }
                    Toggle("Show files attached to notes", isOn: $showAttachments)
                }
            }
        }
        .navigationTitle(title)
        .onCreate(.files) { choosingSource = true }
        .attachmentChooser(isPresented: $choosingSource) { attachKind = $0 }
        .attachmentPresenter($attachKind, noteID: nil)
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $photoSelection, maxSelectionCount: 30, matching: .any(of: [.images, .videos]))
        .onChange(of: photoSelection) { _, picked in importPhotos(picked) }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, url in if url == nil { TempFiles.clear() } }
        .alert("Rename File", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if !renameText.trimmed.isEmpty { renaming?.name = renameText.trimmed } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't open file", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "") }
    }

    private func open(_ file: StoredFile) {
        guard let data = DataCrypto.open(file.sealedData) else {
            errorMessage = "The file couldn't be decrypted."
            return
        }
        previewURL = TempFiles.write(data, name: file.name)
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
            context.insert(StoredFile(name: url.lastPathComponent, typeIdentifier: type, data: data))
        }
    }

    private func importPhotos(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        Task {
            for (i, p) in picked.enumerated() {
                guard let data = try? await p.loadTransferable(type: Data.self) else { continue }
                let type = p.supportedContentTypes.first ?? .jpeg
                let ext = type.preferredFilenameExtension ?? "jpg"
                let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
                context.insert(StoredFile(name: "Photo \(stamp) \(i + 1).\(ext)", typeIdentifier: type.identifier, data: data))
            }
            photoSelection = []
        }
    }
}

private struct FileRow: View {
    let file: StoredFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.hush(.title3))
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(file.name).lineLimit(1)
                    if file.noteID != nil { Image(systemName: "paperclip").font(.hush(.caption2)).foregroundStyle(.secondary) }
                }
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)) · \(file.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.hush(.caption)).foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        guard let t = UTType(file.typeIdentifier) else { return "doc" }
        if t.conforms(to: .image) { return "photo" }
        if t.conforms(to: .movie) { return "film" }
        if t.conforms(to: .audio) { return "waveform" }
        if t.conforms(to: .pdf) { return "doc.richtext" }
        if t.conforms(to: .spreadsheet) { return "tablecells" }
        if t.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if t.conforms(to: .archive) { return "doc.zipper" }
        if t.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}

import SwiftUI
import SwiftData
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

struct FilesView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredFile.createdAt, order: .reverse) private var files: [StoredFile]
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

    private var filtered: [StoredFile] {
        let base = files.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .newest: return base
        case .name: return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size: return base.sorted { $0.size > $1.size }
        }
    }

    var body: some View {
        List {
            if !files.isEmpty && search.isEmpty {
                Section {
                    LabeledContent("\(files.count) file\(files.count == 1 ? "" : "s")",
                                   value: ByteCountFormatter.string(fromByteCount: Int64(files.reduce(0) { $0 + $1.size }), countStyle: .file))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(filtered) { file in
                Button { open(file) } label: { FileRow(file: file) }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button(role: .destructive) { context.delete(file) } label: { Label("Delete", systemImage: "trash") }
                        Button { renameText = file.name; renaming = file } label: { Label("Rename", systemImage: "pencil") }
                    }
                    .contextMenu {
                        Button { open(file) } label: { Label("Open", systemImage: "eye") }
                        Button { renameText = file.name; renaming = file } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { context.delete(file) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .hushBackground()
        .overlay {
            if files.isEmpty {
                ContentUnavailableView("No files yet", systemImage: "folder",
                                       description: Text("Import photos, PDFs and documents. They're copied into Hush and encrypted."))
            }
        }
        .searchable(text: $search, prompt: "Search files")
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(FileSort.allCases) { Text($0.label).tag($0) } }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { importingFiles = true } label: { Label("From Files", systemImage: "folder") }
                    Button { pickingPhotos = true } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Import")
            }
        }
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
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(1)
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)) · \(file.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
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

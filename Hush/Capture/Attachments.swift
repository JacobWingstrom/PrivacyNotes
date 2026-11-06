import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Adding photos, files, scans and voice memos — to a note or straight into Files.
enum AttachmentKind: String, Identifiable {
    case photos, files, scan, memo
    var id: String { rawValue }
}

enum Attach {
    static func stamp() -> String { Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute()) .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".") }

    @MainActor
    static func addFiles(_ urls: [URL], noteID: UUID?, into ctx: ModelContext) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
            ctx.insert(StoredFile(name: url.lastPathComponent, typeIdentifier: type, data: data, noteID: noteID))
        }
    }

    @MainActor
    static func addPhotos(_ items: [PhotosPickerItem], noteID: UUID?, into ctx: ModelContext) async {
        for (i, p) in items.enumerated() {
            guard let data = try? await p.loadTransferable(type: Data.self) else { continue }
            let type = p.supportedContentTypes.first ?? .jpeg
            let ext = type.preferredFilenameExtension ?? "jpg"
            ctx.insert(StoredFile(name: "Photo \(stamp())\(items.count > 1 ? " \(i + 1)" : "").\(ext)",
                                  typeIdentifier: type.identifier, data: data, noteID: noteID))
        }
    }

    @MainActor
    static func addScan(_ images: [UIImage], noteID: UUID?, into ctx: ModelContext) async {
        guard !images.isEmpty else { return }
        let pdf = ScanProcessor.pdf(from: images)
        let file = StoredFile(name: "Scan \(stamp()).pdf", typeIdentifier: UTType.pdf.identifier, data: pdf, noteID: noteID)
        ctx.insert(file)
        file.searchText = await ScanProcessor.recognizeText(images)
    }

    @MainActor
    static func addMemo(_ data: Data, duration: TimeInterval, noteID: UUID?, into ctx: ModelContext) {
        let mins = Int(duration) / 60, secs = Int(duration) % 60
        ctx.insert(StoredFile(name: "Memo \(stamp()) (\(mins):\(String(format: "%02d", secs))).m4a",
                              typeIdentifier: UTType.mpeg4Audio.identifier, data: data, noteID: noteID))
    }
}

/// Presents the right picker for an attachment kind and saves the result.
struct AttachmentPresenter: ViewModifier {
    @Binding var kind: AttachmentKind?
    let noteID: UUID?
    @Environment(\.modelContext) private var context
    @State private var photoItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: Binding(get: { kind == .photos }, set: { if !$0 && kind == .photos { kind = nil } }),
                          selection: $photoItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos]))
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await Attach.addPhotos(items, noteID: noteID, into: context); photoItems = [] }
            }
            .fileImporter(isPresented: Binding(get: { kind == .files }, set: { if !$0 && kind == .files { kind = nil } }),
                          allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Attach.addFiles(urls, noteID: noteID, into: context) }
            }
            .fullScreenCover(isPresented: Binding(get: { kind == .scan }, set: { if !$0 && kind == .scan { kind = nil } })) {
                DocumentScanner { images in Task { await Attach.addScan(images, noteID: noteID, into: context) } }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(get: { kind == .memo }, set: { if !$0 && kind == .memo { kind = nil } })) {
                MemoRecorderView { data, time in Attach.addMemo(data, duration: time, noteID: noteID, into: context) }
            }
    }
}

extension View {
    func attachmentPresenter(_ kind: Binding<AttachmentKind?>, noteID: UUID?) -> some View {
        modifier(AttachmentPresenter(kind: kind, noteID: noteID))
    }

    /// The four ways to add something, as dialog buttons.
    func attachmentChooser(isPresented: Binding<Bool>, choose: @escaping (AttachmentKind) -> Void) -> some View {
        confirmationDialog("Add", isPresented: isPresented) {
            Button("Photos & Videos") { choose(.photos) }
            Button("Files") { choose(.files) }
            if DocumentScanner.isAvailable { Button("Scan Document") { choose(.scan) } }
            Button("Voice Memo") { choose(.memo) }
        }
    }
}

/// Horizontal strip of a note's attachments with thumbnails.
struct AttachmentStrip: View {
    let noteID: UUID
    var onInsertText: (String) -> Void = { _ in }
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Query(sort: \StoredFile.createdAt) private var allFiles: [StoredFile]
    @State private var previewURL: URL?

    var body: some View {
        let files = allFiles.filter { $0.noteID == noteID && $0.deletedAt == nil }
        if !files.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(files) { f in
                        Button { open(f) } label: { AttachmentTile(file: f) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { open(f) } label: { Label("Open", systemImage: "eye") }
                                if !f.searchText.isEmpty {
                                    Button { onInsertText(f.searchText) } label: { Label("Insert Scanned Text", systemImage: "text.viewfinder") }
                                }
                                Button(role: .destructive) { context.delete(f) } label: { Label("Remove", systemImage: "trash") }
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .background(palette.surface)
            .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
            .quickLookPreview($previewURL)
            .onChange(of: previewURL) { _, url in if url == nil { TempFiles.clear() } }
        }
    }

    private func open(_ f: StoredFile) {
        guard let data = DataCrypto.open(f.sealedData) else { return }
        previewURL = TempFiles.write(data, name: f.name)
    }
}

struct AttachmentTile: View {
    let file: StoredFile
    @State private var thumb: UIImage?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(palette.field)
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Image(systemName: FileIcon.symbol(for: file.typeIdentifier)).font(.hush(.title2)).foregroundStyle(.tint)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border))
            Text(file.name).font(.hush(.caption2)).lineLimit(1).frame(width: 64)
        }
        .task(id: file.id) {
            guard UTType(file.typeIdentifier)?.conforms(to: .image) == true,
                  let data = DataCrypto.open(file.sealedData) else { return }
            thumb = await Task.detached { UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 160, height: 160)) }.value
        }
    }
}

enum FileIcon {
    static func symbol(for typeIdentifier: String) -> String {
        guard let t = UTType(typeIdentifier) else { return "doc" }
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

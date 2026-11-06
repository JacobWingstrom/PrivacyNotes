import SwiftUI
import SwiftData
import PencilKit

struct DrawingsView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @Query(sort: \Drawing.updatedAt, order: .reverse) private var drawingsStored: [Drawing]
    @Environment(AppSettings.self) private var drawingsSpace
    private var drawings: [Drawing] { drawingsStored.live(drawingsSpace.spaceFilter) }
    @State private var search = ""
    @State private var newDrawing: Drawing?
    @State private var renaming: Drawing?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(drawings.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { drawing in
                    NavigationLink { DrawingEditorView(drawing: drawing) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            DrawingThumbnail(data: drawing.data)
                                .frame(height: 150)
                                .frame(maxWidth: .infinity)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.border))
                            Text(drawing.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(drawing.updatedAt, format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { renameText = drawing.title; renaming = drawing } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { TrashActions.trash(drawing) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .padding()
        }
        .background(palette.background)
        .overlay {
            if drawings.isEmpty {
                EmptyMessage(text: "No drawings yet. Tap + to sketch with your finger or Apple Pencil.")
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search drawings…") }
        .navigationTitle(title)
        .navigationDestination(item: $newDrawing) { DrawingEditorView(drawing: $0) }
        .onCreate(.drawings) {
            let d = Drawing()
            context.insert(d)
            newDrawing = d
        }
        .alert("Rename Drawing", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") { renaming?.title = renameText.trimmed.isEmpty ? "Untitled Drawing" : renameText.trimmed }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct DrawingThumbnail: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(10)
            } else {
                Image(systemName: "scribble").font(.largeTitle).foregroundStyle(.gray.opacity(0.5))
            }
        }
        .task(id: data) { image = Self.render(data) }
    }

    static func render(_ data: Data) -> UIImage? {
        guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -12, dy: -12)
        var img: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = drawing.image(from: bounds, scale: 1)
        }
        return img
    }
}

struct DrawingEditorView: View {
    @Bindable var drawing: Drawing
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false

    var body: some View {
        CanvasView(data: $drawing.data)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle($drawing.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let image = DrawingThumbnail.render(drawing.data) {
                            ShareLink(item: Image(uiImage: image), preview: SharePreview(drawing.title, image: Image(uiImage: image))) {
                                Label("Share Image…", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button(role: .destructive) {
                            deleting = true
                            dismiss()
                        } label: { Label("Delete Drawing", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onChange(of: drawing.data) { drawing.updatedAt = .now }
            .onDisappear {
                let empty = (try? PKDrawing(data: drawing.data))?.strokes.isEmpty ?? true
                if deleting && !empty { TrashActions.trash(drawing) } else if empty { context.delete(drawing) }
            }
    }
}

/// PencilKit canvas with Apple's tool picker (pens, markers, eraser, ruler, colors).
struct CanvasView: UIViewRepresentable {
    @Binding var data: Data

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
        canvas.delegate = context.coordinator
        canvas.alwaysBounceVertical = true
        canvas.backgroundColor = .systemBackground
        let picker = context.coordinator.toolPicker
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        let toolPicker = PKToolPicker()
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.data = canvasView.drawing.dataRepresentation()
        }
    }
}

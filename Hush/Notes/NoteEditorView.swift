import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @FocusState private var focus: Field?
    @State private var deleting = false
    @State private var editingTags = false
    @State private var tagText = ""
    @State private var editingEmoji = false
    @State private var emojiText = ""

    private enum Field { case title, body }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $note.title)
                .font(.title2.bold())
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onSubmit { focus = .body }
                .padding(.top, 8)

            if !note.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            TextEditor(text: $note.body)
                .focused($focus, equals: .body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5) // line up with the title
        }
        .padding(.horizontal)
        .background {
            ZStack {
                palette.background
                if let c = note.color { c.opacity(0.08) }
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
            ToolbarItemGroup(placement: .keyboard) {
                Button { insertChecklistItem() } label: { Image(systemName: "checklist") }
                Button { insertBullet() } label: { Image(systemName: "list.bullet") }
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .onChange(of: note.title) { note.updatedAt = .now }
        .onChange(of: note.body) { note.updatedAt = .now }
        .onAppear { if note.isEmpty { focus = .title } }
        .onDisappear {
            if deleting || note.isEmpty { context.delete(note) }
        }
        .alert("Tags", isPresented: $editingTags) {
            TextField("work, ideas, personal", text: $tagText)
                .textInputAutocapitalization(.never)
            Button("Save") {
                note.tags = .tags(from: tagText)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Separate tags with commas.")
        }
        .alert("Note Icon", isPresented: $editingEmoji) {
            TextField("Type an emoji", text: $emojiText)
            Button("Save") { note.emoji = String(emojiText.trimmingCharacters(in: .whitespaces).prefix(1)) }
            Button("Remove", role: .destructive) { note.emoji = "" }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var menu: some View {
        Menu {
            Button { note.isPinned.toggle() } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            Picker(selection: $note.colorName) {
                ForEach(NoteColor.allCases) { Text($0.label).tag($0.rawValue) }
            } label: {
                Label("Color", systemImage: "paintpalette")
            }
            .pickerStyle(.menu)
            Button {
                tagText = note.tags.joined(separator: ", ")
                editingTags = true
            } label: { Label("Tags", systemImage: "tag") }
            Button {
                emojiText = note.emoji
                editingEmoji = true
            } label: { Label("Icon", systemImage: "face.smiling") }
            ShareLink(item: shareText) { Label("Share…", systemImage: "square.and.arrow.up") }
            Divider()
            Text("Edited \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            Button(role: .destructive) {
                deleting = true
                dismiss()
            } label: { Label("Delete Note", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var shareText: String {
        note.title.isEmpty ? note.body : "\(note.title)\n\n\(note.body)"
    }

    private func insertChecklistItem() { appendLinePrefix("☐ ") }
    private func insertBullet() { appendLinePrefix("• ") }

    /// Adds a new line starting with the prefix at the end of the note.
    private func appendLinePrefix(_ prefix: String) {
        if !note.body.isEmpty && !note.body.hasSuffix("\n") { note.body += "\n" }
        note.body += prefix
        focus = .body
    }
}

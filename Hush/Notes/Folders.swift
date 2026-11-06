import SwiftUI
import SwiftData

enum FolderPath {
    static func chain(for id: UUID?, folders: [Folder]) -> [Folder] {
        var out: [Folder] = []
        var current = id
        var guardCount = 0
        while let c = current, let f = folders.first(where: { $0.id == c }), guardCount < 32 {
            out.insert(f, at: 0)
            current = f.parentID
            guardCount += 1
        }
        return out
    }

    static func string(for id: UUID?, in ctx: ModelContext) -> String? {
        guard id != nil else { return nil }
        let folders = (try? ctx.fetch(FetchDescriptor<Folder>())) ?? []
        let c = chain(for: id, folders: folders)
        return c.isEmpty ? nil : c.map(\.name).joined(separator: " › ")
    }

    /// All folders in tree order with their depth, for pickers.
    static func flattened(_ folders: [Folder], parent: UUID? = nil, depth: Int = 0) -> [(Folder, Int)] {
        guard depth < 16 else { return [] }
        let children = folders.filter { $0.parentID == parent }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return children.flatMap { [($0, depth)] + flattened(folders, parent: $0.id, depth: depth + 1) }
    }

    static func descendants(of id: UUID, in folders: [Folder]) -> Set<UUID> {
        var out: Set<UUID> = [id]
        var frontier = [id]
        while let next = frontier.popLast() {
            for f in folders where f.parentID == next && !out.contains(f.id) {
                out.insert(f.id); frontier.append(f.id)
            }
        }
        return out
    }

    /// Deleting a folder keeps its notes: they move up to the parent folder.
    static func delete(_ folder: Folder, in ctx: ModelContext) {
        let notes = (try? ctx.fetch(FetchDescriptor<Note>())) ?? []
        for n in notes where n.folderID == folder.id { n.folderID = folder.parentID }
        let folders = (try? ctx.fetch(FetchDescriptor<Folder>())) ?? []
        for f in folders where f.parentID == folder.id { f.parentID = folder.parentID }
        ctx.delete(folder)
    }
}

struct FolderPicker: View {
    @Binding var selection: UUID?
    var excluding: UUID? = nil
    var title = "Move to Folder"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var foldersStored: [Folder]
    @Environment(AppSettings.self) private var settings
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        let folders = foldersStored.live(settings.spaceFilter)
        let blocked = excluding.map { FolderPath.descendants(of: $0, in: folders) } ?? []
        List {
            Button { selection = nil; dismiss() } label: {
                HStack {
                    Label("No Folder", systemImage: "tray")
                    Spacer()
                    if selection == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .foregroundStyle(.primary)
            .hushRow()
            ForEach(FolderPath.flattened(folders).filter { !blocked.contains($0.0.id) }, id: \.0.id) { folder, depth in
                Button { selection = folder.id; dismiss() } label: {
                    HStack {
                        Label(folder.name, systemImage: "folder")
                            .padding(.leading, CGFloat(depth) * 18)
                        Spacer()
                        if selection == folder.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .foregroundStyle(.primary)
                .hushRow()
            }
        }
        .hushList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button { newName = ""; creating = true } label: { Image(systemName: "folder.badge.plus") }
                    .accessibilityLabel("New folder")
            }
        }
        .alert("New Folder", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") {
                guard !newName.trimmed.isEmpty else { return }
                let f = Folder(name: newName.trimmed, parentID: nil)
                context.insert(f)
                if excluding == nil { selection = f.id; dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// A folder row inside the Notes list.
struct FolderRow: View {
    let folder: Folder
    let count: Int
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            Text(folder.emoji.isEmpty ? folder.name : "\(folder.emoji) \(folder.name)").font(.headline)
            Spacer()
            Text("\(count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 6)
    }
}

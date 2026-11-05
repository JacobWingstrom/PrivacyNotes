import SwiftUI
import SwiftData

struct BookmarksView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var favoritesOnly = false
    @State private var editing: Bookmark?
    @State private var adding = false

    private var allTags: [String] { Array(Set(bookmarks.flatMap(\.tags))).sorted() }

    private var filtered: [Bookmark] {
        bookmarks.filter { b in
            (search.isEmpty || b.displayTitle.localizedCaseInsensitiveContains(search)
                || b.urlString.localizedCaseInsensitiveContains(search) || b.notes.localizedCaseInsensitiveContains(search))
            && (tagFilter == nil || b.tags.contains(tagFilter!))
            && (!favoritesOnly || b.isFavorite)
        }
    }

    var body: some View {
        List {
            if !bookmarks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TagChip(text: "All", selected: tagFilter == nil && !favoritesOnly) { tagFilter = nil; favoritesOnly = false }
                        TagChip(text: "★ Favorites", selected: favoritesOnly) { favoritesOnly.toggle() }
                        ForEach(allTags, id: \.self) { tag in
                            TagChip(text: "#\(tag)", selected: tagFilter == tag) { tagFilter = tagFilter == tag ? nil : tag }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .chipRow()
            }
            ForEach(filtered) { b in
                Button { if let url = b.url { openURL(url) } } label: { BookmarkRow(bookmark: b) }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { context.delete(b) } label: { Label("Delete", systemImage: "trash") }
                        Button { editing = b } label: { Label("Edit", systemImage: "pencil") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { b.isFavorite.toggle() } label: { Label("Favorite", systemImage: b.isFavorite ? "star.slash" : "star") }
                            .tint(.yellow)
                    }
                    .contextMenu {
                        Button { editing = b } label: { Label("Edit", systemImage: "pencil") }
                        Button { UIPasteboard.general.string = b.urlString } label: { Label("Copy Link", systemImage: "doc.on.doc") }
                        if let url = b.url { ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") } }
                        Button(role: .destructive) { context.delete(b) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain)
        .hushBackground()
        .overlay {
            if bookmarks.isEmpty {
                ContentUnavailableView("No bookmarks yet", systemImage: "bookmark",
                                       description: Text("Save links here. Hush never loads them in the background, so nothing is tracked."))
            }
        }
        .searchable(text: $search, prompt: "Search bookmarks")
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("New bookmark")
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { BookmarkForm(bookmark: nil) } }
        .sheet(item: $editing) { b in NavigationStack { BookmarkForm(bookmark: b) } }
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    var body: some View {
        HStack(spacing: 12) {
            Text(String(bookmark.host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(bookmark.displayTitle).lineLimit(1)
                    if bookmark.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                }
                Text(bookmark.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !bookmark.tags.isEmpty {
                    Text(bookmark.tags.map { "#\($0)" }.joined(separator: " ")).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Add or edit a bookmark. Changes are saved only when you tap Save.
struct BookmarkForm: View {
    let bookmark: Bookmark?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    @State private var notes = ""
    @State private var tags = ""
    @State private var favorite = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("example.com", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first { url = s.trimmed }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
                TextField("Title (optional)", text: $title)
            }
            Section {
                TextField("Tags, comma separated", text: $tags).textInputAutocapitalization(.never)
                Toggle("Favorite", isOn: $favorite)
            }
            Section("Notes") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...8) }
        }
        .navigationTitle(bookmark == nil ? "New Bookmark" : "Edit Bookmark")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(url.trimmed.isEmpty) }
        }
        .onAppear {
            guard !loaded, let b = bookmark else { return }
            url = b.urlString; title = b.title; notes = b.notes
            tags = b.tags.joined(separator: ", "); favorite = b.isFavorite
            loaded = true
        }
    }

    private func save() {
        let b = bookmark ?? Bookmark()
        b.urlString = Bookmark.normalize(url)
        b.title = title.trimmed
        b.notes = notes
        b.tags = .tags(from: tags)
        b.isFavorite = favorite
        if bookmark == nil { context.insert(b) }
        dismiss()
    }
}

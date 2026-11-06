import SwiftUI
import SwiftData

struct BookmarksView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(Router.self) private var router
    @State private var quickLink = ""
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarksStored: [Bookmark]
    @Environment(AppSettings.self) private var bookmarksSpace
    private var bookmarks: [Bookmark] { bookmarksStored.live(bookmarksSpace.spaceFilter) }
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
            QuickAddField(prompt: "Paste or type a link…", text: $quickLink, keyboard: .URL, onSubmit: addQuick)
                .plainRow(top: 12, bottom: 6)
            if !bookmarks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TagChip(text: "All", selected: tagFilter == nil && !favoritesOnly) { tagFilter = nil; favoritesOnly = false }
                        TagChip(text: "Favorites", selected: favoritesOnly) { favoritesOnly.toggle() }
                        ForEach(allTags, id: \.self) { tag in
                            TagChip(text: "#\(tag)", selected: tagFilter == tag) { tagFilter = tagFilter == tag ? nil : tag }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .plainRow(top: 4, bottom: 6)
            }
            ForEach(filtered) { b in
                HStack(alignment: .top) {
                    Button { if let url = b.url { openURL(url) } } label: { BookmarkRow(bookmark: b) }
                        .buttonStyle(.plain)
                    Menu {
                        Button { editing = b } label: { Label("Edit", systemImage: "pencil") }
                        Button { b.isFavorite.toggle() } label: { Label(b.isFavorite ? "Unfavorite" : "Favorite", systemImage: "star") }
                        Button { UIPasteboard.general.string = b.urlString } label: { Label("Copy Link", systemImage: "doc.on.doc") }
                        if let url = b.url { ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") } }
                        Button(role: .destructive) { TrashActions.trash(b) } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .frame(width: 36, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    }
                    .foregroundStyle(.secondary)
                }
                    .foregroundStyle(.primary)
                    .hushRow()
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { TrashActions.trash(b) } label: { Label("Delete", systemImage: "trash") }
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
                        Button(role: .destructive) { TrashActions.trash(b) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .hushList()
        .overlay {
            if bookmarks.isEmpty {
                EmptyMessage(text: "No bookmarks yet. Hush never loads links in the background, so nothing is tracked.")
                    .padding(.top, 80)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchHeader(text: $search, prompt: "Search bookmarks…") {
                FilterButton(active: favoritesOnly || tagFilter != nil) {
                    Toggle("Favorites only", isOn: $favoritesOnly)
                    Picker("Tag", selection: $tagFilter) {
                        Text("All tags").tag(String?.none)
                        ForEach(allTags, id: \.self) { Text("#\($0)").tag(Optional($0)) }
                    }
                }
            }
        }
        .navigationTitle(title)
        .onCreate(.bookmarks) { adding = true }
        .sheet(isPresented: $adding) { NavigationStack { BookmarkForm(bookmark: nil) } }
        .sheet(item: $editing) { b in NavigationStack { BookmarkForm(bookmark: b) } }
    }

    private func addQuick() {
        let raw = quickLink.trimmed
        guard !raw.isEmpty else { return }
        let b = Bookmark()
        b.urlString = Bookmark.normalize(raw)
        context.insert(b)
        quickLink = ""
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(bookmark.host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                .font(.hush(.headline))
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(bookmark.displayTitle).lineLimit(1)
                    if bookmark.isFavorite { Image(systemName: "star.fill").font(.hush(.caption2)).foregroundStyle(.yellow) }
                }
                Text(bookmark.urlString).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
                if !bookmark.tags.isEmpty {
                    Text(bookmark.tags.map { "#\($0)" }.joined(separator: " ")).font(.hush(.caption2)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
        HushForm {
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

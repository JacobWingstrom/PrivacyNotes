import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum FeedSelection: Hashable {
    case unread, all, starred, today
    case folder(String)
    case feed(UUID)
}

/// RSS and Atom feeds, laid out like Mail.
struct FeedsView: View {
    let title: String
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: [SortDescriptor(\Feed.sortIndex), SortDescriptor(\Feed.title)]) private var feeds: [Feed]
    @State private var engine = FeedEngine.shared
    @State private var selection: FeedSelection = .unread
    @State private var selected: FeedArticle?
    @State private var adding = false
    @State private var showSources = false

    var body: some View {
        Group {
            if feeds.isEmpty {
                FeedsOnboarding { adding = true }
            } else if sizeClass == .regular {
                ThreePane {
                    FeedSidebar(selection: $selection, feeds: feeds) { adding = true }
                } list: {
                    ArticleListView(selection: selection, feedIDs: ids(for: selection), selected: $selected, compact: false)
                        .id(selection)
                } reader: {
                    if let selected, selected.modelContext != nil {
                        ArticleReaderView(article: selected).id(selected.id)
                    } else {
                        PaneEmpty(symbol: "doc.richtext", text: "No article selected")
                    }
                }
            } else {
                ArticleListView(selection: selection, feedIDs: ids(for: selection), selected: $selected, compact: true)
                    .id(selection)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showSources = true } label: { Image(systemName: "list.bullet.indent") }
                                .accessibilityLabel("Feeds")
                        }
                    }
                    .sheet(isPresented: $showSources) {
                        NavigationStack {
                            FeedSidebar(selection: Binding(get: { selection }, set: { selection = $0; showSources = false }), feeds: feeds) {
                                showSources = false
                                adding = true
                            }
                            .navigationTitle("Feeds")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSources = false } } }
                        }
                        .presentationDetents([.medium, .large])
                    }
            }
        }
        .navigationTitle(title)
        .onCreate(.feeds) { adding = true }
        .sheet(isPresented: $adding) { AddFeedView() }
        .task { await engine.refreshIfDue() }
        .onChange(of: selection) { _, _ in selected = nil }
    }

    private func ids(for s: FeedSelection) -> [UUID]? {
        switch s {
        case .folder(let f): return feeds.filter { $0.folder == f }.map(\.id)
        case .feed(let id): return [id]
        default: return nil
        }
    }
}

private struct FeedsOnboarding: View {
    let add: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 54, weight: .light)).foregroundStyle(.tint).padding(.top, 40)
                Text("Follow the sites you read").font(.hush(.title2).bold())
                Text("Add any RSS or Atom feed, or paste a website and Hush finds its feed. Hush fetches feeds straight from each site, with no tracking and no account.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button(action: add) {
                    Label("Add a Feed", systemImage: "plus").font(.hush(.headline)).frame(maxWidth: 320).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .hushBackground()
    }
}

struct FeedSidebar: View {
    @Binding var selection: FeedSelection
    let feeds: [Feed]
    var add: () -> Void
    @State private var engine = FeedEngine.shared
    @Query(filter: #Predicate<FeedArticle> { !$0.isRead }) private var unread: [FeedArticle]
    @Query(filter: #Predicate<FeedArticle> { $0.isStarred }) private var starred: [FeedArticle]
    @State private var editing: Feed?

    var body: some View {
        let unreadByFeed = Dictionary(grouping: unread, by: \.feedID).mapValues(\.count)
        let folders = Array(Set(feeds.map(\.folder).filter { !$0.isEmpty })).sorted()
        List {
            Section {
                row(.unread, "circle.inset.filled", "Unread", unread.count)
                row(.today, "sun.max", "Today", unread.filter { Calendar.current.isDateInToday($0.published) }.count)
                row(.all, "tray.full", "All Articles", 0)
                row(.starred, "star", "Starred", starred.count)
            }
            ForEach(folders, id: \.self) { folder in
                Section {
                    row(.folder(folder), "folder", "All in \(folder)", feeds.filter { $0.folder == folder }.reduce(0) { $0 + (unreadByFeed[$1.id] ?? 0) })
                    ForEach(feeds.filter { $0.folder == folder }) { f in feedRow(f, unreadByFeed[f.id] ?? 0) }
                } header: { ListHeader(title: folder) }
            }
            let loose = feeds.filter { $0.folder.isEmpty }
            if !loose.isEmpty {
                Section {
                    ForEach(loose) { f in feedRow(f, unreadByFeed[f.id] ?? 0) }
                } header: { ListHeader(title: "Feeds") }
            }
            Section {
                Button(action: add) { Label("Add Feed", systemImage: "plus") }.font(.hush(.subheadline))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .refreshable { await engine.refreshAll() }
        .sheet(item: $editing) { f in EditFeedView(feed: f) }
    }

    private func row(_ s: FeedSelection, _ symbol: String, _ title: String, _ count: Int) -> some View {
        Button { selection = s } label: { PaneRow(symbol: symbol, title: title, count: count, selected: selection == s) }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func feedRow(_ f: Feed, _ count: Int) -> some View {
        row(.feed(f.id), f.isReddit ? "bubble.left.and.text.bubble.right" : (f.errorText.isEmpty ? "dot.radiowaves.up.forward" : "exclamationmark.triangle"), f.displayTitle, count)
            .contextMenu {
                Button { editing = f } label: { Label("Edit", systemImage: "pencil") }
                Button { Task { await engine.refresh(f.id) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button(role: .destructive) { engine.remove(f) } label: { Label("Unsubscribe", systemImage: "trash") }
            }
    }
}

struct ArticleListView: View {
    let selection: FeedSelection
    @Binding var selected: FeedArticle?
    let compact: Bool
    @Query private var articles: [FeedArticle]
    @Query private var feeds: [Feed]
    @State private var engine = FeedEngine.shared
    @State private var search = ""

    init(selection: FeedSelection, feedIDs: [UUID]?, selected: Binding<FeedArticle?>, compact: Bool) {
        self.selection = selection
        _selected = selected
        self.compact = compact
        let sort = [SortDescriptor(\FeedArticle.published, order: .reverse)]
        switch selection {
        case .unread: _articles = Query(filter: #Predicate<FeedArticle> { !$0.isRead }, sort: sort)
        case .starred: _articles = Query(filter: #Predicate<FeedArticle> { $0.isStarred }, sort: sort)
        case .today:
            let start = Calendar.current.startOfDay(for: .now)
            _articles = Query(filter: #Predicate<FeedArticle> { $0.published >= start }, sort: sort)
        case .all: _articles = Query(sort: sort)
        case .folder, .feed:
            let ids = feedIDs ?? []
            _articles = Query(filter: #Predicate<FeedArticle> { ids.contains($0.feedID) }, sort: sort)
        }
    }

    private var title: String {
        switch selection {
        case .unread: "Unread"
        case .all: "All Articles"
        case .starred: "Starred"
        case .today: "Today"
        case .folder(let f): f
        case .feed(let id): feeds.first { $0.id == id }?.displayTitle ?? "Feed"
        }
    }

    var body: some View {
        let names = Dictionary(feeds.map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { a, _ in a })
        let shown = search.isEmpty ? Array(articles.prefix(500)) : articles.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search)
        }
        List {
            HStack {
                Text(title).font(.hush(.title3).bold())
                Spacer()
                if engine.refreshing { ProgressView().controlSize(.small) }
                Menu {
                    Button { engine.markRead(shown) } label: { Label("Mark All as Read", systemImage: "checkmark.circle") }
                    Button { Task { await engine.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                } label: { Image(systemName: "ellipsis.circle").font(.hush(.title3)) }
            }
            .plainRow(top: 6, bottom: 2)
            if case .feed(let id) = selection, let f = feeds.first(where: { $0.id == id }), !f.errorText.isEmpty {
                Label(f.errorText, systemImage: "exclamationmark.triangle").font(.hush(.footnote)).foregroundStyle(.orange).plainRow(top: 0, bottom: 6)
            }
            ForEach(shown) { a in
                Group {
                    if compact {
                        NavigationLink { ArticleReaderView(article: a) } label: { ArticleRow(article: a, feedName: names[a.feedID] ?? "") }
                    } else {
                        Button { selected = a } label: { ArticleRow(article: a, feedName: names[a.feedID] ?? "").contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .listRowBackground(selected?.id == a.id ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { engine.markRead([a], !a.isRead) } label: { Label(a.isRead ? "Unread" : "Read", systemImage: a.isRead ? "circle" : "checkmark.circle") }
                        .tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    Button { a.isStarred.toggle() } label: { Label(a.isStarred ? "Unstar" : "Star", systemImage: a.isStarred ? "star.slash" : "star") }
                        .tint(.yellow)
                }
            }
            if shown.isEmpty {
                EmptyMessage(text: selection == .unread ? "All caught up." : "No articles.")
            }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search articles…") }
        .refreshable { await engine.refreshAll() }
    }
}

struct ArticleRow: View {
    let article: FeedArticle
    let feedName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(article.isRead ? Color.clear : Color.accentColor).frame(width: 8, height: 8).padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(.hush(.body).weight(article.isRead ? .regular : .semibold))
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(feedName).lineLimit(1)
                    if !article.author.isEmpty { Text("· \(article.author)").lineLimit(1) }
                    Spacer(minLength: 4)
                    if article.isStarred { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                    if !article.savedHTML.isEmpty { Image(systemName: "arrow.down.circle") }
                    Text(MessageRow.when(article.published)).monospacedDigit()
                }
                .font(.hush(.caption))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ArticleReaderView: View {
    let article: FeedArticle
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Query private var feeds: [Feed]
    @State private var engine = FeedEngine.shared
    @State private var link: URL?
    @State private var loadImages = false
    @State private var saving = false
    @State private var error: String?

    private var feed: Feed? { feeds.first { $0.id == article.feedID } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title).font(.hush(.title3).bold()).textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(feed?.displayTitle ?? "")
                    if !article.author.isEmpty { Text("· \(article.author)") }
                    Spacer()
                    Text(article.published.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.hush(.caption)).foregroundStyle(.secondary)
                HStack(spacing: 22) {
                    Button { article.isStarred.toggle() } label: { Image(systemName: article.isStarred ? "star.fill" : "star") }
                        .accessibilityLabel(article.isStarred ? "Unstar" : "Star")
                    if !article.link.isEmpty {
                        Button { Task { await save() } } label: {
                            if saving { ProgressView() } else { Image(systemName: article.savedHTML.isEmpty ? "doc.text.magnifyingglass" : "arrow.down.circle.fill") }
                        }
                        .accessibilityLabel(article.savedHTML.isEmpty ? "Reader view, save offline" : "Saved for offline")
                        if let url = URL(string: article.link) {
                            Button { link = url } label: { Image(systemName: "safari") }.accessibilityLabel("Open in browser")
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                    Button { saveBookmark() } label: { Image(systemName: "bookmark") }.accessibilityLabel("Save as bookmark")
                    Spacer()
                    Button { engine.markRead([article], false) } label: { Image(systemName: "circle") }.accessibilityLabel("Mark unread")
                }
                .font(.hush(.title3))
                .foregroundStyle(.tint)
                .padding(.top, 4)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Rectangle().fill(palette.border).frame(height: 1)
            let remote = SafeHTMLView.remoteContentCount(article.bodyHTML)
            if remote > 0 && !(loadImages || feed?.loadImages == true) {
                HStack {
                    Image(systemName: "eye.slash").foregroundStyle(.secondary)
                    Text("\(remote) image\(remote == 1 ? "" : "s") not loaded").font(.hush(.footnote))
                    Spacer()
                    Button("Load") { loadImages = true }.font(.hush(.footnote).weight(.semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(palette.surface)
            }
            SafeHTMLView(html: article.bodyHTML.isEmpty ? "<p><em>No text in this feed item. Open it in the browser or tap the reader button.</em></p>" : article.bodyHTML,
                         allowRemote: loadImages || feed?.loadImages == true, themed: true,
                         textHex: (palette.text ?? (palette.isDark ? .white : .black)).hexString,
                         backgroundHex: palette.background.hexString, accentHex: settings.accentHex) { url in link = url }
        }
        .background(palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .confirmLinks($link)
        .onAppear { if !article.isRead { engine.markRead([article]) } }
        .alert("Reader View", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func save() async {
        guard article.savedHTML.isEmpty else { return }
        saving = true
        defer { saving = false }
        do { try await engine.saveForOffline(article) } catch { self.error = error.localizedDescription }
    }

    private func saveBookmark() {
        let ctx = Storage.shared.mainContext
        let b = Bookmark()
        b.title = article.title
        b.urlString = article.link
        b.tags = [feed?.isReddit == true ? "reddit" : "feeds"]
        ctx.insert(b)
        try? ctx.save()
    }
}

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var feeds: [Feed]
    @State private var url = ""
    @State private var folder = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            HushForm {
                Section {
                    TextField("Website or feed address", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Folder (optional)", text: $folder)
                    let folders = Array(Set(feeds.map(\.folder).filter { !$0.isEmpty })).sorted()
                    if !folders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(folders, id: \.self) { f in TagChip(text: f, selected: folder == f) { folder = f } } }
                        }
                    }
                } footer: {
                    Text("Paste a website and Hush will look for its feed.")
                }
                Section {
                    Label("Reddit turned off its RSS feeds on November 13, 2026, so subreddits can't be added here anymore. YouTube channels, blogs, news sites, GitHub releases, Mastodon accounts and podcasts still work.", systemImage: "info.circle")
                } header: {
                    Text("Reddit")
                }
                .font(.hush(.footnote))
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Add") { Task { await add() } }.disabled(url.trimmed.isEmpty)
                    }
                }
            }
            .alert("Couldn't add feed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
    }

    private func add() async {
        working = true
        defer { working = false }
        do {
            try await FeedEngine.shared.add(url, folder: folder)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EditFeedView: View {
    @Bindable var feed: Feed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HushForm {
                Section {
                    TextField("Title", text: $feed.title)
                    TextField("Folder", text: $feed.folder)
                    Toggle("Always Load Images", isOn: $feed.loadImages)
                } footer: {
                    Text("Images are fetched from the site (and can be used to track that you opened the article). Off by default.")
                }
                Section {
                    LabeledContent("Address", value: feed.urlString).font(.hush(.footnote))
                    if let d = feed.lastFetched { LabeledContent("Updated", value: d.formatted(.relative(presentation: .named))) }
                    if !feed.errorText.isEmpty { Text(feed.errorText).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { try? Storage.shared.mainContext.save(); dismiss() } } }
        }
    }
}

struct FeedSettingsView: View {
    @Query(sort: [SortDescriptor(\Feed.sortIndex), SortDescriptor(\Feed.title)]) private var feeds: [Feed]
    @State private var importing = false
    @State private var message: String?
    @State private var exportURL: URL?

    var body: some View {
        HushForm {
            Section {
                ForEach(feeds) { f in
                    NavigationLink { EditFeedView(feed: f) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.displayTitle)
                            Text(f.folder.isEmpty ? f.urlString : "\(f.folder) · \(f.urlString)").font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { idx in for i in idx { FeedEngine.shared.remove(feeds[i]) } }
                .onMove { from, to in
                    var list = feeds
                    list.move(fromOffsets: from, toOffset: to)
                    for (i, f) in list.enumerated() { f.sortIndex = i }
                }
            } header: {
                Text("Feeds")
            }
            Section {
                Button { importing = true } label: { Label("Import OPML…", systemImage: "square.and.arrow.down") }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Export OPML", systemImage: "square.and.arrow.up") }
                }
            } footer: {
                Text("Move your subscriptions from another reader (Feedly, NetNewsWire, Inoreader…) with an OPML file.")
            }
        }
        .navigationTitle("Feeds")
        .onAppear {
            exportURL = TempFiles.write(FeedEngine.shared.exportOPML(), name: "Hush Feeds.opml")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "opml") ?? .xml, .xml], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            Task {
                let n = await FeedEngine.shared.importOPML(data)
                message = "Added \(n) feeds."
            }
        }
        .alert("Import", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }
}

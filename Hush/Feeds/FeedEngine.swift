import Foundation
import SwiftData
import WidgetKit

/// Fetches feeds straight from the sites you follow (no feed service in between).
@MainActor
@Observable
final class FeedEngine {
    static let shared = FeedEngine()

    private(set) var refreshing = false
    private(set) var lastRefresh: Date?
    var errors: [UUID: String] = [:]

    private var context: ModelContext { Storage.shared.mainContext }

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.httpCookieStorage = nil
        c.httpAdditionalHeaders = ["User-Agent": "Hush/2.6 (iOS; feed reader)", "Accept": "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5"]
        return URLSession(configuration: c)
    }()

    var feeds: [Feed] { (try? context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.title)]))) ?? [] }
    var hasFeeds: Bool { ((try? context.fetchCount(FetchDescriptor<Feed>())) ?? 0) > 0 }

    // MARK: Adding

    static let redditGone = "Reddit turned off its RSS feeds on November 13, 2026, so subreddits can't be followed as feeds anymore. If you run an RSS bridge (such as RSS-Bridge) that still reaches Reddit, add its feed address instead."

    /// "r/swift" or "reddit.com/r/swift" → its RSS feed (in case Reddit brings them back).
    static func normalize(_ input: String) -> String {
        var s = input.trimmed
        if s.lowercased().hasPrefix("feed://") { s = "https://" + s.dropFirst(7) }
        if s.range(of: "^/?r/[A-Za-z0-9_+]+/?$", options: .regularExpression) != nil {
            let name = s.split(separator: "/").last.map(String.init) ?? s
            return "https://www.reddit.com/r/\(name)/.rss"
        }
        if !s.contains("://") { s = "https://" + s }
        if let u = URL(string: s), let host = u.host()?.lowercased(), host.hasSuffix("reddit.com") {
            // Private front-page links (with feed= and user=) are used as-is.
            if u.query?.contains("feed=") == true { return s }
            if u.path.hasPrefix("/r/") || u.path.hasPrefix("/user/") || u.path.hasPrefix("/u/") {
                var path = u.path
                if !path.hasSuffix(".rss") { path = (path.hasSuffix("/") ? path : path + "/") + ".rss" }
                return "https://www.reddit.com" + path
            }
        }
        return s
    }

    @discardableResult
    func add(_ input: String, folder: String) async throws -> Feed {
        var url = Self.normalize(input)
        guard var u = URL(string: url), u.scheme == "https" || u.scheme == "http" else { throw MailError.server("That doesn't look like a web address.") }
        if let existing = feeds.first(where: { $0.urlString == url }) { return existing }
        let first = try await fetch(u, etag: "", modified: "").0
        var parsed: ParsedFeed? = first.flatMap { FeedParser.parse($0) }
        if parsed == nil, let page = first, let html = String(data: page, encoding: .utf8), let found = FeedParser.discover(inHTML: html, base: u) {
            u = found
            url = found.absoluteString
            let second = try await fetch(u, etag: "", modified: "").0
            parsed = second.flatMap { FeedParser.parse($0) }
        }
        guard let parsed else { throw MailError.server("No RSS or Atom feed was found at that address.") }
        let feed = Feed(url: url)
        feed.title = parsed.title
        feed.siteURL = parsed.siteURL
        feed.folder = folder.trimmed
        feed.kindRaw = (u.host() ?? "").contains("reddit.com") ? "reddit" : "rss"
        feed.sortIndex = (feeds.map(\.sortIndex).max() ?? 0) + 1
        context.insert(feed)
        store(parsed, in: feed)
        feed.lastFetched = Date()
        try? context.save()
        return feed
    }

    func remove(_ feed: Feed) {
        let id = feed.id
        for a in (try? context.fetch(FetchDescriptor<FeedArticle>(predicate: #Predicate { $0.feedID == id }))) ?? [] { context.delete(a) }
        context.delete(feed)
        try? context.save()
    }

    // MARK: Refreshing

    func refreshAll() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await withTaskGroup(of: Void.self) { group in
            for f in feeds {
                let id = f.id
                group.addTask { await self.refresh(id) }
            }
        }
        prune()
        lastRefresh = Date()
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshIfDue() async {
        if Date().timeIntervalSince(lastRefresh ?? .distantPast) > 1800 { await refreshAll() }
    }

    func refresh(_ id: UUID) async {
        guard let feed = (try? context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.id == id })))?.first,
              let url = URL(string: feed.urlString) else { return }
        do {
            let (data, response) = try await fetch(url, etag: feed.etag, modified: feed.lastModified)
            if let response {
                feed.etag = response.value(forHTTPHeaderField: "ETag") ?? ""
                feed.lastModified = response.value(forHTTPHeaderField: "Last-Modified") ?? ""
            }
            if let data {
                guard let parsed = FeedParser.parse(data) else { throw MailError.server("The feed couldn't be read.") }
                if feed.title.isEmpty { feed.title = parsed.title }
                store(parsed, in: feed)
            }
            feed.lastFetched = Date()
            feed.errorText = ""
            errors[id] = nil
        } catch {
            feed.errorText = error.localizedDescription
            errors[id] = error.localizedDescription
        }
    }

    /// nil data means "not modified".
    private func fetch(_ url: URL, etag: String, modified: String) async throws -> (Data?, HTTPURLResponse?) {
        var req = URLRequest(url: url)
        if !etag.isEmpty { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if !modified.isEmpty { req.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await session.data(for: req)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304 { return (nil, http) }
        if let code = http?.statusCode, !(200..<300).contains(code), (url.host() ?? "").lowercased().hasSuffix("reddit.com") {
            throw MailError.server(Self.redditGone)
        }
        if let code = http?.statusCode, !(200..<300).contains(code) {
            throw MailError.server(code == 429 ? "The site asked Hush to slow down. It will try again later." : "The site answered \(code).")
        }
        return (data, http)
    }

    private func store(_ parsed: ParsedFeed, in feed: Feed) {
        let id = feed.id
        let existing = (try? context.fetch(FetchDescriptor<FeedArticle>(predicate: #Predicate { $0.feedID == id }))) ?? []
        var byGuid: [String: FeedArticle] = [:]
        for a in existing { byGuid[a.guid] = a }
        let base = URL(string: feed.siteURL.isEmpty ? feed.urlString : feed.siteURL)
        for item in parsed.items.prefix(200) {
            let a: FeedArticle
            if let found = byGuid[item.guid] { a = found } else {
                a = FeedArticle(feedID: id, guid: item.guid)
                a.published = item.published ?? Date()
                context.insert(a)
                byGuid[item.guid] = a
            }
            a.title = item.title.isEmpty ? "Untitled" : item.title
            if let base, let resolved = URL(string: item.link, relativeTo: base)?.absoluteString { a.link = resolved } else { a.link = item.link }
            a.author = item.author
            if let p = item.published { a.published = p }
            a.summaryHTML = item.summary
            a.contentHTML = item.content
            a.imageURL = item.imageURL
        }
    }

    /// Keeps the newest 300 per feed and drops read, unstarred articles older than 60 days.
    func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .distantPast
        for f in feeds {
            let id = f.id
            let all = ((try? context.fetch(FetchDescriptor<FeedArticle>(predicate: #Predicate { $0.feedID == id }))) ?? []).sorted { $0.published > $1.published }
            for (i, a) in all.enumerated() where !a.isStarred && (i >= 300 || (a.isRead && a.published < cutoff)) { context.delete(a) }
        }
    }

    // MARK: Articles

    func markRead(_ articles: [FeedArticle], _ read: Bool = true) {
        for a in articles where a.isRead != read { a.isRead = read }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Downloads the full article page and keeps a clean copy for offline reading.
    func saveForOffline(_ a: FeedArticle) async throws {
        guard let url = URL(string: a.link) else { throw MailError.server("This article has no link.") }
        var req = URLRequest(url: url)
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw MailError.server("The site answered \(http.statusCode).") }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let clean = Readability.extract(html, base: (response as? HTTPURLResponse)?.url ?? url)
        guard clean.count > 200 else { throw MailError.server("Hush couldn't find the article text on that page.") }
        a.savedHTML = clean
        try? context.save()
    }

    // MARK: OPML

    func importOPML(_ data: Data) async -> Int {
        let outlines = OPML.parse(data)
        var added = 0
        let known = Set(feeds.map(\.urlString))
        for o in outlines where !known.contains(o.url) {
            let f = Feed(url: o.url)
            f.title = o.title
            f.folder = o.folder
            f.kindRaw = o.url.contains("reddit.com") ? "reddit" : "rss"
            f.sortIndex = added
            context.insert(f)
            added += 1
        }
        try? context.save()
        await refreshAll()
        return added
    }

    func exportOPML() -> Data {
        OPML.render(feeds.map { OPML.Outline(title: $0.displayTitle, url: $0.urlString, folder: $0.folder) })
    }
}

enum OPML {
    struct Outline { var title: String; var url: String; var folder: String }

    static func parse(_ data: Data) -> [Outline] {
        final class Delegate: NSObject, XMLParserDelegate {
            var out: [Outline] = []
            var folders: [String?] = []
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
                guard name.lowercased() == "outline" else { return }
                let title = attributes["title"] ?? attributes["text"] ?? ""
                if let url = attributes["xmlUrl"] ?? attributes["xmlurl"] {
                    out.append(Outline(title: title, url: url, folder: folders.compactMap { $0 }.last ?? ""))
                    folders.append(nil)
                } else {
                    folders.append(title)
                }
            }
            func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
                if name.lowercased() == "outline", !folders.isEmpty { folders.removeLast() }
            }
        }
        let p = XMLParser(data: data)
        let d = Delegate()
        p.delegate = d
        p.parse()
        return d.out
    }

    static func render(_ outlines: [Outline]) -> Data {
        func esc(_ s: String) -> String { MIME.escapeHTML(s) }
        var body = ""
        let grouped = Dictionary(grouping: outlines, by: \.folder)
        for folder in grouped.keys.sorted() {
            let items = grouped[folder] ?? []
            let lines = items.map { "<outline type=\"rss\" text=\"\(esc($0.title))\" title=\"\(esc($0.title))\" xmlUrl=\"\(esc($0.url))\"/>" }
            if folder.isEmpty {
                body += lines.map { "    " + $0 }.joined(separator: "\n") + "\n"
            } else {
                body += "    <outline text=\"\(esc(folder))\" title=\"\(esc(folder))\">\n" + lines.map { "      " + $0 }.joined(separator: "\n") + "\n    </outline>\n"
            }
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Hush feeds</title></head>
          <body>
        \(body)  </body>
        </opml>
        """
        return Data(xml.utf8)
    }
}

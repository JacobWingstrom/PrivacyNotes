import Foundation

/// A subreddit (or several joined with "+") followed like a feed: "reddit:selfhosted+homelab?sort=top&t=week".
struct RedditFeedSpec: Equatable {
    static let sorts = ["hot", "new", "top", "rising"]
    static let periods = ["hour", "day", "week", "month", "year", "all"]

    var subreddit: String
    var sort = "hot"
    var period = "day"

    init(subreddit: String, sort: String = "hot", period: String = "day") {
        self.subreddit = subreddit
        self.sort = Self.sorts.contains(sort) ? sort : "hot"
        self.period = Self.periods.contains(period) ? period : "day"
    }

    init?(_ stored: String) {
        guard stored.hasPrefix("reddit:") else { return nil }
        let rest = String(stored.dropFirst(7))
        let parts = rest.split(separator: "?", maxSplits: 1).map(String.init)
        guard let sub = parts.first, !sub.isEmpty else { return nil }
        var sort = "hot", period = "day"
        if parts.count > 1 {
            for kv in parts[1].split(separator: "&") {
                let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
                guard p.count == 2 else { continue }
                if p[0] == "sort" { sort = p[1] }
                if p[0] == "t" { period = p[1] }
            }
        }
        self.init(subreddit: sub, sort: sort, period: period)
    }

    var stored: String { "reddit:\(subreddit)?sort=\(sort)" + (sort == "top" ? "&t=\(period)" : "") }
    var title: String { "r/" + subreddit.replacingOccurrences(of: "+", with: " + r/") }
    var siteURL: String { "https://www.reddit.com/r/\(subreddit)/" }

    /// Accepts "r/name", "r/a+b", "reddit.com/r/name/top", old .rss links and pasted subreddit URLs.
    static func parse(_ input: String) -> RedditFeedSpec? {
        var s = input.trimmed
        if let spec = RedditFeedSpec(s) { return spec }
        if s.range(of: "^/?r/[A-Za-z0-9_+]+/?$", options: .regularExpression) != nil {
            return RedditFeedSpec(subreddit: s.split(separator: "/").last.map(String.init) ?? s)
        }
        if !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s), let host = u.host()?.lowercased(), host.hasSuffix("reddit.com") else { return nil }
        let parts = u.path.split(separator: "/").map(String.init).filter { $0 != ".rss" }
        guard parts.count >= 2, parts[0] == "r" else { return nil }
        let sub = parts[1].replacingOccurrences(of: ".rss", with: "").replacingOccurrences(of: ".json", with: "")
        let sort = parts.count >= 3 ? parts[2].replacingOccurrences(of: ".json", with: "") : "hot"
        let period = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "t" }?.value ?? "day"
        return RedditFeedSpec(subreddit: sub, sort: sort, period: period)
    }
}

struct RedditComment: Identifiable {
    let id: String
    let author: String
    let score: Int
    let html: String
    let date: Date
    let replies: [RedditComment]
}

/// Reads subreddits the way Glance/Dynacat do: Reddit's JSON listings, optionally signed in with your own
/// Reddit app (client ID + secret), or sent through a proxy / front end of your choice.
enum RedditSource {
    // Settings
    static let clientIDKey = "reddit.clientID"
    static let templateKey = "reddit.requestTemplate"
    static let commentsHostKey = "reddit.commentsHost"
    static let nsfwKey = "reddit.showNSFW"
    static let stickiedKey = "reddit.showStickied"

    static var clientID: String { UserDefaults.standard.string(forKey: clientIDKey)?.trimmed ?? "" }
    static var template: String { UserDefaults.standard.string(forKey: templateKey)?.trimmed ?? "" }
    static var commentsHost: String { UserDefaults.standard.string(forKey: commentsHostKey) ?? "www.reddit.com" }
    static var showNSFW: Bool { UserDefaults.standard.bool(forKey: nsfwKey) }
    static var showStickied: Bool { UserDefaults.standard.bool(forKey: stickiedKey) }
    static var secret: String {
        get { Keychain.load("reddit.secret").map { String(decoding: $0, as: UTF8.self) } ?? "" }
        set { if newValue.isEmpty { Keychain.delete("reddit.secret") } else { Keychain.save(Data(newValue.utf8), for: "reddit.secret") } }
    }
    static var usesApp: Bool { !clientID.isEmpty && !secret.isEmpty && template.isEmpty }

    /// Reddit asks API clients to identify themselves this way.
    private static let userAgent = "ios:com.jacobwingstrom.hush:v2.6 (personal feed reader)"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "application/json"]
        return URLSession(configuration: c)
    }()

    private static var token: (value: String, expires: Date)?

    // MARK: Requests

    /// GET a path like "/r/selfhosted/hot" with query items; picks app login, template or the public JSON.
    private static func get(_ path: String, query: [String: String]) async throws -> Any {
        var q = query
        q["raw_json"] = "1"
        let queryString = q.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        let publicURL = "https://www.reddit.com\(path).json?\(queryString)"
        var req: URLRequest
        if !template.isEmpty {
            let filled = template.replacingOccurrences(of: "{REQUEST-URL}", with: template.contains("?") ? (publicURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? publicURL) : publicURL)
                .replacingOccurrences(of: "{PATH}", with: path)
            guard let u = URL(string: filled) else { throw MailError.server("The Reddit request template isn't a valid address.") }
            req = URLRequest(url: u)
        } else if usesApp {
            guard let u = URL(string: "https://oauth.reddit.com\(path)?\(queryString)") else { throw MailError.server("Bad subreddit name.") }
            req = URLRequest(url: u)
            req.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        } else {
            guard let u = URL(string: publicURL) else { throw MailError.server("Bad subreddit name.") }
            req = URLRequest(url: u)
        }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: break
        case 401 where usesApp:
            token = nil
            throw MailError.server("Reddit didn't accept your app's client ID and secret.")
        case 403:
            throw MailError.server(usesApp
                ? "Reddit refused the request (403). The subreddit may be private or banned."
                : "Reddit blocked the request (403). Add your Reddit app's client ID and secret, or a request template, in Settings → Mail, Calendars & Feeds → Feeds.")
        case 404:
            throw MailError.server("Reddit says this subreddit doesn't exist (404), or it no longer answers this kind of request.")
        case 429:
            throw MailError.server("Reddit asked Hush to slow down. It will try again later.")
        default:
            throw MailError.server("Reddit answered \(code).")
        }
        guard let j = try? JSONSerialization.jsonObject(with: data) else {
            throw MailError.server("Reddit sent a page instead of data. If you use a request template, check that it returns Reddit's JSON.")
        }
        return j
    }

    /// App-only OAuth token ("client credentials"), as Glance's app-auth does.
    private static func accessToken() async throws -> String {
        if let t = token, t.expires > Date().addingTimeInterval(60) { return t.value }
        var req = URLRequest(url: URL(string: "https://www.reddit.com/api/v1/access_token")!)
        req.httpMethod = "POST"
        req.setValue("Basic " + Data("\(clientID):\(secret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("grant_type=client_credentials".utf8)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let value = j["access_token"] as? String else {
            throw MailError.server("Reddit didn't accept your app's client ID and secret.")
        }
        let seconds = (j["expires_in"] as? Double) ?? 3600
        token = (value, Date().addingTimeInterval(seconds))
        return value
    }

    // MARK: Posts

    static func fetch(_ spec: RedditFeedSpec, limit: Int = 50) async throws -> ParsedFeed {
        var q = ["limit": String(limit)]
        if spec.sort == "top" { q["t"] = spec.period }
        let j = try await get("/r/\(spec.subreddit)/\(spec.sort)", query: q)
        let children = ((j as? [String: Any])?["data"] as? [String: Any])?["children"] as? [[String: Any]] ?? []
        var feed = ParsedFeed(title: spec.title, siteURL: spec.siteURL, items: [])
        for child in children {
            guard let d = child["data"] as? [String: Any] else { continue }
            if (d["stickied"] as? Bool ?? false) && !showStickied { continue }
            let nsfw = d["over_18"] as? Bool ?? false
            if nsfw && !showNSFW { continue }
            feed.items.append(article(d, nsfw: nsfw))
        }
        return feed
    }

    static func commentsURL(permalink: String) -> String {
        "https://\(commentsHost)\(permalink)"
    }

    private static func article(_ d: [String: Any], nsfw: Bool) -> ParsedArticle {
        let id = d["name"] as? String ?? (d["id"] as? String ?? UUID().uuidString)
        let permalink = d["permalink"] as? String ?? ""
        let link = d["url"] as? String ?? ""
        let isSelf = d["is_self"] as? Bool ?? false
        let score = (d["score"] as? Int) ?? Int((d["score"] as? Double) ?? 0)
        let comments = (d["num_comments"] as? Int) ?? 0
        let author = d["author"] as? String ?? ""
        let sub = d["subreddit"] as? String ?? ""
        let flair = (d["link_flair_text"] as? String)?.trimmed ?? ""
        let domain = d["domain"] as? String ?? ""

        var image = ""
        if !nsfw {
            if let src = ((((d["preview"] as? [String: Any])?["images"] as? [[String: Any]])?.first)?["source"] as? [String: Any])?["url"] as? String {
                image = src
            } else if let thumb = d["thumbnail"] as? String, thumb.hasPrefix("http") {
                image = thumb
            } else if let meta = d["media_metadata"] as? [String: Any], let first = meta.values.first as? [String: Any],
                      let s = (first["s"] as? [String: Any])?["u"] as? String {
                image = s
            }
        }

        var html = "<p style=\"opacity:.7;font-size:.9em\">"
        if !flair.isEmpty { html += "<b>\(MIME.escapeHTML(flair))</b> · " }
        html += "▲ \(score) · \(comments) comments · r/\(MIME.escapeHTML(sub)) · u/\(MIME.escapeHTML(author))"
        if !isSelf && !domain.isEmpty { html += " · \(MIME.escapeHTML(domain))" }
        if nsfw { html += " · <b>NSFW</b>" }
        html += "</p>"
        if let body = d["selftext_html"] as? String, !body.isEmpty { html += body }
        if !image.isEmpty { html += "<p><img src=\"\(MIME.escapeHTML(image))\" alt=\"\"></p>" }
        if (d["is_video"] as? Bool) == true { html += "<p>▶︎ Video: open the post on Reddit to play it.</p>" }
        if !isSelf && !link.isEmpty && !link.contains(permalink) {
            html += "<p><a href=\"\(MIME.escapeHTML(link))\">\(MIME.escapeHTML(link))</a></p>"
        }
        let created = (d["created_utc"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return ParsedArticle(guid: id, title: d["title"] as? String ?? "Untitled", link: commentsURL(permalink: permalink),
                             author: "u/" + author, published: created, summary: "", content: html, imageURL: image)
    }

    // MARK: Comments

    /// Top comments with one level of replies.
    static func comments(permalink: String, limit: Int = 30) async throws -> [RedditComment] {
        var path = permalink
        while path.hasSuffix("/") { path.removeLast() }
        let j = try await get(path, query: ["limit": String(limit), "depth": "2", "sort": "top"])
        guard let arr = j as? [Any], arr.count > 1 else { return [] }
        return parse(listing: arr[1])
    }

    private static func parse(listing: Any) -> [RedditComment] {
        let children = ((listing as? [String: Any])?["data"] as? [String: Any])?["children"] as? [[String: Any]] ?? []
        return children.compactMap { c in
            guard (c["kind"] as? String) == "t1", let d = c["data"] as? [String: Any] else { return nil }
            let replies = (d["replies"] as? [String: Any]).map { parse(listing: $0) } ?? []
            return RedditComment(id: d["id"] as? String ?? UUID().uuidString, author: d["author"] as? String ?? "",
                                 score: (d["score"] as? Int) ?? 0, html: d["body_html"] as? String ?? MIME.escapeHTML(d["body"] as? String ?? ""),
                                 date: Date(timeIntervalSince1970: (d["created_utc"] as? Double) ?? 0), replies: replies)
        }
    }

    static func commentsHTML(_ list: [RedditComment]) -> String {
        guard !list.isEmpty else { return "<hr><p><em>No comments yet.</em></p>" }
        func render(_ c: RedditComment, depth: Int) -> String {
            var s = "<div style=\"margin:10px 0;\"><p style=\"opacity:.65;font-size:.85em;margin:0\">u/\(MIME.escapeHTML(c.author)) · ▲ \(c.score) · \(c.date.formatted(.relative(presentation: .numeric)))</p>\(c.html)"
            if depth < 2 {
                for r in c.replies.prefix(3) { s += "<blockquote>" + render(r, depth: depth + 1) + "</blockquote>" }
            }
            return s + "</div>"
        }
        return "<hr><h3>Top comments</h3>" + list.map { render($0, depth: 1) }.joined()
    }
}

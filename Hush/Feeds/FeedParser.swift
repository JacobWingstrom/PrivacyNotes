import Foundation

struct ParsedFeed {
    var title = ""
    var siteURL = ""
    var items: [ParsedArticle] = []
}

struct ParsedArticle {
    var guid = ""
    var title = ""
    var link = ""
    var author = ""
    var published: Date?
    var summary = ""
    var content = ""
    var imageURL = ""
}

/// Reads RSS 2.0, RSS 1.0 (RDF) and Atom (Reddit's .rss feeds are Atom).
final class FeedParser: NSObject, XMLParserDelegate {
    private var feed = ParsedFeed()
    private var item: ParsedArticle?
    private var stack: [String] = []
    private var text = ""
    private var isAtom = false
    private var authorDepth = false

    static func parse(_ data: Data) -> ParsedFeed? {
        let p = XMLParser(data: data)
        p.shouldProcessNamespaces = false
        p.shouldResolveExternalEntities = false
        let d = FeedParser()
        p.delegate = d
        guard p.parse() || !d.feed.items.isEmpty else { return nil }
        if d.feed.title.isEmpty && d.feed.items.isEmpty && !d.sawFeed { return nil }
        return d.feed
    }

    private var sawFeed = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let n = name.lowercased()
        stack.append(n)
        text = ""
        switch n {
        case "rss", "rdf:rdf", "channel": sawFeed = true
        case "feed": sawFeed = true; isAtom = true
        case "item", "entry": item = ParsedArticle()
        case "author": authorDepth = true
        case "link":
            let href = attributes["href"] ?? ""
            let rel = attributes["rel"] ?? "alternate"
            if !href.isEmpty {
                if item != nil {
                    if rel == "alternate" && (item?.link.isEmpty ?? true) { item?.link = href }
                    if rel == "enclosure", (attributes["type"] ?? "").hasPrefix("image/"), item?.imageURL.isEmpty ?? false { item?.imageURL = href }
                } else if rel == "alternate" && feed.siteURL.isEmpty {
                    feed.siteURL = href
                }
            }
        case "media:thumbnail", "media:content":
            if let url = attributes["url"], item != nil, item?.imageURL.isEmpty ?? false,
               n == "media:thumbnail" || (attributes["medium"] == "image" || (attributes["type"] ?? "").hasPrefix("image/")) {
                item?.imageURL = url
            }
        case "enclosure":
            if let url = attributes["url"], (attributes["type"] ?? "").hasPrefix("image/"), item != nil, item?.imageURL.isEmpty ?? false {
                item?.imageURL = url
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let n = name.lowercased()
        defer { if !stack.isEmpty { stack.removeLast() } }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if n == "author" { authorDepth = false }
        if var it = item {
            switch n {
            case "title": if it.title.isEmpty { it.title = MIME.decodeEntities(MIME.htmlToText(value)) }
            case "link": if it.link.isEmpty && !value.isEmpty { it.link = value }
            case "guid", "id": if it.guid.isEmpty { it.guid = value }
            case "pubdate", "published", "dc:date", "updated", "issued":
                if it.published == nil || n == "published" || n == "pubdate" { it.published = Self.date(value) ?? it.published }
            case "dc:creator", "name": if it.author.isEmpty && (n == "dc:creator" || authorDepth) { it.author = value }
            case "author": if it.author.isEmpty && !value.contains("\n") && !isAtom { it.author = value }
            case "description", "summary": if it.summary.isEmpty { it.summary = value }
            case "content:encoded", "content": if it.content.isEmpty { it.content = value }
            case "item", "entry":
                if it.guid.isEmpty { it.guid = it.link.isEmpty ? it.title : it.link }
                if it.imageURL.isEmpty { it.imageURL = Self.firstImage(it.content.isEmpty ? it.summary : it.content) }
                feed.items.append(it)
                item = nil
                text = ""
                return
            default: break
            }
            item = it
        } else {
            let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
            if n == "title" && feed.title.isEmpty && (parent == "channel" || parent == "feed") { feed.title = MIME.decodeEntities(value) }
            if n == "link" && feed.siteURL.isEmpty && parent == "channel" && !value.isEmpty { feed.siteURL = value }
        }
        text = ""
    }

    static func firstImage(_ html: String) -> String {
        guard let r = html.range(of: "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']", options: [.regularExpression, .caseInsensitive]) else { return "" }
        let tag = String(html[r])
        guard let s = tag.range(of: "src\\s*=\\s*[\"']", options: .regularExpression) else { return "" }
        let rest = tag[s.upperBound...]
        return String(rest.prefix { $0 != "\"" && $0 != "'" })
    }

    private static let rfc822: [DateFormatter] = ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss Z",
                                                  "EEE, d MMM yyyy HH:mm Z", "EEE, d MMM yyyy HH:mm zzz", "EEE, dd MMM yyyy HH:mm:ss Z"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func date(_ s: String) -> Date? {
        let v = s.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: v) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: v) { return d }
        for f in rfc822 { if let d = f.date(from: v) { return d } }
        return MIME.parseDate(v)
    }

    /// Finds a feed link in an HTML page (<link rel="alternate" type="application/rss+xml">).
    static func discover(inHTML html: String, base: URL) -> URL? {
        guard let re = try? NSRegularExpression(pattern: "<link[^>]+>", options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            let lower = tag.lowercased()
            guard lower.contains("alternate"), lower.contains("application/rss+xml") || lower.contains("application/atom+xml") else { continue }
            guard let h = tag.range(of: "href\\s*=\\s*[\"']([^\"']+)[\"']", options: [.regularExpression, .caseInsensitive]) else { continue }
            let attr = String(tag[h])
            guard let q = attr.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
            let href = MIME.decodeEntities(String(attr[attr.index(after: q)...].dropLast()))
            if let u = URL(string: href, relativeTo: base)?.absoluteURL { return u }
        }
        return nil
    }
}

/// Turns a web page into a clean, readable article (kept for reading offline).
enum Readability {
    static let keep: Set<String> = ["p", "h1", "h2", "h3", "h4", "ul", "ol", "li", "blockquote", "pre", "code", "em", "strong", "b", "i",
                                    "a", "img", "figure", "figcaption", "br", "hr", "table", "tr", "td", "th", "thead", "tbody", "sup", "sub"]

    static func extract(_ html: String, base: URL) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "iframe", "nav", "header", "footer", "aside", "form", "svg", "button", "template"] {
            s = s.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>", with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "(?is)<!--.*?-->", with: "", options: .regularExpression)
        let region = section(s, "article") ?? section(s, "main") ?? section(s, "body") ?? s
        return sanitize(region, base: base)
    }

    private static func section(_ s: String, _ tag: String) -> String? {
        guard let start = s.range(of: "<\(tag)\\b[^>]*>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let end = s.range(of: "</\(tag)>", options: [.caseInsensitive, .backwards])
        guard let end, end.lowerBound > start.upperBound else { return String(s[start.upperBound...]) }
        let inner = String(s[start.upperBound..<end.lowerBound])
        return inner.count > 200 ? inner : nil
    }

    /// Keeps simple formatting tags with safe attributes; drops everything else.
    static func sanitize(_ html: String, base: URL) -> String {
        guard let re = try? NSRegularExpression(pattern: "<(/?)([a-zA-Z0-9]+)([^>]*)>") else { return MIME.escapeHTML(html) }
        let ns = html as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            last = m.range.location + m.range.length
            let closing = ns.substring(with: m.range(at: 1)) == "/"
            let tag = ns.substring(with: m.range(at: 2)).lowercased()
            guard keep.contains(tag) else { continue }
            if closing { out += "</\(tag)>"; continue }
            let attrs = ns.substring(with: m.range(at: 3))
            var kept = ""
            for name in tag == "a" ? ["href"] : (tag == "img" ? ["src", "alt"] : []) {
                if let v = attribute(attrs, name) {
                    let value = name == "alt" ? v : (URL(string: v, relativeTo: base)?.absoluteString ?? v)
                    if name != "alt", !(value.hasPrefix("http://") || value.hasPrefix("https://")) { continue }
                    kept += " \(name)=\"\(MIME.escapeHTML(value))\""
                }
            }
            out += "<\(tag)\(kept)>"
        }
        out += ns.substring(from: last)
        // Collapse empty paragraphs and runs of blank space.
        out = out.replacingOccurrences(of: "(?is)<p>\\s*</p>", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return out.trimmed
    }

    private static func attribute(_ attrs: String, _ name: String) -> String? {
        guard let r = attrs.range(of: "\\b\(name)\\s*=\\s*([\"'])(.*?)\\1", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let a = String(attrs[r])
        guard let q = a.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        return MIME.decodeEntities(String(a[a.index(after: q)...].dropLast()))
    }
}

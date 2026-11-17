import SwiftUI
import WebKit

/// Shows email or article HTML with JavaScript off and nothing loaded from the internet
/// (images, fonts, styles, tracking pixels) until you allow it. Links are handed back to be confirmed.
struct SafeHTMLView: UIViewRepresentable {
    var html: String
    var allowRemote = false
    /// Content-ID → (data, mime type) for images embedded in the email.
    var inlineParts: [String: (Data, String)] = [:]
    /// Light page for HTML email (designed for white); themed page for plain text and articles.
    var themed = false
    var textHex = "1C1B1A"
    var backgroundHex = "FFFFFF"
    var accentHex = "4A8FE0"
    var onLink: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onLink: onLink) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.dataDetectorTypes = [.link, .phoneNumber, .address, .calendarEvent]
        config.setURLSchemeHandler(context.coordinator.cidHandler, forURLScheme: "cid")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.allowsLinkPreview = false
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onLink = onLink
        context.coordinator.cidHandler.parts = inlineParts
        let page = Self.page(html, allowRemote: allowRemote, themed: themed, text: textHex, background: backgroundHex, accent: accentHex)
        if context.coordinator.lastPage != page {
            context.coordinator.lastPage = page
            web.loadHTMLString(page, baseURL: nil)
        }
    }

    static func page(_ body: String, allowRemote: Bool, themed: Bool, text: String, background: String, accent: String) -> String {
        let remote = allowRemote ? " https: http:" : ""
        let csp = "default-src 'none'; img-src cid: data:\(remote); media-src data:\(remote); style-src 'unsafe-inline'\(remote); font-src data:\(remote); form-action 'none'; base-uri 'none'"
        let colors = themed
            ? "html,body{background:#\(background);color:#\(text);color-scheme:\(isDark(background) ? "dark" : "light");} a{color:#\(accent);} blockquote{border-left:3px solid #\(accent)55;margin-left:0;padding-left:12px;opacity:.85} pre,code{white-space:pre-wrap;font-family:ui-monospace,Menlo,monospace;font-size:.92em}"
            : "html{background:#FFFFFF;color:#111;color-scheme:light;} body{background:#FFFFFF;}"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body{font:-apple-system-body;font-family:-apple-system,system-ui,sans-serif;margin:14px;overflow-wrap:anywhere;-webkit-text-size-adjust:100%;line-height:1.45}
        img,video{max-width:100%;height:auto} table{max-width:100%} figure{margin:0}
        \(colors)
        </style></head><body>\(body)</body></html>
        """
    }

    private static func isDark(_ hex: String) -> Bool {
        guard let v = UInt32(hex.prefix(6), radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128
    }

    /// Wraps plain text so it shows with line breaks, quotes and tappable links.
    static func plainTextHTML(_ text: String) -> String {
        var lines: [String] = []
        var quoteDepth = 0
        for raw in text.components(separatedBy: "\n") {
            var line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            var depth = 0
            while line.hasPrefix(">") {
                depth += 1
                line = String(line.dropFirst())
                if line.hasPrefix(" ") { line = String(line.dropFirst()) }
            }
            while quoteDepth < depth { lines.append("<blockquote>"); quoteDepth += 1 }
            while quoteDepth > depth { lines.append("</blockquote>"); quoteDepth -= 1 }
            lines.append(linkify(MIME.escapeHTML(line)) + "<br>")
        }
        while quoteDepth > 0 { lines.append("</blockquote>"); quoteDepth -= 1 }
        return "<div style=\"white-space:normal\">" + lines.joined() + "</div>"
    }

    private static func linkify(_ s: String) -> String {
        s.replacingOccurrences(of: "(https?://[^\\s<>\"]+)", with: "<a href=\"$1\">$1</a>", options: .regularExpression)
    }

    /// Images, styles and fonts the page would fetch from the internet.
    static func remoteContentCount(_ html: String) -> Int {
        let patterns = ["(?i)<img[^>]+src\\s*=\\s*[\"']?\\s*https?:", "(?i)url\\(\\s*[\"']?https?:", "(?i)<link[^>]+href\\s*=\\s*[\"']?https?:",
                        "(?i)background\\s*=\\s*[\"']?https?:"]
        return patterns.reduce(0) { total, p in
            total + ((try? NSRegularExpression(pattern: p))?.numberOfMatches(in: html, range: NSRange(html.startIndex..., in: html)) ?? 0)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onLink: (URL) -> Void
        var lastPage = ""
        let cidHandler = CIDHandler()

        init(onLink: @escaping (URL) -> Void) { self.onLink = onLink }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            let scheme = url?.scheme?.lowercased() ?? "about"
            if scheme == "about" || scheme == "data" || scheme == "cid" {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, let url { onLink(url) }
        }
    }

    /// Serves "cid:" images from the email's own parts.
    final class CIDHandler: NSObject, WKURLSchemeHandler {
        var parts: [String: (Data, String)] = [:]

        func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
            guard let url = task.request.url else { return }
            let key = (url.absoluteString.dropFirst(4)).removingPercentEncoding ?? String(url.absoluteString.dropFirst(4))
            guard let part = parts[key] ?? parts[key.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))] else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let (data, mime) = part
            task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        }

        func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
    }
}

/// Asks before opening a link, showing where it really goes.
struct LinkConfirmation: ViewModifier {
    @Binding var url: URL?

    func body(content: Content) -> some View {
        content.confirmationDialog("Open link?", isPresented: Binding(get: { url != nil }, set: { if !$0 { url = nil } }), titleVisibility: .visible) {
            if let url {
                if url.scheme == "mailto" {
                    Button("Write Email") { MailLinks.compose(url) }
                } else {
                    Button("Open in Browser") { UIApplication.shared.open(url) }
                }
                Button("Copy Link") { UIPasteboard.general.string = url.absoluteString }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(url?.absoluteString ?? "")
        }
    }
}

extension View {
    func confirmLinks(_ url: Binding<URL?>) -> some View { modifier(LinkConfirmation(url: url)) }
}

/// mailto: links open Hush's composer when a mail account is set up.
enum MailLinks {
    static func compose(_ url: URL) {
        Router.shared?.composeRequest = ComposeRequest(mailto: url)
    }
}

import SwiftUI
import UIKit

extension NSAttributedString.Key {
    static let hushCheckbox = NSAttributedString.Key("hushCheckbox")
    static let hushNoteLink = NSAttributedString.Key("hushNoteLink")
    static let hushWebLink = NSAttributedString.Key("hushWebLink")
}

/// Styles Markdown in place: headings, bold, italic, strikethrough, code, quotes, lists,
/// checkboxes, [[note links]] and [web](links). The text itself stays plain Markdown.
enum MarkdownStyler {
    struct Colors {
        var text: UIColor = .label
        var dim: UIColor = .tertiaryLabel
        var secondary: UIColor = .secondaryLabel
        var accent: UIColor = .systemBlue
        var codeBackground: UIColor = UIColor.secondarySystemFill
        var heading: UIColor? = nil
        var bold: UIColor? = nil
        var italic: UIColor? = nil
        var code: UIColor? = nil
        var link: UIColor? = nil
        var list: UIColor? = nil

        init(text: UIColor = .label, dim: UIColor = .tertiaryLabel, secondary: UIColor = .secondaryLabel,
             accent: UIColor = .systemBlue, codeBackground: UIColor = .secondarySystemFill) {
            self.text = text; self.dim = dim; self.secondary = secondary; self.accent = accent; self.codeBackground = codeBackground
        }

        /// Colors from the current theme, like an editor's syntax highlighting.
        init(palette: Palette, accent: UIColor) {
            self.init(text: palette.text.map(UIColor.init) ?? .label,
                      dim: (palette.secondaryText.map(UIColor.init) ?? .secondaryLabel).withAlphaComponent(0.6),
                      secondary: palette.secondaryText.map(UIColor.init) ?? .secondaryLabel,
                      accent: accent,
                      codeBackground: UIColor(palette.field))
            if let s = palette.syntax {
                heading = UIColor(Color(hex: s.heading)); bold = UIColor(Color(hex: s.bold))
                italic = UIColor(Color(hex: s.italic)); code = UIColor(Color(hex: s.code))
                link = UIColor(Color(hex: s.link)); list = UIColor(Color(hex: s.list))
            }
        }
    }

    private static func regex(_ p: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }

    private static let heading = regex("^(#{1,6})[ \\t]+(.*)$")
    private static let bold = regex("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = regex("(?<![\\*\\w])([\\*_])(?![\\*_\\s])(.+?)(?<![\\s\\*_])\\1(?![\\*\\w])")
    private static let strike = regex("~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let inlineCode = regex("`([^`\\n]+)`")
    private static let fence = try! NSRegularExpression(pattern: "^```([\\w+#.-]*)[^\\n]*\\n([\\s\\S]*?)^```[ \\t]*$", options: [.anchorsMatchLines])
    private static let tableRow = regex("^\\|.*\\|[ \\t]*$")
    private static let tableRule = regex("^\\|?[ \\t]*:?-{3,}:?[ \\t]*(\\|[ \\t]*:?-{3,}:?[ \\t]*)*\\|?[ \\t]*$")
    private static let quote = regex("^>[ \\t]?.*$")
    private static let bullet = regex("^([ \\t]*)([-*+]|\\d+\\.)[ \\t]")
    private static let checkbox = regex("^([ \\t]*)[-*+][ \\t]\\[([ xX])\\](.*)$")
    private static let noteLink = regex("\\[\\[([^\\]\\n]+)\\]\\]")
    private static let webLink = regex("\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)")
    private static let rule = regex("^(-{3,}|\\*{3,})[ \\t]*$")

    static func font(_ base: UIFont, bold: Bool = false, italic: Bool = false, scale: CGFloat = 1) -> UIFont {
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let desc = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
        return UIFont(descriptor: desc, size: base.pointSize * scale)
    }

    static func style(_ storage: NSMutableAttributedString, base: UIFont, colors: Colors, highlight: String = "") {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let mono = UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular)
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: colors.text, .paragraphStyle: EditorParagraph.style], range: full)

        func each(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            re.enumerateMatches(in: storage.string, range: full) { m, _, _ in if let m { body(m) } }
        }

        each(heading) { m in
            let level = m.range(at: 1).length
            let scale: CGFloat = [1.6, 1.35, 1.2, 1.1, 1.05, 1.0][min(level, 6) - 1]
            storage.addAttribute(.font, value: font(base, bold: true, scale: scale), range: m.range)
            if let c = colors.heading { storage.addAttribute(.foregroundColor, value: c, range: m.range) }
            storage.addAttribute(.foregroundColor, value: colors.dim, range: m.range(at: 1))
        }
        each(bold) { m in
            storage.addAttribute(.font, value: font(base, bold: true), range: m.range)
            if let c = colors.bold { storage.addAttribute(.foregroundColor, value: c, range: m.range) }
            dimMarkers(storage, m.range, marker: m.range(at: 1).length, colors)
        }
        each(italic) { m in
            storage.addAttribute(.font, value: font(base, italic: true), range: m.range)
            if let c = colors.italic { storage.addAttribute(.foregroundColor, value: c, range: m.range) }
            dimMarkers(storage, m.range, marker: 1, colors)
        }
        each(strike) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range)
            storage.addAttribute(.foregroundColor, value: colors.secondary, range: m.range)
            dimMarkers(storage, m.range, marker: 2, colors)
        }
        each(quote) { m in
            storage.addAttribute(.foregroundColor, value: colors.secondary, range: m.range)
            storage.addAttribute(.font, value: font(base, italic: true), range: m.range)
            storage.addAttribute(.foregroundColor, value: colors.accent, range: NSRange(location: m.range.location, length: 1))
        }
        each(rule) { m in storage.addAttribute(.foregroundColor, value: colors.dim, range: m.range) }
        each(bullet) { m in storage.addAttribute(.foregroundColor, value: colors.list ?? colors.accent, range: m.range(at: 2)) }
        each(checkbox) { m in
            let boxRange = NSRange(location: m.range(at: 2).location - 1, length: 3)
            let checked = text.substring(with: m.range(at: 2)).lowercased() == "x"
            storage.addAttribute(.foregroundColor, value: colors.accent, range: NSRange(location: m.range(at: 1).upperBound, length: 1))
            storage.addAttributes([.foregroundColor: colors.accent, .font: font(base, bold: true), .hushCheckbox: m.range(at: 2).location], range: boxRange)
            if checked {
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: colors.secondary], range: m.range(at: 3))
            }
        }
        each(inlineCode) { m in
            storage.addAttributes([.font: mono, .backgroundColor: colors.codeBackground, .foregroundColor: colors.code ?? colors.text], range: m.range)
        }
        each(tableRow) { m in
            let ns = storage.string as NSString
            let line = ns.substring(with: m.range) as NSString
            for i in 0..<line.length where line.character(at: i) == 124 { // "|"
                storage.addAttribute(.foregroundColor, value: colors.dim, range: NSRange(location: m.range.location + i, length: 1))
            }
        }
        each(tableRule) { m in
            storage.addAttribute(.foregroundColor, value: colors.dim, range: m.range)
            // The row above a separator is the header: make it bold.
            let ns = storage.string as NSString
            if m.range.location > 0 {
                let prev = ns.lineRange(for: NSRange(location: m.range.location - 1, length: 0))
                storage.addAttribute(.font, value: font(base, bold: true), range: prev)
            }
        }
        each(fence) { m in
            storage.addAttributes([.font: mono, .backgroundColor: colors.codeBackground, .foregroundColor: colors.code ?? colors.text], range: m.range)
            let lang = (storage.string as NSString).substring(with: m.range(at: 1)).lowercased()
            CodeHighlighter.highlight(storage, range: m.range(at: 2), language: lang, colors: colors)
            storage.addAttribute(.foregroundColor, value: colors.dim, range: NSRange(location: m.range.location, length: 3))
        }
        if !highlight.isEmpty {
            var search = NSRange(location: 0, length: text.length)
            while search.length > 0 {
                let r = text.range(of: highlight, options: [.caseInsensitive], range: search)
                guard r.location != NSNotFound else { break }
                storage.addAttribute(.backgroundColor, value: colors.accent.withAlphaComponent(0.35), range: r)
                search = NSRange(location: r.upperBound, length: text.length - r.upperBound)
            }
        }
        each(noteLink) { m in
            let name = text.substring(with: m.range(at: 1))
            storage.addAttributes([.foregroundColor: colors.link ?? colors.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .hushNoteLink: name], range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: colors.dim, range: NSRange(location: m.range.location, length: 2))
            storage.addAttribute(.foregroundColor, value: colors.dim, range: NSRange(location: m.range.upperBound - 2, length: 2))
        }
        each(webLink) { m in
            let url = text.substring(with: m.range(at: 2))
            storage.addAttributes([.foregroundColor: colors.link ?? colors.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .hushWebLink: url], range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: colors.dim, range: NSRange(location: m.range(at: 1).upperBound, length: m.range.upperBound - m.range(at: 1).upperBound))
        }
        storage.endEditing()
    }

    private static func dimMarkers(_ s: NSMutableAttributedString, _ r: NSRange, marker: Int, _ c: Colors) {
        guard r.length >= marker * 2 else { return }
        s.addAttribute(.foregroundColor, value: c.dim, range: NSRange(location: r.location, length: marker))
        s.addAttribute(.foregroundColor, value: c.dim, range: NSRange(location: r.upperBound - marker, length: marker))
    }

    /// A rendered copy for PDF export: dark text on white, Markdown symbols kept but dimmed.
    static func printable(title: String, body: String) -> NSAttributedString {
        let base = UIFont.systemFont(ofSize: 12)
        let s = NSMutableAttributedString(string: body)
        style(s, base: base, colors: Colors(text: .black, dim: .gray, secondary: .darkGray, accent: .systemBlue,
                                             codeBackground: UIColor(white: 0.94, alpha: 1)))
        let out = NSMutableAttributedString(string: title.isEmpty ? "" : title + "\n\n",
                                            attributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.black])
        out.append(s)
        return out
    }
}

/// A UITextView that styles Markdown live, toggles checkboxes on tap and opens [[links]].
struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var pendingInsert: String?
    var fontDesign: FontStyle = .system
    var fontScale: CGFloat = 1
    var accent: UIColor = .systemBlue
    var horizontalInset: CGFloat = 0
    var palette: Palette = .charcoal
    var focusOnAppear = false
    var onOpenNoteLink: (String) -> Void = { _ in }
    var onLinkPicker: () -> Void = {}
    var onAttach: (() -> Void)? = nil
    var onTable: (() -> Void)? = nil
    var highlight: String = ""
    var selectRequest: Binding<NSRange?> = .constant(nil)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = HushTextView()
        tv.sideInset = horizontalInset
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.textContainerInset = UIEdgeInsets(top: 8, left: horizontalInset, bottom: 120, right: horizontalInset)
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.autocorrectionType = EditorPrefs.autocorrect ? .default : .no
        tv.spellCheckingType = EditorPrefs.spellCheck ? .default : .no
        tv.smartDashesType = EditorPrefs.smartPunctuation ? .yes : .no
        tv.smartQuotesType = EditorPrefs.smartPunctuation ? .yes : .no
        tv.text = text
        tv.inputAccessoryView = context.coordinator.makeToolbar()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)
        context.coordinator.restyle(tv)
        if focusOnAppear { DispatchQueue.main.async { tv.becomeFirstResponder() } }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text {
            let sel = tv.selectedRange
            tv.text = text
            context.coordinator.restyle(tv)
            tv.selectedRange = NSRange(location: min(sel.location, (tv.text as NSString).length), length: 0)
        }
        if context.coordinator.lastHighlight != highlight {
            context.coordinator.lastHighlight = highlight
            context.coordinator.restyle(tv)
        }
        if let r = selectRequest.wrappedValue {
            DispatchQueue.main.async {
                let len = (tv.text as NSString).length
                let safe = NSRange(location: min(r.location, len), length: min(r.length, max(len - r.location, 0)))
                tv.becomeFirstResponder()
                tv.selectedRange = safe
                tv.scrollRangeToVisible(safe)
                selectRequest.wrappedValue = nil
            }
        }
        if let insert = pendingInsert {
            DispatchQueue.main.async {
                context.coordinator.insert(insert, in: tv)
                pendingInsert = nil
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: MarkdownEditor
        weak var textView: UITextView?
        var lastHighlight = ""
        init(_ parent: MarkdownEditor) { self.parent = parent }

        var baseFont: UIFont {
            let body = UIFont.preferredFont(forTextStyle: .body)
            return parent.fontDesign.uiFont(size: body.pointSize * parent.fontScale * EditorPrefs.fontScale)
        }

        func restyle(_ tv: UITextView) {
            textView = tv
            let sel = tv.selectedRange
            let colors = MarkdownStyler.Colors(palette: parent.palette, accent: parent.accent)
            MarkdownStyler.style(tv.textStorage, base: baseFont, colors: colors, highlight: parent.highlight)
            tv.typingAttributes = [.font: baseFont, .foregroundColor: colors.text, .paragraphStyle: EditorParagraph.style]
            tv.tintColor = parent.accent
            tv.selectedRange = sel
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            restyle(tv)
            (tv as? HushTextView)?.centerCaretIfNeeded()
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            (tv as? HushTextView)?.centerCaretIfNeeded()
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText repl: String) -> Bool {
            // Continue lists and checklists when pressing return.
            guard repl == "\n" else { return true }
            let ns = tv.text as NSString
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let line = ns.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
            let patterns = ["^(\\s*)([-*+]) \\[[ xX]\\] ", "^(\\s*)([-*+]) ", "^(\\s*)(\\d+)\\. "]
            for (i, p) in patterns.enumerated() {
                guard let re = try? NSRegularExpression(pattern: p),
                      let m = re.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { continue }
                let lineNS = line as NSString
                if m.range.length == lineNS.length {
                    // Empty item: end the list.
                    replace(in: tv, range: NSRange(location: lineRange.location, length: lineNS.length), with: "")
                    return false
                }
                let indent = lineNS.substring(with: m.range(at: 1))
                var prefix = lineNS.substring(with: m.range)
                if i == 0 { prefix = indent + lineNS.substring(with: m.range(at: 2)) + " [ ] " }
                if i == 2, let n = Int(lineNS.substring(with: m.range(at: 2))) { prefix = "\(indent)\(n + 1). " }
                replace(in: tv, range: range, with: "\n" + prefix)
                return false
            }
            return true
        }

        private func replace(in tv: UITextView, range: NSRange, with s: String) {
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end = tv.position(from: start, offset: range.length),
                  let r = tv.textRange(from: start, to: end) else { return }
            tv.replace(r, withText: s)
        }

        func insert(_ s: String, in tv: UITextView) {
            if let r = tv.selectedTextRange { tv.replace(r, withText: s) } else { tv.insertText(s) }
        }

        // MARK: Taps on checkboxes and links

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let tv = g.view as? UITextView else { return }
            let point = g.location(in: tv)
            guard let pos = tv.closestPosition(to: point) else { return }
            let index = tv.offset(from: tv.beginningOfDocument, to: pos)
            let length = tv.textStorage.length
            for i in [index, index - 1] where i >= 0 && i < length {
                let attrs = tv.textStorage.attributes(at: i, effectiveRange: nil)
                if let loc = attrs[.hushCheckbox] as? Int {
                    let ns = tv.text as NSString
                    let current = ns.substring(with: NSRange(location: loc, length: 1))
                    replace(in: tv, range: NSRange(location: loc, length: 1), with: current == " " ? "x" : " ")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    textViewDidChange(tv)
                    return
                }
                if let name = attrs[.hushNoteLink] as? String {
                    tv.resignFirstResponder()
                    parent.onOpenNoteLink(name)
                    return
                }
                if let url = (attrs[.hushWebLink] as? String).flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true {
                    UIApplication.shared.open(url)
                    return
                }
            }
        }

        // MARK: Formatting bar

        func makeToolbar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            func item(_ symbol: String, _ label: String, _ action: Selector) -> UIBarButtonItem {
                let b = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
                b.accessibilityLabel = label
                return b
            }
            let flex = UIBarButtonItem.flexibleSpace()
            var items = [
                item("bold", "Bold", #selector(boldTapped)), flex,
                item("italic", "Italic", #selector(italicTapped)), flex,
                item("number", "Heading", #selector(headingTapped)), flex,
                item("list.bullet", "Bulleted list", #selector(bulletTapped)), flex,
                item("checklist", "Checklist", #selector(checkTapped)), flex,
                item("link", "Link to note", #selector(linkTapped)), flex,
                item("chevron.left.forwardslash.chevron.right", "Code", #selector(codeTapped)), flex,
            ]
            if parent.onTable != nil { items += [item("tablecells", "Table", #selector(tableTapped)), flex] }
            if parent.onAttach != nil { items += [item("paperclip", "Attach", #selector(attachTapped)), flex] }
            items.append(item("keyboard.chevron.compact.down", "Hide keyboard", #selector(doneTapped)))
            bar.items = items
            bar.sizeToFit()
            return bar
        }

        private func wrap(_ marker: String) {
            guard let tv = textView, let r = tv.selectedTextRange else { return }
            let selected = tv.text(in: r) ?? ""
            tv.replace(r, withText: marker + selected + marker)
            if selected.isEmpty, let p = tv.position(from: r.start, offset: marker.count) {
                tv.selectedTextRange = tv.textRange(from: p, to: p)
            }
        }

        private func linePrefix(_ prefix: String, toggleHeading: Bool = false) {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            let lineRange = ns.lineRange(for: tv.selectedRange)
            let line = ns.substring(with: lineRange)
            if toggleHeading {
                let hashes = line.prefix { $0 == "#" }.count
                let stripped = line.drop { $0 == "#" }.drop { $0 == " " }
                let next = hashes >= 3 ? "" : String(repeating: "#", count: hashes + 1) + " "
                replace(in: tv, range: lineRange, with: next + stripped)
            } else if line.hasPrefix(prefix) {
                replace(in: tv, range: NSRange(location: lineRange.location, length: prefix.count), with: "")
            } else {
                replace(in: tv, range: NSRange(location: lineRange.location, length: 0), with: prefix)
            }
        }

        @objc func boldTapped() { wrap("**") }
        @objc func italicTapped() { wrap("*") }
        @objc func codeTapped() { wrap("`") }
        @objc func headingTapped() { linePrefix("", toggleHeading: true) }
        @objc func bulletTapped() { linePrefix("- ") }
        @objc func checkTapped() { linePrefix("- [ ] ") }
        @objc func linkTapped() { parent.onLinkPicker() }
        @objc func attachTapped() { parent.onAttach?() }
        @objc func tableTapped() { parent.onTable?() }
        @objc func doneTapped() { textView?.resignFirstResponder() }
    }
}


/// Lightweight syntax colors for fenced code blocks (bash, yaml, json, python, js/ts, swift, go, rust, sql, docker, nix, toml, ini).
enum CodeHighlighter {
    private static func re(_ p: String, _ opts: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: p, options: opts)
    }

    private static let keywords: [String: [String]] = [
        "bash": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "in", "function", "return", "export", "local", "sudo", "echo", "cd", "exit"],
        "python": ["def", "class", "return", "if", "elif", "else", "for", "while", "in", "import", "from", "as", "with", "try", "except", "finally", "raise", "lambda", "None", "True", "False", "and", "or", "not", "yield", "async", "await", "pass", "break", "continue"],
        "js": ["const", "let", "var", "function", "return", "if", "else", "for", "while", "class", "new", "import", "from", "export", "default", "async", "await", "try", "catch", "throw", "null", "undefined", "true", "false", "this", "typeof", "interface", "type"],
        "swift": ["let", "var", "func", "return", "if", "else", "guard", "for", "while", "in", "struct", "class", "enum", "protocol", "extension", "import", "switch", "case", "default", "nil", "true", "false", "self", "private", "static", "async", "await", "throws", "try"],
        "go": ["package", "import", "func", "return", "if", "else", "for", "range", "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "nil", "true", "false", "switch", "case"],
        "rust": ["fn", "let", "mut", "pub", "struct", "enum", "impl", "trait", "use", "mod", "match", "if", "else", "for", "while", "loop", "return", "self", "Self", "true", "false", "async", "await"],
        "sql": ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "JOIN", "LEFT", "RIGHT", "INNER", "ON", "AND", "OR", "NOT", "NULL", "ORDER", "BY", "GROUP", "LIMIT", "AS", "PRIMARY", "KEY"],
        "docker": ["FROM", "RUN", "CMD", "ENTRYPOINT", "COPY", "ADD", "ENV", "ARG", "EXPOSE", "WORKDIR", "VOLUME", "USER", "LABEL", "HEALTHCHECK"],
        "nix": ["let", "in", "with", "rec", "inherit", "import", "if", "then", "else", "true", "false", "null"],
    ]

    private static func family(_ lang: String) -> String {
        switch lang {
        case "sh", "bash", "zsh", "shell", "console", "fish": "bash"
        case "py", "python": "python"
        case "js", "javascript", "ts", "typescript", "jsx", "tsx": "js"
        case "swift": "swift"
        case "go", "golang": "go"
        case "rs", "rust": "rust"
        case "sql", "psql", "mysql": "sql"
        case "dockerfile", "docker": "docker"
        case "nix": "nix"
        case "yaml", "yml", "compose": "yaml"
        case "json", "jsonc": "json"
        case "toml", "ini", "conf", "env", "properties": "ini"
        default: lang.isEmpty ? "auto" : lang
        }
    }

    static func highlight(_ s: NSMutableAttributedString, range: NSRange, language: String, colors: MarkdownStyler.Colors) {
        guard range.length > 0, range.upperBound <= s.length else { return }
        var fam = family(language)
        if fam == "auto" {
            let body = (s.string as NSString).substring(with: range)
            if body.contains("services:") || body.range(of: "^\\s*[\\w-]+:\\s", options: .regularExpression) != nil { fam = "yaml" }
            else if body.hasPrefix("{") || body.hasPrefix("[") { fam = "json" }
            else { fam = "bash" }
        }
        let keyword = colors.heading ?? UIColor.systemPink
        let string = colors.bold ?? UIColor.systemOrange
        let number = colors.list ?? UIColor.systemPurple
        let key = colors.link ?? UIColor.systemTeal
        let comment = colors.dim
        func paint(_ r: NSRegularExpression, _ color: UIColor, group: Int = 0) {
            r.enumerateMatches(in: s.string, range: range) { m, _, _ in
                guard let m, m.range(at: group).location != NSNotFound else { return }
                s.addAttribute(.foregroundColor, value: color, range: m.range(at: group))
            }
        }
        paint(re("\\b-?\\d+(\\.\\d+)?\\b"), number)
        switch fam {
        case "yaml":
            paint(re("^(\\s*-?\\s*)([\\w.-]+)(?=:)"), key, group: 2)
            paint(re("\\b(true|false|yes|no|null)\\b"), keyword)
        case "json":
            paint(re("\"[^\"\\n]*\"(?=\\s*:)"), key)
            paint(re("\\b(true|false|null)\\b"), keyword)
        case "ini":
            paint(re("^\\s*([\\w.-]+)\\s*(?==)"), key, group: 1)
            paint(re("^\\s*\\[.*\\]"), keyword)
        default:
            if let words = keywords[fam] {
                let opts: NSRegularExpression.Options = fam == "sql" || fam == "docker" ? [.anchorsMatchLines, .caseInsensitive] : [.anchorsMatchLines]
                paint(re("\\b(" + words.joined(separator: "|") + ")\\b", opts), keyword)
            }
            if fam == "bash" { paint(re("\\$\\{?[\\w]+\\}?"), key); paint(re("(?<=\\s)--?[\\w-]+"), key) }
        }
        // Strings after keys so quoted values win.
        if fam != "json" { paint(re("\"[^\"\\n]*\"|'[^'\\n]*'"), string) } else { paint(re(":\\s*(\"[^\"\\n]*\")"), string, group: 1) }
        // Comments last.
        switch fam {
        case "js", "swift", "go", "rust": paint(re("//.*$"), comment)
        case "sql": paint(re("--.*$"), comment)
        case "json": break
        default: paint(re("(^|\\s)#.*$"), comment)
        }
    }
}


enum EditorParagraph {
    static var style: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = EditorPrefs.lineSpacing
        p.paragraphSpacing = EditorPrefs.paragraphSpacing
        return p
    }
}

/// Keeps lines to a comfortable width and, in typewriter mode, the current line centered.
final class HushTextView: UITextView {
    var sideInset: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxWidth = EditorPrefs.maxWidth
        var side = sideInset
        if maxWidth > 0, bounds.width > maxWidth + sideInset * 2 { side = (bounds.width - maxWidth) / 2 }
        let bottom: CGFloat = EditorPrefs.typewriter ? bounds.height / 2 : 120
        if abs(textContainerInset.left - side) > 0.5 || abs(textContainerInset.bottom - bottom) > 0.5 {
            textContainerInset = UIEdgeInsets(top: 8, left: side, bottom: bottom, right: side)
        }
    }

    func centerCaretIfNeeded() {
        guard EditorPrefs.typewriter, isFirstResponder, let end = selectedTextRange?.end else { return }
        let caret = caretRect(for: end)
        let target = max(caret.midY - bounds.height * 0.4, -adjustedContentInset.top)
        if abs(contentOffset.y - target) > 4 { setContentOffset(CGPoint(x: 0, y: target), animated: true) }
    }
}

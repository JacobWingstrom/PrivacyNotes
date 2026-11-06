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
    private static let rule = regex("^(-{3,}|\\*{3,}|_{3,})[ \\t]*$")
    private static let highlightRe = regex("==(?=\\S)(.+?)(?<=\\S)==")
    private static let underlineRe = regex("<u>(.+?)</u>")
    private static let calloutRe = regex("^>[ \\t]?\\[!(NOTE|TIP|INFO|WARNING|IMPORTANT|CAUTION|TODO|SUCCESS|QUESTION)\\]([^\\n]*)$")
    private static let quoteLine = regex("^>[ \\t]?")

    static func calloutStyle(_ type: String) -> (UIColor, String) {
        switch type {
        case "TIP", "SUCCESS": (.systemGreen, "lightbulb")
        case "WARNING", "CAUTION": (.systemOrange, "exclamationmark.triangle")
        case "IMPORTANT": (.systemPurple, "exclamationmark.bubble")
        case "TODO": (.systemBlue, "checklist")
        case "QUESTION": (.systemTeal, "questionmark.circle")
        default: (.systemBlue, "info.circle")
        }
    }

    static func font(_ base: UIFont, bold: Bool = false, italic: Bool = false, scale: CGFloat = 1) -> UIFont {
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let desc = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
        return UIFont(descriptor: desc, size: base.pointSize * scale)
    }

    static func style(_ storage: NSMutableAttributedString, base: UIFont, colors: Colors, highlight: String = "",
                      hideMarkers: Bool = false, activeRange: NSRange? = nil) {
        var markers: [NSRange] = []
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let mono = UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular)
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: colors.text, .paragraphStyle: EditorParagraph.style], range: full)

        func each(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            re.enumerateMatches(in: storage.string, range: full) { m, _, _ in if let m { body(m) } }
        }

        var calloutBlocks: [NSRange] = []
        // Callouts: > [!TIP] Title, and the quote lines that follow.
        each(calloutRe) { m in
            let ns = storage.string as NSString
            let type = ns.substring(with: m.range(at: 1))
            let (color, _) = calloutStyle(type)
            var block = m.range
            var next = NSMaxRange(ns.lineRange(for: m.range))
            while next < ns.length {
                let line = ns.lineRange(for: NSRange(location: next, length: 0))
                guard ns.substring(with: line).hasPrefix(">") else { break }
                block = NSUnionRange(block, line)
                next = NSMaxRange(line)
            }
            storage.addAttributes([.backgroundColor: color.withAlphaComponent(0.12), .foregroundColor: colors.text, .font: base], range: block)
            storage.addAttributes([.foregroundColor: color, .font: font(base, bold: true)], range: NSRange(location: m.range(at: 1).location, length: m.range(at: 1).length))
            let bracketOpen = NSRange(location: m.range(at: 1).location - 2, length: 2)
            let bracketClose = NSRange(location: m.range(at: 1).upperBound, length: 1)
            storage.addAttribute(.foregroundColor, value: colors.dim, range: bracketOpen)
            storage.addAttribute(.foregroundColor, value: colors.dim, range: bracketClose)
            storage.addAttribute(.font, value: font(base, bold: true), range: m.range(at: 2))
            markers += [bracketOpen, bracketClose]
            calloutBlocks.append(block)
            quoteLine.enumerateMatches(in: storage.string, range: block) { q, _, _ in
                if let q {
                    storage.addAttribute(.foregroundColor, value: color, range: q.range)
                }
            }
        }
        each(heading) { m in
            let level = m.range(at: 1).length
            let scale: CGFloat = [1.6, 1.35, 1.2, 1.1, 1.05, 1.0][min(level, 6) - 1]
            storage.addAttribute(.font, value: font(base, bold: true, scale: scale), range: m.range)
            if let c = colors.heading { storage.addAttribute(.foregroundColor, value: c, range: m.range) }
            storage.addAttribute(.foregroundColor, value: colors.dim, range: m.range(at: 1))
            markers.append(NSRange(location: m.range(at: 1).location, length: m.range(at: 2).location - m.range(at: 1).location))
        }
        each(bold) { m in
            storage.addAttribute(.font, value: font(base, bold: true), range: m.range)
            if let c = colors.bold { storage.addAttribute(.foregroundColor, value: c, range: m.range) }
            dimMarkers(storage, m.range, marker: m.range(at: 1).length, colors)
            markers += ends(m.range, m.range(at: 1).length)
        }
        each(italic) { m in
            storage.addAttribute(.font, value: font(base, italic: true), range: m.range)
            if let c = colors.italic { storage.addAttribute(.foregroundColor, value: c, range: m.range) }
            dimMarkers(storage, m.range, marker: 1, colors)
            markers += ends(m.range, 1)
        }
        each(strike) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range)
            storage.addAttribute(.foregroundColor, value: colors.secondary, range: m.range)
            dimMarkers(storage, m.range, marker: 2, colors)
            markers += ends(m.range, 2)
        }
        each(highlightRe) { m in
            storage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: m.range)
            dimMarkers(storage, m.range, marker: 2, colors)
            markers += ends(m.range, 2)
        }
        each(underlineRe) { m in
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            let open = NSRange(location: m.range.location, length: 3), close = NSRange(location: m.range.upperBound - 4, length: 4)
            storage.addAttribute(.foregroundColor, value: colors.dim, range: open)
            storage.addAttribute(.foregroundColor, value: colors.dim, range: close)
            markers += [open, close]
        }
        each(quote) { m in
            if calloutBlocks.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { return }
            storage.addAttribute(.foregroundColor, value: colors.secondary, range: m.range)
            storage.addAttribute(.font, value: font(base, italic: true), range: m.range)
            storage.addAttribute(.foregroundColor, value: colors.accent, range: NSRange(location: m.range.location, length: 1))
        }
        each(rule) { m in
            storage.addAttributes([.foregroundColor: colors.dim, .strikethroughStyle: NSUnderlineStyle.thick.rawValue,
                                   .strikethroughColor: colors.dim, .kern: 6], range: m.range)
        }
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
            markers += ends(m.range, 1)
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
        // Hide formatting symbols except on the line being edited (like a word processor).
        if hideMarkers {
            let tiny = UIFont.systemFont(ofSize: 0.01)
            for r in markers where r.length > 0 && NSMaxRange(r) <= storage.length {
                if let a = activeRange, NSIntersectionRange(a, r).length > 0 || (r.location >= a.location && r.location <= NSMaxRange(a)) { continue }
                storage.addAttributes([.font: tiny, .foregroundColor: UIColor.clear, .backgroundColor: UIColor.clear], range: r)
            }
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
            markers += ends(m.range, 2)
        }
        each(webLink) { m in
            let url = text.substring(with: m.range(at: 2))
            storage.addAttributes([.foregroundColor: colors.link ?? colors.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .hushWebLink: url], range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: colors.dim, range: NSRange(location: m.range(at: 1).upperBound, length: m.range.upperBound - m.range(at: 1).upperBound))
            markers.append(NSRange(location: m.range.location, length: 1))
            markers.append(NSRange(location: m.range(at: 1).upperBound, length: m.range.upperBound - m.range(at: 1).upperBound))
        }
        storage.endEditing()
    }

    private static func ends(_ r: NSRange, _ n: Int) -> [NSRange] {
        guard r.length >= n * 2 else { return [] }
        return [NSRange(location: r.location, length: n), NSRange(location: r.upperBound - n, length: n)]
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
    var command: Binding<EditorCommand?> = .constant(nil)
    var onSlash: (() -> Void)? = nil
    var showAccessoryBar = true

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
        tv.inputAccessoryView = showAccessoryBar ? context.coordinator.makeToolbar() : nil
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
        if let cmd = command.wrappedValue {
            DispatchQueue.main.async {
                context.coordinator.perform(cmd, in: tv)
                command.wrappedValue = nil
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
        var lastActiveLine: NSRange?
        init(_ parent: MarkdownEditor) { self.parent = parent }

        var baseFont: UIFont {
            let body = UIFont.preferredFont(forTextStyle: .body)
            return parent.fontDesign.uiFont(size: body.pointSize * parent.fontScale * EditorPrefs.fontScale)
        }

        func restyle(_ tv: UITextView) {
            textView = tv
            let sel = tv.selectedRange
            let colors = MarkdownStyler.Colors(palette: parent.palette, accent: parent.accent)
            let ns = tv.text as NSString
            let active: NSRange? = tv.isFirstResponder ? ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0)) : nil
            lastActiveLine = active
            MarkdownStyler.style(tv.textStorage, base: baseFont, colors: colors, highlight: parent.highlight,
                                 hideMarkers: EditorPrefs.hideMarkers, activeRange: active)
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
            // Reveal symbols on the new line, hide them on the old one.
            guard EditorPrefs.hideMarkers else { return }
            let ns = tv.text as NSString
            let line = ns.lineRange(for: NSRange(location: min(tv.selectedRange.location, ns.length), length: 0))
            if line != lastActiveLine { restyle(tv) }
        }

        func textViewDidBeginEditing(_ tv: UITextView) { if EditorPrefs.hideMarkers { restyle(tv) } }
        func textViewDidEndEditing(_ tv: UITextView) { if EditorPrefs.hideMarkers { restyle(tv) } }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText repl: String) -> Bool {
            if repl == "/", EditorPrefs.slashCommands, parent.onSlash != nil {
                let ns = tv.text as NSString
                let atLineStart = range.location == 0 || ns.substring(with: NSRange(location: range.location - 1, length: 1)) == "\n"
                if atLineStart { DispatchQueue.main.async { self.parent.onSlash?() } }
                return true
            }
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


/// Everything the formatting bar and slash menu can do. Each one writes plain Markdown.
indirect enum EditorCommand: Equatable {
    case heading(Int)
    case bold, italic, underline, strike, highlight, code
    case webLink, noteLink
    case bullet, numbered, checklist, quote
    case callout(String)
    case codeBlock(String)
    case divider, table, addRow, addColumn
    case indent, outdent, undo, redo, date, toc
    case insert(String)
    case fromSlash(EditorCommand)

    static let slashItems: [(String, String, EditorCommand)] = [
        ("Heading 1", "textformat.size.larger", .heading(1)), ("Heading 2", "textformat.size", .heading(2)),
        ("Heading 3", "textformat.size.smaller", .heading(3)), ("Bulleted List", "list.bullet", .bullet),
        ("Numbered List", "list.number", .numbered), ("Checklist", "checklist", .checklist), ("Quote", "text.quote", .quote),
        ("Note Callout", "info.circle", .callout("NOTE")), ("Tip Callout", "lightbulb", .callout("TIP")),
        ("Warning Callout", "exclamationmark.triangle", .callout("WARNING")), ("Code Block", "chevron.left.forwardslash.chevron.right", .codeBlock("")),
        ("Bash Block", "terminal", .codeBlock("bash")), ("YAML Block", "doc.plaintext", .codeBlock("yaml")),
        ("Table", "tablecells", .table), ("Divider", "minus", .divider), ("Today's Date", "calendar", .date),
        ("Link to Note", "link", .noteLink), ("Web Link", "safari", .webLink), ("Table of Contents", "list.bullet.indent", .toc),
    ]
}

extension MarkdownEditor.Coordinator {
    func perform(_ cmd: EditorCommand, in tv: UITextView) {
        textView = tv
        if !tv.isFirstResponder { tv.becomeFirstResponder() }
        switch cmd {
        case .fromSlash(let inner):
            let sel = tv.selectedRange
            let ns = tv.text as NSString
            if sel.location > 0, ns.substring(with: NSRange(location: sel.location - 1, length: 1)) == "/" {
                replaceRange(tv, NSRange(location: sel.location - 1, length: 1), "")
            }
            perform(inner, in: tv)
        case .heading(let level): setHeading(level, tv)
        case .bold: wrapSelection("**", tv)
        case .italic: wrapSelection("*", tv)
        case .underline: wrapSelection("<u>", tv, close: "</u>")
        case .strike: wrapSelection("~~", tv)
        case .highlight: wrapSelection("==", tv)
        case .code: wrapSelection("`", tv)
        case .webLink:
            let selected = tv.selectedTextRange.flatMap { tv.text(in: $0) } ?? ""
            let text = "[\(selected.isEmpty ? "link" : selected)](https://)"
            if let r = tv.selectedTextRange { tv.replace(r, withText: text) }
            let loc = tv.selectedRange.location - 1
            tv.selectedRange = NSRange(location: max(loc, 0), length: 0)
        case .noteLink: parent.onLinkPicker()
        case .bullet: togglePrefix("- ", tv)
        case .numbered: togglePrefix("1. ", tv)
        case .checklist: togglePrefix("- [ ] ", tv)
        case .quote: togglePrefix("> ", tv)
        case .callout(let type):
            insertBlock("> [!\(type)] \(type.capitalized)\n> ", tv)
        case .codeBlock(let lang):
            let selected = tv.selectedTextRange.flatMap { tv.text(in: $0) } ?? ""
            insertBlock("```\(lang)\n\(selected)", tv, after: "\n```")
        case .divider: insertBlock("---\n", tv)
        case .table:
            insertBlock("| Column 1 | Column 2 | Column 3 |\n|---|---|---|\n|  |  |  |\n", tv)
        case .addRow: addTableRow(tv)
        case .addColumn: addTableColumn(tv)
        case .indent: indentLines(tv, by: 1)
        case .outdent: indentLines(tv, by: -1)
        case .undo: tv.undoManager?.undo()
        case .redo: tv.undoManager?.redo()
        case .date: tv.insertText(Date().formatted(date: .long, time: .omitted))
        case .toc: insertBlock(TableOfContents.markdown(for: tv.text), tv)
        case .insert(let s): tv.insertText(s)
        }
        textViewDidChange(tv)
    }

    private func replaceRange(_ tv: UITextView, _ range: NSRange, _ s: String) {
        guard let a = tv.position(from: tv.beginningOfDocument, offset: range.location),
              let b = tv.position(from: a, offset: range.length), let r = tv.textRange(from: a, to: b) else { return }
        tv.replace(r, withText: s)
    }

    private func wrapSelection(_ open: String, _ tv: UITextView, close: String? = nil) {
        let close = close ?? open
        guard let r = tv.selectedTextRange else { return }
        let selected = tv.text(in: r) ?? ""
        // Toggle off when the selection is already wrapped.
        if selected.hasPrefix(open), selected.hasSuffix(close), selected.count >= open.count + close.count {
            tv.replace(r, withText: String(selected.dropFirst(open.count).dropLast(close.count)))
            return
        }
        tv.replace(r, withText: open + selected + close)
        if selected.isEmpty, let p = tv.position(from: r.start, offset: open.count) { tv.selectedTextRange = tv.textRange(from: p, to: p) }
    }

    private func currentLine(_ tv: UITextView) -> NSRange {
        let ns = tv.text as NSString
        return ns.lineRange(for: NSRange(location: min(tv.selectedRange.location, ns.length), length: 0))
    }

    private func setHeading(_ level: Int, _ tv: UITextView) {
        let ns = tv.text as NSString
        let lineRange = currentLine(tv)
        let line = ns.substring(with: lineRange)
        let stripped = String(line.drop { $0 == "#" }.drop { $0 == " " })
        let prefix = level > 0 ? String(repeating: "#", count: level) + " " : ""
        replaceRange(tv, lineRange, prefix + stripped)
        tv.selectedRange = NSRange(location: lineRange.location + prefix.count + stripped.trimmingCharacters(in: .newlines).count, length: 0)
    }

    private func togglePrefix(_ prefix: String, _ tv: UITextView) {
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        let block = ns.lineRange(for: sel)
        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let trailingNewline = ns.substring(with: block).hasSuffix("\n")
        let body = trailingNewline ? Array(lines.dropLast()) : lines
        let allHave = body.allSatisfy { $0.hasPrefix(prefix) }
        var n = 0
        let changed = body.map { l -> String in
            if allHave { return String(l.dropFirst(prefix.count)) }
            let clean = l.replacingOccurrences(of: "^(\\s*)([-*+] \\[[ xX]\\] |[-*+] |\\d+\\. |> )", with: "$1", options: .regularExpression)
            n += 1
            return (prefix == "1. " ? "\(n). " : prefix) + clean
        }
        replaceRange(tv, block, changed.joined(separator: "\n") + (trailingNewline ? "\n" : ""))
        let end = block.location + (changed.joined(separator: "\n") as NSString).length
        tv.selectedRange = NSRange(location: end, length: 0)
    }

    private func insertBlock(_ text: String, _ tv: UITextView, after: String = "") {
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        let line = currentLine(tv)
        let lineText = ns.substring(with: line).trimmingCharacters(in: .newlines)
        var prefix = ""
        if !lineText.isEmpty && lineText != "/" { prefix = sel.location == NSMaxRange(line) || sel.location == NSMaxRange(line) - 1 ? "\n" : "\n\n" }
        guard let r = tv.selectedTextRange else { return }
        tv.replace(r, withText: prefix + text + after)
        let caret = sel.location + (prefix as NSString).length + (text as NSString).length
        tv.selectedRange = NSRange(location: min(caret, (tv.text as NSString).length), length: 0)
    }

    private func indentLines(_ tv: UITextView, by delta: Int) {
        let ns = tv.text as NSString
        let block = ns.lineRange(for: tv.selectedRange)
        let text = ns.substring(with: block)
        let lines = text.components(separatedBy: "\n")
        let changed = lines.enumerated().map { i, l -> String in
            if i == lines.count - 1 && l.isEmpty { return l }
            if delta > 0 { return "  " + l }
            if l.hasPrefix("  ") { return String(l.dropFirst(2)) }
            if l.hasPrefix("\t") || l.hasPrefix(" ") { return String(l.dropFirst()) }
            return l
        }
        replaceRange(tv, block, changed.joined(separator: "\n"))
    }

    private func tableBounds(_ tv: UITextView) -> (NSRange, [String])? {
        let ns = tv.text as NSString
        let line = currentLine(tv)
        guard ns.substring(with: line).trimmingCharacters(in: .whitespaces).hasPrefix("|") else { return nil }
        var start = line.location, end = NSMaxRange(line)
        while start > 0 {
            let prev = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            guard ns.substring(with: prev).trimmingCharacters(in: .whitespaces).hasPrefix("|") else { break }
            start = prev.location
        }
        while end < ns.length {
            let next = ns.lineRange(for: NSRange(location: end, length: 0))
            guard ns.substring(with: next).trimmingCharacters(in: .whitespaces).hasPrefix("|") else { break }
            end = NSMaxRange(next)
        }
        let r = NSRange(location: start, length: end - start)
        return (r, ns.substring(with: r).components(separatedBy: "\n"))
    }

    private func addTableRow(_ tv: UITextView) {
        guard let (_, _) = tableBounds(tv) else { insertBlock("| Column 1 | Column 2 |\n|---|---|\n|  |  |\n", tv); return }
        let ns = tv.text as NSString
        let line = currentLine(tv)
        let cols = max(ns.substring(with: line).filter { $0 == "|" }.count - 1, 1)
        let row = "|" + String(repeating: "  |", count: cols)
        let insertAt = NSMaxRange(line)
        let needsNewline = !ns.substring(with: line).hasSuffix("\n")
        replaceRange(tv, NSRange(location: insertAt, length: 0), (needsNewline ? "\n" : "") + row + (needsNewline ? "" : "\n"))
        tv.selectedRange = NSRange(location: insertAt + (needsNewline ? 1 : 0) + 2, length: 0)
    }

    private func addTableColumn(_ tv: UITextView) {
        guard let (range, lines) = tableBounds(tv) else { return }
        let changed = lines.map { l -> String in
            let t = l.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("|") else { return l }
            let isRule = t.replacingOccurrences(of: "|", with: "").allSatisfy { "-: ".contains($0) }
            return l + (isRule ? "---|" : "  |")
        }
        replaceRange(tv, range, changed.joined(separator: "\n"))
    }
}

enum TableOfContents {
    static func markdown(for text: String) -> String {
        let ns = text as NSString
        guard let re = try? NSRegularExpression(pattern: "^(#{1,3})[ \\t]+(.+)$", options: .anchorsMatchLines) else { return "" }
        let items = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m -> String in
            let level = m.range(at: 1).length
            return String(repeating: "  ", count: level - 1) + "- " + ns.substring(with: m.range(at: 2))
        }
        return items.isEmpty ? "**Contents**\n- (add headings with #)\n" : "**Contents**\n" + items.joined(separator: "\n") + "\n"
    }
}

/// Box-Notes-style formatting bar shown at the top of a note.
struct FormatBar: View {
    @Binding var command: EditorCommand?
    var onAttach: () -> Void
    var onTablePicker: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Menu {
                    Button { command = .heading(0) } label: { Label("Body", systemImage: "text.alignleft") }
                    Button { command = .heading(1) } label: { Label("Heading 1", systemImage: "textformat.size.larger") }
                    Button { command = .heading(2) } label: { Label("Heading 2", systemImage: "textformat.size") }
                    Button { command = .heading(3) } label: { Label("Heading 3", systemImage: "textformat.size.smaller") }
                } label: {
                    HStack(spacing: 3) { Image(systemName: "textformat"); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
                        .frame(width: 44, height: 36)
                }
                .accessibilityLabel("Text style")
                divider
                key("bold", "Bold") { command = .bold }
                key("italic", "Italic") { command = .italic }
                key("underline", "Underline") { command = .underline }
                key("strikethrough", "Strikethrough") { command = .strike }
                key("highlighter", "Highlight") { command = .highlight }
                key("chevron.left.forwardslash.chevron.right", "Inline code") { command = .code }
                divider
                key("list.bullet", "Bulleted list") { command = .bullet }
                key("list.number", "Numbered list") { command = .numbered }
                key("checklist", "Checklist") { command = .checklist }
                key("increase.indent", "Indent") { command = .indent }
                key("decrease.indent", "Outdent") { command = .outdent }
                divider
                key("text.quote", "Quote") { command = .quote }
                Menu {
                    ForEach(["NOTE", "TIP", "WARNING", "IMPORTANT", "TODO", "QUESTION"], id: \.self) { t in
                        Button { command = .callout(t) } label: { Label(t.capitalized, systemImage: MarkdownStyler.calloutStyle(t).1) }
                    }
                } label: { Image(systemName: "exclamationmark.bubble").frame(width: 36, height: 36) }
                .accessibilityLabel("Callout")
                Menu {
                    ForEach(["", "bash", "yaml", "json", "python", "js", "sql", "swift", "dockerfile"], id: \.self) { lang in
                        Button(lang.isEmpty ? "Plain" : lang) { command = .codeBlock(lang) }
                    }
                } label: { Image(systemName: "curlybraces.square").frame(width: 36, height: 36) }
                .accessibilityLabel("Code block")
                Menu {
                    Button { onTablePicker() } label: { Label("Insert Table…", systemImage: "tablecells") }
                    Button { command = .addRow } label: { Label("Add Row", systemImage: "rectangle.split.1x2") }
                    Button { command = .addColumn } label: { Label("Add Column", systemImage: "rectangle.split.2x1") }
                } label: { Image(systemName: "tablecells").frame(width: 36, height: 36) }
                .accessibilityLabel("Table")
                key("minus", "Divider") { command = .divider }
                divider
                key("link", "Link to note") { command = .noteLink }
                key("safari", "Web link") { command = .webLink }
                key("paperclip", "Attach") { onAttach() }
                Menu {
                    Button { command = .date } label: { Label("Today's Date", systemImage: "calendar") }
                    Button { command = .toc } label: { Label("Table of Contents", systemImage: "list.bullet.indent") }
                } label: { Image(systemName: "plus.circle").frame(width: 36, height: 36) }
                .accessibilityLabel("Insert")
                divider
                key("arrow.uturn.backward", "Undo") { command = .undo }
                key("arrow.uturn.forward", "Redo") { command = .redo }
            }
            .padding(.horizontal, 8)
            .foregroundStyle(.primary)
        }
        .frame(height: 42)
        .background(palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private var divider: some View { Rectangle().fill(palette.border).frame(width: 1, height: 22).padding(.horizontal, 4) }

    private func key(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The "/" menu.
struct SlashMenu: View {
    var onPick: (EditorCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(EditorCommand.slashItems.filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) }, id: \.0) { name, symbol, cmd in
                    Button {
                        onPick(.fromSlash(cmd))
                        dismiss()
                    } label: { Label(name, systemImage: symbol).foregroundStyle(.primary) }
                    .hushRow()
                }
            }
            .hushList()
            .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Insert…") }
            .navigationTitle("Insert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

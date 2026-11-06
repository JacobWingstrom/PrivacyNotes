import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, charcoal, dark, black, light
    // Editor-inspired themes
    case spectrum, vampire, arctic, oneDark, midnightCity, mocha, retro, solarDark, solarLight, latte

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Match iPhone"
        case .charcoal: "Charcoal"
        case .light: "Light"
        case .dark: "Dark"
        case .black: "Pure Black"
        case .spectrum: "Monokai Pro style"
        case .vampire: "Dracula"
        case .arctic: "Nord"
        case .oneDark: "One Dark"
        case .midnightCity: "Tokyo Night"
        case .mocha: "Catppuccin Mocha"
        case .retro: "Gruvbox"
        case .solarDark: "Solarized Dark"
        case .solarLight: "Solarized Light"
        case .latte: "Catppuccin Latte"
        }
    }

    static let basics: [ThemeMode] = [.system, .charcoal, .dark, .black, .light]
    static let editorThemes: [ThemeMode] = [.spectrum, .vampire, .arctic, .oneDark, .midnightCity, .mocha, .retro, .solarDark, .solarLight, .latte]

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .solarLight, .latte: .light
        default: .dark
        }
    }
}

/// Colors for Markdown styling, like syntax highlighting for your notes.
struct SyntaxColors: Equatable {
    var heading: String
    var bold: String
    var italic: String
    var code: String
    var link: String
    var list: String
}

/// Surface colors for each theme.
struct Palette: Equatable {
    var background: Color
    var surface: Color
    var field: Color
    var border: Color
    var isDark: Bool
    var text: Color? = nil
    var secondaryText: Color? = nil
    /// The theme's own accent; applied when you pick the theme.
    var accentHex: String? = nil
    var syntax: SyntaxColors? = nil

    static let charcoal = Palette(background: Color(hex: "1C1B1A"), surface: Color(hex: "262523"),
                                  field: Color(hex: "232220"), border: Color(hex: "363431"), isDark: true)
    static let dark = Palette(background: Color(hex: "121316"), surface: Color(hex: "1D1E22"),
                              field: Color(hex: "1A1B1E"), border: Color(hex: "2C2D32"), isDark: true)
    static let black = Palette(background: Color(hex: "000000"), surface: Color(hex: "131313"),
                               field: Color(hex: "0E0E0E"), border: Color(hex: "262626"), isDark: true)
    static let light = Palette(background: Color(hex: "F7F6F3"), surface: Color(hex: "FFFFFF"),
                               field: Color(hex: "FFFFFF"), border: Color(hex: "E1DED8"), isDark: false)

    private static func editor(_ bg: String, _ surface: String, _ field: String, _ border: String, dark: Bool = true,
                               text: String, dim: String, accent: String, syntax: SyntaxColors) -> Palette {
        Palette(background: Color(hex: bg), surface: Color(hex: surface), field: Color(hex: field), border: Color(hex: border),
                isDark: dark, text: Color(hex: text), secondaryText: Color(hex: dim), accentHex: accent, syntax: syntax)
    }

    static let spectrum = editor("2D2A2E", "363337", "221F22", "403E41", text: "FCFCFA", dim: "939293", accent: "FF6188",
        syntax: .init(heading: "FF6188", bold: "FC9867", italic: "AB9DF2", code: "A9DC76", link: "78DCE8", list: "FFD866"))
    static let vampire = editor("282A36", "343746", "21222C", "44475A", text: "F8F8F2", dim: "8A93B8", accent: "BD93F9",
        syntax: .init(heading: "FF79C6", bold: "FFB86C", italic: "F1FA8C", code: "50FA7B", link: "8BE9FD", list: "BD93F9"))
    static let arctic = editor("2E3440", "3B4252", "2A303B", "434C5E", text: "ECEFF4", dim: "9AA3B5", accent: "88C0D0",
        syntax: .init(heading: "81A1C1", bold: "EBCB8B", italic: "B48EAD", code: "A3BE8C", link: "88C0D0", list: "D08770"))
    static let oneDark = editor("282C34", "2F343F", "21252B", "3E4451", text: "D7DAE0", dim: "8B919C", accent: "61AFEF",
        syntax: .init(heading: "E06C75", bold: "D19A66", italic: "C678DD", code: "98C379", link: "61AFEF", list: "E5C07B"))
    static let midnightCity = editor("1A1B26", "24283B", "16161E", "2F3549", text: "C0CAF5", dim: "8389AA", accent: "7AA2F7",
        syntax: .init(heading: "BB9AF7", bold: "FF9E64", italic: "7DCFFF", code: "9ECE6A", link: "7AA2F7", list: "E0AF68"))
    static let mocha = editor("1E1E2E", "313244", "181825", "45475A", text: "CDD6F4", dim: "9399B2", accent: "CBA6F7",
        syntax: .init(heading: "F38BA8", bold: "FAB387", italic: "F5C2E7", code: "A6E3A1", link: "89B4FA", list: "F9E2AF"))
    static let retro = editor("282828", "32302F", "1D2021", "504945", text: "EBDBB2", dim: "A89984", accent: "FE8019",
        syntax: .init(heading: "FB4934", bold: "FABD2F", italic: "D3869B", code: "B8BB26", link: "83A598", list: "8EC07C"))
    static let solarDark = editor("002B36", "073642", "00212B", "0E4A57", text: "C5CFCF", dim: "7F9297", accent: "268BD2",
        syntax: .init(heading: "CB4B16", bold: "B58900", italic: "6C71C4", code: "859900", link: "268BD2", list: "2AA198"))
    static let solarLight = editor("FDF6E3", "EEE8D5", "FFFBEF", "DDD6C1", dark: false, text: "4A5A60", dim: "839496", accent: "268BD2",
        syntax: .init(heading: "CB4B16", bold: "B58900", italic: "6C71C4", code: "859900", link: "268BD2", list: "2AA198"))
    static let latte = editor("EFF1F5", "E6E9EF", "FFFFFF", "CCD0DA", dark: false, text: "4C4F69", dim: "6C6F85", accent: "8839EF",
        syntax: .init(heading: "D20F39", bold: "FE640B", italic: "EA76CB", code: "40A02B", link: "1E66F5", list: "DF8E1D"))

    static func forTheme(_ t: ThemeMode, scheme: ColorScheme) -> Palette {
        switch t {
        case .system: scheme == .dark ? .charcoal : .light
        case .charcoal: .charcoal
        case .dark: .dark
        case .black: .black
        case .light: .light
        case .spectrum: .spectrum
        case .vampire: .vampire
        case .arctic: .arctic
        case .oneDark: .oneDark
        case .midnightCity: .midnightCity
        case .mocha: .mocha
        case .retro: .retro
        case .solarDark: .solarDark
        case .solarLight: .solarLight
        case .latte: .latte
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.charcoal
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

enum Appearance {
    /// Navigation bars are UIKit, so they're themed through the appearance proxy.
    static func apply(_ p: Palette) {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(p.background)
        nav.shadowColor = UIColor(p.border)
        let font = FontStyle.current
        var title: [NSAttributedString.Key: Any] = [.font: font.uiFont(size: 17, weight: .semibold)]
        var large: [NSAttributedString.Key: Any] = [.font: font.uiFont(size: 34, weight: .bold)]
        if let text = p.text {
            title[.foregroundColor] = UIColor(text)
            large[.foregroundColor] = UIColor(text)
        }
        nav.titleTextAttributes = title
        nav.largeTitleTextAttributes = large
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

enum FontStyle: String, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced
    case jetbrainsMono, firaCode, sourceCodePro, ibmPlexMono, spaceMono, inter, atkinson, lora

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .monospaced: "SF Mono"
        case .jetbrainsMono: "JetBrains Mono"
        case .firaCode: "Fira Code"
        case .sourceCodePro: "Source Code Pro"
        case .ibmPlexMono: "IBM Plex Mono"
        case .spaceMono: "Space Mono"
        case .inter: "Inter"
        case .atkinson: "Atkinson Hyperlegible"
        case .lora: "Lora"
        }
    }

    var note: String {
        switch self {
        case .system, .rounded, .serif, .monospaced: "Built into iOS"
        case .jetbrainsMono, .firaCode, .sourceCodePro, .ibmPlexMono, .spaceMono: "Coding font"
        case .inter: "Clean sans-serif"
        case .atkinson: "Designed for easy reading"
        case .lora: "Book-style serif"
        }
    }

    static let builtIn: [FontStyle] = [.system, .rounded, .serif, .monospaced]
    static let bundled: [FontStyle] = [.jetbrainsMono, .firaCode, .sourceCodePro, .ibmPlexMono, .spaceMono, .inter, .atkinson, .lora]

    /// Font family registered from the app bundle, or nil for iOS system fonts.
    var family: String? {
        switch self {
        case .system, .rounded, .serif, .monospaced: nil
        case .jetbrainsMono: "JetBrains Mono"
        case .firaCode: "Fira Code"
        case .sourceCodePro: "Source Code Pro"
        case .ibmPlexMono: "IBM Plex Mono"
        case .spaceMono: "Space Mono"
        case .inter: "Inter"
        case .atkinson: "Atkinson Hyperlegible"
        case .lora: "Lora"
        }
    }

    var design: Font.Design {
        switch self {
        case .rounded: .rounded
        case .serif, .lora: .serif
        case .monospaced, .jetbrainsMono, .firaCode, .sourceCodePro, .ibmPlexMono, .spaceMono: .monospaced
        default: .default
        }
    }

    /// The font in use right now (kept in sync by AppSettings).
    static var current: FontStyle = FontStyle(rawValue: UserDefaults.standard.string(forKey: "fontStyle") ?? "") ?? .system

    /// A UIKit font at a given size and weight, used by the note editor and navigation bars.
    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        if let family {
            let desc = UIFontDescriptor(fontAttributes: [.family: family])
                .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            return UIFont(descriptor: desc, size: size)
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign = switch self {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        default: .default
        }
        return UIFont(descriptor: base.fontDescriptor.withDesign(design) ?? base.fontDescriptor, size: size)
    }
}

extension Font {
    /// A text style in the font you picked in Settings, Design.
    static func hush(_ style: Font.TextStyle) -> Font {
        let current = FontStyle.current
        guard let family = current.family else { return .system(style, design: current.design) }
        let size: CGFloat = switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
        let f = Font.custom(family, size: size, relativeTo: style)
        return style == .headline ? f.weight(.semibold) : f
    }
}

enum TextSize: String, CaseIterable, Identifiable {
    case xSmall, small, standard, large, xLarge, huge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .xSmall: "Extra Small"
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .xLarge: "Extra Large"
        case .huge: "Huge"
        }
    }
    var dynamicType: DynamicTypeSize {
        switch self {
        case .xSmall: .small
        case .small: .medium
        case .standard: .large
        case .large: .xLarge
        case .xLarge: .xxLarge
        case .huge: .xxxLarge
        }
    }
}

enum AutoLock: Int, CaseIterable, Identifiable {
    case immediately = 0, oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900, oneHour = 3600
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        case .oneHour: "After 1 hour"
        }
    }
}

enum NoteSort: String, CaseIterable, Identifiable {
    case edited, created, title
    var id: String { rawValue }
    var label: String {
        switch self {
        case .edited: "Last Edited"
        case .created: "Date Created"
        case .title: "Title"
        }
    }
}

struct AccentPreset: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }

    static let all: [AccentPreset] = [
        .init(name: "Sky", hex: "4A8FE0"),
        .init(name: "Ember", hex: "E2733D"),
        .init(name: "Moss", hex: "4E9F5B"),
        .init(name: "Plum", hex: "8E5BD6"),
        .init(name: "Rose", hex: "D64F7A"),
        .init(name: "Gold", hex: "C99A2E"),
        .init(name: "Teal", hex: "2A9D9A"),
        .init(name: "Crimson", hex: "D9473F"),
        .init(name: "Indigo", hex: "5560D6"),
        .init(name: "Mint", hex: "3FBF8F"),
        .init(name: "Slate", hex: "6B7A8F"),
        .init(name: "Ocean", hex: "2F6FD6"),
    ]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count != 6 { s = "E2733D" }
        let v = UInt64(s, radix: 16) ?? 0xE2733D
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", c(r), c(g), c(b))
    }
}

/// Plain, edge-to-edge list on the theme background.
struct HushList: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.background)
    }
}

/// Grouped forms (editors, settings) on the theme background.
struct HushBackground: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background(palette.background)
    }
}

struct HushRow: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content.listRowBackground(Color.clear).listRowSeparatorTint(palette.border)
    }
}

/// A Form whose cards use the theme's surface color.
struct HushForm<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: Content
    var body: some View {
        Form {
            Group { content }
                .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }
}

extension View {
    func hushBackground() -> some View { modifier(HushBackground()) }
    func hushList() -> some View { modifier(HushList()) }
    func hushRow() -> some View { modifier(HushRow()) }
}

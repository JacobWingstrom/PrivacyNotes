import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, charcoal, dark, black, light
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Match iPhone"
        case .charcoal: "Charcoal"
        case .light: "Light"
        case .dark: "Dark"
        case .black: "Pure Black"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .charcoal, .dark, .black: .dark
        }
    }
}

/// Surface colors for each theme.
struct Palette: Equatable {
    var background: Color
    var surface: Color
    var field: Color
    var border: Color
    var isDark: Bool

    static let charcoal = Palette(background: Color(hex: "1C1B1A"), surface: Color(hex: "262523"),
                                  field: Color(hex: "232220"), border: Color(hex: "363431"), isDark: true)
    static let dark = Palette(background: Color(hex: "121316"), surface: Color(hex: "1D1E22"),
                              field: Color(hex: "1A1B1E"), border: Color(hex: "2C2D32"), isDark: true)
    static let black = Palette(background: Color(hex: "000000"), surface: Color(hex: "131313"),
                               field: Color(hex: "0E0E0E"), border: Color(hex: "262626"), isDark: true)
    static let light = Palette(background: Color(hex: "F7F6F3"), surface: Color(hex: "FFFFFF"),
                               field: Color(hex: "FFFFFF"), border: Color(hex: "E1DED8"), isDark: false)
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
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

enum FontStyle: String, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var design: Font.Design {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
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

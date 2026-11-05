import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark, black
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Match iPhone"
        case .light: "Light"
        case .dark: "Dark"
        case .black: "Pure Black"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .black: .dark
        }
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
        .init(name: "Ember", hex: "E2733D"),
        .init(name: "Ocean", hex: "3B82F6"),
        .init(name: "Moss", hex: "4E9F5B"),
        .init(name: "Plum", hex: "8E5BD6"),
        .init(name: "Rose", hex: "D64F7A"),
        .init(name: "Gold", hex: "C99A2E"),
        .init(name: "Teal", hex: "2A9D9A"),
        .init(name: "Crimson", hex: "D9473F"),
        .init(name: "Indigo", hex: "5560D6"),
        .init(name: "Mint", hex: "3FBF8F"),
        .init(name: "Slate", hex: "6B7A8F"),
        .init(name: "Graphite", hex: "8A8A8E"),
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

/// Applies the pure-black background to lists and forms when that theme is on.
struct HushBackground: ViewModifier {
    @Environment(AppSettings.self) private var settings
    func body(content: Content) -> some View {
        if settings.theme == .black {
            content.scrollContentBackground(.hidden).background(Color.black)
        } else {
            content
        }
    }
}

extension View {
    func hushBackground() -> some View { modifier(HushBackground()) }
}

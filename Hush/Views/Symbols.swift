import SwiftUI

/// Curated SF Symbols for notes, habits, contacts, templates and Home widgets.
enum SymbolCatalog {
    static let groups: [(String, [String])] = [
        ("General", ["star", "heart", "bookmark", "flag", "bell", "tag", "pin", "bolt", "sparkles", "lightbulb",
                     "flame", "leaf", "drop", "snowflake", "sun.max", "moon", "cloud", "globe", "key", "lock"]),
        ("Writing", ["doc.text", "note.text", "pencil", "square.and.pencil", "highlighter", "book", "book.closed",
                     "books.vertical", "newspaper", "text.quote", "list.bullet", "checklist", "calendar", "clock", "archivebox"]),
        ("Health", ["figure.run", "figure.walk", "figure.yoga", "figure.strengthtraining.traditional", "dumbbell", "bicycle",
                    "heart.text.square", "pills", "cross.case", "bed.double", "fork.knife", "cup.and.saucer", "carrot",
                    "waterbottle", "brain.head.profile", "lungs", "mouth", "eye"]),
        ("Home & Life", ["house", "sofa", "cart", "bag", "gift", "creditcard", "banknote", "car", "airplane", "tram",
                         "map", "mappin", "tree", "pawprint", "camera", "music.note", "gamecontroller", "paintbrush",
                         "scissors", "wrench.and.screwdriver", "hammer", "trash"]),
        ("Work & Study", ["briefcase", "building.2", "graduationcap", "studentdesk", "person.2", "person.crop.circle",
                          "bubble.left.and.bubble.right", "envelope", "phone", "video", "chart.bar", "chart.pie",
                          "target", "trophy", "rosette", "flag.checkered"]),
        ("Tech & Homelab", ["server.rack", "desktopcomputer", "laptopcomputer", "iphone", "keyboard", "cpu", "memorychip",
                            "externaldrive", "internaldrive", "network", "wifi", "antenna.radiowaves.left.and.right",
                            "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "gearshape", "gearshape.2",
                            "shield", "lock.shield", "cable.connector", "powerplug", "battery.100", "bolt.horizontal",
                            "externaldrive.connected.to.line.below", "cloud.fill", "icloud.and.arrow.up"]),
    ]

    static var all: [String] { groups.flatMap(\.1) }
}

/// Shows an SF Symbol, or the fallback when the stored name isn't a symbol (for example an old emoji).
struct SymbolIcon: View {
    let name: String
    var fallback = "doc.text"
    var body: some View { Image(systemName: SymbolName.resolve(name, fallback: fallback)) }
}

/// A rounded tile with a symbol, used for habits, templates and widgets.
struct SymbolTile: View {
    let name: String
    var fallback = "circle"
    var tint: Color = .accentColor
    var size: CGFloat = 40

    var body: some View {
        SymbolIcon(name: name, fallback: fallback)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct SymbolPicker: View {
    @Binding var selection: String
    var allowNone = true
    var title = "Choose Icon"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var search = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if allowNone && search.isEmpty {
                        Button {
                            selection = ""
                            dismiss()
                        } label: {
                            Label("No Icon", systemImage: "circle.slash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(SymbolCatalog.groups, id: \.0) { group, names in
                        let shown = names.filter(SymbolName.isValid).filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search.replacingOccurrences(of: " ", with: ".")) }
                        if !shown.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ListHeader(title: group)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                                    ForEach(shown, id: \.self) { name in
                                        Button {
                                            selection = name
                                            dismiss()
                                        } label: {
                                            Image(systemName: name)
                                                .font(.system(size: 22))
                                                .frame(width: 52, height: 52)
                                                .foregroundStyle(selection == name ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                                                .background(selection == name ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.surface),
                                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(name.replacingOccurrences(of: ".", with: " "))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(palette.background)
            .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search icons (e.g. server, book)") }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

extension Mood {
    /// Weather-style symbols instead of faces.
    var symbol: String {
        switch self {
        case .none: "circle.dashed"
        case .awful: "cloud.bolt.rain"
        case .low: "cloud.rain"
        case .okay: "cloud"
        case .good: "cloud.sun"
        case .great: "sun.max"
        }
    }
}

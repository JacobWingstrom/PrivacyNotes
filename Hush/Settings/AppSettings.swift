import SwiftUI

@Observable
final class AppSettings {
    private enum K {
        static let theme = "theme", accent = "accentHex", font = "fontStyle", size = "textSize"
        static let compact = "compactLists", order = "sectionOrder", hidden = "hiddenSections"
        static let names = "customNames", start = "startSection", lock = "lockEnabled"
        static let bio = "useBiometrics", autoLock = "autoLock", blur = "blurInSwitcher"
        static let sort = "noteSort", preview = "previewLines"
    }

    @ObservationIgnored private let store = UserDefaults.standard

    var theme: ThemeMode { didSet { store.set(theme.rawValue, forKey: K.theme) } }
    var accentHex: String { didSet { store.set(accentHex, forKey: K.accent) } }
    var fontStyle: FontStyle { didSet { store.set(fontStyle.rawValue, forKey: K.font) } }
    var textSize: TextSize { didSet { store.set(textSize.rawValue, forKey: K.size) } }
    var compactLists: Bool { didSet { store.set(compactLists, forKey: K.compact) } }
    var previewLines: Int { didSet { store.set(previewLines, forKey: K.preview) } }
    var sectionOrder: [AppSection] { didSet { store.set(Self.encode(sectionOrder), forKey: K.order) } }
    var hiddenSections: Set<AppSection> { didSet { store.set(Self.encode(hiddenSections), forKey: K.hidden) } }
    var customNames: [String: String] { didSet { store.set(customNames, forKey: K.names) } }
    var startSection: AppSection { didSet { store.set(startSection.rawValue, forKey: K.start) } }
    var lockEnabled: Bool { didSet { store.set(lockEnabled, forKey: K.lock) } }
    var useBiometrics: Bool { didSet { store.set(useBiometrics, forKey: K.bio) } }
    var autoLock: AutoLock { didSet { store.set(autoLock.rawValue, forKey: K.autoLock) } }
    var blurInSwitcher: Bool { didSet { store.set(blurInSwitcher, forKey: K.blur) } }
    var noteSort: NoteSort { didSet { store.set(noteSort.rawValue, forKey: K.sort) } }

    static let lockEnabledKey = K.lock

    init() {
        let d = UserDefaults.standard
        theme = ThemeMode(rawValue: d.string(forKey: K.theme) ?? "") ?? .system
        accentHex = d.string(forKey: K.accent) ?? AccentPreset.all[0].hex
        fontStyle = FontStyle(rawValue: d.string(forKey: K.font) ?? "") ?? .system
        textSize = TextSize(rawValue: d.string(forKey: K.size) ?? "") ?? .standard
        compactLists = d.object(forKey: K.compact) as? Bool ?? false
        previewLines = d.object(forKey: K.preview) as? Int ?? 2

        var order: [AppSection] = Self.decode(d.data(forKey: K.order)) ?? AppSection.allCases
        for s in AppSection.allCases where !order.contains(s) { order.append(s) } // new sections show up automatically
        sectionOrder = order
        hiddenSections = Self.decode(d.data(forKey: K.hidden)) ?? []
        customNames = d.dictionary(forKey: K.names) as? [String: String] ?? [:]
        startSection = AppSection(rawValue: d.string(forKey: K.start) ?? "") ?? .notes

        lockEnabled = d.bool(forKey: K.lock)
        useBiometrics = d.object(forKey: K.bio) as? Bool ?? true
        autoLock = AutoLock(rawValue: d.object(forKey: K.autoLock) as? Int ?? 60) ?? .oneMinute
        blurInSwitcher = d.object(forKey: K.blur) as? Bool ?? true
        noteSort = NoteSort(rawValue: d.string(forKey: K.sort) ?? "") ?? .edited
    }

    var accentColor: Color { Color(hex: accentHex) }

    var visibleSections: [AppSection] {
        let v = sectionOrder.filter { !hiddenSections.contains($0) }
        return v.isEmpty ? [.notes] : v
    }

    var effectiveStartSection: AppSection {
        visibleSections.contains(startSection) ? startSection : visibleSections[0]
    }

    func title(for section: AppSection) -> String {
        let custom = customNames[section.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? section.defaultTitle : custom
    }

    func resetSidebar() {
        sectionOrder = AppSection.allCases
        hiddenSections = []
        customNames = [:]
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

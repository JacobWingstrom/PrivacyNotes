import SwiftUI

struct SpaceInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var symbol: String

    static let defaults = [
        SpaceInfo(id: Spaces.defaultID, name: "Personal", symbol: "house"),
        SpaceInfo(id: "work", name: "Work", symbol: "briefcase"),
    ]
    static let symbols = ["house", "briefcase", "graduationcap", "heart", "star", "leaf", "hammer", "server.rack",
                          "gamecontroller", "airplane", "cart", "dumbbell", "book", "paintbrush", "music.note", "person.2"]
}

@Observable
final class AppSettings {
    private enum K {
        static let theme = "theme", accent = "accentHex", font = "fontStyle", size = "textSize"
        static let compact = "compactLists", order = "sectionOrder", hidden = "hiddenSections"
        static let names = "customNames", start = "startSection", lock = "lockEnabled"
        static let bio = "useBiometrics", autoLock = "autoLock", blur = "blurInSwitcher"
        static let sort = "noteSort", preview = "previewLines"
        static let homeOrder = "homeBlocks", homeHidden = "hiddenHomeBlocks"
        static let monday = "weekStartsMonday", journalOn = "journalReminder", journalTime = "journalReminderMinutes"
        static let vaultBio = "vaultUseBiometrics", showDone = "showCompletedInAll", greeting = "showGreeting"
    }

    @ObservationIgnored private let store = UserDefaults.standard

    // Spaces
    var spaces: [SpaceInfo] { didSet { store.set(Self.encode(spaces), forKey: "spaces") } }
    /// "all" or a space ID.
    var currentSpace: String { didSet { store.set(currentSpace, forKey: Spaces.currentKey) } }
    var widgetsShowContentWhenLocked: Bool {
        didSet { store.set(widgetsShowContentWhenLocked, forKey: "widgetsWhenLocked"); syncWidgetPrivacy() }
    }
    static let lockEnabledKey = K.lock

    // Appearance
    var theme: ThemeMode {
        didSet {
            store.set(theme.rawValue, forKey: K.theme)
            // Editor themes come with their own accent color.
            if let hex = Palette.forTheme(theme, scheme: .dark).accentHex { accentHex = hex }
        }
    }
    var accentHex: String { didSet { store.set(accentHex, forKey: K.accent) } }
    var fontStyle: FontStyle { didSet { store.set(fontStyle.rawValue, forKey: K.font); FontStyle.current = fontStyle } }
    var textSize: TextSize { didSet { store.set(textSize.rawValue, forKey: K.size) } }
    var compactLists: Bool { didSet { store.set(compactLists, forKey: K.compact) } }
    var previewLines: Int { didSet { store.set(previewLines, forKey: K.preview) } }

    // Sidebar
    var sectionOrder: [AppSection] { didSet { store.set(Self.encode(sectionOrder), forKey: K.order) } }
    var hiddenSections: Set<AppSection> { didSet { store.set(Self.encode(hiddenSections), forKey: K.hidden) } }
    var customNames: [String: String] { didSet { store.set(customNames, forKey: K.names) } }
    var startSection: AppSection { didSet { store.set(startSection.rawValue, forKey: K.start) } }

    // Home
    var homeBlocks: [HomeBlock] { didSet { store.set(Self.encode(homeBlocks), forKey: K.homeOrder) } }
    var hiddenHomeBlocks: Set<HomeBlock> { didSet { store.set(Self.encode(hiddenHomeBlocks), forKey: K.homeHidden) } }
    var showGreeting: Bool { didSet { store.set(showGreeting, forKey: K.greeting) } }

    // Security
    var lockEnabled: Bool { didSet { store.set(lockEnabled, forKey: K.lock); syncWidgetPrivacy() } }
    var useBiometrics: Bool { didSet { store.set(useBiometrics, forKey: K.bio) } }
    var vaultUseBiometrics: Bool { didSet { store.set(vaultUseBiometrics, forKey: K.vaultBio) } }
    var autoLock: AutoLock { didSet { store.set(autoLock.rawValue, forKey: K.autoLock) } }
    var blurInSwitcher: Bool { didSet { store.set(blurInSwitcher, forKey: K.blur) } }

    // Content
    var noteSort: NoteSort { didSet { store.set(noteSort.rawValue, forKey: K.sort) } }
    var weekStartsMonday: Bool { didSet { store.set(weekStartsMonday, forKey: K.monday) } }
    var showCompletedInAll: Bool { didSet { store.set(showCompletedInAll, forKey: K.showDone) } }

    // Reminders
    var defaultReminderMinutes: Int { didSet { store.set(defaultReminderMinutes, forKey: Reminders.defaultMinutesKey) } }
    var hideNotificationText: Bool { didSet { store.set(hideNotificationText, forKey: Reminders.hideTextKey) } }
    var journalReminder: Bool {
        didSet { store.set(journalReminder, forKey: K.journalOn); syncJournalReminder() }
    }
    var journalReminderMinutes: Int {
        didSet { store.set(journalReminderMinutes, forKey: K.journalTime); syncJournalReminder() }
    }

    init() {
        let d = UserDefaults.standard
        spaces = Self.decode(d.data(forKey: "spaces")) ?? SpaceInfo.defaults
        currentSpace = d.string(forKey: Spaces.currentKey) ?? "all"
        widgetsShowContentWhenLocked = d.bool(forKey: "widgetsWhenLocked")
        theme = ThemeMode(rawValue: d.string(forKey: K.theme) ?? "") ?? .charcoal
        accentHex = d.string(forKey: K.accent) ?? AccentPreset.all[0].hex
        let font = FontStyle(rawValue: d.string(forKey: K.font) ?? "") ?? .system
        fontStyle = font
        FontStyle.current = font
        textSize = TextSize(rawValue: d.string(forKey: K.size) ?? "") ?? .standard
        compactLists = d.object(forKey: K.compact) as? Bool ?? false
        previewLines = d.object(forKey: K.preview) as? Int ?? 2

        var order: [AppSection] = Self.decode(d.data(forKey: K.order)) ?? AppSection.allCases
        for s in AppSection.allCases where !order.contains(s) { order.append(s) }
        sectionOrder = order
        hiddenSections = Self.decode(d.data(forKey: K.hidden)) ?? []
        customNames = d.dictionary(forKey: K.names) as? [String: String] ?? [:]
        startSection = AppSection(rawValue: d.string(forKey: K.start) ?? "") ?? .home

        var blocks: [HomeBlock] = Self.decode(d.data(forKey: K.homeOrder)) ?? HomeBlock.allCases
        for b in HomeBlock.allCases where !blocks.contains(b) { blocks.append(b) }
        homeBlocks = blocks
        hiddenHomeBlocks = Self.decode(d.data(forKey: K.homeHidden)) ?? []
        showGreeting = d.object(forKey: K.greeting) as? Bool ?? true

        lockEnabled = d.bool(forKey: K.lock)
        useBiometrics = d.object(forKey: K.bio) as? Bool ?? true
        vaultUseBiometrics = d.object(forKey: K.vaultBio) as? Bool ?? true
        autoLock = AutoLock(rawValue: d.object(forKey: K.autoLock) as? Int ?? 60) ?? .oneMinute
        blurInSwitcher = d.object(forKey: K.blur) as? Bool ?? true

        noteSort = NoteSort(rawValue: d.string(forKey: K.sort) ?? "") ?? .edited
        weekStartsMonday = d.bool(forKey: K.monday)
        showCompletedInAll = d.object(forKey: K.showDone) as? Bool ?? false

        defaultReminderMinutes = d.object(forKey: Reminders.defaultMinutesKey) as? Int ?? 540
        hideNotificationText = d.bool(forKey: Reminders.hideTextKey)
        journalReminder = d.bool(forKey: K.journalOn)
        journalReminderMinutes = d.object(forKey: K.journalTime) as? Int ?? 1260
    }

    var accentColor: Color { Color(hex: accentHex) }

    /// nil when showing every space.
    var spaceFilter: String? { currentSpace == "all" ? nil : currentSpace }
    var currentSpaceInfo: SpaceInfo? { spaces.first { $0.id == currentSpace } }

    /// Widgets show content only if the app isn't locked, or you allowed it.
    func syncWidgetPrivacy() {
        AppGroup.defaults.set(!lockEnabled || widgetsShowContentWhenLocked, forKey: "widgetsShowContent")
        AppGroup.defaults.set(accentHex, forKey: "accentHex")
    }

    func palette(for scheme: ColorScheme) -> Palette { Palette.forTheme(theme, scheme: scheme) }

    var visibleSections: [AppSection] {
        let v = sectionOrder.filter { !hiddenSections.contains($0) }
        return v.isEmpty ? [.notes] : v
    }

    var effectiveStartSection: AppSection {
        visibleSections.contains(startSection) ? startSection : visibleSections[0]
    }

    var visibleHomeBlocks: [HomeBlock] { homeBlocks.filter { !hiddenHomeBlocks.contains($0) } }

    var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = weekStartsMonday ? 2 : 1
        return c
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

    func resetHome() {
        homeBlocks = HomeBlock.allCases
        hiddenHomeBlocks = []
    }

    private func syncJournalReminder() {
        Reminders.syncJournal(enabled: journalReminder, minutes: journalReminderMinutes)
    }

    /// A Date binding backed by "minutes after midnight".
    static func timeBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(get() * 60)) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                set((c.hour ?? 0) * 60 + (c.minute ?? 0))
            })
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

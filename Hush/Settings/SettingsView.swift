import SwiftUI
import SwiftData

/// Top-level settings: a flat list of categories, each opening its own page.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var search = ""

    private struct Item: Identifiable {
        let id: String
        let symbol: String
        let keywords: String
        let destination: () -> AnyView
    }

    private var groups: [(String, [Item])] {
        [
            ("Your Data", [
                Item(id: "Connected Calendars", symbol: "calendar.badge.checkmark", keywords: "outlook apple icloud google exchange sync link") { AnyView(ConnectedCalendarsView()) },
                Item(id: "Import from iPhone", symbol: "square.and.arrow.down", keywords: "contacts reminders events notes vcf ics markdown text") { AnyView(ImportView()) },
                Item(id: "Statistics", symbol: "chart.bar", keywords: "counts words") { AnyView(StatisticsView()) },
                Item(id: "Backup & Restore", symbol: "arrow.triangle.2.circlepath", keywords: "import export file") { AnyView(BackupView()) },
                Item(id: "Export", symbol: "square.and.arrow.up", keywords: "markdown csv pdf vcf ics html share") { AnyView(ExportView()) },
                Item(id: "Trash", symbol: "trash", keywords: "deleted restore recover") { AnyView(TrashView()) },
            ]),
            ("Preferences", [
                Item(id: "Design", symbol: "paintpalette", keywords: "theme dark light accent color font text size icon") { AnyView(DesignSettings()) },
                Item(id: "Spaces", symbol: "square.split.2x1", keywords: "personal work separate") { AnyView(SpacesSettings()) },
                Item(id: "Layout", symbol: "sidebar.left", keywords: "sidebar sections home dashboard start launch") { AnyView(LayoutSettings()) },
                Item(id: "Templates", symbol: "doc.on.doc", keywords: "note homelab meeting") { AnyView(TemplatesSettings()) },
                Item(id: "Widgets & Siri", symbol: "square.grid.2x2", keywords: "home screen shortcuts voice") { AnyView(WidgetSiriSettings()) },
                Item(id: "Lists", symbol: "list.bullet", keywords: "compact preview sort completed") { AnyView(ListSettings()) },
                Item(id: "Reminders", symbol: "bell", keywords: "notifications journal time") { AnyView(ReminderSettings()) },
                Item(id: "Date & Time", symbol: "calendar", keywords: "week monday sunday") { AnyView(DateSettings()) },
            ]),
            ("Security", [
                Item(id: "App Lock", symbol: "lock", keywords: "passcode face id touch auto switcher") { AnyView(LockSettings()) },
                Item(id: "Vault", symbol: "lock.shield", keywords: "passcode face id") { AnyView(VaultSettings()) },
            ]),
            ("About", [
                Item(id: "Privacy", symbol: "hand.raised", keywords: "data network offline") { AnyView(PrivacyInfo()) },
                Item(id: "Acknowledgements", symbol: "text.book.closed", keywords: "fonts licenses credits") { AnyView(Acknowledgements()) },
            ]),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { title, items in
                    let shown = items.filter {
                        search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) || $0.keywords.localizedCaseInsensitiveContains(search)
                    }
                    if !shown.isEmpty {
                        Section {
                            ForEach(shown) { item in
                                NavigationLink { item.destination() } label: {
                                    HStack(spacing: 16) {
                                        Image(systemName: item.symbol)
                                            .font(.hush(.title3))
                                            .foregroundStyle(.tint)
                                            .frame(width: 28)
                                        Text(item.id).font(.hush(.body))
                                    }
                                    .padding(.vertical, 8)
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text(title.uppercased())
                                .font(.hush(.footnote).weight(.semibold))
                                .tracking(0.8)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                        .font(.hush(.footnote))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .hushList()
            .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search settings") }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Close")
                }
            }
        }
    }
}

// MARK: - Category pages

struct DesignSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section("Theme") {
                themeGrid(ThemeMode.basics)
            }
            Section {
                themeGrid(ThemeMode.editorThemes)
            } header: {
                Text("Editor Themes")
            } footer: {
                Text("Color themes inspired by popular code editors. Headings, bold, code and links in notes are colored like syntax highlighting. Not affiliated with the original themes.")
            }
            Section("Accent Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(AccentPreset.all) { preset in
                        Circle()
                            .fill(Color(hex: preset.hex))
                            .frame(width: 34, height: 34)
                            .overlay {
                                if preset.hex == settings.accentHex {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                            .onTapGesture { settings.accentHex = preset.hex }
                            .accessibilityLabel(preset.name)
                            .accessibilityAddTraits(preset.hex == settings.accentHex ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, 6)
                ColorPicker("Custom Color", selection: Binding(
                    get: { settings.accentColor },
                    set: { settings.accentHex = $0.hexString }
                ), supportsOpacity: false)
            }
            Section("Font") {
                ForEach(FontStyle.builtIn + FontStyle.bundled) { f in
                    Button { settings.fontStyle = f } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.label).font(sample(f, 17)).foregroundStyle(.primary)
                                Text(f.note).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Aa 123 {}").font(sample(f, 15)).foregroundStyle(.secondary)
                            if settings.fontStyle == f {
                                Image(systemName: "checkmark").foregroundStyle(.tint).padding(.leading, 6)
                            }
                        }
                    }
                    .accessibilityAddTraits(settings.fontStyle == f ? .isSelected : [])
                }
            }
            Section {
                Picker("Text Size", selection: $s.textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                NavigationLink("App Icon") { AppIconPicker() }
            }
        }
        .navigationTitle("Design")
    }

    private func sample(_ f: FontStyle, _ size: CGFloat) -> Font {
        if let family = f.family { return .custom(family, fixedSize: size) }
        return .system(size: size, design: f.design)
    }

    private func themeGrid(_ themes: [ThemeMode]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 12)], spacing: 12) {
            ForEach(themes) { t in
                ThemeCard(theme: t, palette: Palette.forTheme(t, scheme: scheme), selected: settings.theme == t)
                    .onTapGesture { withAnimation(.snappy) { settings.theme = t } }
            }
        }
        .padding(.vertical, 6)
    }
}

/// A tiny preview of a theme: background, a heading, text lines and an accent dot.
private struct ThemeCard: View {
    let theme: ThemeMode
    let palette: Palette
    let selected: Bool

    var body: some View {
        let text = palette.text ?? (palette.isDark ? .white : .black)
        let accent = palette.accentHex.map { Color(hex: $0) } ?? Color.accentColor
        let syntax = palette.syntax
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(syntax.map { Color(hex: $0.heading) } ?? text).frame(width: 46, height: 6)
                Capsule().fill(text.opacity(0.75)).frame(width: 64, height: 4)
                HStack(spacing: 4) {
                    Capsule().fill(syntax.map { Color(hex: $0.code) } ?? text.opacity(0.5)).frame(width: 26, height: 4)
                    Capsule().fill(syntax.map { Color(hex: $0.link) } ?? accent).frame(width: 22, height: 4)
                }
                Capsule().fill(text.opacity(0.45)).frame(width: 52, height: 4)
                HStack {
                    Spacer()
                    Circle().fill(accent).frame(width: 12, height: 12)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.border), lineWidth: selected ? 2.5 : 1))
            Text(theme.label).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.label) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct Acknowledgements: View {
    private let fonts: [(String, String)] = [
        ("JetBrains Mono", "JetBrainsMono"), ("Fira Code", "FiraCode"), ("Source Code Pro", "SourceCodePro"),
        ("IBM Plex Mono", "IBMPlexMono"), ("Space Mono", "SpaceMono"), ("Inter", "Inter"),
        ("Atkinson Hyperlegible", "AtkinsonHyperlegible"), ("Lora", "Lora"),
    ]

    var body: some View {
        HushForm {
            Section {
                ForEach(fonts, id: \.0) { name, file in
                    NavigationLink(name) { LicenseText(title: name, file: "OFL-\(file)") }
                }
            } header: {
                Text("Fonts")
            } footer: {
                Text("These fonts are used under the SIL Open Font License 1.1.")
            }
        }
        .navigationTitle("Acknowledgements")
    }
}

private struct LicenseText: View {
    let title: String
    let file: String
    var body: some View {
        ScrollView {
            Text((Bundle.main.url(forResource: file, withExtension: "txt").flatMap { try? String(contentsOf: $0) }) ?? "License not found.")
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LayoutSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section {
                NavigationLink("Sidebar Sections") { SidebarSettingsView() }
                Picker("Open On Launch", selection: $s.startSection) {
                    ForEach(settings.visibleSections) { Text(settings.title(for: $0)).tag($0) }
                }
            } footer: {
                Text("Reorder, rename or hide any section.")
            }
            Section {
                NavigationLink("Home Dashboard") { HomeCustomizeView() }
            }
        }
        .navigationTitle("Layout")
    }
}

struct ListSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section {
                Toggle("Compact Lists", isOn: $s.compactLists)
                Stepper("Note Preview Lines: \(settings.previewLines)", value: $s.previewLines, in: 0...5)
                    .disabled(settings.compactLists)
                Picker("Sort Notes By", selection: $s.noteSort) {
                    ForEach(NoteSort.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show Completed Tasks in All", isOn: $s.showCompletedInAll)
            }
        }
        .navigationTitle("Lists")
    }
}

struct ReminderSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section {
                DatePicker("Default Reminder Time",
                           selection: AppSettings.timeBinding({ settings.defaultReminderMinutes }, { settings.defaultReminderMinutes = $0 }),
                           displayedComponents: .hourAndMinute)
            } footer: {
                Text("Used for all-day tasks, all-day events and birthdays.")
            }
            Section {
                Toggle("Daily Journal Reminder", isOn: $s.journalReminder)
                if settings.journalReminder {
                    DatePicker("Time",
                               selection: AppSettings.timeBinding({ settings.journalReminderMinutes }, { settings.journalReminderMinutes = $0 }),
                               displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Toggle("Hide Text in Notifications", isOn: $s.hideNotificationText)
                Button("Open iPhone Notification Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
            } footer: {
                Text("When on, your lock screen only says “You have a reminder”.")
            }
        }
        .navigationTitle("Reminders")
    }
}

struct DateSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section {
                Toggle("Week Starts on Monday", isOn: $s.weekStartsMonday)
            }
        }
        .navigationTitle("Date & Time")
    }
}

struct LockSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LockManager.self) private var lock
    @State private var settingPasscode = false

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section {
                Toggle("Passcode Lock", isOn: Binding(
                    get: { settings.lockEnabled },
                    set: { on in
                        if on { settingPasscode = true } else { settings.lockEnabled = false; Passcode.app.clear() }
                    }
                ))
                if settings.lockEnabled {
                    Button("Change Passcode") { settingPasscode = true }
                    if lock.biometryAvailable {
                        Toggle("Unlock with \(lock.biometryName)", isOn: $s.useBiometrics)
                    }
                    Picker("Auto-Lock", selection: $s.autoLock) {
                        ForEach(AutoLock.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            Section {
                Toggle("Hide Content in App Switcher", isOn: $s.blurInSwitcher)
            }
        }
        .navigationTitle("App Lock")
        .sheet(isPresented: $settingPasscode) {
            PasscodeSetupView(onSave: { code in
                Passcode.app.set(code)
                settings.lockEnabled = true
            }, onBiometrics: { settings.useBiometrics = $0 })
        }
    }
}

struct VaultSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LockManager.self) private var lock
    @State private var settingPasscode = false

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section {
                Button(Passcode.vault.isSet ? "Change Vault Passcode" : "Set Vault Passcode") { settingPasscode = true }
                if lock.biometryAvailable {
                    Toggle("Unlock Vault with \(lock.biometryName)", isOn: $s.vaultUseBiometrics)
                }
            } footer: {
                Text("The Vault has its own passcode, is encrypted with AES-256, and re-locks whenever you leave it or the app.")
            }
        }
        .navigationTitle("Vault")
        .sheet(isPresented: $settingPasscode) {
            PasscodeSetupView(title: "Vault Passcode", onSave: { Passcode.vault.set($0) },
                              onBiometrics: { settings.vaultUseBiometrics = $0 })
        }
    }
}

struct PrivacyInfo: View {
    var body: some View {
        HushForm {
            Section {
                Label("No internet connection is ever made", systemImage: "wifi.slash")
                Label("Connected calendars are read through iOS, not the internet", systemImage: "calendar")
                Label("No accounts, ads or analytics", systemImage: "person.crop.circle.badge.xmark")
                Label("Data stays on this iPhone and out of iCloud backups", systemImage: "iphone")
                Label("Vault and Files encrypted with AES-256", systemImage: "lock.shield")
                Label("Backups encrypted with your own password", systemImage: "key")
            } footer: {
                Text("Because nothing leaves your phone, deleting Hush deletes your data. Make backups from Backup & Restore.")
            }
        }
        .navigationTitle("Privacy")
    }
}

struct StatisticsView: View {
    @Query private var notesStored: [Note]
    @Environment(AppSettings.self) private var notesSpace
    private var notes: [Note] { notesStored.live(notesSpace.spaceFilter) }
    @Query private var tasksStored: [TaskItem]
    @Environment(AppSettings.self) private var tasksSpace
    private var tasks: [TaskItem] { tasksStored.live(tasksSpace.spaceFilter) }
    @Query private var journalsStored: [JournalEntry]
    @Environment(AppSettings.self) private var journalsSpace
    private var journals: [JournalEntry] { journalsStored.live(journalsSpace.spaceFilter) }
    @Query private var drawingsStored: [Drawing]
    @Environment(AppSettings.self) private var drawingsSpace
    private var drawings: [Drawing] { drawingsStored.live(drawingsSpace.spaceFilter) }
    @Query private var filesStored: [StoredFile]
    @Environment(AppSettings.self) private var filesSpace
    private var files: [StoredFile] { filesStored.live(filesSpace.spaceFilter) }
    @Query private var eventsStored: [CalendarEvent]
    @Environment(AppSettings.self) private var eventsSpace
    private var events: [CalendarEvent] { eventsStored.live(eventsSpace.spaceFilter) }
    @Query private var contactsStored: [Contact]
    @Environment(AppSettings.self) private var contactsSpace
    private var contacts: [Contact] { contactsStored.live(contactsSpace.spaceFilter) }
    @Query private var bookmarksStored: [Bookmark]
    @Environment(AppSettings.self) private var bookmarksSpace
    private var bookmarks: [Bookmark] { bookmarksStored.live(bookmarksSpace.spaceFilter) }

    var body: some View {
        let words = notes.reduce(0) { $0 + $1.body.split { $0.isWhitespace }.count + $1.title.split { $0.isWhitespace }.count }
            + journals.reduce(0) { $0 + $1.body.split { $0.isWhitespace }.count }
        HushForm {
            Section("Content") {
                LabeledContent("Notes", value: "\(notes.count)")
                LabeledContent("Open tasks", value: "\(tasks.filter { !$0.isDone }.count)")
                LabeledContent("Completed tasks", value: "\(tasks.filter(\.isDone).count)")
                LabeledContent("Events", value: "\(events.count)")
                LabeledContent("Journal entries", value: "\(journals.count)")
                LabeledContent("Drawings", value: "\(drawings.count)")
                LabeledContent("Contacts", value: "\(contacts.count)")
                LabeledContent("Bookmarks", value: "\(bookmarks.count)")
                LabeledContent("Files", value: "\(files.count)")
            }
            Section("Writing") {
                LabeledContent("Words written", value: words.formatted())
                LabeledContent("Journal streak", value: "\(JournalStats.streak(journals)) days")
            }
            Section("Storage") {
                LabeledContent("Files", value: ByteCountFormatter.string(fromByteCount: Int64(files.reduce(0) { $0 + $1.size }), countStyle: .file))
            }
        }
        .navigationTitle("Statistics")
    }
}

struct SidebarSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        List {
            Section {
                ForEach(settings.sectionOrder) { section in
                    SidebarRow(section: section)
                }
                .onMove { s.sectionOrder.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Drag to reorder. Tap a name to rename it. Switch a section off to hide it.")
            }
            Section {
                Button("Reset Sidebar", role: .destructive) { settings.resetSidebar() }
            }
        }
        .environment(\.editMode, .constant(.active))
        .hushBackground()
        .navigationTitle("Sidebar")
    }
}

private struct SidebarRow: View {
    let section: AppSection
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .foregroundStyle(.tint)
                .frame(width: 26)
            TextField(section.defaultTitle, text: Binding(
                get: { settings.customNames[section.rawValue] ?? "" },
                set: { settings.customNames[section.rawValue] = $0.isEmpty ? nil : $0 }
            ))
            .submitLabel(.done)
            Toggle("Show \(section.defaultTitle)", isOn: Binding(
                get: { !settings.hiddenSections.contains(section) },
                set: { visible in
                    if visible { settings.hiddenSections.remove(section) }
                    else { settings.hiddenSections.insert(section) }
                }
            ))
            .labelsHidden()
        }
    }
}

struct AppIconPicker: View {
    @State private var current = UIApplication.shared.alternateIconName ?? "AppIcon"
    private let icons: [(String, String)] = [
        ("AppIcon", "Ember"), ("AppIcon-Midnight", "Midnight"), ("AppIcon-Forest", "Forest"),
        ("AppIcon-Plum", "Plum"), ("AppIcon-Paper", "Paper"), ("AppIcon-Mono", "Mono"),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 18)], spacing: 18) {
                ForEach(icons, id: \.0) { name, label in
                    Button {
                        UIApplication.shared.setAlternateIconName(name == "AppIcon" ? nil : name) { error in
                            if error == nil { current = name }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image("Preview-\(name)")
                                .resizable()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(current == name ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: current == name ? 3 : 1))
                            Text(label).font(.hush(.caption))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(current == name ? .isSelected : [])
                }
            }
            .padding()
        }
        .navigationTitle("App Icon")
    }
}

struct SpacesSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section {
                Picker("Showing", selection: $s.currentSpace) {
                    Text("All Spaces").tag("all")
                    ForEach(settings.spaces) { Text($0.name).tag($0.id) }
                }
            } footer: {
                Text("Switch spaces from the top of the menu (☰). New items go into the space you're viewing.")
            }
            Section("Spaces") {
                ForEach($s.spaces) { $sp in
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(SpaceInfo.symbols, id: \.self) { sym in
                                Button { sp.symbol = sym } label: { Label(sym, systemImage: sym) }
                            }
                        } label: {
                            Image(systemName: sp.symbol).foregroundStyle(.tint).frame(width: 28)
                        }
                        TextField("Name", text: $sp.name)
                    }
                }
                .onDelete { idx in
                    let removing = idx.map { settings.spaces[$0].id }
                    guard !removing.contains(Spaces.defaultID) else { return }
                    settings.spaces.remove(atOffsets: idx)
                    if removing.contains(settings.currentSpace) { settings.currentSpace = "all" }
                }
                Button { newName = ""; adding = true } label: { Label("Add Space", systemImage: "plus") }
            }
            Section {
                Text("Deleting a space doesn't delete anything: its items show up under All Spaces and can be moved. The Personal space can't be removed.")
                    .font(.hush(.footnote)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spaces")
        .alert("New Space", isPresented: $adding) {
            TextField("Name (e.g. School)", text: $newName)
            Button("Add") {
                let name = newName.trimmed
                guard !name.isEmpty else { return }
                settings.spaces.append(SpaceInfo(id: UUID().uuidString, name: name, symbol: "star"))
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct WidgetSiriSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section {
                Label("**Today** — tasks due today", systemImage: "checkmark.circle")
                Label("**Habits** — check them off from the Home Screen", systemImage: "flame")
                Label("**Quick Add** — new note, task, journal entry or habit", systemImage: "plus.square")
            } header: {
                Text("Widgets")
            } footer: {
                Text("Long-press your Home Screen, tap Edit → Add Widget, and search for Hush.")
            }
            Section {
                Toggle("Show Widget Content While Locked", isOn: $s.widgetsShowContentWhenLocked)
                    .disabled(!settings.lockEnabled)
            } footer: {
                Text(settings.lockEnabled
                     ? "With App Lock on, widgets show “Hush is locked” unless you allow this."
                     : "Turn on App Lock to hide widget content.")
            }
            Section {
                Label("“Add a task in Hush”", systemImage: "mic")
                Label("“Take a note in Hush”", systemImage: "mic")
                Label("“Log a habit in Hush”", systemImage: "mic")
                Label("“Journal in Hush”", systemImage: "mic")
            } header: {
                Text("Siri & Shortcuts")
            } footer: {
                Text("Siri can add things to Hush but never reads your content aloud. These actions also appear in the Shortcuts app.")
            }
        }
        .navigationTitle("Widgets & Siri")
        .onAppear { settings.syncWidgetPrivacy() }
    }
}

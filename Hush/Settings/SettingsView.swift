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
            ]),
            ("Preferences", [
                Item(id: "Design", symbol: "paintpalette", keywords: "theme dark light accent color font text size icon") { AnyView(DesignSettings()) },
                Item(id: "Layout", symbol: "sidebar.left", keywords: "sidebar sections home dashboard start launch") { AnyView(LayoutSettings()) },
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
                                            .font(.title3)
                                            .foregroundStyle(.tint)
                                            .frame(width: 28)
                                        Text(item.id).font(.body)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text(title.uppercased())
                                .font(.footnote.weight(.semibold))
                                .tracking(0.8)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                        .font(.footnote)
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

    var body: some View {
        @Bindable var s = settings
        HushForm {
            Section("Theme") {
                Picker("Theme", selection: $s.theme) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
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
            Section("Text") {
                Picker("Font", selection: $s.fontStyle) {
                    ForEach(FontStyle.allCases) { Text($0.label).fontDesign($0.design).tag($0) }
                }
                Picker("Text Size", selection: $s.textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                NavigationLink("App Icon") { AppIconPicker() }
            }
        }
        .navigationTitle("Design")
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
            PasscodeSetupView { code in
                Passcode.app.set(code)
                settings.lockEnabled = true
            }
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
            PasscodeSetupView(title: "Vault Passcode") { Passcode.vault.set($0) }
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
    @Query private var notes: [Note]
    @Query private var tasks: [TaskItem]
    @Query private var journals: [JournalEntry]
    @Query private var drawings: [Drawing]
    @Query private var files: [StoredFile]
    @Query private var events: [CalendarEvent]
    @Query private var contacts: [Contact]
    @Query private var bookmarks: [Bookmark]

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
                            Text(label).font(.caption)
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

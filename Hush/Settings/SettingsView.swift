import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LockManager.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var settingPasscode = false
    @State private var settingVaultPasscode = false

    var body: some View {
        @Bindable var s = settings
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $s.theme) {
                        ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent Color")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(AccentPreset.all) { preset in
                                Circle()
                                    .fill(Color(hex: preset.hex))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if preset.hex == settings.accentHex {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture { settings.accentHex = preset.hex }
                                    .accessibilityLabel(preset.name)
                                    .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    ColorPicker("Custom Color", selection: Binding(
                        get: { settings.accentColor },
                        set: { settings.accentHex = $0.hexString }
                    ), supportsOpacity: false)
                    Picker("Font", selection: $s.fontStyle) {
                        ForEach(FontStyle.allCases) { Text($0.label).fontDesign($0.design).tag($0) }
                    }
                    Picker("Text Size", selection: $s.textSize) {
                        ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                    }
                    NavigationLink("App Icon") { AppIconPicker() }
                }

                Section("Layout") {
                    NavigationLink("Sidebar Sections") { SidebarSettingsView() }
                    Picker("Open On Launch", selection: $s.startSection) {
                        ForEach(settings.visibleSections) { Text(settings.title(for: $0)).tag($0) }
                    }
                    NavigationLink("Home Dashboard") { HomeCustomizeView() }
                    Toggle("Compact Lists", isOn: $s.compactLists)
                    Stepper("Note Preview Lines: \(settings.previewLines)", value: $s.previewLines, in: 0...5)
                        .disabled(settings.compactLists)
                    Picker("Sort Notes By", selection: $s.noteSort) {
                        ForEach(NoteSort.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Week Starts on Monday", isOn: $s.weekStartsMonday)
                    Toggle("Show Completed Tasks in All", isOn: $s.showCompletedInAll)
                }

                Section {
                    DatePicker("Default Reminder Time",
                               selection: AppSettings.timeBinding({ settings.defaultReminderMinutes }, { settings.defaultReminderMinutes = $0 }),
                               displayedComponents: .hourAndMinute)
                    Toggle("Daily Journal Reminder", isOn: $s.journalReminder)
                    if settings.journalReminder {
                        DatePicker("Journal Reminder Time",
                                   selection: AppSettings.timeBinding({ settings.journalReminderMinutes }, { settings.journalReminderMinutes = $0 }),
                                   displayedComponents: .hourAndMinute)
                    }
                    Toggle("Hide Text in Notifications", isOn: $s.hideNotificationText)
                    Button("Open iPhone Notification Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("The default time is used for all-day tasks, events and birthdays. Hiding text shows only “You have a reminder” on your lock screen.")
                }

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
                    Toggle("Hide Content in App Switcher", isOn: $s.blurInSwitcher)
                } header: {
                    Text("App Lock")
                }

                Section {
                    if Passcode.vault.isSet {
                        Button("Change Vault Passcode") { settingVaultPasscode = true }
                    }
                    if lock.biometryAvailable {
                        Toggle("Unlock Vault with \(lock.biometryName)", isOn: $s.vaultUseBiometrics)
                    }
                } header: {
                    Text("Vault")
                } footer: {
                    Text("The Vault has its own passcode and re-locks whenever you leave it or the app.")
                }

                Section {
                    NavigationLink("Backup & Restore") { BackupView() }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Hush has no accounts, no analytics and never connects to the internet. Your data stays on this iPhone and is left out of iCloud backups, so make your own backups.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
            }
            .hushBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $settingPasscode) {
                PasscodeSetupView { code in
                    Passcode.app.set(code)
                    settings.lockEnabled = true
                }
            }
            .sheet(isPresented: $settingVaultPasscode) {
                PasscodeSetupView(title: "Vault Passcode") { Passcode.vault.set($0) }
            }
        }
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

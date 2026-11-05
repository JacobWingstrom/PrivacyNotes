import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LockManager.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var settingPasscode = false

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
                }

                Section("Lists") {
                    Toggle("Compact Lists", isOn: $s.compactLists)
                    Stepper("Preview Lines: \(settings.previewLines)", value: $s.previewLines, in: 0...5)
                        .disabled(settings.compactLists)
                    Picker("Sort Notes By", selection: $s.noteSort) {
                        ForEach(NoteSort.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Sidebar") {
                    NavigationLink("Reorder, Rename & Hide Sections") { SidebarSettingsView() }
                    Picker("Open On Launch", selection: $s.startSection) {
                        ForEach(settings.visibleSections) { Text(settings.title(for: $0)).tag($0) }
                    }
                }

                Section {
                    Toggle("Passcode Lock", isOn: Binding(
                        get: { settings.lockEnabled },
                        set: { on in
                            if on {
                                settingPasscode = true
                            } else {
                                settings.lockEnabled = false
                                Passcode.clear()
                            }
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
                    Text("Privacy & Security")
                } footer: {
                    Text("Hush has no accounts, no analytics and never connects to the internet. Your notes stay on this iPhone.")
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
                    Passcode.set(code)
                    settings.lockEnabled = true
                }
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
            if !section.isReady {
                Text("Soon").font(.caption2).foregroundStyle(.secondary)
            }
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

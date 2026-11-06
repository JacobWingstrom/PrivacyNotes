import SwiftUI

// MARK: - Custom theme editor

struct CustomThemeEditor: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State var theme: CustomTheme
    var isNew = false

    var body: some View {
        HushForm {
            Section { ThemePreviewCard(palette: theme.palette, accent: Color(hex: theme.accent)) }
            Section {
                TextField("Theme name", text: $theme.name).font(.hush(.headline))
                Toggle("Dark Theme", isOn: $theme.dark)
                Menu {
                    ForEach(ThemeMode.allCases.filter { $0 != .custom && $0 != .system }) { t in
                        Button(t.label) {
                            let base = CustomTheme.from(Palette.forTheme(t, scheme: .dark), name: theme.name, accent: theme.accent)
                            var copy = base
                            copy.id = theme.id
                            theme = copy
                        }
                    }
                } label: { Label("Start from a Theme…", systemImage: "wand.and.stars") }
            }
            Section("Interface") {
                color("Background", $theme.background)
                color("Cards", $theme.surface)
                color("Fields", $theme.field)
                color("Borders", $theme.border)
                color("Text", $theme.text)
                color("Secondary text", $theme.dim)
                color("Accent", $theme.accent)
            }
            Section {
                color("Headings", $theme.heading)
                color("Bold", $theme.bold)
                color("Italic", $theme.italic)
                color("Code", $theme.code)
                color("Links", $theme.link)
                color("Lists", $theme.list)
            } header: { Text("Notes (syntax colors)") }
            if !isNew {
                Section {
                    Button("Delete Theme", role: .destructive) {
                        settings.customThemes.removeAll { $0.id == theme.id }
                        if settings.theme == .custom && settings.customThemes.isEmpty { settings.theme = .charcoal }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New Theme" : theme.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use Theme") {
                    if let i = settings.customThemes.firstIndex(where: { $0.id == theme.id }) { settings.customThemes[i] = theme }
                    else { settings.customThemes.append(theme) }
                    settings.customThemeID = theme.id
                    settings.theme = .custom
                    dismiss()
                }
            }
        }
    }

    private func color(_ label: String, _ hex: Binding<String>) -> some View {
        ColorPicker(label, selection: Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hexString }), supportsOpacity: false)
    }
}

/// A miniature note so you can see a theme before using it.
struct ThemePreviewCard: View {
    let palette: Palette
    let accent: Color

    var body: some View {
        let text = palette.text ?? (palette.isDark ? .white : .black)
        let dim = palette.secondaryText ?? .gray
        let s = palette.syntax
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.and.pencil").foregroundStyle(accent)
                Text("Notes").font(.headline).foregroundStyle(text)
                Spacer()
                Circle().fill(accent).frame(width: 22, height: 22).overlay(Image(systemName: "plus").font(.caption.bold()).foregroundStyle(.white))
            }
            VStack(alignment: .leading, spacing: 5) {
                (Text("## ").foregroundColor(dim) + Text("Weekend plan").foregroundColor(s.map { Color(hex: $0.heading) } ?? text)).font(.headline)
                (Text("- ").foregroundColor(s.map { Color(hex: $0.list) } ?? accent) + Text("Back up ").foregroundColor(text)
                    + Text("**NAS**").foregroundColor(s.map { Color(hex: $0.bold) } ?? text).bold()).font(.callout)
                (Text("See ").foregroundColor(text) + Text("[[Server notes]]").foregroundColor(s.map { Color(hex: $0.link) } ?? accent).underline()).font(.callout)
                Text("docker compose up -d").font(.system(.caption, design: .monospaced))
                    .foregroundStyle(s.map { Color(hex: $0.code) } ?? text)
                    .padding(4)
                    .background(palette.field, in: RoundedRectangle(cornerRadius: 4))
                Text("Modified today").font(.caption2).foregroundStyle(dim)
            }
            .padding(10)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border))
        }
        .padding(12)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 14))
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }
}

struct MyThemesSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Section {
            ForEach(settings.customThemes) { t in
                HStack {
                    Button {
                        settings.customThemeID = t.id
                        settings.theme = .custom
                    } label: {
                        HStack(spacing: 10) {
                            HStack(spacing: 2) {
                                ForEach([t.background, t.surface, t.accent, t.heading, t.code], id: \.self) { h in
                                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: h)).frame(width: 10, height: 22)
                                }
                            }
                            Text(t.name).foregroundStyle(.primary)
                            Spacer()
                            if settings.theme == .custom && settings.customThemeID == t.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    NavigationLink("") { CustomThemeEditor(theme: t) }.frame(width: 20)
                }
            }
            NavigationLink {
                CustomThemeEditor(theme: CustomTheme.from(settings.palette(for: scheme), name: "My Theme \(settings.customThemes.count + 1)",
                                                         accent: settings.accentHex), isNew: true)
            } label: { Label("Create a Theme", systemImage: "paintbrush.pointed") }
        } header: {
            Text("My Themes")
        } footer: {
            Text("Pick every color yourself, starting from the theme you're using now.")
        }
    }
}

// MARK: - Space look

struct SpaceDetailSettings: View {
    let spaceID: String
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let i = settings.spaces.firstIndex(where: { $0.id == spaceID }) {
            let sp = Binding(get: { settings.spaces[min(i, settings.spaces.count - 1)] }, set: { settings.spaces[i] = $0 })
            HushForm {
                Section {
                    TextField("Name", text: sp.name).font(.hush(.headline))
                    Picker("Icon", selection: sp.symbol) {
                        ForEach(SpaceInfo.symbols, id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                }
                Section {
                    Picker("Theme", selection: Binding(get: { sp.wrappedValue.theme ?? "" }, set: { sp.wrappedValue.theme = $0.isEmpty ? nil : $0 })) {
                        Text("Same as Main").tag("")
                        ForEach(ThemeMode.allCases.filter { $0 != .custom }) { Text($0.label).tag($0.rawValue) }
                        ForEach(settings.customThemes) { c in Text(c.name).tag("custom:" + c.id) }
                    }
                    .onChange(of: sp.wrappedValue.theme) { _, v in
                        if let v, v.hasPrefix("custom:") {
                            sp.wrappedValue.customThemeID = String(v.dropFirst(7))
                            sp.wrappedValue.theme = ThemeMode.custom.rawValue
                        }
                    }
                    Picker("Accent", selection: Binding(get: { sp.wrappedValue.accentHex ?? "" }, set: { sp.wrappedValue.accentHex = $0.isEmpty ? nil : $0 })) {
                        Text("Same as Main").tag("")
                        ForEach(AccentPreset.all) { Text($0.name).tag($0.hex) }
                    }
                } header: { Text("Look") } footer: {
                    Text("Switching to this space changes the app's look — handy for telling Work and Personal apart at a glance.")
                }
                Section {
                    Toggle("Own Home Layout", isOn: Binding(get: { sp.wrappedValue.ownHome == true }, set: { on in
                        if on && settings.spaceHomes[spaceID] == nil { settings.spaceHomes[spaceID] = settings.baseHomeWidgets }
                        sp.wrappedValue.ownHome = on
                    }))
                } footer: {
                    Text("Give this space its own Home widgets. It starts as a copy of your main Home.")
                }
            }
            .navigationTitle(sp.wrappedValue.name)
        }
    }
}

// MARK: - Editor preferences

struct EditorSettings: View {
    @AppStorage("editorFontScale") private var fontScale = 1.0
    @AppStorage("editorLineSpacing") private var lineSpacing = 3.0
    @AppStorage("editorParagraphSpacing") private var paragraphSpacing = 6.0
    @AppStorage("editorMaxWidth") private var maxWidth = 0.0
    @AppStorage("editorTypewriter") private var typewriter = false
    @AppStorage("editorAutocorrect") private var autocorrect = true
    @AppStorage("editorSpellCheck") private var spellCheck = true
    @AppStorage("editorSmartPunctuation") private var smartPunctuation = false
    @AppStorage("editorHideMarkers") private var hideMarkers = true
    @AppStorage("editorSlashCommands") private var slashCommands = true
    @AppStorage("editorFormatBar") private var formatBar = "both"
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HushForm {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes are easier to read when the lines aren't too long and have a little room to breathe.")
                        .font(.system(size: 17 * fontScale, design: settings.fontStyle.design))
                        .lineSpacing(lineSpacing)
                    Text("This is the second paragraph, so you can see the spacing between them.")
                        .font(.system(size: 17 * fontScale, design: settings.fontStyle.design))
                        .lineSpacing(lineSpacing)
                        .padding(.top, paragraphSpacing)
                }
                .padding(.vertical, 6)
            } header: { Text("Preview") }
            Section("Text") {
                slider("Text Size", $fontScale, 0.8...1.6, step: 0.05, label: "\(Int(fontScale * 100))%")
                slider("Line Spacing", $lineSpacing, 0...14, step: 1, label: "\(Int(lineSpacing))")
                slider("Paragraph Spacing", $paragraphSpacing, 0...24, step: 1, label: "\(Int(paragraphSpacing))")
                Picker("Line Width", selection: $maxWidth) {
                    Text("Full").tag(0.0)
                    Text("Wide").tag(720.0)
                    Text("Medium").tag(600.0)
                    Text("Narrow").tag(480.0)
                }
            }
            Section {
                Picker("Formatting Bar", selection: $formatBar) {
                    Text("Top & Keyboard").tag("both")
                    Text("Top of Note").tag("top")
                    Text("Above Keyboard").tag("keyboard")
                }
                Toggle("Hide Markdown Symbols", isOn: $hideMarkers)
                Toggle("Slash Commands", isOn: $slashCommands)
            } header: { Text("Formatting") } footer: {
                Text("With symbols hidden, notes look finished — the ** and ## only appear on the line you're editing. Type / at the start of a line to insert headings, lists, callouts, code, tables and more.")
            }
            Section {
                Toggle("Typewriter Scrolling", isOn: $typewriter)
            } footer: { Text("Keeps the line you're typing in the middle of the screen.") }
            Section("Typing") {
                Toggle("Autocorrect", isOn: $autocorrect)
                Toggle("Spell Check", isOn: $spellCheck)
                Toggle("Smart Quotes & Dashes", isOn: $smartPunctuation)
            }
        }
        .navigationTitle("Editor")
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(label).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range, step: step)
        }
    }
}

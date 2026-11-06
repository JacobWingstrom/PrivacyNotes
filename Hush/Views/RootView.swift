import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LockManager.self) private var lock
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var systemScheme
    @State private var showSettings = false

    var body: some View {
        let palette = settings.palette(for: systemScheme)
        let _ = Appearance.apply(palette)
        let themeKey = "\(settings.activeTheme.rawValue)-\(settings.activeCustomTheme?.id ?? "")-\(systemScheme == .dark ? "d" : "l")-\(settings.fontStyle.rawValue)-\(settings.currentSpace)"

        ZStack(alignment: .leading) {
            NavigationStack {
                SectionView(section: router.section)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            Button {
                                withAnimation(.snappy(duration: 0.25)) { router.drawerOpen = true }
                            } label: {
                                Image(systemName: "line.3.horizontal").font(.hush(.title3)).foregroundStyle(.primary)
                            }
                            .accessibilityLabel("Open menu")
                            SectionSwitcher()
                        }
                        ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) { BottomBar(showSettings: $showSettings) }
            }
            .id("\(router.section.rawValue)-\(themeKey)")

            if router.drawerOpen {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy(duration: 0.25)) { router.drawerOpen = false } }
                    .transition(.opacity)
                DrawerView { showSettings = true }
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }

            if lock.isLocked {
                LockScreen().transition(.opacity).zIndex(2)
            } else if settings.blurInSwitcher && phase != .active {
                PrivacyCover().zIndex(2)
            }
        }
        .environment(\.palette, palette)
        .animation(.easeOut(duration: 0.2), value: lock.isLocked)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.palette, palette)
                .foregroundStyle(palette.text.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                .font(.hush(.body))
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: "demoOpenDrawer") { router.drawerOpen = true }
            if UserDefaults.standard.bool(forKey: "demoOpenSettings") { showSettings = true }
        }
        .onChange(of: router.section) { _, _ in lock.vaultUnlocked = false }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .background: lock.didEnterBackground()
            case .active: lock.didBecomeActive(settings: settings)
            default: break
            }
        }
        .onChange(of: lock.isLocked) { _, locked in
            if locked { showSettings = false; router.drawerOpen = false }
        }
        .preferredColorScheme(settings.activeColorScheme)
        .tint(settings.accentColor)
        .foregroundStyle(palette.text.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
        .font(.hush(.body))
        .fontDesign(settings.fontStyle.design)
        .dynamicTypeSize(settings.textSize.dynamicType)
    }
}

/// Section icon + name + chevron; tap to jump to another section.
struct SectionSwitcher: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router

    var body: some View {
        Menu {
            ForEach(settings.visibleSections) { s in
                Button { router.go(s) } label: { Label(settings.title(for: s), systemImage: s.symbol) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: router.section.symbol).font(.hush(.headline)).foregroundStyle(settings.accentColor)
                Text(settings.title(for: router.section)).font(.hush(.title3).bold()).foregroundStyle(.primary)
                Image(systemName: "chevron.down").font(.hush(.caption).weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
        .accessibilityLabel("Section: \(settings.title(for: router.section)). Switch section")
    }
}

struct BottomBar: View {
    @Binding var showSettings: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(LockManager.self) private var lock
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @State private var settingPasscode = false

    var body: some View {
        @Bindable var s = settings
        HStack(spacing: 24) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
            Menu {
                Picker("Theme", selection: $s.theme) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: palette.isDark ? "moon" : "sun.max")
            } primaryAction: {
                settings.theme = palette.isDark ? .light : .charcoal
            }
            .accessibilityLabel("Theme. Tap to switch light or dark, hold for more")
            Button {
                if settings.lockEnabled && Passcode.app.isSet { lock.lockNow() } else { settingPasscode = true }
            } label: {
                Image(systemName: settings.lockEnabled ? "lock" : "lock.open")
            }
            .accessibilityLabel(settings.lockEnabled ? "Lock now" : "Set up app lock")
            Label("On device", systemImage: "checkmark.shield")
                .font(.hush(.footnote))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Your data is stored only on this device")
            Spacer(minLength: 0)
            if showsPlus {
                Button { router.create() } label: {
                    Image(systemName: "plus")
                        .font(.hush(.title2).weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(.tint))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .accessibilityLabel("New")
            }
        }
        .font(.hush(.title3))
        .foregroundStyle(.tint)
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .padding(.vertical, 8)
        .background(palette.background)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        .sheet(isPresented: $settingPasscode) {
            PasscodeSetupView(onSave: { code in
                Passcode.app.set(code)
                settings.lockEnabled = true
            }, onBiometrics: { settings.useBiometrics = $0 })
        }
    }

    private var showsPlus: Bool { !(router.section == .vault && !lock.vaultUnlocked) }
}

struct SectionView: View {
    let section: AppSection
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let title = settings.title(for: section)
        switch section {
        case .home: HomeView(title: title)
        case .all: AllItemsView(title: title)
        case .notes: NotesListView(title: title)
        case .tasks: TasksView(title: title)
        case .habits: HabitsView(title: title)
        case .boards: BoardsView(title: title)
        case .drawings: DrawingsView(title: title)
        case .vault: VaultView(title: title)
        case .files: FilesView(title: title)
        case .homelab: HomelabView(title: title)
        case .journals: JournalView(title: title)
        case .calendar: CalendarView(title: title)
        case .contacts: ContactsView(title: title)
        case .bookmarks: BookmarksView(title: title)
        }
    }
}

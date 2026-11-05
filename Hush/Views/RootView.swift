import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LockManager.self) private var lock
    @Environment(\.scenePhase) private var phase
    @State private var selection: AppSection?
    @State private var showSettings = false

    var body: some View {
        ZStack {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(settings.visibleSections) { section in
                        NavigationLink(value: section) {
                            Label(settings.title(for: section), systemImage: section.symbol)
                                .padding(.vertical, settings.compactLists ? 0 : 4)
                        }
                    }
                }
                .hushBackground()
                .navigationTitle("Hush")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                    }
                    if settings.lockEnabled {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { lock.lockNow() } label: { Image(systemName: "lock") }
                                .accessibilityLabel("Lock now")
                        }
                    }
                }
            } detail: {
                if let selection {
                    NavigationStack {
                        SectionView(section: selection)
                    }
                    .id(selection)
                } else {
                    ContentUnavailableView("Pick a section", systemImage: "sidebar.left")
                }
            }

            if lock.isLocked {
                LockScreen().transition(.opacity)
            } else if settings.blurInSwitcher && phase != .active {
                PrivacyCover()
            }
        }
        .animation(.easeOut(duration: 0.2), value: lock.isLocked)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { if selection == nil { selection = settings.effectiveStartSection } }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .background: lock.didEnterBackground()
            case .active: lock.didBecomeActive(settings: settings)
            default: break
            }
        }
        .onChange(of: lock.isLocked) { _, locked in
            if locked { showSettings = false }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .tint(settings.accentColor)
        .fontDesign(settings.fontStyle.design)
        .dynamicTypeSize(settings.textSize.dynamicType)
    }
}

struct SectionView: View {
    let section: AppSection
    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch section {
        case .notes, .all:
            NotesListView(title: settings.title(for: section))
        default:
            ComingSoonView(section: section, title: settings.title(for: section))
        }
    }
}

struct ComingSoonView: View {
    let section: AppSection
    let title: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: section.symbol)
        } description: {
            Text(section.comingSoonBlurb + "\n\nComing in a future update.")
        }
        .navigationTitle(title)
    }
}

import SwiftUI
import SwiftData
import WidgetKit

@main
struct HushApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: AppSettings
    @State private var lock = LockManager()
    @State private var router: Router
    @State private var phoneCalendar = PhoneCalendar()
    @Environment(\.scenePhase) private var scenePhase
    private let container = Storage.shared

    init() {
        let s = AppSettings()
        _settings = State(initialValue: s)
        _router = State(initialValue: Router(section: s.effectiveStartSection))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(lock)
                .environment(router)
                .environment(phoneCalendar)
                .onAppear {
                    DemoData.seedIfRequested(container.mainContext)
                    TrashActions.purgeExpired(container.mainContext)
                    ShareInbox.importPending(into: container.mainContext)
                    SyncEngine.shared.runTestIfRequested()
                    SyncEngine.shared.appBecameActive()
                    // Turn habit reminders back on once a vacation ends.
                    for h in (try? container.mainContext.fetch(FetchDescriptor<Habit>())) ?? [] where h.remind { Reminders.sync(h) }
                }
                .onOpenURL { url in router.handle(url) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        ShareInbox.importPending(into: container.mainContext)
                        SyncEngine.shared.appBecameActive()
                    }
                    if phase == .background {
                        SyncEngine.shared.appWentToBackground()
                        settings.syncWidgetPrivacy()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
        }
        .modelContainer(container)
    }
}


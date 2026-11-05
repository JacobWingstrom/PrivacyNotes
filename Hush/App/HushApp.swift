import SwiftUI
import SwiftData

@main
struct HushApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()
    @State private var lock = LockManager()
    private let container = Storage.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(lock)
        }
        .modelContainer(container)
    }
}

enum Storage {
    /// Everything lives in the app's private Application Support folder.
    /// iOS encrypts it with your device passcode; nothing ever leaves the phone.
    static func makeContainer() -> ModelContainer {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Store", isDirectory: true)
        let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: protection)
        try? fm.setAttributes(protection, ofItemAtPath: dir.path)

        var excluded = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true // keep data out of iCloud backups too
        try? excluded.setResourceValues(values)

        let config = ModelConfiguration(url: dir.appendingPathComponent("hush.store"), cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: Schema(Models.all), configurations: config)
        } catch {
            fatalError("Hush could not open its storage: \(error)")
        }
    }
}

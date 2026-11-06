import UIKit
import UserNotifications

/// Local notifications only: scheduled on this iPhone, no server involved.
enum Reminders {
    static let defaultMinutesKey = "defaultReminderMinutes"
    static let hideTextKey = "hideNotificationText"

    static var defaultMinutes: Int { UserDefaults.standard.object(forKey: defaultMinutesKey) as? Int ?? 540 }
    static var hideText: Bool { UserDefaults.standard.bool(forKey: hideTextKey) }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func schedule(id: String, title: String, body: String, at date: Date) {
        guard date > .now else { cancel(id); return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        add(id: id, title: title, body: body, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    static func scheduleRepeating(id: String, title: String, body: String, components: DateComponents) {
        add(id: id, title: title, body: body, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
    }

    private static func add(id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        let hidden = hideText
        Task {
            guard await requestPermission() else { return }
            let content = UNMutableNotificationContent()
            if hidden {
                content.title = "Hush"
                content.body = "You have a reminder."
            } else {
                content.title = title
                content.body = body
            }
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: Per-item sync

    static func sync(_ task: TaskItem) {
        syncLocation(task)
        let id = "task.\(task.id.uuidString)"
        if let date = task.reminderDate(defaultMinutes: defaultMinutes) {
            schedule(id: id, title: task.title.isEmpty ? "Task" : task.title,
                     body: task.notes.isEmpty ? "Task due" : task.notes, at: date)
        } else {
            cancel(id)
        }
    }

    static func sync(_ event: CalendarEvent) {
        let id = "event.\(event.id.uuidString)"
        guard event.alertMinutes >= 0 else { cancel(id); return }
        let base = event.isAllDay
            ? Calendar.current.startOfDay(for: event.start).addingTimeInterval(Double(defaultMinutes * 60))
            : event.start
        let when = base.addingTimeInterval(Double(-event.alertMinutes * 60))
        let time = event.isAllDay ? "Today" : event.start.formatted(date: .omitted, time: .shortened)
        schedule(id: id, title: event.title.isEmpty ? "Event" : event.title,
                 body: event.location.isEmpty ? time : "\(time) · \(event.location)", at: when)
    }

    static func sync(_ contact: Contact) {
        let id = "birthday.\(contact.id.uuidString)"
        guard contact.birthdayReminder, let bday = contact.birthday else { cancel(id); return }
        var comps = Calendar.current.dateComponents([.month, .day], from: bday)
        comps.hour = defaultMinutes / 60
        comps.minute = defaultMinutes % 60
        scheduleRepeating(id: id, title: "Birthday: \(contact.displayName)", body: "Say happy birthday today.", components: comps)
    }

    static func sync(_ habit: Habit) {
        let base = "habit.\(habit.id.uuidString)"
        let ids = ["\(base).daily"] + (1...7).map { "\(base).\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        guard habit.remind, !habit.archived, habit.deletedAt == nil else { return }
        let title = habit.name.trimmed.isEmpty ? "Habit" : habit.name.trimmed
        let body = habit.target > 1 ? "Time for your habit (\(habit.target)× today)" : "Time for your habit"
        var comps = DateComponents()
        comps.hour = habit.reminderMinutes / 60
        comps.minute = habit.reminderMinutes % 60
        if habit.days.isEmpty {
            scheduleRepeating(id: "\(base).daily", title: title, body: body, components: comps)
        } else {
            for d in habit.days {
                var c = comps
                c.weekday = d
                scheduleRepeating(id: "\(base).\(d)", title: title, body: body, components: c)
            }
        }
    }

    static func syncJournal(enabled: Bool, minutes: Int) {
        let id = "journal.daily"
        guard enabled else { cancel(id); return }
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        scheduleRepeating(id: id, title: "Journal", body: "Take a minute to write today's entry.", components: comps)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        TempFiles.clear()
        return true
    }

    /// Show reminders as banners even while Hush is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

/// Decrypted copies of files for previewing live here briefly and are wiped on launch and after use.
enum TempFiles {
    static var dir: URL { FileManager.default.temporaryDirectory.appendingPathComponent("hush-open", isDirectory: true) }

    static func write(_ data: Data, name: String) -> URL? {
        clear()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent(safe.isEmpty ? "file" : safe)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch { return nil }
    }

    static func clear() { try? FileManager.default.removeItem(at: dir) }
}

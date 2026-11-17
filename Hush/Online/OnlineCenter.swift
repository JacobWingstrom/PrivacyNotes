import Foundation
import BackgroundTasks
import WidgetKit

/// Decides when Hush goes online: on launch, every few minutes while open, and when iOS grants
/// a background refresh. Nothing runs unless you've added an account or a feed.
@MainActor
enum OnlineCenter {
    nonisolated static let refreshTaskID = "com.jacobwingstrom.hush.refresh"
    static let backgroundKey = "onlineBackgroundRefresh"

    private static var timer: Task<Void, Never>?

    static var isActive: Bool { MailEngine.shared.hasAccounts || FeedEngine.shared.hasFeeds }

    static func appBecameActive() {
        guard isActive else { return }
        timer?.cancel()
        timer = Task { @MainActor in
            while !Task.isCancelled {
                await refresh(background: false)
                try? await Task.sleep(nanoseconds: 3 * 60 * 1_000_000_000)
            }
        }
    }

    static func appWentToBackground() {
        timer?.cancel()
        timer = nil
        MailEngine.shared.disconnectAll()
        scheduleBackgroundRefresh()
        writeWidgetSnapshot()
    }

    static func refresh(background: Bool) async {
        let mail = MailEngine.shared
        if mail.hasAccounts {
            await mail.syncAll(includeDAV: true)
            if background { await mail.postNotifications() } else { mail.collectedNew = [] }
        }
        await FeedEngine.shared.refreshIfDue()
        writeWidgetSnapshot()
    }

    // MARK: Background refresh

    /// Must run before the app finishes launching.
    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let work = Task { @MainActor in
                scheduleBackgroundRefresh()
                await refresh(background: true)
                MailEngine.shared.disconnectAll()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        guard isActive, UserDefaults.standard.object(forKey: backgroundKey) as? Bool ?? true else { return }
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
    }

    // MARK: Widgets

    static func reloadWidgets() {
        writeWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Small summary for the Home Screen widgets (they can't decrypt mail themselves).
    static func writeWidgetSnapshot() {
        let ctx = Storage.shared.mainContext
        let inbox = (try? ctx.fetch(FetchDescriptor<MailMessage>(predicate: #Predicate { $0.folder == "INBOX" },
                                                                 sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let unread = inbox.filter { !$0.isSeen && !$0.isDeleted }
        let mail = unread.prefix(5).map { WidgetSnapshot.Line(title: $0.senderLabel, detail: $0.summary.subject) }

        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.reviewRaw == "pending" && $0.deletedAt == nil }))) ?? []
        let events = (try? ctx.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.reviewRaw == "pending" && $0.deletedAt == nil }))) ?? []
        let contacts = (try? ctx.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.reviewRaw == "pending" && $0.deletedAt == nil }))) ?? []
        var review: [WidgetSnapshot.Line] = events.map { .init(title: $0.title, detail: $0.start.formatted(date: .abbreviated, time: $0.isAllDay ? .omitted : .shortened)) }
        review += tasks.map { .init(title: $0.title, detail: $0.dueDate.map { "Due " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "Task") }
        review += contacts.map { .init(title: $0.displayName, detail: "Contact") }

        let articles = (try? ctx.fetch(FetchDescriptor<FeedArticle>(predicate: #Predicate { !$0.isRead }, sortBy: [SortDescriptor(\.published, order: .reverse)]))) ?? []
        let feeds = Dictionary(((try? ctx.fetch(FetchDescriptor<Feed>())) ?? []).map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { a, _ in a })
        let headlines = articles.prefix(6).map { WidgetSnapshot.Line(title: $0.title, detail: feeds[$0.feedID] ?? "") }

        let snap = WidgetSnapshot(updated: Date(), unreadMail: unread.count, mail: Array(mail), reviewCount: review.count,
                                  review: Array(review.prefix(5)), unreadArticles: articles.count, headlines: Array(headlines),
                                  hasMail: MailEngine.shared.hasAccounts, hasFeeds: !feeds.isEmpty)
        snap.save()
    }
}

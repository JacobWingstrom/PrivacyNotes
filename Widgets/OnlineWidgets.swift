import WidgetKit
import SwiftUI

struct OnlineEntry: TimelineEntry {
    let date: Date
    let hidden: Bool
    let snap: WidgetSnapshot
    let accent: Color
}

struct OnlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> OnlineEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping (OnlineEntry) -> Void) {
        completion(context.isPreview ? Self.sample : Self.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnlineEntry>) -> Void) {
        completion(Timeline(entries: [Self.current()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    static func current() -> OnlineEntry {
        OnlineEntry(date: .now, hidden: !WidgetData.showContent, snap: WidgetSnapshot.load(), accent: WidgetData.accent)
    }

    static var sample: OnlineEntry {
        OnlineEntry(date: .now, hidden: false, snap: WidgetSnapshot(
            updated: .now, unreadMail: 3,
            mail: [.init(title: "Lena", detail: "Dinner on Friday?"), .init(title: "mailbox.org", detail: "Your invoice")],
            reviewCount: 2, review: [.init(title: "Dinner with Lena", detail: "Fri 19:30"), .init(title: "Pay invoice", detail: "Due Nov 30")],
            unreadArticles: 12, headlines: [.init(title: "Self-hosting a mail server in 2026", detail: "Blog"), .init(title: "Release notes", detail: "Blog")],
            hasMail: true, hasFeeds: true), accent: .blue)
    }
}

private struct OnlineLockedView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill").font(.title2)
            Text("Hush is locked").font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LinesView: View {
    let symbol: String
    let title: String
    let count: Int
    let lines: [WidgetSnapshot.Line]
    let empty: String
    let accent: Color
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                if count > 0 {
                    Text("\(count)").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(accent)
                }
            }
            if lines.isEmpty {
                Spacer()
                Text(empty).font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(lines.prefix(family == .systemSmall ? 2 : (family == .systemLarge ? 6 : 3)).enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.title).font(.caption.weight(.medium)).lineLimit(family == .systemSmall ? 2 : 1)
                        if !line.detail.isEmpty {
                            Text(line.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct MailWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HushMail", provider: OnlineProvider()) { entry in
            Group {
                if entry.hidden { OnlineLockedView() } else if !entry.snap.hasMail {
                    Text("Add a mail account in Hush").font(.caption).foregroundStyle(.secondary)
                } else {
                    LinesView(symbol: "envelope", title: "Inbox", count: entry.snap.unreadMail, lines: entry.snap.mail, empty: "No unread mail", accent: entry.accent)
                }
            }
            .widgetURL(URL(string: "hush://open/mail"))
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mail")
        .description("Unread email in your inbox.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ReviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HushReview", provider: OnlineProvider()) { entry in
            Group {
                if entry.hidden { OnlineLockedView() } else {
                    LinesView(symbol: "checklist", title: "To Review", count: entry.snap.reviewCount, lines: entry.snap.review,
                              empty: "Nothing to review", accent: entry.accent)
                }
            }
            .widgetURL(URL(string: "hush://open/mail?review=1"))
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("To Review")
        .description("Events, tasks and contacts found in your email, waiting for you to confirm.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HeadlinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HushHeadlines", provider: OnlineProvider()) { entry in
            Group {
                if entry.hidden { OnlineLockedView() } else if !entry.snap.hasFeeds {
                    Text("Add feeds in Hush").font(.caption).foregroundStyle(.secondary)
                } else {
                    LinesView(symbol: "dot.radiowaves.up.forward", title: "Headlines", count: entry.snap.unreadArticles, lines: entry.snap.headlines,
                              empty: "All caught up", accent: entry.accent)
                }
            }
            .widgetURL(URL(string: "hush://open/feeds"))
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Headlines")
        .description("The newest unread posts from your feeds and subreddits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

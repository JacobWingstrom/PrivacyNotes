import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

@main
struct HushWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        HabitsWidget()
        QuickAddWidget()
    }
}

// MARK: - Data

struct HabitSnap: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let count: Int
    let target: Int
    let streak: Int
    var done: Bool { count >= target }
}

struct HushEntry: TimelineEntry {
    let date: Date
    let hidden: Bool
    let tasks: [(title: String, overdue: Bool)]
    let taskCount: Int
    let habits: [HabitSnap]
    let accent: Color
}

enum WidgetData {
    /// Respects the app lock: content is hidden unless allowed in Settings.
    static var showContent: Bool { AppGroup.defaults.object(forKey: "widgetsShowContent") as? Bool ?? true }
    static var accent: Color { Color(hex: AppGroup.defaults.string(forKey: "accentHex") ?? "4A8FE0") }

    @MainActor
    static func load() -> HushEntry {
        let now = Date()
        guard showContent else {
            return HushEntry(date: now, hidden: true, tasks: [], taskCount: 0, habits: [], accent: accent)
        }
        let ctx = Storage.shared.mainContext
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? [])
            .filter { $0.deletedAt == nil && !$0.isDone && ($0.dueDate.map { $0 < end } ?? false) }
            .sorted(by: TaskItem.order)
        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [])
            .filter { $0.deletedAt == nil && !$0.archived && $0.isScheduled(on: now) }
            .map { HabitSnap(id: $0.id.uuidString, name: $0.name, emoji: $0.emoji, count: $0.count(on: now),
                             target: max($0.target, 1), streak: $0.streak) }
        return HushEntry(date: now, hidden: false,
                         tasks: tasks.prefix(6).map { ($0.title, $0.isOverdue) }, taskCount: tasks.count,
                         habits: habits, accent: accent)
    }

    static var sample: HushEntry {
        HushEntry(date: .now, hidden: false, tasks: [("Call the dentist", false), ("Water plants", false)], taskCount: 2,
                  habits: [HabitSnap(id: "1", name: "Water", emoji: "💧", count: 3, target: 8, streak: 4),
                           HabitSnap(id: "2", name: "Read", emoji: "📖", count: 1, target: 1, streak: 12)],
                  accent: .blue)
    }
}

struct HushProvider: TimelineProvider {
    func placeholder(in context: Context) -> HushEntry { WidgetData.sample }

    func getSnapshot(in context: Context, completion: @escaping (HushEntry) -> Void) {
        if context.isPreview { completion(WidgetData.sample); return }
        Task { @MainActor in completion(WidgetData.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HushEntry>) -> Void) {
        Task { @MainActor in
            let entry = WidgetData.load()
            let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400 + 60)
            let soon = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(min(midnight, soon))))
        }
    }
}

private struct LockedView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill").font(.title2)
            Text("Hush is locked").font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HushToday", provider: HushProvider()) { entry in
            TodayView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Tasks due today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TodayView: View {
    let entry: HushEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.hidden { LockedView() } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(entry.accent)
                    Text(entry.taskCount == 0 ? "All clear" : "\(entry.taskCount) today").font(.headline)
                }
                if entry.tasks.isEmpty {
                    Text("Nothing due today.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(entry.tasks.prefix(family == .systemSmall ? 4 : (family == .accessoryRectangular ? 2 : 5)).enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 6) {
                        Image(systemName: "circle").font(.caption2).foregroundStyle(t.overdue ? .red : .secondary)
                        Text(t.title).font(.caption).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "hush://open/tasks"))
        }
    }
}

// MARK: - Habits (interactive)

struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HushHabits", provider: HushProvider()) { entry in
            HabitsWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Habits")
        .description("Check off today's habits right from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HabitsWidgetView: View {
    let entry: HushEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.hidden { LockedView() } else {
            let limit = family == .systemSmall ? 3 : (family == .systemMedium ? 4 : 9)
            let done = entry.habits.filter(\.done).count
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("Habits").font(.headline)
                    Spacer()
                    Text("\(done)/\(entry.habits.count)").font(.caption).foregroundStyle(.secondary)
                }
                if entry.habits.isEmpty {
                    Text("No habits today.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(entry.habits.prefix(limit)) { h in
                    Button(intent: ToggleHabitIntent(habitID: h.id)) {
                        HStack(spacing: 8) {
                            Text(h.emoji)
                            Text(h.name).font(.caption).lineLimit(1)
                            Spacer(minLength: 2)
                            if h.target > 1 && !h.done {
                                Text("\(h.count)/\(h.target)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(h.done ? entry.accent : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Quick add

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HushQuickAdd", provider: HushProvider()) { entry in
            QuickAddView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Add")
        .description("Start a note, task or journal entry in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickAddView: View {
    let entry: HushEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let items: [(String, String, String)] = [
            ("Note", "square.and.pencil", "notes"), ("Task", "checkmark.circle", "tasks"),
            ("Journal", "book.closed", "journals"), ("Habit", "flame", "habits"),
        ]
        let shown = family == .systemSmall ? Array(items.prefix(4)) : items
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: family == .systemSmall ? 2 : 4), spacing: 8) {
            ForEach(shown, id: \.2) { label, symbol, section in
                Link(destination: URL(string: "hush://new/\(section)")!) {
                    VStack(spacing: 4) {
                        Image(systemName: symbol).font(.title3)
                        Text(label).font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(entry.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(entry.accent)
                }
            }
        }
    }
}

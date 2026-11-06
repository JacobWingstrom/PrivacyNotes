import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import ActivityKit

@main
struct HushWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        HabitsWidget()
        QuickAddWidget()
        FocusLiveActivity()
        if #available(iOS 18.0, *) {
            NewNoteControl()
            NewTaskControl()
            TodaysNoteControl()
            FocusControl()
            MemoControl()
        }
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
                  habits: [HabitSnap(id: "1", name: "Water", emoji: "drop", count: 3, target: 8, streak: 4),
                           HabitSnap(id: "2", name: "Read", emoji: "book", count: 1, target: 1, streak: 12)],
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayView: View {
    let entry: HushEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.hidden {
            if family == .accessoryInline || family == .accessoryCircular { Image(systemName: "lock.fill") } else { LockedView() }
        } else if family == .accessoryInline {
            Label(entry.taskCount == 0 ? "No tasks today" : "\(entry.taskCount) tasks · \(entry.tasks.first?.title ?? "")", systemImage: "checkmark.circle")
        } else if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "checkmark.circle").font(.caption)
                    Text("\(entry.taskCount)").font(.title3.bold())
                }
            }
            .widgetURL(URL(string: "hush://open/tasks"))
        } else {
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

struct HabitsWidgetView: View {
    let entry: HushEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.hidden {
            if family == .accessoryCircular { Image(systemName: "lock.fill") } else { LockedView() }
        } else if family == .accessoryCircular {
            let done = entry.habits.filter(\.done).count
            Gauge(value: Double(done), in: 0...Double(max(entry.habits.count, 1))) {
                Image(systemName: "flame")
            } currentValueLabel: {
                Text("\(done)/\(entry.habits.count)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(URL(string: "hush://open/habits"))
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Label("Habits \(entry.habits.filter(\.done).count)/\(entry.habits.count)", systemImage: "flame").font(.headline)
                ForEach(entry.habits.filter { !$0.done }.prefix(2)) { h in
                    Text("○ \(h.name)").font(.caption).lineLimit(1)
                }
                if entry.habits.allSatisfy(\.done) && !entry.habits.isEmpty { Text("All done today").font(.caption) }
            }
            .widgetURL(URL(string: "hush://open/habits"))
        } else {
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
                            Image(systemName: SymbolName.resolve(h.emoji, fallback: "checkmark.circle")).foregroundStyle(entry.accent).frame(width: 18)
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

// MARK: - Focus timer Live Activity

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            let accent = Color(hex: context.attributes.accentHex)
            let s = context.state
            HStack(spacing: 14) {
                Image(systemName: s.phase == "focus" ? "timer" : "cup.and.saucer.fill")
                    .font(.title2)
                    .foregroundStyle(s.phase == "focus" ? accent : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.phase == "focus" ? "Focus · \(s.round)/\(s.rounds)" : "Break").font(.caption).foregroundStyle(.secondary)
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                Spacer()
                if s.paused {
                    Text(Self.format(s.remainingWhenPaused)).font(.system(.title, design: .rounded).monospacedDigit())
                } else {
                    Text(timerInterval: Date()...max(s.endsAt, Date()), countsDown: true)
                        .font(.system(.title, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            let accent = Color(hex: context.attributes.accentHex)
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.phase == "focus" ? "Focus" : "Break", systemImage: s.phase == "focus" ? "timer" : "cup.and.saucer.fill")
                        .foregroundStyle(s.phase == "focus" ? accent : .green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if s.paused { Text("Paused").foregroundStyle(.secondary) }
                    else { Text(timerInterval: Date()...max(s.endsAt, Date()), countsDown: true).monospacedDigit().frame(maxWidth: 70) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title).font(.caption).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: s.phase == "focus" ? "timer" : "cup.and.saucer.fill").foregroundStyle(s.phase == "focus" ? accent : .green)
            } compactTrailing: {
                if s.paused { Image(systemName: "pause.fill") }
                else { Text(timerInterval: Date()...max(s.endsAt, Date()), countsDown: true).monospacedDigit().frame(maxWidth: 44) }
            } minimal: {
                Image(systemName: "timer").foregroundStyle(accent)
            }
        }
    }

    static func format(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}


// MARK: - Control Center (iOS 18+)

@available(iOS 18.0, *)
private struct HushControl {
    static func button(_ kind: String, _ name: LocalizedStringResource, _ symbol: String, _ url: String) -> some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: url)!)) {
                Label(name, systemImage: symbol)
            }
        }
        .displayName(name)
    }
}

@available(iOS 18.0, *)
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration { HushControl.button("HushNewNote", "New Note", "square.and.pencil", "hush://new/notes") }
}

@available(iOS 18.0, *)
struct NewTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration { HushControl.button("HushNewTask", "New Task", "checkmark.circle", "hush://new/tasks") }
}

@available(iOS 18.0, *)
struct TodaysNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration { HushControl.button("HushDaily", "Today's Note", "sun.max", "hush://daily") }
}

@available(iOS 18.0, *)
struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration { HushControl.button("HushFocus", "Focus Timer", "timer", "hush://focus") }
}

@available(iOS 18.0, *)
struct MemoControl: ControlWidget {
    var body: some ControlWidgetConfiguration { HushControl.button("HushMemo", "Voice Memo", "mic", "hush://memo") }
}

import SwiftUI
import SwiftData
import EventKit
import WidgetKit
import QuickLook

/// Card frame shared by every Home widget.
struct WidgetFrame<Content: View>: View {
    let widget: HomeWidget
    var openSection: AppSection? = nil
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings

    var tint: Color { widget.tintHex.isEmpty ? settings.accentColor : Color(hex: widget.tintHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if widget.showHeader {
                HStack(spacing: 8) {
                    Image(systemName: widget.displaySymbol).foregroundStyle(tint)
                    Text(widget.displayTitle).font(.hush(.subheadline).weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let openSection {
                        Button { router.go(openSection) } label: {
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .accessibilityLabel("Open \(settings.title(for: openSection))")
                    }
                }
            }
            content
        }
        .tint(tint)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: widget.size == .large ? 300 : (widget.size == .small ? 150 : 0), alignment: .topLeading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.border))
    }
}

struct HomeWidgetView: View {
    let widget: HomeWidget

    var body: some View {
        switch widget.kind {
        case .greeting: GreetingWidget(widget: widget)
        case .quickAdd: QuickAddWidgetView(widget: widget)
        case .tasks: TasksWidgetView(widget: widget)
        case .board: BoardWidgetView(widget: widget)
        case .habits: HabitsHomeWidget(widget: widget)
        case .calendar: CalendarWidgetView(widget: widget)
        case .agenda: AgendaWidgetView(widget: widget)
        case .notes: NotesWidgetView(widget: widget)
        case .note: SingleNoteWidget(widget: widget)
        case .journal: JournalWidgetView(widget: widget)
        case .mood: MoodWidgetView(widget: widget)
        case .stats: StatsWidgetView(widget: widget)
        case .bookmarks: BookmarksWidgetView(widget: widget)
        case .contacts: ContactsWidgetView(widget: widget)
        case .countdown: CountdownWidgetView(widget: widget)
        case .files: FilesWidgetView(widget: widget)
        }
    }
}

private struct EmptyLine: View {
    let text: String
    var body: some View { Text(text).font(.hush(.subheadline)).foregroundStyle(.secondary) }
}

// MARK: - Greeting

struct GreetingWidget: View {
    let widget: HomeWidget
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(widget.title.trimmed.isEmpty ? greeting : widget.title).font(.hush(.title2).bold())
            if widget.showDate {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).foregroundStyle(.secondary)
            }
            if !widget.message.trimmed.isEmpty {
                Text(widget.message).font(.hush(.callout)).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello"
        }
    }
}

// MARK: - Quick add

struct QuickAddWidgetView: View {
    let widget: HomeWidget
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @State private var text = ""
    @State private var asTask = true
    @State private var added = false

    private let kinds: [(String, String, AppSection)] = [
        ("notes", "Note", .notes), ("tasks", "Task", .tasks), ("habits", "Habit", .habits), ("journals", "Journal", .journals),
        ("calendar", "Event", .calendar), ("bookmarks", "Link", .bookmarks), ("contacts", "Contact", .contacts), ("drawings", "Sketch", .drawings),
    ]

    var body: some View {
        WidgetFrame(widget: widget) {
            if widget.showQuickField {
                HStack(spacing: 10) {
                    Button { asTask.toggle() } label: {
                        Image(systemName: asTask ? "checkmark.circle" : "square.and.pencil").font(.title3)
                    }
                    .accessibilityLabel(asTask ? "Adding a task. Tap for note" : "Adding a note. Tap for task")
                    TextField(asTask ? "New task for today…" : "New note…", text: $text)
                        .submitLabel(.done)
                        .onSubmit(add)
                    if added { Image(systemName: "checkmark").foregroundStyle(.green).transition(.scale) }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 12))
            }
            let shown = kinds.filter { widget.quickKinds.contains($0.0) }
            if !shown.isEmpty {
                HStack(spacing: 8) {
                    ForEach(shown, id: \.0) { _, label, section in
                        Button { router.startNew(in: section) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: section.symbol).font(.system(size: 18))
                                Text(label).font(.hush(.caption2))
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func add() {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        if asTask {
            let task = TaskItem(title: t)
            task.dueDate = Calendar.current.startOfDay(for: .now)
            context.insert(task)
        } else {
            let n = Note()
            n.title = t
            context.insert(n)
        }
        text = ""
        withAnimation { added = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { added = false } }
    }
}

// MARK: - Tasks

struct TasksWidgetView: View {
    let widget: HomeWidget
    @Query private var tasksStored: [TaskItem]
    @Environment(AppSettings.self) private var settings

    private var items: [TaskItem] {
        let cal = Calendar.current
        let endToday = cal.startOfDay(for: .now).addingTimeInterval(86400)
        let all = tasksStored.live(settings.spaceFilter)
        var list: [TaskItem]
        switch widget.taskScope {
        case "upcoming": list = all.filter { t in t.dueDate.map { $0 >= endToday } ?? false }
        case "overdue": list = all.filter(\.isOverdue)
        case "all": list = all
        case "nodate": list = all.filter { $0.dueDate == nil }
        case "list": list = all.filter { $0.list == widget.listName }
        default: list = all.filter { t in t.dueDate.map { $0 < endToday } ?? false }
        }
        let open = list.filter { !$0.isDone }.sorted(by: TaskItem.order)
        let done = widget.showCompleted ? list.filter(\.isDone).filter { ($0.completedAt ?? .distantPast) > cal.startOfDay(for: .now) } : []
        return open + done
    }

    var body: some View {
        let list = items
        let shown = Array(list.prefix(widget.size == .small ? min(widget.limit, 4) : (widget.size == .large ? max(widget.limit, 10) : widget.limit)))
        WidgetFrame(widget: widget, openSection: .tasks) {
            if list.isEmpty { EmptyLine(text: widget.taskScope == "today" ? "Nothing due today." : "No tasks here.") }
            ForEach(shown) { t in
                HStack(spacing: 10) {
                    CheckButton(done: t.isDone, tint: t.priority.color) { withAnimation { TaskActions.toggle(t) } }
                    NavigationLink { TaskEditorView(task: t) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).lineLimit(1).strikethrough(t.isDone).foregroundStyle(t.isDone ? .secondary : .primary)
                            if widget.size != .small, let d = DateText.due(t), widget.taskScope != "today" || t.isOverdue {
                                Text(d).font(.hush(.caption)).foregroundStyle(t.isOverdue ? Color.red : Color.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .buttonStyle(.plain)
                }
            }
            if list.count > shown.count {
                Text("+ \(list.count - shown.count) more").font(.hush(.caption)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Board

struct BoardWidgetView: View {
    let widget: HomeWidget
    @Query(sort: \Board.sortIndex) private var boards: [Board]
    @Query(sort: \BoardCard.order) private var cards: [BoardCard]
    @Environment(\.palette) private var palette

    var body: some View {
        let board = boards.first { $0.id == widget.boardID && $0.deletedAt == nil } ?? boards.first { $0.deletedAt == nil && !$0.archived }
        WidgetFrame(widget: widget, openSection: .boards) {
            if let board {
                let mine = cards.filter { $0.boardID == board.id && $0.deletedAt == nil }
                if let colID = widget.columnID, let col = board.columns.first(where: { $0.id == colID }) {
                    let list = mine.filter { $0.columnID == col.id }
                    Text("\(board.title) · \(col.name)").font(.hush(.caption)).foregroundStyle(.secondary)
                    if list.isEmpty { Text("No cards here.").font(.hush(.subheadline)).foregroundStyle(.secondary) }
                    ForEach(list.prefix(widget.size == .large ? 10 : widget.limit)) { c in
                        NavigationLink { BoardView(board: board) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(c.color ?? Color.accentColor).frame(width: 7, height: 7)
                                Text(c.title).lineLimit(1)
                                Spacer(minLength: 0)
                                if let d = c.dueDate { Text(DateText.relativeDay(d)).font(.hush(.caption)).foregroundStyle(c.isOverdue ? Color.red : Color.secondary) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    NavigationLink { BoardView(board: board) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(board.title).font(.hush(.headline))
                            HStack(alignment: .bottom, spacing: 6) {
                                ForEach(board.columns) { col in
                                    let n = mine.filter { $0.columnID == col.id }.count
                                    VStack(spacing: 4) {
                                        Text("\(n)").font(.hush(.headline)).monospacedDigit()
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill((NoteColor(rawValue: col.colorName)?.color ?? Color.accentColor).opacity(0.8))
                                            .frame(height: CGFloat(6 + min(n, 12) * 4))
                                        Text(col.name).font(.hush(.caption2)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Create a board in Boards first.").font(.hush(.subheadline)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Habits

struct HabitsHomeWidget: View {
    let widget: HomeWidget
    @Query(sort: \Habit.sortIndex) private var habitsStored: [Habit]
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router

    var body: some View {
        let today = Date()
        let all = habitsStored.live(settings.spaceFilter).filter { !$0.archived }
        let chosen = widget.habitIDs.isEmpty ? all.filter { $0.isScheduled(on: today) } : all.filter { widget.habitIDs.contains($0.id) }
        let shown = Array(chosen.prefix(widget.size == .large ? 12 : (widget.size == .small ? 4 : 6)))
        let done = chosen.filter { $0.isDone(on: today) }.count
        WidgetFrame(widget: widget, openSection: .habits) {
            if chosen.isEmpty {
                Button("Start a habit") { router.startNew(in: .habits) }.font(.hush(.subheadline))
            } else if widget.habitStyle == "rings" {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: widget.size == .small ? 2 : 4), spacing: 10) {
                    ForEach(shown) { h in
                        VStack(spacing: 5) {
                            ZStack {
                                HabitCheck(habit: h, date: today, tint: h.color ?? settings.accentColor, size: widget.size == .small ? 46 : 52)
                                if !h.isDone(on: today) && h.target == 1 {
                                    SymbolIcon(name: h.emoji, fallback: "checkmark.circle").font(.system(size: 17)).foregroundStyle(.secondary)
                                        .allowsHitTesting(false)
                                }
                            }
                            Text(h.name).font(.hush(.caption2)).lineLimit(1)
                        }
                    }
                }
                Text("\(done) of \(chosen.count) done").font(.hush(.caption)).foregroundStyle(.secondary)
            } else {
                ForEach(shown) { h in
                    HStack(spacing: 10) {
                        SymbolTile(name: h.emoji, fallback: "checkmark.circle", tint: h.color ?? settings.accentColor, size: 30)
                        Text(h.name).lineLimit(1)
                        if h.streak > 0 && widget.size != .small {
                            Label("\(h.streak)", systemImage: "flame.fill").font(.hush(.caption).bold()).foregroundStyle(.orange)
                        }
                        Spacer()
                        HabitCheck(habit: h, date: today, tint: h.color ?? settings.accentColor, size: 30)
                    }
                }
            }
        }
    }
}

// MARK: - Calendar

struct CalendarWidgetView: View {
    let widget: HomeWidget
    @Environment(AppSettings.self) private var settings
    @Environment(PhoneCalendar.self) private var phone
    @Environment(Router.self) private var router
    @Query private var eventsStored: [CalendarEvent]
    @Query private var tasksStored: [TaskItem]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selected = Calendar.current.startOfDay(for: .now)

    var body: some View {
        let cal = settings.calendar
        var marked = Set<Date>()
        for e in eventsStored.live(settings.spaceFilter) { marked.insert(cal.startOfDay(for: e.start)) }
        if widget.includeTasks {
            for t in tasksStored.live(settings.spaceFilter) where !t.isDone { if let d = t.dueDate { marked.insert(cal.startOfDay(for: d)) } }
        }
        if widget.includePhoneEvents {
            let from = cal.date(byAdding: .month, value: -1, to: month) ?? month
            let to = cal.date(byAdding: .month, value: 2, to: month) ?? month
            for e in phone.events(from: from, to: to) { marked.insert(cal.startOfDay(for: e.startDate)) }
        }
        return WidgetFrame(widget: widget, openSection: .calendar) {
            MonthGrid(month: $month, selected: $selected, calendar: cal, marked: marked,
                      collapsed: widget.calendarStyle == "week" || widget.size == .medium)
        }
    }
}

// MARK: - Agenda

struct AgendaWidgetView: View {
    let widget: HomeWidget
    @Environment(AppSettings.self) private var settings
    @Environment(PhoneCalendar.self) private var phone
    @Query(sort: \CalendarEvent.start) private var eventsStored: [CalendarEvent]
    @Query private var tasksStored: [TaskItem]
    @State private var phoneRef: PhoneEventRef?

    private enum Item: Identifiable {
        case event(CalendarEvent), task(TaskItem), phone(EKEvent)
        var id: String {
            switch self {
            case .event(let e): "e\(e.id)"
            case .task(let t): "t\(t.id)"
            case .phone(let p): "p\(p.calendarItemIdentifier)\(p.startDate.timeIntervalSince1970)"
            }
        }
        var date: Date {
            switch self {
            case .event(let e): e.start
            case .task(let t): t.dueDate ?? .distantFuture
            case .phone(let p): p.startDate
            }
        }
    }

    var body: some View {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: max(widget.days, 1), to: start) ?? start
        var items: [Item] = eventsStored.live(settings.spaceFilter).filter { $0.end >= start && $0.start < end }.map { .event($0) }
        if widget.includeTasks {
            items += tasksStored.live(settings.spaceFilter).filter { t in !t.isDone && (t.dueDate.map { $0 >= start && $0 < end } ?? false) }.map { .task($0) }
        }
        if widget.includePhoneEvents { items += phone.events(from: start, to: end).map { .phone($0) } }
        items.sort { $0.date < $1.date }
        let shown = Array(items.prefix(widget.size == .large ? max(widget.limit, 10) : widget.limit))
        return WidgetFrame(widget: widget, openSection: .calendar) {
            if items.isEmpty { EmptyLine(text: "Nothing in the next \(widget.days) days.") }
            ForEach(shown) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(dayLabel(item.date)).font(.hush(.caption).weight(.semibold)).foregroundStyle(.tint).frame(width: 74, alignment: .leading)
                    switch item {
                    case .event(let e):
                        NavigationLink { EventEditorView(event: e) } label: { row(e.title.isEmpty ? "Event" : e.title, e.isAllDay ? nil : e.start, "calendar") }
                            .buttonStyle(.plain)
                    case .task(let t):
                        NavigationLink { TaskEditorView(task: t) } label: { row(t.title, t.hasDueTime ? t.dueDate : nil, "circle") }
                            .buttonStyle(.plain)
                    case .phone(let p):
                        Button { phoneRef = PhoneEventRef(event: p) } label: { row(p.title ?? "Event", p.isAllDay ? nil : p.startDate, "calendar", Color(cgColor: p.calendar.cgColor)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $phoneRef) { ref in PhoneEventEditor(store: phone.store, ref: ref).ignoresSafeArea() }
    }

    private func dayLabel(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "Today" : DateText.relativeDay(d).replacingOccurrences(of: ",", with: "")
    }

    private func row(_ title: String, _ time: Date?, _ symbol: String, _ color: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color ?? .secondary)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            if let time { Text(time.formatted(date: .omitted, time: .shortened)).font(.hush(.caption)).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Notes

struct NotesWidgetView: View {
    let widget: HomeWidget
    @Query(sort: \Note.updatedAt, order: .reverse) private var notesStored: [Note]
    @Query private var folders: [Folder]
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        let list = filtered(notesStored.live(settings.spaceFilter))
        let shown = Array(list.prefix(widget.size == .small ? min(widget.limit, 3) : (widget.size == .large ? max(widget.limit, 8) : widget.limit)))
        WidgetFrame(widget: widget, openSection: .notes) {
            if list.isEmpty { EmptyLine(text: widget.noteScope == "pinned" ? "Pin a note to see it here." : "No notes here yet.") }
            if widget.noteStyle == "cards" && widget.size != .small {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shown) { n in
                            NavigationLink { NoteEditorView(note: n) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 5) {
                                        if SymbolName.isValid(n.emoji) { Image(systemName: n.emoji).font(.caption).foregroundStyle(.tint) }
                                        Text(n.displayTitle).font(.hush(.subheadline).weight(.semibold)).lineLimit(2)
                                    }
                                    Text(n.plainPreview).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(widget.size == .large ? 7 : 3)
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(width: 150, height: widget.size == .large ? 180 : 104, alignment: .topLeading)
                                .background((n.color ?? Color.gray).opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ForEach(shown) { n in
                    NavigationLink { NoteEditorView(note: n) } label: {
                        HStack(spacing: 8) {
                            SymbolIcon(name: n.emoji, fallback: "doc.text").font(.caption).foregroundStyle(n.color ?? Color.secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.displayTitle).lineLimit(1)
                                if widget.size == .large && !n.plainPreview.isEmpty {
                                    Text(n.plainPreview).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if widget.size != .small {
                                Text(n.updatedAt, format: .relative(presentation: .named)).font(.hush(.caption2)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension NotesWidgetView {
    func filtered(_ all: [Note]) -> [Note] {
        switch widget.noteScope {
        case "pinned": return all.filter(\.isPinned)
        case "folder":
            guard let fid = widget.folderID else { return all }
            let ids = FolderPath.descendants(of: fid, in: folders)
            return all.filter { n in n.folderID.map(ids.contains) ?? false }
        case "tag": return all.filter { $0.tags.contains(widget.tag) }
        default: return all
        }
    }
}

struct SingleNoteWidget: View {
    let widget: HomeWidget
    @Query private var notes: [Note]

    var body: some View {
        let note = notes.first { $0.id == widget.noteID && $0.deletedAt == nil }
        WidgetFrame(widget: widget) {
            if let note {
                NavigationLink { NoteEditorView(note: note) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.displayTitle).font(.hush(.headline))
                        Text(Markdown.plain(note.body))
                            .font(.hush(.callout))
                            .foregroundStyle(.secondary)
                            .lineLimit(widget.size == .large ? 14 : (widget.size == .small ? 5 : 6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            } else {
                EmptyLine(text: "Choose a note in this widget's settings.")
            }
        }
    }
}

// MARK: - Journal & mood

struct JournalWidgetView: View {
    let widget: HomeWidget
    @Query(sort: \JournalEntry.date, order: .reverse) private var entriesStored: [JournalEntry]
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router

    var body: some View {
        let entries = entriesStored.live(settings.spaceFilter)
        let wroteToday = entries.contains { Calendar.current.isDateInToday($0.date) }
        let streak = JournalStats.streak(entries)
        WidgetFrame(widget: widget, openSection: .journals) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(streak)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(streak > 0 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                Text("day streak").font(.hush(.caption)).foregroundStyle(.secondary)
            }
            if widget.size != .small, let last = entries.first {
                Text(last.title.isEmpty ? Markdown.plain(last.body) : last.title).font(.hush(.subheadline)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if wroteToday {
                Label("Written today", systemImage: "checkmark").font(.hush(.caption)).foregroundStyle(.green)
            } else {
                Button { router.startNew(in: .journals) } label: { Label("Write", systemImage: "square.and.pencil") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
}

struct MoodWidgetView: View {
    let widget: HomeWidget
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    var body: some View {
        let today = entries.first { $0.deletedAt == nil && Calendar.current.isDateInToday($0.date) }
        let moods = Mood.allCases.filter { $0 != .none }
        WidgetFrame(widget: widget) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: widget.size == .small ? 3 : 5), spacing: 6) {
                ForEach(moods) { mood in
                    Button { set(mood, today) } label: {
                        Image(systemName: mood.symbol)
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(today?.mood == mood ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                            .background(today?.mood == mood ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.field), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mood.label)
                }
            }
            Text(today.map { $0.mood == .none ? "How are you today?" : "Feeling \($0.mood.label.lowercased())" } ?? "How are you today?")
                .font(.hush(.caption)).foregroundStyle(.secondary)
        }
    }

    private func set(_ mood: Mood, _ today: JournalEntry?) {
        let entry = today ?? {
            let e = JournalEntry()
            context.insert(e)
            return e
        }()
        entry.mood = entry.mood == mood ? .none : mood
        entry.updatedAt = .now
        if entry.isEmpty { context.delete(entry) }
    }
}

// MARK: - Stats

enum StatKind: String, CaseIterable, Identifiable {
    case notes, openTasks, tasksDoneToday, habitsToday, bestStreak, journalStreak, journals, bookmarks, contacts, files, words
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notes: "Notes"
        case .openTasks: "Open tasks"
        case .tasksDoneToday: "Done today"
        case .habitsToday: "Habits today"
        case .bestStreak: "Best habit streak"
        case .journalStreak: "Journal streak"
        case .journals: "Journal entries"
        case .bookmarks: "Bookmarks"
        case .contacts: "Contacts"
        case .files: "Files"
        case .words: "Words written"
        }
    }
    var symbol: String {
        switch self {
        case .notes: "square.and.pencil"
        case .openTasks: "circle"
        case .tasksDoneToday: "checkmark.circle"
        case .habitsToday: "flame"
        case .bestStreak: "trophy"
        case .journalStreak: "book.closed"
        case .journals: "books.vertical"
        case .bookmarks: "bookmark"
        case .contacts: "person.2"
        case .files: "folder"
        case .words: "text.alignleft"
        }
    }
}

struct StatsWidgetView: View {
    let widget: HomeWidget
    @Environment(AppSettings.self) private var settings
    @Query private var notes: [Note]
    @Query private var tasks: [TaskItem]
    @Query private var habits: [Habit]
    @Query private var journals: [JournalEntry]
    @Query private var bookmarks: [Bookmark]
    @Query private var contacts: [Contact]
    @Query private var files: [StoredFile]

    private func value(_ k: StatKind) -> String {
        let sp = settings.spaceFilter
        let today = Date()
        switch k {
        case .notes: return "\(notes.live(sp).count)"
        case .openTasks: return "\(tasks.live(sp).filter { !$0.isDone }.count)"
        case .tasksDoneToday: return "\(tasks.live(sp).filter { $0.isDone && ($0.completedAt.map(Calendar.current.isDateInToday) ?? false) }.count)"
        case .habitsToday:
            let due = habits.live(sp).filter { !$0.archived && $0.isScheduled(on: today) }
            return "\(due.filter { $0.isDone(on: today) }.count)/\(due.count)"
        case .bestStreak: return "\(habits.live(sp).map(\.streak).max() ?? 0)"
        case .journalStreak: return "\(JournalStats.streak(journals.live(sp)))"
        case .journals: return "\(journals.live(sp).count)"
        case .bookmarks: return "\(bookmarks.live(sp).count)"
        case .contacts: return "\(contacts.live(sp).count)"
        case .files: return "\(files.live(sp).count)"
        case .words: return notes.live(sp).reduce(0) { $0 + $1.wordCount }.formatted(.number.notation(.compactName))
        }
    }

    var body: some View {
        let kinds = widget.stats.compactMap(StatKind.init(rawValue:))
        WidgetFrame(widget: widget) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: widget.size == .small ? 2 : 4), spacing: 12) {
                ForEach(kinds) { k in
                    VStack(spacing: 3) {
                        Image(systemName: k.symbol).font(.caption).foregroundStyle(.tint)
                        Text(value(k)).font(.hush(.title3).bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        Text(k.label).font(.hush(.caption2)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Bookmarks, contacts, files

struct BookmarksWidgetView: View {
    let widget: HomeWidget
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var stored: [Bookmark]
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        let list = stored.live(settings.spaceFilter).filter { !widget.favoritesOnly || $0.isFavorite }
            .filter { widget.tag.isEmpty || $0.tags.contains(widget.tag) }
        let shown = Array(list.prefix(widget.size == .small ? 4 : (widget.size == .large ? max(widget.limit, 12) : widget.limit)))
        WidgetFrame(widget: widget, openSection: .bookmarks) {
            if list.isEmpty { EmptyLine(text: widget.favoritesOnly ? "Favorite a bookmark to see it here." : "No bookmarks yet.") }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: widget.size == .small ? 2 : 4), spacing: 10) {
                ForEach(shown) { b in
                    Button { if let u = b.url { openURL(u) } } label: {
                        VStack(spacing: 4) {
                            Text(String(b.host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                                .font(.hush(.headline))
                                .frame(width: 40, height: 40)
                                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.tint)
                            Text(b.displayTitle).font(.hush(.caption2)).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ContactsWidgetView: View {
    let widget: HomeWidget
    @Query private var stored: [Contact]
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let list = stored.live(settings.spaceFilter).filter { !widget.favoritesOnly || $0.isFavorite }.sorted { $0.sortKey < $1.sortKey }
        let shown = Array(list.prefix(widget.size == .small ? 3 : widget.limit))
        WidgetFrame(widget: widget, openSection: .contacts) {
            if list.isEmpty { EmptyLine(text: widget.favoritesOnly ? "Favorite a contact to see it here." : "No contacts yet.") }
            ForEach(shown) { c in
                HStack(spacing: 10) {
                    Avatar(text: c.initials, emoji: c.emoji, size: 32)
                    NavigationLink { ContactEditorView(contact: c) } label: { Text(c.displayName).lineLimit(1) }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if widget.size != .small {
                        if let p = c.phones.first?.value, let url = URL(string: "tel:\(p.filter { "+0123456789".contains($0) })") {
                            Link(destination: url) { Image(systemName: "phone.fill") }
                        }
                        if let p = c.phones.first?.value, let url = URL(string: "sms:\(p.filter { "+0123456789".contains($0) })") {
                            Link(destination: url) { Image(systemName: "message.fill") }.padding(.leading, 8)
                        }
                        if let e = c.emails.first?.value, let url = URL(string: "mailto:\(e)") {
                            Link(destination: url) { Image(systemName: "envelope.fill") }.padding(.leading, 8)
                        }
                    }
                }
            }
        }
    }
}

struct FilesWidgetView: View {
    let widget: HomeWidget
    @Query(sort: \StoredFile.createdAt, order: .reverse) private var stored: [StoredFile]
    @Environment(AppSettings.self) private var settings
    @State private var previewURL: URL?

    var body: some View {
        let list = stored.live(settings.spaceFilter)
        let shown = Array(list.prefix(widget.size == .small ? 3 : widget.limit))
        WidgetFrame(widget: widget, openSection: .files) {
            if list.isEmpty { EmptyLine(text: "No files yet.") }
            ForEach(shown) { f in
                Button {
                    if let data = DataCrypto.open(f.sealedData) { previewURL = TempFiles.write(data, name: f.name) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: FileIcon.symbol(for: f.typeIdentifier)).foregroundStyle(.tint).frame(width: 18)
                        Text(f.name).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, u in if u == nil { TempFiles.clear() } }
    }
}

// MARK: - Countdown

struct CountdownWidgetView: View {
    let widget: HomeWidget

    var body: some View {
        let cal = Calendar.current
        let target = cal.startOfDay(for: widget.targetDate ?? .now)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: target).day ?? 0
        WidgetFrame(widget: widget) {
            Text("\(abs(days))")
                .font(.system(size: widget.size == .small ? 44 : 56, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .monospacedDigit()
            Text(days == 0 ? "Today" : (days > 0 ? "day\(days == 1 ? "" : "s") to go" : "day\(days == -1 ? "" : "s") ago"))
                .font(.hush(.subheadline)).foregroundStyle(.secondary)
            Text(target.formatted(date: .abbreviated, time: .omitted)).font(.hush(.caption)).foregroundStyle(.tertiary)
        }
    }
}

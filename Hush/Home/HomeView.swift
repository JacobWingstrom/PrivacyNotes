import SwiftUI
import SwiftData
import EventKit

struct HomeView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @Environment(PhoneCalendar.self) private var phone
    @State private var phoneRef: PhoneEventRef?
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var choosing = false
    @State private var calMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var calSelected = Calendar.current.startOfDay(for: .now)
    @Query private var tasks: [TaskItem]
    @Query(sort: \CalendarEvent.start) private var events: [CalendarEvent]
    @Query(sort: \JournalEntry.date, order: .reverse) private var journals: [JournalEntry]
    @Query private var bookmarks: [Bookmark]
    @State private var customizing = false
    @State private var quickText = ""
    @State private var quickKind: QuickKind = .task
    @State private var added = false
    @State private var newNote: Note?
    @State private var newEntry: JournalEntry?

    enum QuickKind: String, CaseIterable, Identifiable {
        case task, note
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var symbol: String { self == .task ? "checkmark.circle" : "square.and.pencil" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if settings.showGreeting {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting).font(.title2.bold())
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
                ForEach(settings.visibleHomeBlocks) { block in
                    blockView(block)
                }
                if settings.visibleHomeBlocks.isEmpty {
                    ContentUnavailableView("Your Home is empty", systemImage: "house",
                                           description: Text("Tap Customize to choose what shows here."))
                }
            }
            .padding()
        }
        .background(palette.background)
        .navigationTitle(title)
        .onCreate(.home) { choosing = true }
        .sheet(item: $phoneRef) { ref in PhoneEventEditor(store: phone.store, ref: ref).ignoresSafeArea() }
        .newItemDialog(isPresented: $choosing)
        .navigationDestination(item: $newNote) { NoteEditorView(note: $0) }
        .navigationDestination(item: $newEntry) { JournalEditorView(entry: $0, isNew: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { customizing = true } label: { Image(systemName: "square.grid.2x2") }
                    .accessibilityLabel("Customize Home")
            }
        }
        .sheet(isPresented: $customizing) { NavigationStack { HomeCustomizeView() } }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello"
        }
    }

    @ViewBuilder
    private func blockView(_ block: HomeBlock) -> some View {
        switch block {
        case .quickAdd: quickAddCard
        case .mood: moodCard
        case .calendar: calendarCard
        case .today: todayCard
        case .upcoming: upcomingCard
        case .pinned: pinnedCard
        case .recentNotes: recentCard
        case .journal: journalCard
        case .stats: statsCard
        }
    }

    // MARK: Blocks

    private var quickAddCard: some View {
        Card(title: "Quick Add", symbol: "plus.circle") {
            HStack(spacing: 10) {
                Menu {
                    Picker("Type", selection: $quickKind) {
                        ForEach(QuickKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Image(systemName: quickKind.symbol).font(.title3).foregroundStyle(.tint)
                }
                .accessibilityLabel("Type: \(quickKind.label)")
                TextField(quickKind == .task ? "New task for today…" : "New note…", text: $quickText)
                    .submitLabel(.done)
                    .onSubmit(quickAdd)
                if added { Image(systemName: "checkmark").foregroundStyle(.green).transition(.scale) }
            }
        }
    }

    private var moodCard: some View {
        let today = journals.first { Calendar.current.isDateInToday($0.date) }
        return Card(title: "How are you today?", symbol: "face.smiling") {
            HStack(spacing: 8) {
                ForEach(Mood.allCases.filter { $0 != .none }) { mood in
                    Button {
                        let entry = today ?? {
                            let e = JournalEntry()
                            context.insert(e)
                            return e
                        }()
                        entry.mood = entry.mood == mood ? .none : mood
                        entry.updatedAt = .now
                        if entry.isEmpty { context.delete(entry) }
                    } label: {
                        Text(mood.emoji)
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(today?.mood == mood ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(palette.field),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mood.label)
                }
            }
            HStack {
                Text("Awful").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Great").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var calendarCard: some View {
        let cal = settings.calendar
        var marked = Set<Date>()
        for e in events { marked.insert(cal.startOfDay(for: e.start)) }
        for t in tasks where !t.isDone { if let d = t.dueDate { marked.insert(cal.startOfDay(for: d)) } }
        for j in journals { marked.insert(cal.startOfDay(for: j.date)) }
        return Card(title: "Calendar", symbol: "calendar.badge.clock") {
            MonthGrid(month: $calMonth, selected: $calSelected, calendar: cal, marked: marked)
            Button("Open Calendar") { router.go(.calendar) }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
    }

    private var todayCard: some View {
        let endOfToday = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400)
        let due = tasks.filter { t in !t.isDone && (t.dueDate.map { $0 < endOfToday } ?? false) }.sorted(by: TaskItem.order)
        let todayEvents = events.filter { $0.occurs(on: .now) }
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let phoneToday = phone.events(from: startOfToday, to: endOfToday)
        return Card(title: "Today", symbol: "sun.max") {
            ForEach(phoneToday.prefix(6), id: \.calendarItemIdentifier) { e in
                Button { phoneRef = PhoneEventRef(event: e) } label: { PhoneEventRow(event: e) }.buttonStyle(.plain)
            }
            if due.isEmpty && todayEvents.isEmpty && phoneToday.isEmpty {
                Text("Nothing due today. Enjoy it.").foregroundStyle(.secondary)
            }
            ForEach(todayEvents.prefix(4)) { e in
                NavigationLink { EventEditorView(event: e) } label: { EventRow(event: e) }.buttonStyle(.plain)
            }
            ForEach(due.prefix(8)) { t in
                HStack(spacing: 10) {
                    CheckButton(done: t.isDone, tint: t.priority.color) { withAnimation { TaskActions.toggle(t) } }
                    NavigationLink { TaskEditorView(task: t) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).lineLimit(1)
                            if t.isOverdue, let d = DateText.due(t) {
                                Text(d).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .buttonStyle(.plain)
                }
            }
            if due.count > 8 { Text("+ \(due.count - 8) more").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var upcomingCard: some View {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now).addingTimeInterval(86400)
        let end = start.addingTimeInterval(86400 * 7)
        let upcomingEvents = events.filter { $0.start >= start && $0.start < end }
        let upcomingTasks = tasks.filter { t in !t.isDone && (t.dueDate.map { $0 >= start && $0 < end } ?? false) }.sorted(by: TaskItem.order)
        return Card(title: "Next 7 Days", symbol: "calendar") {
            if upcomingEvents.isEmpty && upcomingTasks.isEmpty {
                Text("Nothing scheduled.").foregroundStyle(.secondary)
            }
            ForEach(upcomingEvents.prefix(5)) { e in
                NavigationLink { EventEditorView(event: e) } label: {
                    HStack {
                        Text(DateText.relativeDay(e.start)).font(.caption.weight(.semibold)).foregroundStyle(.tint).frame(width: 82, alignment: .leading)
                        Text(e.title.isEmpty ? "Event" : e.title).lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(upcomingTasks.prefix(5)) { t in
                NavigationLink { TaskEditorView(task: t) } label: {
                    HStack {
                        Text(t.dueDate.map(DateText.relativeDay) ?? "").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
                        Label(t.title, systemImage: "circle").lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pinnedCard: some View {
        let pinned = notes.filter(\.isPinned)
        return Card(title: "Pinned Notes", symbol: "pin") {
            if pinned.isEmpty {
                Text("Pin a note to keep it here.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pinned.prefix(12)) { n in
                            NavigationLink { NoteEditorView(note: n) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(n.emoji.isEmpty ? n.displayTitle : "\(n.emoji) \(n.displayTitle)")
                                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(n.preview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(width: 140, height: 100, alignment: .topLeading)
                                .background((n.color ?? Color.gray).opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var recentCard: some View {
        Card(title: "Recent Notes", symbol: "clock") {
            if notes.isEmpty { Text("No notes yet.").foregroundStyle(.secondary) }
            ForEach(notes.prefix(5)) { n in
                NavigationLink { NoteEditorView(note: n) } label: {
                    HStack {
                        Text(n.emoji.isEmpty ? n.displayTitle : "\(n.emoji) \(n.displayTitle)").lineLimit(1)
                        Spacer()
                        Text(n.updatedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var journalCard: some View {
        let wroteToday = journals.contains { Calendar.current.isDateInToday($0.date) }
        let streak = JournalStats.streak(journals)
        return Card(title: "Journal", symbol: "book.closed") {
            HStack {
                Label("\(streak) day streak", systemImage: "flame.fill").foregroundStyle(streak > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                Spacer()
                if wroteToday {
                    Label("Done today", systemImage: "checkmark").font(.subheadline).foregroundStyle(.green)
                } else {
                    Button("Write today's entry") {
                        let e = JournalEntry()
                        context.insert(e)
                        newEntry = e
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var statsCard: some View {
        Card(title: "At a Glance", symbol: "chart.bar") {
            HStack {
                stat(notes.count, "Notes")
                stat(tasks.filter { !$0.isDone }.count, "Open tasks")
                stat(journals.count, "Entries")
                stat(bookmarks.count, "Links")
            }
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title3.bold()).foregroundStyle(.tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func quickAdd() {
        let text = quickText.trimmed
        guard !text.isEmpty else { return }
        switch quickKind {
        case .task:
            let t = TaskItem(title: text)
            t.dueDate = Calendar.current.startOfDay(for: .now)
            context.insert(t)
        case .note:
            let n = Note()
            n.title = text
            context.insert(n)
        }
        quickText = ""
        withAnimation { added = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { added = false } }
    }
}

struct HomeCustomizeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var s = settings
        List {
            Section {
                Toggle("Show Greeting", isOn: $s.showGreeting)
            }
            Section {
                ForEach(settings.homeBlocks) { block in
                    Toggle(isOn: Binding(
                        get: { !settings.hiddenHomeBlocks.contains(block) },
                        set: { on in
                            if on { settings.hiddenHomeBlocks.remove(block) } else { settings.hiddenHomeBlocks.insert(block) }
                        })) {
                        Label(block.title, systemImage: block.symbol)
                    }
                }
                .onMove { s.homeBlocks.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Blocks")
            } footer: {
                Text("Drag to reorder. Switch off what you don't need.")
            }
            Section { Button("Reset Home", role: .destructive) { settings.resetHome() } }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customize Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

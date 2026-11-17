import SwiftUI
import SwiftData

enum TaskActions {
    static func toggle(_ task: TaskItem) {
        if !task.isDone, let due = task.dueDate, let next = task.repeatRule.next(after: due) {
            // Repeating task: move to the next occurrence instead of finishing.
            task.dueDate = next
            task.subtasks = task.subtasks.map { var s = $0; s.done = false; return s }
        } else {
            task.isDone.toggle()
            task.completedAt = task.isDone ? .now : nil
        }
        Reminders.sync(task)
    }

    static func delete(_ task: TaskItem, in context: ModelContext) {
        TrashActions.trash(task)
    }
}

struct TasksView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasksStored: [TaskItem]
    @Environment(AppSettings.self) private var tasksSpace
    private var tasks: [TaskItem] { tasksStored.live(tasksSpace.spaceFilter) }
    @State private var filter: TaskFilter = .today
    @State private var listFilter: String?
    @State private var quickTitle = ""
    @State private var search = ""
    @State private var newTask: TaskItem?
    @State private var focusing = false

    enum TaskFilter: String, CaseIterable, Identifiable {
        case today, upcoming, all, done
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private var lists: [String] {
        Array(Set(tasks.map(\.list).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [TaskItem] {
        let endOfToday = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400)
        var items = tasks.filter { t in
            (search.isEmpty || t.title.localizedCaseInsensitiveContains(search) || t.notes.localizedCaseInsensitiveContains(search))
            && (listFilter == nil || t.list == listFilter)
        }
        switch filter {
        case .today: items = items.filter { t in !t.isDone && (t.dueDate.map { $0 < endOfToday } ?? false) }
        case .upcoming: items = items.filter { t in !t.isDone && (t.dueDate.map { $0 >= endOfToday } ?? false) }
        case .all: items = items.filter { !$0.isDone }
        case .done:
            return items.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
        return items.sorted(by: TaskItem.order)
    }

    var body: some View {
        List {
            ReviewBanner()
            Picker("Show", selection: $filter) {
                ForEach(TaskFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .plainRow(top: 12, bottom: 4)
            if filter != .done {
                QuickAddField(prompt: "Try “Call mom tomorrow 5pm !high #family”",
                              text: $quickTitle, onSubmit: addQuick)
                    .plainRow(top: 8, bottom: quickTitle.isEmpty ? 8 : 2)
                if !quickTitle.trimmed.isEmpty {
                    ParsedPreview(parsed: TaskParser.parse(quickTitle)).plainRow(top: 0, bottom: 8)
                }
            }
            Section {
                ForEach(filtered) { task in
                    TaskRow(task: task)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { TaskActions.delete(task, in: context) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .hushRow()
                }
            } header: {
                if !filtered.isEmpty { ListHeader(title: listFilter ?? filter.label) }
            }
            if filtered.isEmpty { EmptyMessage(text: emptyText) }
        }
        .hushList()
        .animation(.default, value: filtered.map(\.id))
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchHeader(text: $search, prompt: "Search tasks…") {
                FilterButton(active: listFilter != nil) {
                    Picker("List", selection: $listFilter) {
                        Text("All lists").tag(String?.none)
                        ForEach(lists, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(item: $newTask) { TaskEditorView(task: $0, isNew: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { focusing = true } label: {
                    Image(systemName: FocusTimer.shared.isRunning ? "timer.circle.fill" : "timer")
                }
                .accessibilityLabel("Focus timer")
            }
        }
        .sheet(isPresented: $focusing) { FocusTimerView() }
        .onCreate(.tasks) {
            let t = TaskItem()
            if filter == .today { t.dueDate = Calendar.current.startOfDay(for: .now) }
            t.list = listFilter ?? ""
            context.insert(t)
            newTask = t
        }
    }

    private var emptyText: String {
        switch filter {
        case .today: "Nothing due today. Nice."
        case .upcoming: "Nothing upcoming."
        case .all: "No open tasks. Nice."
        case .done: "Finished tasks show up here."
        }
    }

    private func addQuick() {
        let text = quickTitle.trimmed
        guard !text.isEmpty else { return }
        let parsed = TaskParser.parse(text)
        let t = TaskItem(title: parsed.title)
        let today = Calendar.current.startOfDay(for: .now)
        if filter == .today { t.dueDate = today }
        if filter == .upcoming { t.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: today) }
        t.list = listFilter ?? ""
        TaskParser.apply(parsed, to: t)
        context.insert(t)
        Reminders.sync(t)
        quickTitle = ""
    }
}

struct TaskRow: View {
    @Bindable var task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CheckButton(done: task.isDone, tint: task.priority.color) {
                withAnimation { TaskActions.toggle(task) }
            }
            .padding(.top, 1)
            NavigationLink {
                TaskEditorView(task: task)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                    meta
                }
                .reviewStyle(task)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var meta: some View {
        let subs = task.subtasks
        let due = DateText.due(task)
        if due != nil || !subs.isEmpty || !task.list.isEmpty || task.priority != .none || task.locationRemind || task.focusMinutes > 0 {
            HStack(spacing: 8) {
                if let due {
                    Label(due, systemImage: task.remind ? "bell" : "calendar")
                        .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                }
                if task.repeatRule != .none { Image(systemName: "repeat") }
                if task.locationRemind && !task.locationName.isEmpty { Label(task.locationName, systemImage: "location") }
                if task.focusMinutes > 0 { Label("\(task.focusMinutes)m", systemImage: "timer") }
                if !subs.isEmpty { Label("\(subs.filter(\.done).count)/\(subs.count)", systemImage: "list.bullet") }
                if !task.list.isEmpty { Text(task.list) }
                if let c = task.priority.color {
                    Text(String(repeating: "!", count: task.priority.rawValue)).bold().foregroundStyle(c)
                }
            }
            .font(.hush(.caption))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
    }
}

struct TaskEditorView: View {
    @Bindable var task: TaskItem
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newSubtask = ""
    @State private var deleting = false
    @State private var focusing = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        HushForm {
            Section {
                TextField("Title", text: $task.title, axis: .vertical)
                    .font(.hush(.headline))
                    .focused($titleFocused)
                TextField("Notes", text: $task.notes, axis: .vertical)
                    .lineLimit(2...10)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { task.dueDate != nil },
                    set: { on in
                        task.dueDate = on ? Calendar.current.startOfDay(for: .now) : nil
                        if !on { task.remind = false; task.hasDueTime = false; task.repeatRule = .none }
                    })) { Label("Due Date", systemImage: "calendar") }
                if task.dueDate != nil {
                    DatePicker("Date", selection: Binding(get: { task.dueDate ?? .now }, set: { task.dueDate = $0 }),
                               displayedComponents: task.hasDueTime ? [.date, .hourAndMinute] : [.date])
                    Toggle(isOn: $task.hasDueTime) { Label("Time", systemImage: "clock") }
                    Toggle(isOn: $task.remind) { Label("Remind Me", systemImage: "bell") }
                    Picker(selection: $task.repeatRule) {
                        ForEach(RepeatRule.allCases) { Text($0.label).tag($0) }
                    } label: { Label("Repeat", systemImage: "repeat") }
                }
            } footer: {
                if task.remind && !task.hasDueTime {
                    Text("You'll be reminded at your default reminder time (Settings → Reminders).")
                }
            }

            if task.dueDate != nil && task.hasDueTime {
                Section {
                    Picker(selection: $task.durationMinutes) {
                        ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { m in Text(m < 60 ? "\(m) min" : "\(m / 60)\(m % 60 == 30 ? ".5" : "") h").tag(m) }
                    } label: { Label("Block Length", systemImage: "rectangle.split.1x2") }
                } footer: { Text("How much time this takes on the Calendar's Day timeline.") }
            }
            LocationReminderSection(task: task)
            Section {
                Button { focusing = true } label: {
                    HStack {
                        Label("Start Focus Timer", systemImage: "timer")
                        Spacer()
                        if task.focusMinutes > 0 { Text("\(task.focusMinutes) min so far").foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                Picker(selection: $task.priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                } label: { Label("Priority", systemImage: "exclamationmark.circle") }
                HStack {
                    Label("List", systemImage: "tray")
                    TextField("None", text: $task.list).multilineTextAlignment(.trailing)
                }
            }

            Section("Subtasks") {
                ForEach($task.subtasks) { $sub in
                    HStack(spacing: 10) {
                        CheckButton(done: sub.done) { sub.done.toggle() }
                        TextField("Subtask", text: $sub.title)
                            .strikethrough(sub.done)
                    }
                }
                .onDelete { task.subtasks.remove(atOffsets: $0) }
                .onMove { task.subtasks.move(fromOffsets: $0, toOffset: $1) }
                HStack(spacing: 10) {
                    Image(systemName: "plus").foregroundStyle(.tint)
                    TextField("Add subtask", text: $newSubtask)
                        .submitLabel(.done)
                        .onSubmit(addSubtask)
                }
            }

            if task.isDone, let done = task.completedAt {
                Section { LabeledContent("Completed", value: done.formatted(date: .abbreviated, time: .shortened)) }
            }

            Section {
                Button(task.isDone ? "Mark as Not Done" : "Mark as Done") { TaskActions.toggle(task) }
                Button("Delete Task", role: .destructive) {
                    deleting = true
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $focusing) { FocusTimerView(taskTitle: task.title, taskID: task.id) }
        .navigationTitle(isNew ? "New Task" : "Task")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if isNew { titleFocused = true } }
        .onChange(of: task.remind) { _, on in
            if on { Task { await Reminders.requestPermission() } }
        }
        .onDisappear {
            if task.title.trimmed.isEmpty && task.notes.trimmed.isEmpty {
                Reminders.cancel("task.\(task.id.uuidString)")
                context.delete(task)
            } else if deleting {
                TaskActions.delete(task, in: context)
            } else {
                if isNew && task.dueDate == nil {
                    let p = TaskParser.parse(task.title)
                    if p.hasExtras { TaskParser.apply(p, to: task) }
                }
                Reminders.sync(task)
            }
        }
    }

    private func addSubtask() {
        let text = newSubtask.trimmed
        guard !text.isEmpty else { return }
        task.subtasks.append(Subtask(title: text))
        newSubtask = ""
    }
}


/// Shows what the quick-add box understood before you press return.
struct ParsedPreview: View {
    let parsed: ParsedTask
    var body: some View {
        if parsed.hasExtras {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(parsed.title, "text.cursor")
                    if let d = parsed.dueDate {
                        chip(parsed.hasTime ? "\(DateText.relativeDay(d)), \(d.formatted(date: .omitted, time: .shortened))" : DateText.relativeDay(d),
                             parsed.hasTime ? "bell" : "calendar")
                    }
                    if parsed.priority != .none { chip(parsed.priority.label, "exclamationmark", parsed.priority.color) }
                    if !parsed.list.isEmpty { chip(parsed.list, "tray") }
                    if parsed.repeatRule != .none { chip(parsed.repeatRule.label, "repeat") }
                    if let m = parsed.minutes { chip("\(m) min", "timer") }
                }
            }
        }
    }

    private func chip(_ text: String, _ symbol: String, _ color: Color? = nil) -> some View {
        Label(text, systemImage: symbol)
            .font(.hush(.caption))
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background((color ?? Color.accentColor).opacity(0.15), in: Capsule())
            .foregroundStyle(color ?? Color.accentColor)
    }
}

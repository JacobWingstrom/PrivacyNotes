import SwiftUI
import SwiftData
import WidgetKit

struct HabitsView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Habit.sortIndex) private var habitsStored: [Habit]
    @State private var editing: Habit?
    @State private var showArchived = false
    @State private var todayOnly = false

    private var habits: [Habit] { habitsStored.live(settings.spaceFilter) }

    var body: some View {
        let today = Date()
        let active = habits.filter { !$0.archived && (!todayOnly || $0.isScheduled(on: today)) }
        let archived = habits.filter(\.archived)
        let due = active.filter { $0.isScheduled(on: today) }
        let doneCount = due.filter { $0.isDone(on: today) }.count
        List {
            if !active.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Today").font(.hush(.headline))
                        Spacer()
                        Text("\(doneCount) of \(due.count) done").font(.hush(.subheadline)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    ProgressView(value: due.isEmpty ? 0 : Double(doneCount), total: Double(max(due.count, 1)))
                        .tint(settings.accentColor)
                }
                .plainRow(top: 14, bottom: 8)
            }
            Section {
                ForEach(active) { h in
                    NavigationLink { HabitDetailView(habit: h) } label: { HabitRow(habit: h) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { TrashActions.trash(h) } label: { Label("Delete", systemImage: "trash") }
                            Button { editing = h } label: { Label("Edit", systemImage: "pencil") }
                        }
                        .hushRow()
                }
                .onMove { from, to in
                    var list = active
                    list.move(fromOffsets: from, toOffset: to)
                    for (i, h) in list.enumerated() { h.sortIndex = i }
                }
            }
            if showArchived && !archived.isEmpty {
                Section {
                    ForEach(archived) { h in
                        NavigationLink { HabitDetailView(habit: h) } label: { HabitRow(habit: h).opacity(0.6) }.hushRow()
                    }
                } header: { ListHeader(title: "Archived") }
            }
            if habits.isEmpty {
                EmptyMessage(text: "No habits yet. Tap + to start one — drink water, read, stretch, take vitamins…")
            }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text(today.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.hush(.subheadline).weight(.medium))
                Spacer()
                FilterButton(active: todayOnly || showArchived) {
                    Toggle("Only habits due today", isOn: $todayOnly)
                    Toggle("Show archived", isOn: $showArchived)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modifier(HeaderBackground())
        }
        .navigationTitle(title)
        .onCreate(.habits) {
            let h = Habit()
            h.sortIndex = (habits.map(\.sortIndex).max() ?? 0) + 1
            context.insert(h)
            editing = h
        }
        .sheet(item: $editing) { h in NavigationStack { HabitEditor(habit: h) } }
    }
}

private struct HeaderBackground: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content.background(palette.background).overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }
}

struct HabitRow: View {
    @Bindable var habit: Habit
    @Environment(\.palette) private var palette

    var body: some View {
        let today = Date()
        let tint = habit.color ?? Color.accentColor
        HStack(spacing: 12) {
            Text(habit.emoji.isEmpty ? "✅" : habit.emoji)
                .font(.hush(.title2))
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(habit.name.isEmpty ? "New Habit" : habit.name).font(.hush(.headline)).lineLimit(1)
                    if habit.streak > 0 {
                        Label("\(habit.streak)", systemImage: "flame.fill").font(.hush(.caption).bold()).foregroundStyle(.orange)
                    }
                    if habit.remind { Image(systemName: "bell").font(.hush(.caption2)).foregroundStyle(.secondary) }
                }
                WeekStrip(habit: habit, tint: tint)
            }
            Spacer(minLength: 4)
            HabitCheck(habit: habit, date: today, tint: tint, size: 40)
        }
        .padding(.vertical, 6)
    }
}

/// The last seven days; tap a day to mark it.
struct WeekStrip: View {
    @Bindable var habit: Habit
    let tint: Color

    var body: some View {
        let cal = Calendar.current
        let days = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now)) }
        HStack(spacing: 5) {
            ForEach(days, id: \.self) { d in
                let done = habit.isDone(on: d)
                let partial = !done && habit.count(on: d) > 0
                VStack(spacing: 2) {
                    Text(d.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9)).foregroundStyle(.secondary)
                    Circle()
                        .fill(done ? AnyShapeStyle(tint) : (partial ? AnyShapeStyle(tint.opacity(0.4)) : AnyShapeStyle(.quaternary)))
                        .frame(width: 14, height: 14)
                        .overlay {
                            if !habit.isScheduled(on: d) { Circle().stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2])) }
                        }
                }
                .onTapGesture { habit.tap(on: d); WidgetCenter.shared.reloadAllTimelines() }
                .accessibilityLabel("\(d.formatted(.dateTime.weekday(.wide))): \(done ? "done" : "not done")")
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

struct HabitCheck: View {
    @Bindable var habit: Habit
    let date: Date
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        let count = habit.count(on: date)
        let target = max(habit.target, 1)
        let done = count >= target
        Button {
            withAnimation(.snappy) { habit.tap(on: date) }
            WidgetCenter.shared.reloadAllTimelines()
        } label: {
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(min(count, target)) / CGFloat(target))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done {
                    Image(systemName: "checkmark").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(tint)
                } else if target > 1 {
                    Text("\(count)/\(target)").font(.system(size: size * 0.26, weight: .semibold)).monospacedDigit()
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .accessibilityLabel(done ? "Done" : "Mark done, \(count) of \(target)")
    }
}

struct HabitDetailView: View {
    @Bindable var habit: Habit
    @Environment(\.palette) private var palette
    @State private var editing = false
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    var body: some View {
        let tint = habit.color ?? Color.accentColor
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Text(habit.emoji).font(.system(size: 44))
                    VStack(alignment: .leading) {
                        Text(habit.name).font(.hush(.title2).bold())
                        Text(scheduleText).font(.hush(.subheadline)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HabitCheck(habit: habit, date: .now, tint: tint, size: 54)
                }
                .padding()
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 10) {
                    stat("\(habit.streak)", "Current streak", "flame.fill", .orange)
                    stat("\(habit.bestStreak)", "Best streak", "trophy.fill", .yellow)
                    stat("\(Int(habit.completionRate(lastDays: 30) * 100))%", "Last 30 days", "chart.bar.fill", tint)
                }

                HabitMonth(habit: habit, month: $month, tint: tint)
                    .padding()
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(palette.background)
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) { NavigationStack { HabitEditor(habit: habit) } }
    }

    private var scheduleText: String {
        let target = habit.target > 1 ? "\(habit.target)× a day" : "Once a day"
        if habit.days.isEmpty { return "\(target), every day" }
        let names = Calendar.current.shortWeekdaySymbols
        return "\(target), " + habit.days.map { names[$0 - 1] }.joined(separator: " ")
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.hush(.title3).bold()).monospacedDigit()
            Text(label).font(.hush(.caption2)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Month heat map; tap any past day to change it.
struct HabitMonth: View {
    @Bindable var habit: Habit
    @Binding var month: Date
    let tint: Color
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let cal = settings.calendar
        let first = cal.startOfDay(for: month)
        let range = cal.range(of: .day, in: .month, for: month) ?? 1..<31
        let offset = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: offset) + range.map { cal.date(byAdding: .day, value: $0 - 1, to: first) }
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let start = cal.firstWeekday - 1
        let ordered = Array(symbols[start...] + symbols[..<start])
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.hush(.headline))
                Spacer()
                Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                    .padding(.leading, 14)
            }
            .buttonStyle(.borderless)
            HStack(spacing: 0) {
                ForEach(ordered.indices, id: \.self) { i in
                    Text(ordered[i]).font(.hush(.caption2)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(cells.indices, id: \.self) { i in
                    if let d = cells[i] {
                        let future = d > Date()
                        let done = habit.isDone(on: d)
                        let partial = !done && habit.count(on: d) > 0
                        Text(d.formatted(.dateTime.day()))
                            .font(.hush(.caption).weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(done ? AnyShapeStyle(.white) : AnyShapeStyle(future ? .tertiary : .primary))
                            .background(done ? AnyShapeStyle(tint) : (partial ? AnyShapeStyle(tint.opacity(0.35)) : AnyShapeStyle(.quaternary.opacity(habit.isScheduled(on: d) ? 1 : 0.3))),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { if !future { habit.tap(on: d); WidgetCenter.shared.reloadAllTimelines() } }
                    } else {
                        Color.clear.frame(minHeight: 34)
                    }
                }
            }
        }
    }
}

struct HabitEditor: View {
    @Bindable var habit: Habit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    static let emojis = ["✅", "💧", "📖", "🏃", "🧘", "💊", "🥗", "😴", "🦷", "🚶", "🏋️", "🎸", "✍️", "🧹", "📵", "🌱", "☕️", "💰", "🙏", "🧠"]

    var body: some View {
        HushForm {
            Section {
                TextField("Habit name (e.g. Drink water)", text: $habit.name).font(.hush(.headline))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Text(e).font(.hush(.title2))
                                .frame(width: 42, height: 42)
                                .background(habit.emoji == e ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { habit.emoji = e }
                        }
                    }
                }
                Picker("Color", selection: $habit.colorName) {
                    ForEach(NoteColor.allCases) { Text($0 == .none ? "Accent" : $0.label).tag($0.rawValue) }
                }
            }
            Section {
                Stepper("\(habit.target)× per day", value: $habit.target, in: 1...30)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Days")
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = habit.days.isEmpty || habit.days.contains(d)
                            Text(Calendar.current.veryShortWeekdaySymbols[d - 1])
                                .font(.hush(.subheadline).weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Circle())
                                .foregroundStyle(on ? .white : .primary)
                                .onTapGesture { toggleDay(d) }
                                .accessibilityLabel(Calendar.current.weekdaySymbols[d - 1])
                                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text(habit.days.isEmpty ? "Every day." : "Only on the highlighted days.")
            }
            Section {
                Toggle("Reminder", isOn: $habit.remind)
                if habit.remind {
                    DatePicker("Time", selection: AppSettings.timeBinding({ habit.reminderMinutes }, { habit.reminderMinutes = $0 }),
                               displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("A notification at this time on the days above.")
            }
            Section {
                Toggle("Archived", isOn: $habit.archived)
                Button("Delete Habit", role: .destructive) {
                    TrashActions.trash(habit)
                    dismiss()
                }
            }
        }
        .navigationTitle(habit.name.isEmpty ? "New Habit" : "Edit Habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onChange(of: habit.remind) { _, on in if on { Task { await Reminders.requestPermission() } } }
        .onDisappear {
            if habit.name.trimmed.isEmpty && habit.log.isEmpty && habit.deletedAt == nil {
                context.delete(habit)
            } else {
                Reminders.sync(habit)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func toggleDay(_ d: Int) {
        var set = habit.days.isEmpty ? Array(1...7) : habit.days
        if let i = set.firstIndex(of: d) { set.remove(at: i) } else { set.append(d) }
        habit.days = set.count == 7 || set.isEmpty ? [] : set
    }
}

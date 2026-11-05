import SwiftUI
import SwiftData

struct CalendarView: View {
    let title: String
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarEvent.start) private var events: [CalendarEvent]
    @Query private var tasks: [TaskItem]
    @Query(sort: \JournalEntry.date, order: .reverse) private var journals: [JournalEntry]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var agenda = false
    @State private var newEvent: CalendarEvent?

    private var cal: Calendar { settings.calendar }

    var body: some View {
        List {
            if agenda {
                agendaSections
            } else {
                Section {
                    MonthGrid(month: $month, selected: $selected, calendar: cal, marked: markedDays)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                Section(DateText.relativeDay(selected) == "Today" ? "Today" : selected.formatted(.dateTime.weekday(.wide).month().day())) {
                    DayItems(day: selected, events: events, tasks: tasks, journals: journals)
                }
            }
        }
        .hushBackground()
        .navigationTitle(title)
        .navigationDestination(item: $newEvent) { EventEditorView(event: $0, isNew: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    agenda.toggle()
                } label: { Image(systemName: agenda ? "calendar" : "list.bullet") }
                .accessibilityLabel(agenda ? "Month view" : "Agenda view")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let start = cal.date(bySettingHour: Calendar.current.component(.hour, from: .now) + 1, minute: 0, second: 0, of: selected) ?? selected
                    let e = CalendarEvent(start: start)
                    context.insert(e)
                    newEvent = e
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("New event")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") {
                    selected = cal.startOfDay(for: .now)
                    month = cal.dateInterval(of: .month, for: .now)?.start ?? .now
                }
            }
        }
    }

    private var markedDays: Set<Date> {
        var days = Set<Date>()
        for e in events {
            var d = cal.startOfDay(for: e.start)
            let last = cal.startOfDay(for: max(e.end, e.start))
            var guardCount = 0
            while d <= last && guardCount < 62 {
                days.insert(d)
                d = cal.date(byAdding: .day, value: 1, to: d) ?? last.addingTimeInterval(1)
                guardCount += 1
            }
        }
        for t in tasks where !t.isDone { if let d = t.dueDate { days.insert(cal.startOfDay(for: d)) } }
        for j in journals { days.insert(cal.startOfDay(for: j.date)) }
        return days
    }

    @ViewBuilder private var agendaSections: some View {
        let today = cal.startOfDay(for: .now)
        let days = (0..<60).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .filter { markedDays.contains($0) }
        if days.isEmpty {
            ContentUnavailableView("Nothing in the next 60 days", systemImage: "calendar")
        }
        ForEach(days, id: \.self) { day in
            Section(DateText.relativeDay(day)) {
                DayItems(day: day, events: events, tasks: tasks, journals: journals)
            }
        }
    }
}

struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selected: Date
    let calendar: Calendar
    let marked: Set<Date>

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .padding(.leading, 16)
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)

            let symbols = weekdaySymbols
            HStack(spacing: 0) {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(symbols[i]).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }

            let cells = dayCells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] {
                        DayCell(day: day,
                                isSelected: calendar.isDate(day, inSameDayAs: selected),
                                isToday: calendar.isDateInToday(day),
                                hasItems: marked.contains(day))
                            .onTapGesture { selected = day }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -50 { shift(1) } else if v.translation.width > 50 { shift(-1) }
        })
    }

    private var weekdaySymbols: [String] {
        let s = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(s[start...] + s[..<start])
    }

    private var dayCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let first = calendar.startOfDay(for: month)
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: offset)
        for d in range { cells.append(calendar.date(byAdding: .day, value: d - 1, to: first)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func shift(_ months: Int) {
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let hasItems: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(.callout.weight(isToday || isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : (isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)))
                .frame(width: 32, height: 32)
                .background {
                    if isSelected { Circle().fill(.tint) }
                }
            Circle()
                .fill(hasItems ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (hasItems ? ", has items" : ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Everything that happens on one day: events, tasks due and journal entries.
struct DayItems: View {
    let day: Date
    let events: [CalendarEvent]
    let tasks: [TaskItem]
    let journals: [JournalEntry]

    var body: some View {
        let cal = Calendar.current
        let dayEvents = events.filter { $0.occurs(on: day) }
        let dayTasks = tasks.filter { t in t.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }.sorted(by: TaskItem.order)
        let dayJournals = journals.filter { cal.isDate($0.date, inSameDayAs: day) }

        if dayEvents.isEmpty && dayTasks.isEmpty && dayJournals.isEmpty {
            Text("Nothing planned").foregroundStyle(.secondary)
        }
        ForEach(dayEvents) { e in
            NavigationLink { EventEditorView(event: e) } label: { EventRow(event: e) }
        }
        ForEach(dayTasks) { t in TaskRow(task: t) }
        ForEach(dayJournals) { j in
            NavigationLink { JournalEditorView(entry: j) } label: {
                Label(j.title.isEmpty ? "Journal entry" : j.title, systemImage: "book.closed")
            }
        }
    }
}

struct EventRow: View {
    let event: CalendarEvent
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "New Event" : event.title)
                Group {
                    if event.isAllDay {
                        Text("All day")
                    } else {
                        Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if event.alertMinutes >= 0 { Image(systemName: "bell").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct EventEditorView: View {
    @Bindable var event: CalendarEvent
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @FocusState private var titleFocused: Bool

    static let alertOptions: [(Int, String)] = [
        (-1, "None"), (0, "At time of event"), (5, "5 minutes before"), (15, "15 minutes before"),
        (30, "30 minutes before"), (60, "1 hour before"), (120, "2 hours before"), (1440, "1 day before"),
    ]

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $event.title).font(.headline).focused($titleFocused)
                TextField("Location", text: $event.location)
            }
            Section {
                Toggle("All Day", isOn: $event.isAllDay)
                DatePicker("Starts", selection: $event.start,
                           displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $event.end, in: event.start...,
                           displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
            }
            Section {
                Picker("Alert", selection: $event.alertMinutes) {
                    ForEach(Self.alertOptions, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Color", selection: $event.colorName) {
                    ForEach(NoteColor.allCases) { c in
                        Text(c == .none ? "Accent" : c.label).tag(c.rawValue)
                    }
                }
            }
            Section("Notes") {
                TextField("Notes", text: $event.notes, axis: .vertical).lineLimit(3...12)
            }
            Section {
                Button("Delete Event", role: .destructive) {
                    deleting = true
                    dismiss()
                }
            }
        }
        .hushBackground()
        .navigationTitle(isNew ? "New Event" : "Event")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if isNew { titleFocused = true } }
        .onChange(of: event.start) { old, new in
            // keep the same duration when the start moves
            let duration = max(event.end.timeIntervalSince(old), 0)
            event.end = new.addingTimeInterval(duration)
        }
        .onChange(of: event.alertMinutes) { _, v in
            if v >= 0 { Task { await Reminders.requestPermission() } }
        }
        .onDisappear {
            if deleting || (isNew && event.title.trimmed.isEmpty) {
                Reminders.cancel("event.\(event.id.uuidString)")
                context.delete(event)
            } else {
                if event.end < event.start { event.end = event.start }
                Reminders.sync(event)
            }
        }
    }
}

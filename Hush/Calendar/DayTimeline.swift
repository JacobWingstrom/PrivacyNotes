import SwiftUI
import SwiftData
import EventKit

/// A day as an hour grid. Drag a task onto an hour to block out time for it.
struct DayTimeline: View {
    let day: Date
    let events: [CalendarEvent]
    let tasks: [TaskItem]
    let phoneEvents: [EKEvent]
    var onOpenPhone: (EKEvent) -> Void = { _ in }
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @State private var editingTask: TaskItem?
    @State private var editingEvent: CalendarEvent?
    @State private var targetHour: Int?

    private let hourHeight: CGFloat = 64
    private let firstHour = 0
    private let lastHour = 24

    private struct Block: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: Color
        let symbol: String
        let action: () -> Void
    }

    var body: some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayTasks = tasks.filter { t in !t.isDone && (t.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false) }
        let unscheduled = dayTasks.filter { !$0.hasDueTime }
        var blocks: [Block] = events.filter { !$0.isAllDay && $0.occurs(on: day) }.map { e in
            let occ = e.occurrence(on: day) ?? (start: e.start, end: e.end)
            return Block(id: "e\(e.id)", title: e.title.isEmpty ? "Event" : e.title, start: occ.start, end: max(occ.end, occ.start.addingTimeInterval(900)),
                  color: e.color ?? settings.accentColor, symbol: "calendar") { editingEvent = e }
        }
        blocks += dayTasks.filter(\.hasDueTime).compactMap { t in
            guard let d = t.dueDate else { return nil }
            return Block(id: "t\(t.id)", title: t.title, start: d, end: d.addingTimeInterval(Double(max(t.durationMinutes, 15) * 60)),
                         color: t.priority.color ?? .teal, symbol: "checkmark.circle") { editingTask = t }
        }
        blocks += phoneEvents.filter { !$0.isAllDay && $0.occurs(on: day) }.map { e in
            Block(id: "p\(e.calendarItemIdentifier)\(e.startDate.timeIntervalSince1970)", title: e.title ?? "Event", start: e.startDate,
                  end: max(e.endDate, e.startDate.addingTimeInterval(900)), color: Color(cgColor: e.calendar.cgColor), symbol: "calendar") { onOpenPhone(e) }
        }
        let allDay = events.filter { $0.isAllDay && $0.occurs(on: day) }.map(\.title) + phoneEvents.filter { $0.isAllDay && $0.occurs(on: day) }.map { $0.title ?? "Event" }

        return VStack(alignment: .leading, spacing: 10) {
            if !allDay.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(allDay.indices, id: \.self) { i in TagChip(text: allDay[i], selected: false) {} } }
                }
            }
            if !unscheduled.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Drag onto the timeline to schedule").font(.hush(.caption)).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(unscheduled) { t in
                                Label(t.title, systemImage: "circle")
                                    .font(.hush(.subheadline))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(palette.surface, in: Capsule())
                                    .overlay(Capsule().stroke(palette.border))
                                    .draggable(t.id.uuidString)
                                    .onTapGesture { editingTask = t }
                            }
                        }
                    }
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(firstHour..<lastHour, id: \.self) { h in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(hourLabel(h)).font(.hush(.caption2)).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                                        .offset(y: -6)
                                    Rectangle().fill(targetHour == h ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Color.clear))
                                        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
                                }
                                .frame(height: hourHeight)
                                .id(h)
                                .contentShape(Rectangle())
                                .dropDestination(for: String.self) { items, loc in
                                    schedule(items, hour: h, minute: loc.y > hourHeight / 2 ? 30 : 0)
                                } isTargeted: { on in targetHour = on ? h : (targetHour == h ? nil : targetHour) }
                            }
                        }
                        ForEach(layout(blocks, dayStart: dayStart), id: \.0.id) { b, col, cols in
                            let top = CGFloat(b.start.timeIntervalSince(dayStart) / 3600) * hourHeight
                            let height = max(CGFloat(b.end.timeIntervalSince(b.start) / 3600) * hourHeight - 2, 24)
                            GeometryReader { geo in
                                let width = (geo.size.width - 56) / CGFloat(cols)
                                Button(action: b.action) {
                                    HStack(alignment: .top, spacing: 5) {
                                        Image(systemName: b.symbol).font(.caption2)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(b.title).font(.hush(.caption).weight(.semibold)).lineLimit(height > 40 ? 2 : 1)
                                            if height > 38 {
                                                Text("\(b.start.formatted(date: .omitted, time: .shortened)) – \(b.end.formatted(date: .omitted, time: .shortened))")
                                                    .font(.hush(.caption2)).opacity(0.8)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(6)
                                    .frame(width: width - 3, height: height, alignment: .topLeading)
                                    .background(b.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(b.color).frame(width: 3) }
                                    .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                                .draggable(b.id.hasPrefix("t") ? String(b.id.dropFirst()) : "")
                                .offset(x: 52 + width * CGFloat(col), y: top)
                            }
                            .frame(height: hourHeight * CGFloat(lastHour - firstHour))
                            .allowsHitTesting(true)
                        }
                        if Calendar.current.isDateInToday(day) {
                            let now = CGFloat(Date().timeIntervalSince(dayStart) / 3600) * hourHeight
                            HStack(spacing: 0) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Rectangle().fill(.red).frame(height: 1.5)
                            }
                            .offset(x: 48, y: now - 4)
                            .allowsHitTesting(false)
                        }
                    }
                    .padding(.trailing, 8)
                }
                .onAppear { proxy.scrollTo(max(Calendar.current.component(.hour, from: Date()) - 1, 7), anchor: .top) }
            }
        }
        .sheet(item: $editingTask) { t in NavigationStack { TaskEditorView(task: t) } }
        .sheet(item: $editingEvent) { e in NavigationStack { EventEditorView(event: e) } }
    }

    private func hourLabel(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h % 24, minute: 0, second: 0, of: day) ?? day
        return d.formatted(.dateTime.hour())
    }

    /// Side-by-side columns for overlapping blocks.
    private func layout(_ blocks: [Block], dayStart: Date) -> [(Block, Int, Int)] {
        let sorted = blocks.sorted { $0.start < $1.start }
        var out: [(Block, Int, Int)] = []
        var group: [(Block, Int)] = []
        var groupEnd = Date.distantPast
        func flush() {
            let cols = (group.map(\.1).max() ?? 0) + 1
            out += group.map { ($0.0, $0.1, cols) }
            group = []
        }
        for b in sorted {
            if b.start >= groupEnd { flush(); groupEnd = .distantPast }
            var col = 0
            while group.contains(where: { $0.1 == col && $0.0.end > b.start }) { col += 1 }
            group.append((b, col))
            groupEnd = max(groupEnd, b.end)
        }
        flush()
        return out
    }

    private func schedule(_ items: [String], hour: Int, minute: Int) -> Bool {
        targetHour = nil
        guard let s = items.first, let id = UUID(uuidString: s), let t = tasks.first(where: { $0.id == id }) else { return false }
        let when = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        withAnimation(.snappy) {
            t.dueDate = when
            t.hasDueTime = true
        }
        Reminders.sync(t)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return true
    }
}

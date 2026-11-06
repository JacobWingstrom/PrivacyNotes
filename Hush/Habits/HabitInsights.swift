import SwiftUI
import SwiftData
import Charts
import WidgetKit

// MARK: - Logging a number

struct MeasureEntrySheet: View {
    @Bindable var habit: Habit
    var date: Date = .now
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var quick: [Double] {
        switch habit.unit.lowercased() {
        case "ml": [250, 500, 750]
        case "l": [0.25, 0.5, 1]
        case "oz": [8, 12, 16]
        case "glasses", "cups": [1, 2]
        case "steps": [1000, 2500, 5000]
        case "min", "minutes": [10, 15, 30]
        case "h", "hours": [0.5, 1]
        default: []
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                SymbolTile(name: habit.emoji, fallback: "chart.line.uptrend.xyaxis", tint: habit.color ?? .accentColor, size: 56)
                Text(habit.name).font(.hush(.title3).bold())
                if let v = habit.value(on: date) {
                    Text("\(habit.sumEntries ? "So far" : "Logged"): \(v.formatted(.number.precision(.fractionLength(0...2)))) \(habit.unit)")
                        .font(.hush(.subheadline)).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("0", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                    Text(habit.unit).font(.hush(.title3)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
                if !quick.isEmpty && habit.sumEntries {
                    HStack {
                        ForEach(quick, id: \.self) { q in
                            Button("+\(q.formatted()) \(habit.unit)") { save(q) }.buttonStyle(.bordered)
                        }
                    }
                }
                if habit.goalValue > 0 { Text("Goal: \(habit.formattedGoal)").font(.hush(.caption)).foregroundStyle(.secondary) }
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(habit.sumEntries ? "Add" : "Save") { save(Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0) }
                        .disabled(Double(text.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save(_ v: Double) {
        habit.record(v, on: date)
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}

// MARK: - Charts

struct HabitCharts: View {
    @Bindable var habit: Habit
    @Environment(\.palette) private var palette
    @State private var range = 30

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let done: Bool
        let skipped: Bool
        var id: Date { date }
    }

    private var points: [Point] {
        let cal = Calendar.current
        return (0..<range).reversed().compactMap { i in
            guard let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: .now)) else { return nil }
            let v = habit.isMeasure ? (habit.value(on: d) ?? 0) : Double(habit.count(on: d))
            return Point(date: d, value: v, done: habit.isDone(on: d), skipped: habit.isSkipped(on: d))
        }
    }

    var body: some View {
        let tint = habit.color ?? Color.accentColor
        let pts = points
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(habit.isMeasure ? "\(habit.unit.isEmpty ? "Value" : habit.unit.capitalized) over time" : "Completions").font(.hush(.headline))
                Spacer()
                Picker("Range", selection: $range) {
                    Text("2W").tag(14); Text("1M").tag(30); Text("3M").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            Chart {
                ForEach(pts) { p in
                    if habit.isMeasure && !habit.sumEntries {
                        if p.value > 0 {
                            LineMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value))
                                .foregroundStyle(tint)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value))
                                .foregroundStyle(tint)
                                .symbolSize(range > 30 ? 10 : 30)
                        }
                    } else {
                        BarMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value))
                            .foregroundStyle(p.skipped ? AnyShapeStyle(Color.gray.opacity(0.4)) : (p.done ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.4))))
                            .cornerRadius(3)
                    }
                }
                if habit.isMeasure && habit.goalValue > 0 {
                    RuleMark(y: .value("Goal", habit.goalValue))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) { Text("Goal").font(.caption2).foregroundStyle(.secondary) }
                } else if !habit.isMeasure && habit.target > 1 {
                    RuleMark(y: .value("Target", Double(habit.target))).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: range > 30 ? 14 : (range > 14 ? 7 : 3))) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .frame(height: 180)

            WeekdayBars(habit: habit, tint: tint)

            YearHeatmap(habit: habit, tint: tint)
        }
        .padding()
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// How often you complete the habit on each weekday (last 12 weeks).
private struct WeekdayBars: View {
    let habit: Habit
    let tint: Color

    var body: some View {
        let cal = Calendar.current
        let names = cal.shortWeekdaySymbols
        let stats: [(String, Double)] = (1...7).map { wd in
            var sched = 0, done = 0
            for i in 0..<84 {
                guard let d = cal.date(byAdding: .day, value: -i, to: .now), cal.component(.weekday, from: d) == wd,
                      d >= cal.startOfDay(for: habit.createdAt), habit.isScheduled(on: d) else { continue }
                sched += 1
                if habit.isDone(on: d) { done += 1 }
            }
            return (names[wd - 1], sched == 0 ? 0 : Double(done) / Double(sched))
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Best days").font(.hush(.subheadline).weight(.semibold))
            Chart(stats, id: \.0) { name, rate in
                BarMark(x: .value("Day", name), y: .value("Rate", rate))
                    .foregroundStyle(tint.opacity(0.3 + rate * 0.7))
                    .cornerRadius(3)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis { AxisMarks(values: [0, 0.5, 1]) { v in AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) * 100))%") } } }
            .frame(height: 110)
        }
    }
}

/// A year at a glance, one square per day.
private struct YearHeatmap: View {
    let habit: Habit
    let tint: Color

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weeks = 26
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) ?? today
        let offset = cal.component(.weekday, from: start) - 1
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 6 months").font(.hush(.subheadline).weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<(weeks + 1), id: \.self) { w in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { r in
                                let idx = w * 7 + r - offset
                                if idx >= 0, let d = cal.date(byAdding: .day, value: idx, to: start), d <= today {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color(for: d))
                                        .frame(width: 11, height: 11)
                                } else {
                                    Color.clear.frame(width: 11, height: 11)
                                }
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
        }
    }

    private func color(for d: Date) -> Color {
        if habit.isSkipped(on: d) { return .gray.opacity(0.25) }
        if habit.isDone(on: d) { return tint }
        if !habit.isMeasure, habit.count(on: d) > 0 { return tint.opacity(0.45) }
        if habit.isMeasure, habit.value(on: d) != nil { return tint.opacity(0.45) }
        return Color.secondary.opacity(0.15)
    }
}

// MARK: - Vacation

struct VacationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var habits: [Habit]
    @State private var on = HabitVacation.from != nil
    @State private var from = HabitVacation.from ?? Calendar.current.startOfDay(for: .now)
    @State private var until = HabitVacation.until ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            HushForm {
                Section {
                    Toggle("Vacation Mode", isOn: $on)
                    if on {
                        DatePicker("From", selection: $from, displayedComponents: .date)
                        DatePicker("Until", selection: $until, in: from..., displayedComponents: .date)
                    }
                } footer: {
                    Text("Every habit pauses for these days: they don't count against you, streaks carry on, and habit reminders stay quiet.")
                }
            }
            .navigationTitle("Vacation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HabitVacation.set(from: on ? from : nil, until: on ? until : nil)
                        for h in habits where h.deletedAt == nil { Reminders.sync(h) }
                        WidgetCenter.shared.reloadAllTimelines()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Mood insights

struct MoodInsightsView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Query(sort: \JournalEntry.date) private var entriesStored: [JournalEntry]
    @Query private var habitsStored: [Habit]
    @State private var range = 30

    private struct DayMood: Identifiable { let date: Date; let mood: Double; var id: Date { date } }

    var body: some View {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -range, to: .now) ?? .now
        let entries = entriesStored.live(settings.spaceFilter).filter { $0.moodRaw > 0 }
        let byDay = Dictionary(grouping: entries) { cal.startOfDay(for: $0.date) }
            .mapValues { es in Double(es.map(\.moodRaw).reduce(0, +)) / Double(es.count) }
        let series = byDay.filter { $0.key >= since }.map { DayMood(date: $0.key, mood: $0.value) }.sorted { $0.date < $1.date }
        let weekday: [(String, Double)] = (1...7).map { wd in
            let vals = byDay.filter { cal.component(.weekday, from: $0.key) == wd }.map(\.value)
            return (cal.shortWeekdaySymbols[wd - 1], vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count))
        }
        let habits = habitsStored.live(settings.spaceFilter).filter { !$0.archived }
        let correlations: [(Habit, Double, Double)] = habits.compactMap { h in
            var withH: [Double] = [], without: [Double] = []
            for (d, m) in byDay where h.isScheduled(on: d) { if h.isDone(on: d) { withH.append(m) } else { without.append(m) } }
            guard withH.count >= 3, without.count >= 3 else { return nil }
            return (h, withH.reduce(0, +) / Double(withH.count), without.reduce(0, +) / Double(without.count))
        }.sorted { ($0.1 - $0.2) > ($1.1 - $1.2) }

        ScrollView {
            VStack(spacing: 14) {
                Picker("Range", selection: $range) { Text("1M").tag(30); Text("3M").tag(90); Text("1Y").tag(365) }
                    .pickerStyle(.segmented)
                card("Mood over time") {
                    if series.count < 2 {
                        Text("Log your mood on a few days (Journal or the Mood widget) to see a trend.").font(.hush(.footnote)).foregroundStyle(.secondary)
                    } else {
                        Chart(series) { p in
                            AreaMark(x: .value("Day", p.date, unit: .day), y: .value("Mood", p.mood))
                                .foregroundStyle(.linearGradient(colors: [settings.accentColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Day", p.date, unit: .day), y: .value("Mood", p.mood))
                                .foregroundStyle(settings.accentColor)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: 1...5)
                        .chartYAxis {
                            AxisMarks(values: [1, 3, 5]) { v in
                                AxisValueLabel { Image(systemName: Mood(rawValue: v.as(Int.self) ?? 3)?.symbol ?? "cloud") }
                            }
                        }
                        .frame(height: 180)
                    }
                }
                card("By weekday") {
                    Chart(weekday, id: \.0) { name, v in
                        BarMark(x: .value("Day", name), y: .value("Mood", v)).foregroundStyle(settings.accentColor.opacity(0.35 + v / 8)).cornerRadius(3)
                    }
                    .chartYScale(domain: 0...5)
                    .frame(height: 120)
                }
                card("Habits and your mood") {
                    if correlations.isEmpty {
                        Text("Once you've logged mood and habits for a couple of weeks, this shows which habits line up with better days.")
                            .font(.hush(.footnote)).foregroundStyle(.secondary)
                    }
                    ForEach(correlations, id: \.0.id) { h, withMood, withoutMood in
                        HStack(spacing: 10) {
                            SymbolTile(name: h.emoji, fallback: "checkmark.circle", tint: h.color ?? settings.accentColor, size: 30)
                            Text(h.name).lineLimit(1)
                            Spacer()
                            let diff = withMood - withoutMood
                            Label("\(diff >= 0 ? "+" : "")\(diff.formatted(.number.precision(.fractionLength(1))))", systemImage: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.hush(.subheadline).monospacedDigit())
                                .foregroundStyle(diff >= 0.2 ? Color.green : (diff <= -0.2 ? Color.orange : Color.secondary))
                        }
                    }
                    if !correlations.isEmpty {
                        Text("Average mood on days you did the habit compared with days you didn't. It shows a link, not a cause.")
                            .font(.hush(.caption2)).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding()
        }
        .background(palette.background)
        .navigationTitle("Mood Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.hush(.headline))
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

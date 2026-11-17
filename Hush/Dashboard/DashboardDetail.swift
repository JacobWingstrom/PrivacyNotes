import SwiftUI
import Charts

enum HistoryRange: String, CaseIterable, Identifiable {
    case hour = "1H", sixHours = "6H", day = "24H", week = "7D"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .hour: 3600
        case .sixHours: 6 * 3600
        case .day: 86400
        case .week: 7 * 86400
        }
    }
    var since: Date { Date().addingTimeInterval(-seconds) }
}

/// The in-depth view behind every online widget.
struct DashboardDetailView: View {
    let widget: HomeWidget
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var store = DashboardStore.shared
    @State private var range = HistoryRange.hour

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let e = store.errors[widget.id] {
                    Label(e, systemImage: "exclamationmark.triangle").font(.hush(.footnote)).foregroundStyle(.orange)
                }
                if let p = store.payloads[widget.id] {
                    content(p)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
                StatusLine(widget: widget)
            }
            .padding()
        }
        .background(palette.background)
        .navigationTitle(widget.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh(widget) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { Task { await store.refresh(widget) } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh")
            }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    @ViewBuilder private func content(_ p: WidgetPayload) -> some View {
        switch p {
        case .server(let s): ServerDetail(widget: widget, s: s, range: $range)
        case .containers(let c): ContainersDetail(widget: widget, list: c, range: $range)
        case .monitor(let m): MonitorDetail(widget: widget, list: m, range: $range)
        case .weather(let w): WeatherDetail(w: w)
        case .markets(let q): MarketsDetail(quotes: q)
        case .news(let n): NewsDetail(items: n)
        case .releases(let r): ReleasesDetail(items: r)
        case .dns(let d): DNSDetail(widget: widget, d: d, range: $range)
        case .custom(let f, let raw): CustomDetail(widget: widget, fields: f, raw: raw, range: $range)
        }
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.hush(.caption).weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.border))
    }
}

private struct RangePicker: View {
    @Binding var range: HistoryRange
    var body: some View {
        Picker("Range", selection: $range) { ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented)
    }
}

/// A line chart of one stored value over the chosen range.
private struct HistoryChart: View {
    let points: [(Date, Double)]
    var unit: (Double) -> String = { String(format: "%.0f", $0) }
    var maxY: Double? = nil
    var tint: Color = .accentColor

    var body: some View {
        if points.count < 2 {
            Text("Not enough history yet. Hush records a point each time this widget refreshes while Home is open.")
                .font(.hush(.caption)).foregroundStyle(.secondary).frame(height: 60)
        } else {
            let values = points.map(\.1)
            HStack(spacing: 16) {
                stat("Now", values.last ?? 0)
                stat("Avg", values.reduce(0, +) / Double(values.count))
                stat("Max", values.max() ?? 0)
                stat("Min", values.min() ?? 0)
            }
            Chart(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Time", p.0), y: .value("Value", p.1)).interpolationMethod(.monotone).foregroundStyle(tint)
                AreaMark(x: .value("Time", p.0), y: .value("Value", p.1)).interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
            }
            .chartYScale(domain: 0...(maxY ?? max((values.max() ?? 1) * 1.1, 0.001)))
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(unit(d)).font(.caption2) } }
            } }
            .frame(height: 160)
        }
    }

    private func stat(_ label: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(unit(v)).font(.hush(.subheadline).weight(.semibold)).monospacedDigit()
            Text(label).font(.hush(.caption2)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Server

private struct ServerDetail: View {
    let widget: HomeWidget
    let s: ServerSnapshot
    @Binding var range: HistoryRange
    @State private var store = DashboardStore.shared
    @State private var metric = "cpu"

    private let metrics: [(String, String)] = [("cpu", "CPU"), ("mem", "Memory"), ("load", "Load"), ("disk", "Disk"), ("temp", "Temp"), ("rx", "Down"), ("tx", "Up")]

    var body: some View {
        DetailCard(title: s.hostname.isEmpty ? "Server" : s.hostname) {
            if !s.os.isEmpty { Text(s.os).font(.hush(.subheadline)).foregroundStyle(.secondary) }
            HStack(spacing: 18) {
                Ring(value: s.cpu, label: "CPU", size: 76)
                Ring(value: s.memPercent, label: "RAM", size: 76)
                if s.swapTotal > 0 { Ring(value: s.swapPercent, label: "Swap", size: 76) }
            }
            .frame(maxWidth: .infinity)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if s.uptime > 0 { row("Uptime", Fmt.uptime(s.uptime)) }
                if s.cores > 0 { row("Cores", "\(s.cores)") }
                if s.load.count >= 3 { row("Load 1 · 5 · 15 min", s.load.map { String(format: "%.2f", $0) }.joined(separator: " · ")) }
                row("Memory", "\(Fmt.bytes(s.memUsed)) of \(Fmt.bytes(s.memTotal))")
                if s.swapTotal > 0 { row("Swap", "\(Fmt.bytes(s.swapUsed)) of \(Fmt.bytes(s.swapTotal))") }
                if s.netRx != nil { row("Network", "↓ \(Fmt.rate(s.netRx))   ↑ \(Fmt.rate(s.netTx))") }
            }
            .font(.hush(.subheadline))
        }
        DetailCard(title: "History") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(metrics, id: \.0) { m in TagChip(text: m.1, selected: metric == m.0) { metric = m.0 } } }
            }
            RangePicker(range: $range)
            HistoryChart(points: store.series(widget.id, metric, since: range.since), unit: unitFor(metric),
                         maxY: ["cpu", "mem", "disk"].contains(metric) ? 100 : nil)
        }
        if !s.perCore.isEmpty {
            DetailCard(title: "Per Core") {
                Chart(Array(s.perCore.enumerated()), id: \.offset) { i, v in
                    BarMark(x: .value("Core", "\(i)"), y: .value("Use", v)).foregroundStyle(usageColor(v, .accentColor))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(s.perCore.count > 16 ? .hidden : .automatic)
                .frame(height: 120)
            }
        }
        if !s.disks.isEmpty {
            DetailCard(title: "Disks") {
                ForEach(s.disks, id: \.self) { d in
                    UsageBar(label: d.name, percent: d.total > 0 ? d.used / d.total * 100 : 0,
                             detail: "\(Fmt.bytes(d.used)) of \(Fmt.bytes(d.total)) · \(Fmt.bytes(d.total - d.used)) free")
                }
            }
        }
        if !s.temps.isEmpty {
            DetailCard(title: "Temperatures") {
                ForEach(s.temps, id: \.self) { t in
                    HStack {
                        Text(t.name).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f°C", t.celsius)).monospacedDigit().foregroundStyle(t.celsius >= 85 ? .red : (t.celsius >= 70 ? .orange : .primary))
                    }
                    .font(.hush(.subheadline))
                }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).monospacedDigit()
        }
    }

    private func unitFor(_ m: String) -> (Double) -> String {
        switch m {
        case "cpu", "mem", "disk": { Fmt.percent($0) }
        case "temp": { String(format: "%.0f°", $0) }
        case "rx", "tx": { Fmt.rate($0) }
        default: { String(format: "%.2f", $0) }
        }
    }
}

// MARK: - Containers

private struct ContainersDetail: View {
    let widget: HomeWidget
    let list: [ContainerInfo]
    @Binding var range: HistoryRange
    @State private var store = DashboardStore.shared
    @State private var sort = "name"
    @State private var search = ""

    var body: some View {
        let shown = sorted.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.image.localizedCaseInsensitiveContains(search) }
        DetailCard(title: "\(list.filter(\.running).count) of \(list.count) running") {
            TextField("Filter", text: $search).textFieldStyle(.roundedBorder)
            Picker("Sort", selection: $sort) {
                Text("Name").tag("name"); Text("CPU").tag("cpu"); Text("Memory").tag("memory"); Text("Status").tag("status")
            }
            .pickerStyle(.segmented)
            ForEach(shown) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle().fill(c.running ? Color.green : Color.secondary.opacity(0.5)).frame(width: 9, height: 9)
                        Text(c.name).font(.hush(.subheadline).weight(.semibold)).lineLimit(1)
                        Text(c.kind.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(c.status).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !c.image.isEmpty { Text(c.image).font(.hush(.caption2)).foregroundStyle(.tertiary).lineLimit(1) }
                    if c.running {
                        if let cpu = c.cpu { UsageBar(label: "CPU", percent: cpu) }
                        if let m = c.memory {
                            if let l = c.memoryLimit, l > 0 { UsageBar(label: "Memory", percent: m / l * 100, detail: "\(Fmt.bytes(m)) of \(Fmt.bytes(l))") }
                            else { Text("Memory \(Fmt.bytes(m))").font(.hush(.caption)).foregroundStyle(.secondary) }
                        }
                        if let u = c.uptime, u > 0 { Text("Up \(Fmt.uptime(u))").font(.hush(.caption2)).foregroundStyle(.secondary) }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        DetailCard(title: "Running over time") {
            RangePicker(range: $range)
            HistoryChart(points: store.series(widget.id, "running", since: range.since))
        }
    }

    private var sorted: [ContainerInfo] {
        switch sort {
        case "cpu": list.sorted { ($0.cpu ?? -1) > ($1.cpu ?? -1) }
        case "memory": list.sorted { ($0.memory ?? -1) > ($1.memory ?? -1) }
        case "status": list.sorted { ($0.running ? 1 : 0, $0.name) < ($1.running ? 1 : 0, $1.name) }
        default: list.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }
}

// MARK: - Monitor

private struct MonitorDetail: View {
    let widget: HomeWidget
    let list: [MonitorResult]
    @Binding var range: HistoryRange
    @State private var store = DashboardStore.shared
    @State private var link: URL?

    var body: some View {
        RangePicker(range: $range)
        ForEach(list) { m in
            let ms = store.series(widget.id, "ms:" + m.name, since: range.since).filter { $0.1 >= 0 }
            let ups = store.series(widget.id, "up:" + m.name, since: range.since).map(\.1)
            let uptime = ups.isEmpty ? nil : ups.reduce(0, +) / Double(ups.count) * 100
            DetailCard(title: m.name) {
                HStack {
                    Label(m.up ? "Up" : "Down", systemImage: m.up ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(m.up ? .green : .red).font(.hush(.headline))
                    Spacer()
                    if m.status > 0 { Text("HTTP \(m.status)").foregroundStyle(.secondary) }
                    Text("\(Int(m.ms)) ms").monospacedDigit()
                }
                if let uptime { Text("Uptime in range: \(String(format: "%.2f", uptime))%").font(.hush(.subheadline)) }
                if !m.error.isEmpty { Text(m.error).font(.hush(.caption)).foregroundStyle(.orange) }
                Button { link = URL(string: m.url) } label: { Text(m.url).font(.hush(.caption)).lineLimit(1) }
                HistoryChart(points: ms, unit: { "\(Int($0)) ms" }, tint: m.up ? .green : .red)
                if ups.count > 1 {
                    // A strip of up/down checks, newest on the right.
                    HStack(spacing: 1) {
                        ForEach(Array(ups.suffix(60).enumerated()), id: \.offset) { _, u in
                            RoundedRectangle(cornerRadius: 1).fill(u > 0 ? Color.green : Color.red).frame(height: 16)
                        }
                    }
                }
            }
        }
        .confirmLinks($link)
    }
}

// MARK: - Weather

private struct WeatherDetail: View {
    let w: WeatherData

    var body: some View {
        let unit = w.imperial ? "°F" : "°C"
        DetailCard(title: w.place.isEmpty ? "Now" : w.place) {
            HStack(spacing: 14) {
                Image(systemName: DashboardSources.weatherSymbol(w.code, day: w.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 50))
                VStack(alignment: .leading) {
                    Text("\(Int(w.temperature.rounded()))\(unit)").font(.system(size: 44, weight: .semibold))
                    Text(DashboardSources.weatherText(w.code)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Label("Feels \(Int(w.feelsLike.rounded()))°", systemImage: "thermometer.medium")
                Spacer()
                Label("\(Int(w.humidity))%", systemImage: "humidity")
                Spacer()
                Label("\(Int(w.wind)) \(w.imperial ? "mph" : "km/h")", systemImage: "wind")
            }
            .font(.hush(.subheadline))
        }
        DetailCard(title: "Next 48 hours") {
            Chart(w.hourly, id: \.self) { h in
                LineMark(x: .value("Time", h.time), y: .value("Temp", h.temp)).interpolationMethod(.monotone).foregroundStyle(.orange)
                BarMark(x: .value("Time", h.time), y: .value("Rain", h.rain / 100 * max(w.hourly.map(\.temp).max() ?? 1, 1)))
                    .foregroundStyle(.blue.opacity(0.25))
            }
            .frame(height: 170)
            Text("Line: temperature. Bars: chance of rain.").font(.hush(.caption2)).foregroundStyle(.secondary)
        }
        DetailCard(title: "7 days") {
            ForEach(w.daily, id: \.self) { d in
                HStack {
                    Text(Calendar.current.isDateInToday(d.date) ? "Today" : d.date.formatted(.dateTime.weekday(.wide))).frame(width: 96, alignment: .leading)
                    Image(systemName: DashboardSources.weatherSymbol(d.code)).symbolRenderingMode(.multicolor).frame(width: 28)
                    Text("\(Int(d.rain))%").foregroundStyle(.blue).frame(width: 40)
                    Spacer()
                    Text("\(Int(d.low.rounded()))°").foregroundStyle(.secondary)
                    Text("\(Int(d.high.rounded()))°")
                }
                .font(.hush(.subheadline)).monospacedDigit()
            }
            if let today = w.daily.first, let sr = today.sunrise, let ss = today.sunset {
                HStack {
                    Label(sr.formatted(date: .omitted, time: .shortened), systemImage: "sunrise")
                    Spacer()
                    Label(ss.formatted(date: .omitted, time: .shortened), systemImage: "sunset")
                }
                .font(.hush(.subheadline)).foregroundStyle(.secondary)
            }
            Text("Weather data by Open-Meteo.com").font(.hush(.caption2)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Markets

private struct MarketsDetail: View {
    let quotes: [Quote]
    @State private var selected = ""
    @State private var range = "1mo"
    @State private var chart: Quote?
    @State private var loading = false

    private let ranges: [(String, String, String)] = [("1d", "1D", "5m"), ("5d", "5D", "30m"), ("1mo", "1M", "1d"), ("6mo", "6M", "1d"), ("1y", "1Y", "1d"), ("5y", "5Y", "1wk")]

    var body: some View {
        let sym = selected.isEmpty ? (quotes.first?.symbol ?? "") : selected
        ScrollView(.horizontal, showsIndicators: false) {
            HStack { ForEach(quotes) { q in TagChip(text: q.symbol, selected: q.symbol == sym) { selected = q.symbol } } }
        }
        if let q = quotes.first(where: { $0.symbol == sym }) {
            DetailCard(title: q.name) {
                Text(Fmt.price(q.price, q.currency)).font(.system(size: 34, weight: .semibold)).monospacedDigit()
                Text(String(format: "%+.2f (%+.2f%%) today", q.change, q.changePercent)).foregroundStyle(q.change >= 0 ? .green : .red)
                Picker("Range", selection: $range) { ForEach(ranges, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented)
                if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 180) }
                else if let c = chart, c.points.count > 1 {
                    let up = (c.points.last ?? 0) >= (c.points.first ?? 0)
                    Chart(Array(c.points.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("i", i), y: .value("Price", v)).foregroundStyle(up ? .green : .red)
                    }
                    .chartXAxis(.hidden)
                    .chartYScale(domain: (c.points.min() ?? 0)...(c.points.max() ?? 1))
                    .frame(height: 200)
                    Text(String(format: "%+.2f%% over this range · low %@ · high %@",
                                ((c.points.last ?? 0) / max(c.points.first ?? 1, 0.0001) - 1) * 100,
                                Fmt.price(c.points.min() ?? 0, q.currency), Fmt.price(c.points.max() ?? 0, q.currency)))
                        .font(.hush(.caption)).foregroundStyle(.secondary)
                }
                Text("Prices from Yahoo Finance, may be delayed.").font(.hush(.caption2)).foregroundStyle(.tertiary)
            }
            .task(id: "\(sym)-\(range)") { await load(sym) }
        }
    }

    private func load(_ symbol: String) async {
        guard let r = ranges.first(where: { $0.0 == range }) else { return }
        loading = true
        chart = try? await DashboardSources.quote(symbol, range: r.0, interval: r.2)
        loading = false
    }
}

// MARK: - News & releases

private struct NewsDetail: View {
    let items: [NewsItem]
    @State private var link: URL?

    var body: some View {
        ForEach(items) { n in
            VStack(alignment: .leading, spacing: 4) {
                Button { link = URL(string: n.url) } label: {
                    Text(n.title).font(.hush(.headline)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    Text("\(n.score) points")
                    Button("\(n.comments) comments") { link = URL(string: n.commentsURL) }
                    Text(n.author)
                    Text(n.date, format: .relative(presentation: .numeric))
                }
                .font(.hush(.caption)).foregroundStyle(.secondary)
                if !n.domain.isEmpty { Text(n.domain).font(.hush(.caption2)).foregroundStyle(.tertiary) }
            }
            Divider()
        }
        .confirmLinks($link)
    }
}

private struct ReleasesDetail: View {
    let items: [ReleaseInfo]
    @State private var link: URL?

    var body: some View {
        ForEach(items) { r in
            DetailCard(title: r.repo) {
                HStack {
                    Text(r.tag).font(.hush(.headline)).monospaced()
                    if r.isNew { Text("NEW").font(.system(size: 10, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(.tint.opacity(0.25))) }
                    Spacer()
                    if let d = r.date { Text(d.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary) }
                }
                if !r.name.isEmpty && r.name != r.tag { Text(r.name).font(.hush(.subheadline)) }
                if !r.notes.isEmpty {
                    Text((try? AttributedString(markdown: r.notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(r.notes))
                        .font(.hush(.caption)).lineLimit(14)
                }
                Button("Open on GitHub") { link = URL(string: r.url) }.font(.hush(.subheadline))
            }
        }
        .confirmLinks($link)
    }
}

// MARK: - DNS

private struct DNSDetail: View {
    let widget: HomeWidget
    let d: DNSStats
    @Binding var range: HistoryRange
    @State private var store = DashboardStore.shared

    var body: some View {
        DetailCard(title: "Today") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow { big(Fmt.compact(d.total), "Queries"); big(Fmt.compact(d.blocked), "Blocked") }
                GridRow { big(Fmt.percent(d.percent), "Blocked share"); big(d.listSize > 0 ? Fmt.compact(d.listSize) : "—", "Domains on lists") }
                if d.clients > 0 { GridRow { big(Fmt.compact(d.clients), "Active clients"); big(d.enabled == false ? "Off" : "On", "Blocking") } }
            }
        }
        if d.history.count > 2 {
            DetailCard(title: "Queries over time") {
                Chart(d.history, id: \.self) { p in
                    BarMark(x: .value("Time", p.time), y: .value("Allowed", max(p.total - p.blocked, 0))).foregroundStyle(.tint.opacity(0.4))
                    BarMark(x: .value("Time", p.time), y: .value("Blocked", p.blocked)).foregroundStyle(.red.opacity(0.75))
                }
                .frame(height: 180)
                HStack(spacing: 14) {
                    Label("All queries", systemImage: "circle.fill").foregroundStyle(.tint)
                    Label("Blocked", systemImage: "circle.fill").foregroundStyle(.red)
                }
                .font(.hush(.caption2))
            }
        }
        if !d.topBlocked.isEmpty {
            DetailCard(title: "Top blocked") {
                let top = d.topBlocked.prefix(10)
                let maxCount = top.map(\.count).max() ?? 1
                ForEach(Array(top), id: \.self) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(t.domain).lineLimit(1); Spacer(); Text(Fmt.compact(t.count)).monospacedDigit().foregroundStyle(.secondary) }
                            .font(.hush(.subheadline))
                        GeometryReader { g in Capsule().fill(.red.opacity(0.5)).frame(width: g.size.width * t.count / max(maxCount, 1)) }.frame(height: 4)
                    }
                }
            }
        }
        DetailCard(title: "Blocked share, Hush history") {
            RangePicker(range: $range)
            HistoryChart(points: store.series(widget.id, "percent", since: range.since), unit: { Fmt.percent($0) }, maxY: 100, tint: .red)
        }
    }

    private func big(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.hush(.title3).weight(.semibold)).monospacedDigit()
            Text(l).font(.hush(.caption)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Custom API

private struct CustomDetail: View {
    let widget: HomeWidget
    let fields: [CustomField]
    let raw: String
    @Binding var range: HistoryRange
    @State private var store = DashboardStore.shared
    @State private var showRaw = false

    var body: some View {
        DetailCard(title: "Values") {
            ForEach(fields) { f in
                HStack { Text(f.label).foregroundStyle(.secondary); Spacer(); Text(f.value + (f.unit.isEmpty ? "" : " \(f.unit)")).monospacedDigit() }
                    .font(.hush(.subheadline))
            }
        }
        let numeric = fields.filter { $0.number != nil }
        if !numeric.isEmpty {
            RangePicker(range: $range)
            ForEach(numeric) { f in
                DetailCard(title: f.label) {
                    HistoryChart(points: store.series(widget.id, f.label, since: range.since), unit: { v in
                        (abs(v) >= 100 ? String(format: "%.0f", v) : String(format: "%.2f", v)) + (f.unit.isEmpty ? "" : " \(f.unit)")
                    })
                }
            }
        }
        DetailCard(title: "Response") {
            DisclosureGroup("Raw JSON", isExpanded: $showRaw) {
                ScrollView(.horizontal) {
                    Text(raw).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                }
                .frame(maxHeight: 400)
            }
            Text("Tip: copy a path from here into the widget's fields, e.g. “Temp=main.temp|°C” or “First=items.0.name”.")
                .font(.hush(.caption2)).foregroundStyle(.secondary)
        }
    }
}

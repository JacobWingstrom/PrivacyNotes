import SwiftUI
import SwiftData
import Charts

/// Every Dynacat-style widget: shows the latest data and opens an in-depth view on tap.
struct DashboardWidgetView: View {
    let widget: HomeWidget
    @State private var store = DashboardStore.shared
    @State private var showingDetail = false

    var body: some View {
        WidgetFrame(widget: widget, openSection: section) {
            Group {
                switch widget.kind {
                case .feeds: FeedsHomeWidget(widget: widget)
                case .mail: MailHomeWidget(widget: widget)
                case .review: ReviewHomeWidget(widget: widget)
                case .clock: ClockWidget(widget: widget)
                default: onlineContent
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if widget.isOnline { showingDetail = true } }
        }
        .sheet(isPresented: $showingDetail) {
            NavigationStack { DashboardDetailView(widget: widget) }
        }
        .task(id: widget) {
            if widget.isOnline && store.payloads[widget.id] == nil { await store.refresh(widget) }
        }
    }

    private var section: AppSection? {
        switch widget.kind {
        case .feeds: .feeds
        case .mail, .review: .mail
        default: nil
        }
    }

    @ViewBuilder private var onlineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = store.payloads[widget.id] {
                PayloadSummary(widget: widget, payload: p)
            } else if let e = store.errors[widget.id] {
                Label(e, systemImage: "exclamationmark.triangle").font(.hush(.footnote)).foregroundStyle(.orange)
            } else {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            }
            StatusLine(widget: widget)
        }
    }
}

/// "Updated 2 min ago", or the error after a failed refresh that still has older data.
struct StatusLine: View {
    let widget: HomeWidget
    @State private var store = DashboardStore.shared

    var body: some View {
        HStack(spacing: 6) {
            if store.loading.contains(widget.id) {
                ProgressView().controlSize(.mini)
            } else if store.errors[widget.id] != nil && store.payloads[widget.id] != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if let d = store.updated[widget.id] {
                Text(d, format: .relative(presentation: .named))
            }
            Spacer()
        }
        .font(.hush(.caption2))
        .foregroundStyle(.tertiary)
    }
}

private struct PayloadSummary: View {
    let widget: HomeWidget
    let payload: WidgetPayload

    var body: some View {
        switch payload {
        case .server(let s): ServerSummary(widget: widget, s: s)
        case .containers(let c): ContainersSummary(widget: widget, list: c)
        case .monitor(let m): MonitorSummary(widget: widget, list: m)
        case .weather(let w): WeatherSummary(widget: widget, w: w)
        case .markets(let q): MarketsSummary(widget: widget, quotes: q)
        case .news(let n): NewsSummary(widget: widget, items: n)
        case .releases(let r): ReleasesSummary(widget: widget, items: r)
        case .dns(let d): DNSSummary(widget: widget, d: d)
        case .custom(let f, _): CustomSummary(widget: widget, fields: f)
        }
    }
}

// MARK: - Building blocks

struct Ring: View {
    let value: Double // 0…100
    let label: String
    var tint: Color = .accentColor
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 7)
            Circle().trim(from: 0, to: min(max(value / 100, 0), 1))
                .stroke(usageColor(value, tint), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(Fmt.percent(value)).font(.system(size: size * 0.22, weight: .bold)).monospacedDigit()
                Text(label).font(.system(size: size * 0.15)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Fmt.percent(value))")
    }
}

func usageColor(_ percent: Double, _ base: Color) -> Color {
    percent >= 90 ? .red : (percent >= 75 ? .orange : base)
}

struct UsageBar: View {
    let label: String
    let percent: Double
    var detail = ""
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.hush(.caption).weight(.medium))
                Spacer()
                Text(detail.isEmpty ? Fmt.percent(percent) : detail).font(.hush(.caption)).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule().fill(usageColor(percent, tint)).frame(width: g.size.width * min(max(percent / 100, 0), 1))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Fmt.percent(percent)) \(detail)")
    }
}

struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            LineMark(x: .value("i", i), y: .value("v", v)).interpolationMethod(.monotone).foregroundStyle(tint)
            AreaMark(x: .value("i", i), y: .value("v", v)).interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (values.min() ?? 0)...(max(values.max() ?? 1, (values.min() ?? 0) + 0.0001)))
        .accessibilityHidden(true)
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.hush(.headline)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.hush(.caption2)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Server

private struct ServerSummary: View {
    let widget: HomeWidget
    let s: ServerSnapshot
    @State private var store = DashboardStore.shared

    var body: some View {
        if widget.size == .small {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Ring(value: s.cpu, label: "CPU", size: 58)
                    Ring(value: s.memPercent, label: "RAM", size: 58)
                }
                .frame(maxWidth: .infinity)
                if let t = s.hottest { Label(String(format: "%.0f°C", t), systemImage: "thermometer.medium").font(.hush(.caption)).foregroundStyle(.secondary) }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(s.hostname.isEmpty ? "Server" : s.hostname).font(.hush(.headline)).lineLimit(1)
                    Spacer()
                    if s.uptime > 0 { Label(Fmt.uptime(s.uptime), systemImage: "power").font(.hush(.caption)).foregroundStyle(.secondary) }
                }
                UsageBar(label: "CPU" + (s.cores > 0 ? " · \(s.cores) cores" : ""), percent: s.cpu)
                UsageBar(label: "Memory", percent: s.memPercent, detail: "\(Fmt.bytes(s.memUsed)) of \(Fmt.bytes(s.memTotal))")
                ForEach(s.disks.prefix(widget.size == .large ? 4 : 1), id: \.self) { d in
                    UsageBar(label: d.name, percent: d.total > 0 ? d.used / d.total * 100 : 0, detail: "\(Fmt.bytes(d.used)) of \(Fmt.bytes(d.total))")
                }
                HStack {
                    if s.load.count >= 3 { StatTile(value: s.load.map { String(format: "%.2f", $0) }.joined(separator: " "), label: "Load") }
                    if let t = s.hottest { StatTile(value: String(format: "%.0f°C", t), label: "Hottest") }
                    if s.netRx != nil { StatTile(value: "↓\(Fmt.rate(s.netRx))", label: "↑\(Fmt.rate(s.netTx))") }
                }
                if widget.size == .large {
                    let cpu = store.series(widget.id, "cpu", since: Date().addingTimeInterval(-3600)).map(\.1)
                    if cpu.count > 2 {
                        Text("CPU, last hour").font(.hush(.caption2)).foregroundStyle(.secondary)
                        Sparkline(values: cpu).frame(height: 50)
                    }
                    if !s.perCore.isEmpty {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(Array(s.perCore.prefix(64).enumerated()), id: \.offset) { _, v in
                                RoundedRectangle(cornerRadius: 2).fill(usageColor(v, .accentColor)).frame(height: max(3, 30 * v / 100))
                            }
                        }
                        .frame(height: 30, alignment: .bottom)
                        .accessibilityLabel("CPU per core")
                    }
                }
            }
        }
    }
}

// MARK: - Containers

private struct ContainersSummary: View {
    let widget: HomeWidget
    let list: [ContainerInfo]

    var body: some View {
        let running = list.filter(\.running).count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(running) running").font(.hush(.headline))
                Text("of \(list.count)").foregroundStyle(.secondary)
                Spacer()
            }
            if widget.size != .small {
                ForEach(sorted.prefix(widget.limit)) { c in
                    HStack(spacing: 8) {
                        Circle().fill(c.running ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                        Image(systemName: c.kind == "vm" ? "desktopcomputer" : (c.kind == "lxc" ? "cube" : "shippingbox")).foregroundStyle(.secondary).font(.caption)
                        Text(c.name).lineLimit(1)
                        Spacer()
                        if let cpu = c.cpu, c.running { Text(Fmt.percent(cpu)).monospacedDigit().foregroundStyle(.secondary) }
                        if let m = c.memory, c.running { Text(Fmt.bytes(m)).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    .font(.hush(.caption))
                }
            } else {
                let stopped = list.filter { !$0.running }
                if !stopped.isEmpty { Text("Stopped: " + stopped.prefix(3).map(\.name).joined(separator: ", ")).font(.hush(.caption)).foregroundStyle(.orange).lineLimit(2) }
            }
        }
    }

    private var sorted: [ContainerInfo] {
        switch widget.sortMode {
        case "cpu": list.sorted { ($0.cpu ?? -1) > ($1.cpu ?? -1) }
        case "memory": list.sorted { ($0.memory ?? -1) > ($1.memory ?? -1) }
        default: list.sorted { ($0.running ? 0 : 1, $0.name.lowercased()) < ($1.running ? 0 : 1, $1.name.lowercased()) }
        }
    }
}

// MARK: - Monitor

private struct MonitorSummary: View {
    let widget: HomeWidget
    let list: [MonitorResult]

    var body: some View {
        let up = list.filter(\.up).count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: up == list.count ? "checkmark.circle.fill" : "exclamationmark.octagon.fill")
                    .foregroundStyle(up == list.count ? .green : .red)
                Text(list.isEmpty ? "Nothing to check" : "\(up) of \(list.count) up").font(.hush(.headline))
            }
            if widget.size != .small {
                ForEach(list.prefix(widget.size == .large ? 20 : widget.limit)) { m in
                    HStack(spacing: 8) {
                        Circle().fill(m.up ? Color.green : Color.red).frame(width: 8, height: 8)
                        Text(m.name).lineLimit(1)
                        Spacer()
                        Text(m.up ? "\(Int(m.ms)) ms" : (m.status > 0 ? "\(m.status)" : "down")).monospacedDigit()
                            .foregroundStyle(m.up ? Color.secondary : Color.red)
                    }
                    .font(.hush(.caption))
                }
            } else {
                ForEach(list.filter { !$0.up }.prefix(3)) { Text($0.name).font(.hush(.caption)).foregroundStyle(.red).lineLimit(1) }
            }
        }
    }
}

// MARK: - Weather

private struct WeatherSummary: View {
    let widget: HomeWidget
    let w: WeatherData

    var body: some View {
        let unit = w.imperial ? "°F" : "°C"
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: DashboardSources.weatherSymbol(w.code, day: w.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 34))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(w.temperature.rounded()))\(unit)").font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    Text(DashboardSources.weatherText(w.code)).font(.hush(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                if widget.size != .small, let today = w.daily.first {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("H \(Int(today.high.rounded()))° L \(Int(today.low.rounded()))°").font(.hush(.caption)).monospacedDigit()
                        Text(w.place).font(.hush(.caption2)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if widget.size == .small {
                Text(w.place).font(.hush(.caption2)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(w.hourly.prefix(6).enumerated()), id: \.offset) { _, h in
                        VStack(spacing: 3) {
                            Text(h.time.formatted(.dateTime.hour())).font(.hush(.caption2)).foregroundStyle(.secondary)
                            Image(systemName: DashboardSources.weatherSymbol(h.code)).symbolRenderingMode(.multicolor)
                            Text("\(Int(h.temp.rounded()))°").font(.hush(.caption)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if widget.size == .large {
                ForEach(w.daily.prefix(5), id: \.self) { d in
                    HStack {
                        Text(Calendar.current.isDateInToday(d.date) ? "Today" : d.date.formatted(.dateTime.weekday(.abbreviated))).frame(width: 52, alignment: .leading)
                        Image(systemName: DashboardSources.weatherSymbol(d.code)).symbolRenderingMode(.multicolor).frame(width: 26)
                        if d.rain >= 20 { Text("\(Int(d.rain))%").foregroundStyle(.blue).font(.hush(.caption2)) }
                        Spacer()
                        Text("\(Int(d.low.rounded()))°").foregroundStyle(.secondary).monospacedDigit()
                        Text("\(Int(d.high.rounded()))°").monospacedDigit()
                    }
                    .font(.hush(.caption))
                }
            }
        }
    }
}

// MARK: - Markets

private struct MarketsSummary: View {
    let widget: HomeWidget
    let quotes: [Quote]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(quotes.prefix(widget.size == .small ? 2 : 10)) { q in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(q.symbol).font(.hush(.subheadline).weight(.semibold))
                        if widget.size != .small { Text(q.name).font(.hush(.caption2)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    if widget.size != .small && q.points.count > 2 {
                        Sparkline(values: q.points, tint: q.change >= 0 ? .green : .red).frame(width: 70, height: 26)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.price(q.price, q.currency)).font(.hush(.subheadline)).monospacedDigit()
                        Text(String(format: "%+.2f%%", q.changePercent)).font(.hush(.caption)).monospacedDigit()
                            .foregroundStyle(q.change >= 0 ? .green : .red)
                    }
                }
            }
        }
    }
}

// MARK: - News

private struct NewsSummary: View {
    let widget: HomeWidget
    let items: [NewsItem]
    @State private var link: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.prefix(widget.size == .small ? 2 : widget.limit)) { n in
                Button { link = URL(string: n.url) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.hush(.subheadline)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                        if widget.size != .small {
                            Text("\(n.score) points · \(n.comments) comments · \(n.domain)").font(.hush(.caption2)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .confirmLinks($link)
    }
}

// MARK: - Releases

private struct ReleasesSummary: View {
    let widget: HomeWidget
    let items: [ReleaseInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items.prefix(widget.size == .small ? 3 : widget.limit)) { r in
                HStack(spacing: 6) {
                    Text(r.repo.split(separator: "/").last.map(String.init) ?? r.repo).lineLimit(1)
                    if r.isNew { Text("NEW").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1).background(Capsule().fill(.tint.opacity(0.25))) }
                    Spacer()
                    Text(r.tag).monospaced().foregroundStyle(.secondary).lineLimit(1)
                    if widget.size != .small, let d = r.date { Text(d, format: .relative(presentation: .numeric)).foregroundStyle(.tertiary) }
                }
                .font(.hush(.caption))
            }
        }
    }
}

// MARK: - DNS

private struct DNSSummary: View {
    let widget: HomeWidget
    let d: DNSStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatTile(value: Fmt.compact(d.total), label: "Queries")
                StatTile(value: Fmt.compact(d.blocked), label: "Blocked")
                if widget.size != .small { StatTile(value: Fmt.percent(d.percent), label: "Blocked %") }
            }
            if widget.size == .small {
                UsageBar(label: "Blocked", percent: d.percent, tint: .red)
            } else if d.history.count > 2 {
                Chart(d.history, id: \.self) { p in
                    BarMark(x: .value("Time", p.time), y: .value("Allowed", p.total - p.blocked)).foregroundStyle(.tint.opacity(0.5))
                    BarMark(x: .value("Time", p.time), y: .value("Blocked", p.blocked)).foregroundStyle(.red.opacity(0.8))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: widget.size == .large ? 110 : 60)
            }
            if widget.size == .large {
                ForEach(d.topBlocked.prefix(5), id: \.self) { t in
                    HStack { Text(t.domain).lineLimit(1); Spacer(); Text(Fmt.compact(t.count)).foregroundStyle(.secondary).monospacedDigit() }
                        .font(.hush(.caption))
                }
            }
            if d.enabled == false { Label("Blocking is off", systemImage: "shield.slash").font(.hush(.caption)).foregroundStyle(.orange) }
        }
    }
}

// MARK: - Custom API

private struct CustomSummary: View {
    let widget: HomeWidget
    let fields: [CustomField]

    var body: some View {
        if fields.isEmpty {
            Text("Choose fields in the widget's settings.").font(.hush(.caption)).foregroundStyle(.secondary)
        } else if widget.size == .small && fields.count == 1, let f = fields.first {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.value + (f.unit.isEmpty ? "" : " \(f.unit)")).font(.system(size: 30, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                Text(f.label).font(.hush(.caption)).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(fields.prefix(widget.size == .small ? 3 : 12)) { f in
                    HStack {
                        Text(f.label).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(f.value + (f.unit.isEmpty ? "" : " \(f.unit)")).monospacedDigit().lineLimit(1)
                    }
                    .font(.hush(.subheadline))
                }
            }
        }
    }
}

// MARK: - Local widgets (feeds, mail, review, clock)

private struct FeedsHomeWidget: View {
    let widget: HomeWidget
    @Query(filter: #Predicate<FeedArticle> { !$0.isRead }, sort: \FeedArticle.published, order: .reverse) private var unread: [FeedArticle]
    @Query private var feeds: [Feed]
    @State private var open: FeedArticle?

    var body: some View {
        let ids: Set<UUID>? = {
            if widget.feedScope.hasPrefix("folder:") {
                let f = String(widget.feedScope.dropFirst(7))
                return Set(feeds.filter { $0.folder == f }.map(\.id))
            }
            if let id = UUID(uuidString: widget.feedScope) { return [id] }
            return nil
        }()
        let list = unread.filter { ids == nil || ids!.contains($0.feedID) }
        let names = Dictionary(feeds.map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 8) {
            if feeds.isEmpty {
                Text("Add feeds in the Feeds section.").font(.hush(.subheadline)).foregroundStyle(.secondary)
            } else if list.isEmpty {
                Text("All caught up.").font(.hush(.subheadline)).foregroundStyle(.secondary)
            }
            ForEach(list.prefix(widget.size == .small ? 2 : widget.limit)) { a in
                Button { open = a } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).font(.hush(.subheadline)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                        if widget.size != .small { Text(names[a.feedID] ?? "").font(.hush(.caption2)).foregroundStyle(.secondary) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $open) { a in NavigationStack { ArticleReaderView(article: a).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { open = nil } } } } }
    }
}

private struct MailHomeWidget: View {
    let widget: HomeWidget
    @Query(filter: #Predicate<MailMessage> { $0.folder == "INBOX" }, sort: \MailMessage.date, order: .reverse) private var inbox: [MailMessage]
    @State private var engine = MailEngine.shared
    @State private var open: MailMessage?

    var body: some View {
        let unread = inbox.filter { !$0.isSeen && !$0.isDeleted }
        VStack(alignment: .leading, spacing: 8) {
            if !engine.hasAccounts {
                Text("Add a mail account in Settings → Mail, Calendars & Feeds.").font(.hush(.subheadline)).foregroundStyle(.secondary)
            } else {
                Text(unread.isEmpty ? "No unread mail" : "\(unread.count) unread").font(.hush(.headline))
                ForEach(unread.prefix(widget.size == .small ? 2 : widget.limit)) { m in
                    Button { open = m } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.senderLabel).font(.hush(.subheadline).weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                            Text(m.summary.subject).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $open) { m in
            NavigationStack { MessageReaderView(message: m) { open = nil }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { open = nil } } } }
        }
    }
}

private struct ReviewHomeWidget: View {
    let widget: HomeWidget
    @Query(filter: #Predicate<TaskItem> { $0.reviewRaw == "pending" && $0.deletedAt == nil }) private var tasks: [TaskItem]
    @Query(filter: #Predicate<CalendarEvent> { $0.reviewRaw == "pending" && $0.deletedAt == nil }) private var events: [CalendarEvent]
    @Query(filter: #Predicate<Contact> { $0.reviewRaw == "pending" && $0.deletedAt == nil }) private var contacts: [Contact]

    var body: some View {
        let items: [(String, String, any Reviewable)] = events.map { ("calendar", $0.title, $0 as any Reviewable) }
            + tasks.map { ("checkmark.circle", $0.title, $0 as any Reviewable) } + contacts.map { ("person.crop.circle", $0.displayName, $0 as any Reviewable) }
        VStack(alignment: .leading, spacing: 8) {
            Text(items.isEmpty ? "Nothing to review" : "\(items.count) to review").font(.hush(.headline))
            if widget.size != .small {
                ForEach(Array(items.prefix(widget.limit).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Image(systemName: item.0).foregroundStyle(.tint)
                        Text(item.1.isEmpty ? "Untitled" : item.1).lineLimit(1)
                        Spacer()
                        Button { withAnimation { MailScanner.confirm(item.2) } } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            .buttonStyle(.plain).accessibilityLabel("Confirm")
                        Button { withAnimation { MailScanner.dismiss(item.2) } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss")
                    }
                    .font(.hush(.subheadline))
                }
            }
        }
    }
}

private struct ClockWidget: View {
    let widget: HomeWidget

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 6) {
                Text(ctx.date.formatted(date: .omitted, time: widget.size == .small ? .shortened : .standard))
                    .font(.system(size: widget.size == .small ? 30 : 38, weight: .semibold)).monospacedDigit()
                ForEach(widget.items.prefix(widget.size == .small ? 2 : 8), id: \.self) { id in
                    if let tz = TimeZone(identifier: id) {
                        HStack {
                            Text(id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id).lineLimit(1)
                            Spacer()
                            Text(Self.time(ctx.date, tz)).monospacedDigit()
                            if widget.size != .small { Text(Self.offset(tz, at: ctx.date)).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing) }
                        }
                        .font(.hush(.subheadline))
                    }
                }
            }
        }
    }

    static func time(_ d: Date, _ tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = tz
        return d.formatted(style)
    }

    static func offset(_ tz: TimeZone, at d: Date) -> String {
        let diff = (tz.secondsFromGMT(for: d) - TimeZone.current.secondsFromGMT(for: d)) / 3600
        return diff == 0 ? "±0h" : String(format: "%+dh", diff)
    }
}

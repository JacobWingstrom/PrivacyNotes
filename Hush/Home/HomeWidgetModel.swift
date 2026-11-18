import SwiftUI

enum HomeWidgetKind: String, Codable, CaseIterable, Identifiable {
    case greeting, quickAdd, tasks, board, habits, calendar, agenda, notes, note, journal, mood, stats, bookmarks, contacts, countdown, files
    // Online & homelab (Dynacat-style)
    case server, containers, monitor, weather, markets, news, feeds, mail, review, releases, dns, customAPI, clock

    var id: String { rawValue }

    var name: String {
        switch self {
        case .greeting: "Greeting"
        case .quickAdd: "Quick Add"
        case .tasks: "Tasks"
        case .board: "Board"
        case .habits: "Habits"
        case .calendar: "Calendar"
        case .agenda: "Agenda"
        case .notes: "Notes"
        case .note: "Single Note"
        case .journal: "Journal"
        case .mood: "Mood Check-in"
        case .stats: "Stats"
        case .bookmarks: "Bookmarks"
        case .contacts: "Contacts"
        case .countdown: "Countdown"
        case .files: "Recent Files"
        case .server: "Server Stats"
        case .containers: "Containers & VMs"
        case .monitor: "Uptime Monitor"
        case .weather: "Weather"
        case .markets: "Markets"
        case .news: "Hacker News & Lobsters"
        case .feeds: "Feed Headlines"
        case .mail: "Mail"
        case .review: "To Review"
        case .releases: "Releases"
        case .dns: "DNS Blocking"
        case .customAPI: "Custom API"
        case .clock: "World Clock"
        }
    }

    var symbol: String {
        switch self {
        case .greeting: "sun.horizon"
        case .quickAdd: "plus.square"
        case .tasks: "checkmark.circle"
        case .board: "rectangle.split.3x1"
        case .habits: "flame"
        case .calendar: "calendar"
        case .agenda: "list.bullet.rectangle"
        case .notes: "square.and.pencil"
        case .note: "note.text"
        case .journal: "book.closed"
        case .mood: "cloud.sun"
        case .stats: "chart.bar"
        case .bookmarks: "bookmark"
        case .contacts: "person.crop.circle"
        case .countdown: "hourglass"
        case .files: "folder"
        case .server: "cpu"
        case .containers: "shippingbox"
        case .monitor: "waveform.path.ecg"
        case .weather: "cloud.sun"
        case .markets: "chart.line.uptrend.xyaxis"
        case .news: "newspaper"
        case .feeds: "dot.radiowaves.up.forward"
        case .mail: "envelope"
        case .review: "checklist"
        case .releases: "tag"
        case .dns: "shield.lefthalf.filled"
        case .customAPI: "curlybraces"
        case .clock: "globe"
        }
    }

    var blurb: String {
        switch self {
        case .greeting: "Good morning, today's date and an optional message."
        case .quickAdd: "Type to add a task or note, or tap buttons to start anything."
        case .tasks: "Today, upcoming, overdue or a specific list — with check-off."
        case .board: "A Kanban board's columns at a glance, or the cards in one column."
        case .habits: "Check off habits as a list or as progress rings."
        case .calendar: "A month or week view with dots on busy days."
        case .agenda: "Events, tasks and iPhone calendar items for the next days."
        case .notes: "Recent, pinned, a folder or a tag — as a list or cards."
        case .note: "Pin one note's text to your Home, like a sticky note."
        case .journal: "Your streak, last entry and a button to write today."
        case .mood: "Log today's mood in one tap."
        case .stats: "Counts you pick: notes, tasks done, streaks and more."
        case .bookmarks: "Your favorite links as quick-launch tiles."
        case .contacts: "Favorite people with call, message and email buttons."
        case .countdown: "Days until (or since) a date you choose."
        case .files: "Your newest files, scans and voice memos."
        case .server: "CPU, memory, disks, load, temperatures and network from your hush-server, Glances, Netdata or Proxmox, with history charts."
        case .containers: "Docker containers (Glances) or Proxmox VMs and LXCs: what's running, CPU and memory."
        case .monitor: "Checks your sites and services, with response times and uptime history."
        case .weather: "Current conditions, hourly and 7-day forecast (Open-Meteo, no account)."
        case .markets: "Stocks, ETFs and crypto with sparklines and charts (Yahoo Finance)."
        case .news: "Top stories from Hacker News or Lobsters."
        case .feeds: "Newest unread posts from your feeds and subreddits."
        case .mail: "Unread email in your inbox."
        case .review: "Events, tasks and contacts found in email, waiting for you."
        case .releases: "Latest releases of GitHub projects you follow."
        case .dns: "Pi-hole or AdGuard Home: queries, blocked, top blocked domains."
        case .customAPI: "Any JSON API: pick the values to show, numbers get charts."
        case .clock: "The time here and in other time zones."
        }
    }

    var defaultSize: WidgetSize {
        switch self {
        case .mood, .countdown, .stats, .journal, .clock, .review: .small
        case .calendar, .note: .large
        default: .medium
        }
    }

    var allowedSizes: [WidgetSize] {
        switch self {
        case .greeting, .quickAdd: [.medium]
        case .calendar: [.medium, .large]
        default: WidgetSize.allCases
        }
    }
}

extension HomeWidgetKind {
    static let local: [HomeWidgetKind] = [.greeting, .quickAdd, .tasks, .board, .habits, .calendar, .agenda, .notes, .note, .journal,
                                          .mood, .stats, .bookmarks, .contacts, .countdown, .files, .clock, .mail, .review, .feeds]
    static let online: [HomeWidgetKind] = [.server, .containers, .monitor, .dns, .releases, .weather, .markets, .news, .customAPI]

    /// Contacts a server (yours or a public one) when it refreshes.
    var isOnline: Bool { Self.online.contains(self) }

    /// Shown in the gallery so you know who a widget talks to.
    var connectsTo: String? {
        switch self {
        case .server, .containers, .dns, .customAPI: "Your server only"
        case .monitor: "The addresses you add"
        case .weather: "open-meteo.com"
        case .markets: "query1.finance.yahoo.com"
        case .news: "hacker-news.firebaseio.com or lobste.rs"
        case .releases: "api.github.com"
        default: nil
        }
    }
}

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: "Small (half width)"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
    var short: String { rawValue.capitalized }
}

/// One widget on Home and all of its settings. Unused settings are simply ignored by other kinds.
struct HomeWidget: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: HomeWidgetKind
    var size: WidgetSize
    var title = ""
    var symbol = ""
    var tintHex = ""
    var showHeader = true
    var limit = 5
    // Tasks
    var taskScope = "today"          // today, upcoming, overdue, all, nodate, list
    var listName = ""
    var showCompleted = false
    // Habits
    var habitIDs: [UUID] = []        // empty = all due today
    var habitStyle = "list"          // list, rings
    // Calendar & agenda
    var calendarStyle = "month"      // month, week
    var days = 7
    var includeTasks = true
    var includePhoneEvents = true
    // Notes
    var noteScope = "recent"         // recent, pinned, folder, tag
    var folderID: UUID? = nil
    var tag = ""
    var noteStyle = "list"           // list, cards
    var noteID: UUID? = nil
    // Board
    var boardID: UUID? = nil
    var columnID: UUID? = nil
    // Greeting
    var message = ""
    var showDate = true
    // Stats
    var stats: [String] = ["notes", "openTasks", "habitsToday", "journalStreak"]
    // Quick add
    var quickKinds: [String] = ["notes", "tasks", "habits", "journals"]
    var showQuickField = true
    // Bookmarks / contacts
    var favoritesOnly = true
    // Countdown
    var targetDate: Date? = nil
    // Online & homelab
    /// Base address of the server or API.
    var endpoint = ""
    /// hush, glances, netdata, proxmox · pihole, pihole5, adguard · hn, lobsters
    var source = ""
    /// Monitors ("Name|URL"), tickers, repos ("owner/repo"), time zones, or custom API fields ("Label=path|unit").
    var items: [String] = []
    var refreshMinutes = 5
    var allowSelfSigned = false
    /// User name, Proxmox token ID (user@pam!name) or a custom header name.
    var username = ""
    var node = ""
    var location = ""
    var latitude = 0.0
    var longitude = 0.0
    var imperial = false
    /// Feeds widget: "" (all unread), "folder:Name" or a feed id.
    var feedScope = ""
    /// Monitor: also check the URLs of your Homelab services.
    var includeHomelab = false
    var sortMode = ""

    /// Widgets that talk to the internet or your servers.
    var isOnline: Bool { kind.isOnline }

    init(kind: HomeWidgetKind, size: WidgetSize? = nil) {
        self.kind = kind
        self.size = size ?? kind.defaultSize
        if kind == .countdown {
            targetDate = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: .now))
            title = "Vacation"
        }
        if kind == .notes { limit = 4 }
        switch kind {
        case .server:
            source = SyncSettings.serverURL.isEmpty ? "glances" : "hush"
            endpoint = SyncSettings.serverURL
            refreshMinutes = 1
        case .containers: source = "glances"; limit = 8
        case .monitor: refreshMinutes = 2; includeHomelab = true
        case .weather: refreshMinutes = 30
        case .markets: items = ["AAPL", "VOO", "BTC-USD"]; refreshMinutes = 15
        case .news: source = "hn"; refreshMinutes = 30; limit = 6
        case .releases: items = ["glanceapp/glance", "jellyfin/jellyfin"]; refreshMinutes = 120
        case .dns: source = "pihole"
        case .clock: items = ["Europe/Berlin", "America/New_York", "Asia/Tokyo"]
        default: break
        }
    }

    var displayTitle: String { title.trimmed.isEmpty ? kind.name : title.trimmed }
    var displaySymbol: String { SymbolName.resolve(symbol, fallback: kind.symbol) }

    // Tolerant decoding so new settings never break saved layouts.
    enum CodingKeys: String, CodingKey {
        case boardID, columnID
        case id, kind, size, title, symbol, tintHex, showHeader, limit, taskScope, listName, showCompleted, habitIDs, habitStyle,
             calendarStyle, days, includeTasks, includePhoneEvents, noteScope, folderID, tag, noteStyle, noteID, message, showDate,
             stats, quickKinds, showQuickField, favoritesOnly, targetDate
        case endpoint, source, items, refreshMinutes, allowSelfSigned, username, node, location, latitude, longitude, imperial,
             feedScope, includeHomelab, sortMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(HomeWidgetKind.self, forKey: .kind)
        size = (try? c.decode(WidgetSize.self, forKey: .size)) ?? kind.defaultSize
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? ""
        tintHex = (try? c.decode(String.self, forKey: .tintHex)) ?? ""
        showHeader = (try? c.decode(Bool.self, forKey: .showHeader)) ?? true
        limit = (try? c.decode(Int.self, forKey: .limit)) ?? 5
        taskScope = (try? c.decode(String.self, forKey: .taskScope)) ?? "today"
        listName = (try? c.decode(String.self, forKey: .listName)) ?? ""
        showCompleted = (try? c.decode(Bool.self, forKey: .showCompleted)) ?? false
        habitIDs = (try? c.decode([UUID].self, forKey: .habitIDs)) ?? []
        habitStyle = (try? c.decode(String.self, forKey: .habitStyle)) ?? "list"
        calendarStyle = (try? c.decode(String.self, forKey: .calendarStyle)) ?? "month"
        days = (try? c.decode(Int.self, forKey: .days)) ?? 7
        includeTasks = (try? c.decode(Bool.self, forKey: .includeTasks)) ?? true
        includePhoneEvents = (try? c.decode(Bool.self, forKey: .includePhoneEvents)) ?? true
        noteScope = (try? c.decode(String.self, forKey: .noteScope)) ?? "recent"
        folderID = try? c.decode(UUID.self, forKey: .folderID)
        tag = (try? c.decode(String.self, forKey: .tag)) ?? ""
        noteStyle = (try? c.decode(String.self, forKey: .noteStyle)) ?? "list"
        noteID = try? c.decode(UUID.self, forKey: .noteID)
        boardID = try? c.decode(UUID.self, forKey: .boardID)
        columnID = try? c.decode(UUID.self, forKey: .columnID)
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
        showDate = (try? c.decode(Bool.self, forKey: .showDate)) ?? true
        stats = (try? c.decode([String].self, forKey: .stats)) ?? ["notes", "openTasks", "habitsToday", "journalStreak"]
        quickKinds = (try? c.decode([String].self, forKey: .quickKinds)) ?? ["notes", "tasks", "habits", "journals"]
        showQuickField = (try? c.decode(Bool.self, forKey: .showQuickField)) ?? true
        favoritesOnly = (try? c.decode(Bool.self, forKey: .favoritesOnly)) ?? true
        targetDate = try? c.decode(Date.self, forKey: .targetDate)
        endpoint = (try? c.decode(String.self, forKey: .endpoint)) ?? ""
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        items = (try? c.decode([String].self, forKey: .items)) ?? []
        refreshMinutes = (try? c.decode(Int.self, forKey: .refreshMinutes)) ?? 5
        allowSelfSigned = (try? c.decode(Bool.self, forKey: .allowSelfSigned)) ?? false
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        node = (try? c.decode(String.self, forKey: .node)) ?? ""
        location = (try? c.decode(String.self, forKey: .location)) ?? ""
        latitude = (try? c.decode(Double.self, forKey: .latitude)) ?? 0
        longitude = (try? c.decode(Double.self, forKey: .longitude)) ?? 0
        imperial = (try? c.decode(Bool.self, forKey: .imperial)) ?? false
        feedScope = (try? c.decode(String.self, forKey: .feedScope)) ?? ""
        includeHomelab = (try? c.decode(Bool.self, forKey: .includeHomelab)) ?? false
        sortMode = (try? c.decode(String.self, forKey: .sortMode)) ?? ""
    }

    /// Password, API token or key for this widget (kept in the Keychain, not in settings).
    var secret: String {
        get { Keychain.load("widget.\(id.uuidString)").map { String(decoding: $0, as: UTF8.self) } ?? "" }
        nonmutating set {
            if newValue.isEmpty { Keychain.delete("widget.\(id.uuidString)") } else { Keychain.save(Data(newValue.utf8), for: "widget.\(id.uuidString)") }
        }
    }
}

enum HomeLayouts {
    struct Preset: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let detail: String
        let widgets: () -> [HomeWidget]
    }

    static func w(_ kind: HomeWidgetKind, _ size: WidgetSize? = nil, _ configure: (inout HomeWidget) -> Void = { _ in }) -> HomeWidget {
        var x = HomeWidget(kind: kind, size: size)
        configure(&x)
        return x
    }

    static let standard: [HomeWidget] = [
        w(.greeting), w(.quickAdd), w(.tasks), w(.habits, .small) { $0.habitStyle = "rings" }, w(.mood, .small),
        w(.agenda), w(.notes) { $0.noteScope = "pinned"; $0.noteStyle = "cards" }, w(.journal, .small), w(.stats, .small),
    ]

    static let presets: [Preset] = [
        Preset(id: "standard", name: "Balanced", symbol: "square.grid.2x2", detail: "A bit of everything.", widgets: { standard }),
        Preset(id: "planner", name: "Daily Planner", symbol: "calendar.day.timeline.left", detail: "Today's tasks, agenda and calendar first.", widgets: {
            [w(.greeting), w(.tasks) { $0.limit = 8 }, w(.agenda) { $0.days = 3 }, w(.calendar, .medium) { $0.calendarStyle = "week" },
             w(.quickAdd), w(.habits, .small) { $0.habitStyle = "rings" }, w(.countdown, .small)]
        }),
        Preset(id: "habits", name: "Habit Focus", symbol: "flame", detail: "Habits, mood and journal up front.", widgets: {
            [w(.greeting), w(.habits, .large), w(.mood, .small), w(.journal, .small), w(.stats, .medium) { $0.stats = ["habitsToday", "bestStreak", "journalStreak", "tasksDoneToday"] }]
        }),
        Preset(id: "homelab", name: "Homelab & Work", symbol: "server.rack", detail: "Notes, open tasks and quick links.", widgets: {
            [w(.greeting) { $0.showDate = true }, w(.notes) { $0.noteScope = "recent"; $0.limit = 6 }, w(.tasks) { $0.taskScope = "all"; $0.limit = 8 },
             w(.bookmarks) { $0.favoritesOnly = false; $0.limit = 8 }, w(.files, .small), w(.stats, .small) { $0.stats = ["notes", "openTasks", "files", "bookmarks"] }]
        }),
        Preset(id: "dashboard", name: "Homelab Dashboard", symbol: "gauge.with.dots.needle.67percent", detail: "Server stats, containers, uptime, DNS, releases and weather.", widgets: {
            [w(.server, .large), w(.monitor), w(.containers), w(.dns, .medium), w(.releases), w(.weather, .small), w(.clock, .small), w(.news)]
        }),
        Preset(id: "minimal", name: "Minimal", symbol: "minus.circle", detail: "Just the essentials.", widgets: {
            [w(.greeting) { $0.showDate = true }, w(.tasks), w(.notes) { $0.limit = 3 }]
        }),
    ]

    /// Converts the old fixed Home blocks into widgets once.
    static func migrate(blocks: [HomeBlock], hidden: Set<HomeBlock>, greeting: Bool) -> [HomeWidget] {
        var out: [HomeWidget] = greeting ? [w(.greeting)] : []
        for b in blocks where !hidden.contains(b) {
            switch b {
            case .quickAdd: out.append(w(.quickAdd))
            case .mood: out.append(w(.mood, .small))
            case .today: out.append(w(.tasks))
            case .habits: out.append(w(.habits))
            case .calendar: out.append(w(.calendar, .large))
            case .upcoming: out.append(w(.agenda))
            case .pinned: out.append(w(.notes) { $0.noteScope = "pinned"; $0.noteStyle = "cards"; $0.title = "Pinned Notes" })
            case .recentNotes: out.append(w(.notes) { $0.title = "Recent Notes" })
            case .journal: out.append(w(.journal, .small))
            case .stats: out.append(w(.stats, .small))
            }
        }
        return out
    }
}

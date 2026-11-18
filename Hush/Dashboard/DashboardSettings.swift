import SwiftUI
import SwiftData

/// Settings for the online and dashboard widgets, shown in Widget Settings.
struct DashboardSettingsSection: View {
    @Binding var w: HomeWidget
    @Query private var feeds: [Feed]

    var body: some View {
        Group {
            switch w.kind {
            case .server: server
            case .containers: containers
            case .monitor: monitor
            case .weather: WeatherSettings(w: $w)
            case .markets:
                Section {
                    ItemListEditor(items: $w.items, placeholder: "Symbol, e.g. MSFT or ETH-USD", uppercase: true)
                } header: { Text("Symbols") } footer: { Text("Stocks, ETFs, indexes (^GSPC), currencies (EURUSD=X) and crypto (BTC-USD), as on Yahoo Finance.") }
            case .news:
                Section("Stories") {
                    Picker("Source", selection: $w.source) { Text("Hacker News").tag("hn"); Text("Lobsters").tag("lobsters") }
                    Picker("Show", selection: $w.sortMode) {
                        Text("Top").tag("")
                        Text("Newest").tag("new")
                        if w.source != "lobsters" { Text("Best").tag("best") }
                    }
                    Stepper("Show up to \(w.limit)", value: $w.limit, in: 1...30)
                }
            case .releases:
                Section {
                    ItemListEditor(items: $w.items, placeholder: "owner/repo, e.g. immich-app/immich")
                } header: { Text("Repositories") }
                Section {
                    SecretField(widget: w, label: "GitHub token (optional)")
                    Stepper("Show up to \(w.limit)", value: $w.limit, in: 1...20)
                } footer: { Text("Without a token GitHub allows 60 requests an hour, plenty for a few repos refreshed every couple of hours.") }
            case .dns: dns
            case .customAPI: custom
            case .clock:
                Section {
                    ItemListEditor(items: $w.items, placeholder: "Time zone, e.g. Europe/Paris", suggestions: TimeZone.knownTimeZoneIdentifiers)
                } header: { Text("Time Zones") }
            case .feeds:
                Section("Feeds") {
                    Picker("Show", selection: $w.feedScope) {
                        Text("All unread").tag("")
                        ForEach(Array(Set(feeds.map(\.folder).filter { !$0.isEmpty })).sorted(), id: \.self) { Text("Folder: \($0)").tag("folder:\($0)") }
                        ForEach(feeds) { Text($0.displayTitle).tag($0.id.uuidString) }
                    }
                    Stepper("Show up to \(w.limit)", value: $w.limit, in: 1...20)
                }
            case .mail, .review:
                Section { Stepper("Show up to \(w.limit)", value: $w.limit, in: 1...12) }
            default:
                EmptyView()
            }
            if w.isOnline {
                Section {
                    Picker("Refresh Every", selection: $w.refreshMinutes) {
                        ForEach([1, 2, 5, 10, 15, 30, 60, 120, 360], id: \.self) { m in Text(m < 60 ? "\(m) min" : "\(m / 60) h").tag(m) }
                    }
                } footer: {
                    Text((w.kind.connectsTo.map { "Connects to: \($0). " } ?? "") + "Refreshes only while Home is open. Tap the widget for details and history charts.")
                }
            }
        }
        .onDisappear {
            let widget = w
            if widget.isOnline { Task { await DashboardStore.shared.refresh(widget) } }
        }
    }

    // MARK: Kinds

    @ViewBuilder private var server: some View {
        Section {
            Picker("Source", selection: $w.source) {
                Text("Hush server").tag("hush")
                Text("Glances").tag("glances")
                Text("Netdata").tag("netdata")
                Text("Proxmox VE").tag("proxmox")
            }
            TextField(placeholder, text: $w.endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            auth
        } header: {
            Text("Server")
        } footer: {
            Text(serverHelp)
        }
    }

    @ViewBuilder private var containers: some View {
        Section {
            Picker("Source", selection: $w.source) {
                Text("Docker (via Glances)").tag("glances")
                Text("Proxmox VMs & LXCs").tag("proxmox")
            }
            TextField(placeholder, text: $w.endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            auth
            Picker("Sort", selection: $w.sortMode) { Text("Running first").tag(""); Text("CPU").tag("cpu"); Text("Memory").tag("memory") }
            Stepper("Show up to \(w.limit)", value: $w.limit, in: 1...30)
        } header: { Text("Containers") } footer: { Text(serverHelp) }
    }

    @ViewBuilder private var auth: some View {
        switch w.source {
        case "hush":
            SecretField(widget: w, label: "Token (blank = your Sync token)")
        case "proxmox":
            TextField("Token ID, e.g. root@pam!hush", text: $w.username).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecretField(widget: w, label: "Token secret")
            TextField("Node (blank = first node)", text: $w.node).textInputAutocapitalization(.never).autocorrectionDisabled()
            Toggle("Allow Self-Signed Certificate", isOn: $w.allowSelfSigned)
        default:
            TextField("User name (optional)", text: $w.username).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecretField(widget: w, label: "Password (optional)")
            Toggle("Allow Self-Signed Certificate", isOn: $w.allowSelfSigned)
        }
    }

    private var placeholder: String {
        switch w.source {
        case "hush": "https://hush.your-tailnet.ts.net"
        case "netdata": "http://192.168.1.10:19999"
        case "proxmox": "https://192.168.1.2:8006"
        default: "http://192.168.1.10:61208"
        }
    }

    private var serverHelp: String {
        switch w.source {
        case "hush": "Uses the hush-server you sync with (/v1/system). To also see the host disk, mount / at /host read-only and set HUSH_DISKS=/host (see the compose file)."
        case "netdata": "Netdata's built-in API on port 19999. No login needed on your network."
        case "proxmox": "Create an API token under Datacenter → Permissions → API Tokens with the PVEAuditor role (read-only)."
        default: "Run Glances in web server mode (glances -w, or the nicolargo/glances Docker image) and enter its address, port 61208."
        }
    }

    @ViewBuilder private var monitor: some View {
        Section {
            ItemListEditor(items: $w.items, placeholder: "Name | https://address", hint: "Jellyfin | http://192.168.1.20:8096")
            Toggle("Also Check Homelab Services", isOn: $w.includeHomelab)
            Toggle("Allow Self-Signed Certificates", isOn: $w.allowSelfSigned)
            Stepper("Show up to \(w.limit)", value: $w.limit, in: 1...30)
        } header: { Text("Sites & Services") } footer: {
            Text("Each address is requested and timed. Anything that answers below HTTP 400 (or asks for a login) counts as up. Homelab services use the URL saved on each service.")
        }
    }

    @ViewBuilder private var dns: some View {
        Section {
            Picker("Source", selection: $w.source) {
                Text("Pi-hole 6").tag("pihole")
                Text("Pi-hole 5").tag("pihole5")
                Text("AdGuard Home").tag("adguard")
            }
            TextField(w.source == "adguard" ? "http://192.168.1.3:3000" : "http://pi.hole", text: $w.endpoint)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            if w.source == "adguard" {
                TextField("User name", text: $w.username).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            SecretField(widget: w, label: w.source == "pihole5" ? "API token" : (w.source == "adguard" ? "Password" : "App password (blank if none)"))
            Toggle("Allow Self-Signed Certificate", isOn: $w.allowSelfSigned)
        } header: { Text("DNS Blocker") } footer: {
            Text(w.source == "pihole" ? "In Pi-hole: Settings → Web interface / API → create an app password." : (w.source == "pihole5" ? "In Pi-hole 5: Settings → API → Show API token." : "Your AdGuard Home admin login."))
        }
    }

    @ViewBuilder private var custom: some View {
        Section {
            TextField("https://api.example.com/status", text: $w.endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Header name (e.g. X-API-Key; blank = Authorization)", text: $w.username).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecretField(widget: w, label: "Header value (optional)")
            Toggle("Allow Self-Signed Certificate", isOn: $w.allowSelfSigned)
        } header: { Text("API") }
        Section {
            ItemListEditor(items: $w.items, placeholder: "Label=path|unit", hint: "Temp=main.temp|°C")
        } header: { Text("Fields") } footer: {
            Text("Paths follow the JSON: “data.items.0.name”, “-1” for the last item. Leave empty to show the top-level values. Tap the widget to see the raw response. Numbers get history charts.")
        }
    }
}

/// Password / token stored in the Keychain for one widget.
struct SecretField: View {
    let widget: HomeWidget
    let label: String
    @State private var value = ""
    @State private var loaded = false

    var body: some View {
        SecureField(label, text: $value)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .onAppear { if !loaded { value = widget.secret; loaded = true } }
            .onChange(of: value) { _, v in widget.secret = v }
    }
}

/// Add, edit, reorder and delete simple text lines.
struct ItemListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    var hint = ""
    var uppercase = false
    var suggestions: [String] = []
    @State private var draft = ""

    var body: some View {
        ForEach(items.indices, id: \.self) { i in
            TextField(placeholder, text: Binding(get: { i < items.count ? items[i] : "" }, set: { if i < items.count { items[i] = $0 } }))
                .textInputAutocapitalization(uppercase ? .characters : .never).autocorrectionDisabled()
        }
        .onDelete { items.remove(atOffsets: $0) }
        .onMove { items.move(fromOffsets: $0, toOffset: $1) }
        HStack {
            TextField(hint.isEmpty ? placeholder : hint, text: $draft)
                .textInputAutocapitalization(uppercase ? .characters : .never).autocorrectionDisabled()
                .onSubmit(add)
            Button("Add", action: add).disabled(draft.trimmed.isEmpty)
        }
        if !suggestions.isEmpty && draft.count >= 2 {
            ForEach(suggestions.filter { $0.localizedCaseInsensitiveContains(draft) }.prefix(6), id: \.self) { s in
                Button(s) { draft = s; add() }
            }
        }
    }

    private func add() {
        let v = uppercase ? draft.trimmed.uppercased() : draft.trimmed
        guard !v.isEmpty, !items.contains(v) else { return }
        items.append(v)
        draft = ""
    }
}

private struct WeatherSettings: View {
    @Binding var w: HomeWidget
    @State private var query = ""
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        Section {
            HStack {
                TextField("City", text: $query).onSubmit { Task { await find() } }
                if searching { ProgressView() } else { Button("Find") { Task { await find() } }.disabled(query.trimmed.isEmpty) }
            }
            if !w.location.isEmpty { LabeledContent("Showing", value: w.location) }
            if let error { Text(error).foregroundStyle(.orange).font(.hush(.caption)) }
            Toggle("Fahrenheit & mph", isOn: $w.imperial)
        } header: { Text("Place") } footer: { Text("Only the city you type is sent to Open-Meteo to look up its coordinates. Your device location isn't used.") }
        .onAppear { if query.isEmpty { query = w.location.components(separatedBy: ",").first ?? "" } }
    }

    private func find() async {
        searching = true
        defer { searching = false }
        do {
            let r = try await DashboardSources.geocode(query.trimmed)
            w.location = r.name
            w.latitude = r.lat
            w.longitude = r.lon
            if w.title.isEmpty { w.title = r.name.components(separatedBy: ",").first ?? "" }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

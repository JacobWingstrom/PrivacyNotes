import SwiftUI
import SwiftData

struct ServicesList: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @Query(sort: \LabService.name) private var stored: [LabService]
    @Query private var devicesStored: [LabDevice]
    @State private var search = ""
    @State private var portMap = false
    @State private var newService: LabService?

    var body: some View {
        let services = stored.live(settings.spaceFilter).filter { s in
            search.isEmpty || [s.name, s.url, s.image, s.portSummary, s.notes].contains { $0.localizedCaseInsensitiveContains(search) }
        }
        let devices = devicesStored.live(nil)
        let groups = Dictionary(grouping: services) { $0.hostID }
        let hostName: (UUID?) -> String = { id in devices.first(where: { $0.id == id })?.displayName ?? "~" }
        let hostIDs = groups.keys.sorted { a, b in hostName(a) < hostName(b) }
        List {
            Picker("View", selection: $portMap) {
                Text("By Host").tag(false)
                Text("Port Map").tag(true)
            }
            .pickerStyle(.segmented)
            .plainRow(top: 12, bottom: 4)
            if portMap {
                PortMap(services: services, devices: devices)
            } else {
                ForEach(hostIDs, id: \.self) { hid in
                    Section {
                        ForEach(groups[hid] ?? []) { s in
                            NavigationLink { ServiceEditor(service: s) } label: { ServiceRow(service: s) }
                                .swipeActions(edge: .leading) {
                                    if let u = URL(string: s.url), !s.url.isEmpty {
                                        Button { openURL(u) } label: { Label("Open", systemImage: "safari") }.tint(.blue)
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) { TrashActions.trash(s) } label: { Label("Delete", systemImage: "trash") }
                                }
                                .hushRow()
                        }
                    } header: {
                        ListHeader(title: devices.first { $0.id == hid }?.displayName ?? "No Host")
                    }
                }
            }
            if stored.live(settings.spaceFilter).isEmpty {
                EmptyMessage(text: "No services yet. Tap + to add things like Plex, Pi-hole, Home Assistant or Nextcloud with their ports.")
            }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search services, ports, images…") }
        .onCreate(.homelab) { add() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(action: add) { Image(systemName: "plus") }.accessibilityLabel("New service") } }
        .navigationDestination(item: $newService) { ServiceEditor(service: $0, isNew: true) }
    }

    private func add() {
        let s = LabService()
        context.insert(s)
        newService = s
    }
}

private struct ServiceRow: View {
    let service: LabService
    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(name: service.symbol, fallback: "app.connected.to.app.below.fill", size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name.isEmpty ? "Service" : service.name).font(.hush(.headline))
                Text([service.portSummary, service.image].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.hush(.caption).monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if service.exposedPublicly { Image(systemName: "globe").font(.caption).foregroundStyle(.orange) }
            Image(systemName: service.backedUp ? "externaldrive.badge.checkmark" : "externaldrive.badge.xmark")
                .font(.caption).foregroundStyle(service.backedUp ? Color.green : Color.secondary)
        }
        .padding(.vertical, 3)
    }
}

/// Every port in use, sorted, with clashes on the same host highlighted.
private struct PortMap: View {
    let services: [LabService]
    let devices: [LabDevice]

    var body: some View {
        let rows: [(port: ServicePort, service: LabService)] = services.flatMap { s in s.ports.map { (port: $0, service: s) } }
            .sorted { $0.port.port < $1.port.port }
        let clashes = Set(Dictionary(grouping: rows) { "\($0.service.hostID?.uuidString ?? "-")-\($0.port.port)-\($0.port.proto)" }
            .filter { $0.value.count > 1 }.keys)
        if rows.isEmpty { EmptyMessage(text: "Add ports to your services to see them here.") }
        ForEach(rows, id: \.port.id) { row in
            let key = "\(row.service.hostID?.uuidString ?? "-")-\(row.port.port)-\(row.port.proto)"
            let clash = clashes.contains(key)
            NavigationLink { ServiceEditor(service: row.service) } label: {
                HStack(spacing: 12) {
                    Text("\(row.port.port)").font(.hush(.headline).monospaced()).frame(width: 64, alignment: .leading)
                        .foregroundStyle(clash ? Color.red : Color.primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.service.name.isEmpty ? "Service" : row.service.name)
                        Text([row.port.proto, row.port.purpose, devices.first { $0.id == row.service.hostID }?.displayName ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.hush(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if clash { Label("Clash", systemImage: "exclamationmark.triangle.fill").font(.hush(.caption)).foregroundStyle(.red) }
                    else if let known = CommonPorts.name(row.port.port) {
                        Text(known).font(.hush(.caption2)).foregroundStyle(.tertiary)
                    }
                }
            }
            .hushRow()
        }
    }
}

struct ServiceEditor: View {
    @Bindable var service: LabService
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var devices: [LabDevice]
    @Query private var allServices: [LabService]
    @Query private var vault: [VaultItem]
    @State private var deleting = false
    @State private var newPort = ""
    @State private var pickingIcon = false
    @State private var copied = false

    var body: some View {
        let hosts = devices.live(nil)
        let others = allServices.live(nil).filter { $0.id != service.id }
        HushForm {
            Section {
                HStack(spacing: 12) {
                    Button { pickingIcon = true } label: { SymbolTile(name: service.symbol, fallback: "app.connected.to.app.below.fill", size: 40) }
                        .buttonStyle(.plain)
                    TextField("Service name (e.g. Jellyfin)", text: $service.name).font(.hush(.headline))
                }
                Picker("Host", selection: $service.hostID) {
                    Text("None").tag(UUID?.none)
                    ForEach(hosts) { Text($0.displayName).tag(Optional($0.id)) }
                }
                HStack {
                    TextField("URL (http://10.0.0.5:8096)", text: $service.url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let u = URL(string: service.url), !service.url.isEmpty {
                        Button { openURL(u) } label: { Image(systemName: "safari") }.buttonStyle(.borderless)
                    }
                }
            }
            Section {
                ForEach($service.ports) { $p in
                    HStack {
                        TextField("Port", value: $p.port, format: .number.grouping(.never)).keyboardType(.numberPad).frame(width: 70)
                            .font(.hush(.body).monospaced())
                        Picker("", selection: $p.proto) {
                            ForEach(["TCP", "UDP", "TCP/UDP"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        TextField(CommonPorts.name(p.port) ?? "Purpose (web UI, API…)", text: $p.purpose)
                    }
                }
                .onDelete { service.ports.remove(atOffsets: $0) }
                HStack {
                    TextField("Add port", text: $newPort).keyboardType(.numberPad).onSubmit(addPort)
                    Button("Add", action: addPort).disabled(Int(newPort) == nil)
                }
                Toggle("Exposed to the Internet", isOn: $service.exposedPublicly)
            } header: {
                Text("Ports")
            } footer: {
                if let clash = portClash(others) { Text(clash).foregroundStyle(.red) }
            }
            Section("Deployment") {
                TextField("Image (e.g. lscr.io/linuxserver/jellyfin)", text: $service.image)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(.hush(.body).monospaced())
                TextField("Version / tag", text: $service.version).textInputAutocapitalization(.never)
                TextField("Data path (e.g. /mnt/tank/media)", text: $service.dataPath)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(.hush(.body).monospaced())
                Toggle("Backed Up", isOn: $service.backedUp)
                optionalDate("Last updated", $service.lastUpdated)
            }
            Section {
                TextEditor(text: $service.config)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 140)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !service.config.isEmpty {
                    Button { UIPasteboard.general.string = service.config; copied = true } label: {
                        Label(copied ? "Copied" : "Copy Config", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            } header: {
                Text("Compose / Config")
            } footer: {
                Text("Paste your docker-compose service, .env or config here.")
            }
            Section("Depends On") {
                ForEach(others) { o in
                    Toggle(o.name.isEmpty ? "Service" : o.name, isOn: Binding(
                        get: { service.dependsOn.contains(o.id) },
                        set: { on in if on { service.dependsOn.append(o.id) } else { service.dependsOn.removeAll { $0 == o.id } } }))
                }
                if others.isEmpty { Text("No other services yet.").foregroundStyle(.secondary) }
            }
            Section("Credentials & Notes") {
                Picker("Vault Login", selection: $service.vaultItemID) {
                    Text("None").tag(UUID?.none)
                    ForEach(vault.filter { $0.kind == .login }) { v in Text(v.meta.title.isEmpty ? "Login" : v.meta.title).tag(Optional(v.id)) }
                }
                TextField("Notes", text: $service.notes, axis: .vertical).lineLimit(3...10)
            }
            Section {
                Button("Delete Service", role: .destructive) { deleting = true; dismiss() }
            }
        }
        .navigationTitle(isNew ? "New Service" : (service.name.isEmpty ? "Service" : service.name))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickingIcon) { SymbolPicker(selection: $service.symbol, allowNone: false) }
        .onDisappear {
            if deleting { TrashActions.trash(service) }
            else if isNew && service.name.trimmed.isEmpty && service.ports.isEmpty { context.delete(service) }
        }
    }

    private func addPort() {
        guard let p = Int(newPort), (1...65535).contains(p) else { return }
        service.ports.append(ServicePort(port: p, purpose: CommonPorts.name(p) ?? ""))
        newPort = ""
    }

    private func portClash(_ others: [LabService]) -> String? {
        guard let host = service.hostID else { return nil }
        let mine = Set(service.ports.map { "\($0.port)/\($0.proto)" })
        let clash = others.filter { $0.hostID == host }.first { o in o.ports.contains { mine.contains("\($0.port)/\($0.proto)") } }
        return clash.map { "A port here is also used by \($0.name) on the same host." }
    }

    private func optionalDate(_ label: String, _ date: Binding<Date?>) -> some View {
        HStack {
            Toggle(label, isOn: Binding(get: { date.wrappedValue != nil }, set: { date.wrappedValue = $0 ? .now : nil }))
            if date.wrappedValue != nil {
                DatePicker("", selection: Binding(get: { date.wrappedValue ?? .now }, set: { date.wrappedValue = $0 }), displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

struct LinkEditor: View {
    @Bindable var link: LabLink
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [LabDevice]
    @State private var deleting = false

    var body: some View {
        let list = devices.live(nil)
        HushForm {
            Section("From") {
                Picker("Device", selection: $link.fromID) { ForEach(list) { Text($0.displayName).tag($0.id) } }
                TextField("Port (e.g. eth0, port 3, SFP+1)", text: $link.fromPort).textInputAutocapitalization(.never)
            }
            Section("To") {
                Picker("Device", selection: $link.toID) { ForEach(list) { Text($0.displayName).tag($0.id) } }
                TextField("Port", text: $link.toPort).textInputAutocapitalization(.never)
            }
            Section("Cable") {
                Picker("Type", selection: $link.kindRaw) { ForEach(LabLink.kinds, id: \.0) { Text($0.1).tag($0.0) } }
                TextField("Speed (1G, 2.5G, 10G)", text: $link.speed)
                TextField("Label on cable", text: $link.label)
                Picker("Color", selection: $link.colorName) { ForEach(NoteColor.allCases) { Text($0 == .none ? "Gray" : $0.label).tag($0.rawValue) } }
                TextField("Length (e.g. 1 m)", text: $link.length)
                TextField("VLANs (e.g. trunk, 10, 20)", text: $link.vlan)
                TextField("Notes", text: $link.notes, axis: .vertical)
            }
            Section { Button("Delete Connection", role: .destructive) { deleting = true; dismiss() } }
        }
        .navigationTitle(isNew ? "New Connection" : "Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { if deleting { TrashActions.trash(link) } }
    }
}

/// Well-known ports so purposes fill in automatically.
enum CommonPorts {
    static let table: [Int: String] = [
        20: "FTP data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS", 67: "DHCP", 68: "DHCP client",
        69: "TFTP", 80: "HTTP", 110: "POP3", 123: "NTP", 137: "NetBIOS", 139: "SMB (NetBIOS)", 143: "IMAP", 161: "SNMP",
        389: "LDAP", 443: "HTTPS", 445: "SMB", 465: "SMTPS", 514: "Syslog", 587: "SMTP submission", 636: "LDAPS",
        853: "DNS over TLS", 873: "rsync", 993: "IMAPS", 995: "POP3S", 1194: "OpenVPN", 1433: "MS SQL", 1883: "MQTT",
        2049: "NFS", 2375: "Docker API", 2376: "Docker API (TLS)", 3000: "Grafana / web app", 3306: "MySQL / MariaDB",
        3389: "RDP", 3478: "STUN/TURN", 4443: "HTTPS alt", 5000: "Web app / registry", 5001: "Web app (TLS)",
        5353: "mDNS", 5432: "PostgreSQL", 5900: "VNC", 6379: "Redis", 6443: "Kubernetes API", 8006: "Proxmox VE",
        8007: "Proxmox Backup", 8080: "HTTP alt", 8086: "InfluxDB", 8096: "Jellyfin", 8123: "Home Assistant",
        8200: "Vault", 8443: "HTTPS alt", 8883: "MQTT (TLS)", 9000: "Portainer / MinIO", 9090: "Prometheus / Cockpit",
        9100: "Node exporter", 9443: "Portainer (TLS)", 10050: "Zabbix agent", 19999: "Netdata", 25565: "Minecraft",
        27017: "MongoDB", 32400: "Plex", 51820: "WireGuard",
    ]
    static func name(_ port: Int) -> String? { table[port] }
}

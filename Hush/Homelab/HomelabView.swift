import SwiftUI
import SwiftData

enum LabTab: String, CaseIterable, Identifiable {
    case overview, devices, services, network, diagrams, racks, runbooks, tools
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .devices: "server.rack"
        case .services: "app.connected.to.app.below.fill"
        case .network: "network"
        case .diagrams: "point.3.connected.trianglepath.dotted"
        case .racks: "square.stack.3d.down.right"
        case .runbooks: "list.bullet.clipboard"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

struct HomelabView: View {
    let title: String
    @AppStorage("labTab") private var tabRaw = LabTab.overview.rawValue
    @Environment(\.palette) private var palette

    private var tab: LabTab { LabTab(rawValue: tabRaw) ?? .overview }

    var body: some View {
        Group {
            switch tab {
            case .overview: LabOverview { tabRaw = $0.rawValue }
            case .devices: DevicesList()
            case .services: ServicesList()
            case .network: NetworkList()
            case .diagrams: DiagramsList()
            case .racks: RacksList()
            case .runbooks: RunbooksList()
            case .tools: LabTools()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(LabTab.allCases) { t in
                        Button { withAnimation(.snappy) { tabRaw = t.rawValue } } label: {
                            Label(t.label, systemImage: t.symbol)
                                .font(.hush(.subheadline).weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(tab == t ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(palette.field), in: Capsule())
                                .foregroundStyle(tab == t ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == t ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(palette.background)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
        }
        .navigationTitle(title)
    }
}

/// Small helper so every Homelab list reads the current space.
struct LabData {
    let space: String?
    let devices: [LabDevice]
    let services: [LabService]
    let subnets: [LabSubnet]
    let links: [LabLink]
    let racks: [LabRack]
    let runbooks: [Runbook]

    func device(_ id: UUID?) -> LabDevice? { id.flatMap { i in devices.first { $0.id == i } } }
}

// MARK: - Overview

struct LabOverview: View {
    var go: (LabTab) -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context
    @Query private var devicesStored: [LabDevice]
    @Query private var servicesStored: [LabService]
    @Query private var subnetsStored: [LabSubnet]
    @Query private var runbooksStored: [Runbook]
    @AppStorage("labPricePerKWh") private var pricePerKWh = 0.15
    @State private var docNote: Note?

    var body: some View {
        let sp = settings.spaceFilter
        let devices = devicesStored.live(sp)
        let active = devices.filter { $0.status == .active }
        let services = servicesStored.live(sp)
        let watts = active.filter { !$0.kind.isVirtual }.reduce(0) { $0 + $1.powerWatts }
        let monthly = watts / 1000 * 24 * 30.44 * pricePerKWh
        let dupes = NetworkMath.duplicates(active)
        let warranties = devices.filter(\.warrantyExpiringSoon)
        let due = runbooksStored.live(sp).filter(\.isDue)
        let unbacked = services.filter { !$0.backedUp }
        ScrollView {
            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    tile("\(active.filter { !$0.kind.isVirtual }.count)", "Devices", "server.rack") { go(.devices) }
                    tile("\(active.filter { $0.kind.isVirtual }.count)", "VMs & Containers", "shippingbox") { go(.devices) }
                    tile("\(services.count)", "Services", "app.connected.to.app.below.fill") { go(.services) }
                    tile("\(subnetsStored.live(sp).count)", "Subnets / VLANs", "network") { go(.network) }
                    tile(watts == 0 ? "–" : "\(Int(watts)) W", "Power draw", "bolt") { go(.tools) }
                    tile(watts == 0 ? "–" : monthly.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")), "Per month", "dollarsign.circle") { go(.tools) }
                }

                if !dupes.isEmpty || !warranties.isEmpty || !due.isEmpty || !unbacked.isEmpty {
                    Card(title: "Needs Attention", symbol: "exclamationmark.triangle") {
                        ForEach(dupes.keys.sorted(), id: \.self) { ip in
                            alert("IP \(ip) is used by \(dupes[ip]!.map(\.displayName).joined(separator: ", "))", "exclamationmark.octagon", .red) { go(.network) }
                        }
                        ForEach(due) { r in
                            alert("\(r.title.isEmpty ? "Runbook" : r.title) is due", "calendar.badge.exclamationmark", .orange) { go(.runbooks) }
                        }
                        ForEach(warranties) { d in
                            alert("\(d.displayName) warranty ends \(d.warrantyUntil!.formatted(date: .abbreviated, time: .omitted))", "shield.slash", .orange) { go(.devices) }
                        }
                        if !unbacked.isEmpty {
                            alert("\(unbacked.count) service\(unbacked.count == 1 ? "" : "s") not marked as backed up", "externaldrive.badge.xmark", .yellow) { go(.services) }
                        }
                    }
                }

                Card(title: "Documentation", symbol: "doc.text") {
                    Text("Turn your whole lab — devices, services, ports, subnets, cables and racks — into one Markdown note you can search, link and export.")
                        .font(.hush(.footnote)).foregroundStyle(.secondary)
                    HStack {
                        Button { docNote = LabDocs.makeNote(in: context, space: sp) } label: { Label("Generate Docs Note", systemImage: "doc.badge.plus") }
                            .buttonStyle(.borderedProminent)
                        ShareLink(item: LabDocs.csvFile(devices: devices, services: services, subnets: subnetsStored.live(sp)) ?? URL(fileURLWithPath: "/")) {
                            Label("CSV", systemImage: "tablecells")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if devices.isEmpty {
                    Card(title: "Get Started", symbol: "sparkles") {
                        Text("Add your router, switches and servers in Devices, then services with their ports. Diagrams, rack views and IP maps build themselves from that.")
                            .font(.hush(.footnote)).foregroundStyle(.secondary)
                        Button("Add First Device") { go(.devices) }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
        .navigationDestination(item: $docNote) { NoteEditorView(note: $0) }
    }

    private func tile(_ value: String, _ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.tint)
                Text(value).font(.hush(.title2).bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.hush(.caption)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.border))
        }
        .buttonStyle(.plain)
    }

    private func alert(_ text: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
                Text(text).font(.hush(.subheadline)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Devices

struct DevicesList: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabDevice.name) private var stored: [LabDevice]
    @State private var search = ""
    @State private var kindFilter: DeviceKind?
    @State private var showRetired = false
    @State private var newDevice: LabDevice?

    var body: some View {
        let all = stored.live(settings.spaceFilter)
        let list = all.filter { d in
            (search.isEmpty || [d.name, d.hostname, d.ip, d.mac, d.model, d.serial, d.os, d.location].contains { $0.localizedCaseInsensitiveContains(search) }
                || d.tags.contains { $0.localizedCaseInsensitiveContains(search) })
                && (kindFilter == nil || d.kind == kindFilter)
                && (showRetired || d.status != .retired)
        }
        let listIDs = Set(list.map(\.id))
        let hosts = list.filter { d in d.hostID.map { !listIDs.contains($0) } ?? true }
            .sorted { ($0.kind.tier, $0.displayName) < ($1.kind.tier, $1.displayName) }
        List {
            ForEach(hosts) { d in
                DeviceLink(device: d, all: all)
                let guests = list.filter { $0.hostID == d.id }
                ForEach(guests) { g in
                    DeviceLink(device: g, all: all).padding(.leading, 26)
                }
            }
            if all.isEmpty { EmptyMessage(text: "No devices yet. Tap + to add your router, switch or first server.") }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchHeader(text: $search, prompt: "Search name, IP, MAC, serial…") {
                FilterButton(active: kindFilter != nil || showRetired) {
                    Picker("Type", selection: $kindFilter) {
                        Text("All Types").tag(DeviceKind?.none)
                        ForEach(DeviceKind.allCases) { Label($0.label, systemImage: $0.symbol).tag(Optional($0)) }
                    }
                    Toggle("Show Retired", isOn: $showRetired)
                }
            }
        }
        .onCreate(.homelab) { add() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: add) { Image(systemName: "plus") }.accessibilityLabel("New device")
            }
        }
        .navigationDestination(item: $newDevice) { DeviceEditor(device: $0, isNew: true) }
    }

    private func add() {
        let d = LabDevice()
        context.insert(d)
        newDevice = d
    }
}

private struct DeviceLink: View {
    let device: LabDevice
    let all: [LabDevice]

    var body: some View {
        NavigationLink { DeviceEditor(device: device) } label: {
            HStack(spacing: 12) {
                SymbolTile(name: device.kind.symbol, tint: device.status == .active ? .accentColor : .gray, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.displayName).font(.hush(.headline)).lineLimit(1)
                        Circle().fill(device.status.color).frame(width: 7, height: 7)
                    }
                    Text([device.ip, device.os.isEmpty ? device.kind.label : device.os, device.model].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if device.powerWatts > 0 {
                    Text("\(Int(device.powerWatts)) W").font(.hush(.caption)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.vertical, 3)
        }
        .hushRow()
    }
}

struct DeviceEditor: View {
    @Bindable var device: LabDevice
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query private var allDevices: [LabDevice]
    @Query private var racks: [LabRack]
    @Query private var services: [LabService]
    @Query private var links: [LabLink]
    @Query private var subnets: [LabSubnet]
    @Query private var vault: [VaultItem]
    @State private var deleting = false
    @State private var tagText = ""
    @State private var newService: LabService?
    @State private var newLink: LabLink?

    var body: some View {
        let others = allDevices.live(nil).filter { $0.id != device.id }
        let myServices = services.live(nil).filter { $0.hostID == device.id }
        let myLinks = links.live(nil).filter { $0.fromID == device.id || $0.toID == device.id }
        let dupes = others.filter { !device.ip.isEmpty && $0.ip == device.ip }
        let subnet = IPv4(device.ip).flatMap { ip in subnets.live(nil).first { CIDR($0.cidr)?.contains(ip) ?? false } }
        HushForm {
            Section {
                TextField("Name (e.g. pve-01)", text: $device.name).font(.hush(.headline))
                Picker("Type", selection: $device.kind) {
                    ForEach(DeviceKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Picker("Status", selection: $device.status) {
                    ForEach(DeviceStatus.allCases) { Text($0.label).tag($0) }
                }
                if device.kind.isVirtual || device.kind == .server || device.kind == .sbc {
                    Picker("Runs On", selection: $device.hostID) {
                        Text("Bare metal / none").tag(UUID?.none)
                        ForEach(others.filter { [.hypervisor, .server, .nas, .sbc, .vm].contains($0.kind) }) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                }
            }
            Section {
                field("Hostname", $device.hostname, mono: true)
                field("IP address", $device.ip, mono: true, keyboard: .decimalPad)
                if !dupes.isEmpty {
                    Label("Also used by \(dupes.map(\.displayName).joined(separator: ", "))", systemImage: "exclamationmark.octagon.fill")
                        .font(.hush(.footnote)).foregroundStyle(.red)
                }
                if let subnet {
                    LabeledContent("Subnet", value: "\(subnet.name.isEmpty ? subnet.cidr : subnet.name)\(subnet.vlanID > 0 ? " · VLAN \(subnet.vlanID)" : "")")
                }
                field("MAC address", $device.mac, mono: true)
                field("VLAN", $device.vlan)
            } header: { Text("Network") }
            Section("System") {
                field("OS / firmware", $device.os)
                field("CPU", $device.cpu)
                field("RAM", $device.ram)
                field("Storage", $device.storage)
                if [.switchDevice, .router, .firewall, .pdu].contains(device.kind) {
                    Stepper("Ports: \(device.portCount)", value: $device.portCount, in: 0...96)
                }
            }
            Section("Hardware") {
                field("Manufacturer", $device.manufacturer)
                field("Model", $device.model)
                field("Serial number", $device.serial, mono: true)
                HStack {
                    Text("Power draw")
                    Spacer()
                    TextField("0", value: $device.powerWatts, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("W").foregroundStyle(.secondary)
                }
                optionalDate("Purchased", $device.purchaseDate)
                optionalDate("Warranty until", $device.warrantyUntil)
                HStack {
                    Text("Price")
                    Spacer()
                    TextField("0", value: $device.price, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                }
            }
            Section("Location") {
                field("Room / shelf", $device.location)
                Picker("Rack", selection: $device.rackID) {
                    Text("None").tag(UUID?.none)
                    ForEach(racks.live(nil)) { Text($0.name).tag(Optional($0.id)) }
                }
                if let rid = device.rackID, let rack = racks.first(where: { $0.id == rid }) {
                    Stepper("Position: U\(device.rackU)", value: $device.rackU, in: 1...max(rack.units, 1))
                    Stepper("Height: \(device.heightU)U", value: $device.heightU, in: 1...8)
                }
            }
            Section("Services (\(myServices.count))") {
                ForEach(myServices) { s in
                    NavigationLink { ServiceEditor(service: s) } label: {
                        LabeledContent(s.name.isEmpty ? "Service" : s.name, value: s.portSummary)
                    }
                }
                Button { let s = LabService(); s.hostID = device.id; context.insert(s); newService = s } label: {
                    Label("Add Service", systemImage: "plus")
                }
            }
            Section("Connections (\(myLinks.count))") {
                ForEach(myLinks) { l in
                    let other = allDevices.first { $0.id == (l.fromID == device.id ? l.toID : l.fromID) }
                    NavigationLink { LinkEditor(link: l) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(l.fromID == device.id ? l.fromPort : l.toPort) → \(other?.displayName ?? "?") \(l.fromID == device.id ? l.toPort : l.fromPort)")
                            Text([l.kindLabel, l.speed, l.label].filter { !$0.isEmpty }.joined(separator: " · ")).font(.hush(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
                if let first = others.first {
                    Button { let l = LabLink(from: device.id, to: first.id); context.insert(l); newLink = l } label: {
                        Label("Add Connection", systemImage: "cable.connector")
                    }
                }
            }
            Section("Credentials") {
                Picker("Vault Login", selection: $device.vaultItemID) {
                    Text("None").tag(UUID?.none)
                    ForEach(vault.filter { $0.kind == .login }) { v in Text(v.meta.title.isEmpty ? "Login" : v.meta.title).tag(Optional(v.id)) }
                }
            }
            Section("Notes & Tags") {
                TextField("Notes", text: $device.notes, axis: .vertical).lineLimit(3...12)
                TextField("Tags, comma separated", text: $tagText).textInputAutocapitalization(.never)
                    .onSubmit { device.tags = .tags(from: tagText) }
            }
            Section {
                Button("Duplicate Device") { duplicate() }
                Button("Delete Device", role: .destructive) { deleting = true; dismiss() }
            }
        }
        .navigationTitle(isNew ? "New Device" : device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $newService) { ServiceEditor(service: $0, isNew: true) }
        .navigationDestination(item: $newLink) { LinkEditor(link: $0, isNew: true) }
        .onAppear { tagText = device.tags.joined(separator: ", ") }
        .onChange(of: tagText) { device.tags = .tags(from: tagText) }
        .onDisappear {
            device.updatedAt = .now
            if deleting { TrashActions.trash(device) }
            else if isNew && device.name.trimmed.isEmpty && device.ip.isEmpty && device.hostname.isEmpty { context.delete(device) }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, mono: Bool = false, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(mono ? .hush(.body).monospaced() : .hush(.body))
        }
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

    private func duplicate() {
        let d = LabDevice(name: device.name + " copy", kind: device.kind)
        d.os = device.os; d.cpu = device.cpu; d.ram = device.ram; d.storage = device.storage
        d.manufacturer = device.manufacturer; d.model = device.model; d.powerWatts = device.powerWatts
        d.location = device.location; d.vlan = device.vlan; d.hostID = device.hostID; d.tags = device.tags
        context.insert(d)
    }
}

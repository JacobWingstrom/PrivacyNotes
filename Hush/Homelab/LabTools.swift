import SwiftUI
import SwiftData

struct LabTools: View {
    var body: some View {
        List {
            Section {
                tool("Subnet Calculator", "CIDR → mask, range, broadcast, host count", "network") { SubnetCalculator() }
                tool("Storage / RAID Calculator", "Usable space for RAID, ZFS mirror and RAIDZ", "externaldrive") { StorageCalculator() }
                tool("Power & Cost", "Running cost of your lab per month and year", "bolt") { PowerCalculator() }
                tool("UPS Runtime", "How long your battery lasts at your load", "battery.100.bolt") { UPSCalculator() }
                tool("Transfer Time", "How long a copy takes at a given speed", "arrow.left.arrow.right") { TransferCalculator() }
                tool("Unit Converter", "TB ↔ TiB, Mbps ↔ MB/s", "arrow.triangle.2.circlepath") { UnitConverter() }
                tool("Common Ports", "Well-known ports and what uses them", "list.number") { PortsReference() }
            }
        }
        .hushList()
    }

    private func tool<D: View>(_ t: String, _ d: String, _ s: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: 12) {
                SymbolTile(name: s, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t).font(.hush(.headline))
                    Text(d).font(.hush(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .hushRow()
    }
}

private struct ResultRow: View {
    let label: String
    let value: String
    var body: some View {
        LabeledContent(label) {
            Text(value).font(.hush(.body).monospaced()).textSelection(.enabled)
        }
    }
}

struct SubnetCalculator: View {
    @State private var input = "192.168.1.0/24"
    @State private var split = 0

    var body: some View {
        let c = CIDR(input)
        HushForm {
            Section {
                TextField("e.g. 10.0.20.0/23", text: $input)
                    .font(.hush(.title3).monospaced())
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if let c {
                Section("Result") {
                    ResultRow(label: "Network", value: c.description)
                    ResultRow(label: "Subnet mask", value: c.mask.description)
                    ResultRow(label: "Wildcard", value: c.wildcard.description)
                    ResultRow(label: "First host", value: c.firstHost.description)
                    ResultRow(label: "Last host", value: c.lastHost.description)
                    ResultRow(label: "Broadcast", value: c.broadcast.description)
                    ResultRow(label: "Usable hosts", value: c.usableCount.formatted())
                    ResultRow(label: "Private range", value: c.network.isPrivate ? "Yes" : "No")
                }
                if c.prefix < 30 {
                    Section {
                        Stepper("Split into /\(c.prefix + max(split, 1))", value: $split, in: 1...min(8, 30 - c.prefix))
                        let newPrefix = c.prefix + max(split, 1)
                        let count = 1 << max(split, 1)
                        let step = UInt32(1) << UInt32(32 - newPrefix)
                        ForEach(0..<count, id: \.self) { i in
                            let net = IPv4(c.network.value &+ UInt32(i) &* step)
                            ResultRow(label: "#\(i + 1)", value: "\(net)/\(newPrefix)")
                        }
                    } header: { Text("Split into Smaller Subnets") }
                }
            } else {
                Text("Enter an address and prefix, like 192.168.1.0/24.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Subnet Calculator")
    }
}

struct StorageCalculator: View {
    @State private var drives = 4
    @State private var sizeTB = 8.0
    @State private var layout = "raidz1"

    private let layouts: [(String, String)] = [("stripe", "Stripe / RAID 0"), ("mirror", "Mirror / RAID 1"), ("raid10", "RAID 10 / striped mirrors"),
                                                ("raid5", "RAID 5"), ("raid6", "RAID 6"), ("raidz1", "ZFS RAIDZ1"), ("raidz2", "ZFS RAIDZ2"), ("raidz3", "ZFS RAIDZ3")]

    var body: some View {
        let (usableDrives, tolerance) = calc()
        let usable = Double(usableDrives) * sizeTB
        let raw = Double(drives) * sizeTB
        HushForm {
            Section {
                Stepper("Drives: \(drives)", value: $drives, in: 1...60)
                HStack {
                    Text("Size per drive")
                    Spacer()
                    TextField("TB", value: $sizeTB, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("TB").foregroundStyle(.secondary)
                }
                Picker("Layout", selection: $layout) { ForEach(layouts, id: \.0) { Text($0.1).tag($0.0) } }
            }
            Section("Result") {
                if usableDrives <= 0 {
                    Text("Not enough drives for this layout.").foregroundStyle(.red)
                } else {
                    ResultRow(label: "Raw", value: "\(raw.formatted(.number.precision(.fractionLength(0...1)))) TB")
                    ResultRow(label: "Usable", value: "\(usable.formatted(.number.precision(.fractionLength(0...1)))) TB")
                    ResultRow(label: "Usable (TiB)", value: "\((usable * 1e12 / pow(2, 40)).formatted(.number.precision(.fractionLength(1)))) TiB")
                    ResultRow(label: "Efficiency", value: "\(Int(usable / max(raw, 0.001) * 100))%")
                    ResultRow(label: "Survives", value: "\(tolerance) drive failure\(tolerance == 1 ? "" : "s")")
                }
            }
            Section {
                Text("Real usable space is a little lower after filesystem overhead. ZFS works best kept under about 80% full.")
                    .font(.hush(.footnote)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Storage Calculator")
    }

    private func calc() -> (Int, Int) {
        switch layout {
        case "stripe": return (drives, 0)
        case "mirror": return (drives >= 2 ? 1 : 0, max(drives - 1, 0))
        case "raid10": return (drives >= 4 && drives % 2 == 0 ? drives / 2 : 0, 1)
        case "raid5", "raidz1": return (drives >= 3 ? drives - 1 : 0, 1)
        case "raid6", "raidz2": return (drives >= 4 ? drives - 2 : 0, 2)
        case "raidz3": return (drives >= 5 ? drives - 3 : 0, 3)
        default: return (0, 0)
        }
    }
}

struct PowerCalculator: View {
    @AppStorage("labPricePerKWh") private var price = 0.15
    @State private var custom: Double? = nil
    @State private var hours = 24.0
    @Query private var devicesStored: [LabDevice]
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let devices = devicesStored.live(settings.spaceFilter).filter { $0.status == .active && !$0.kind.isVirtual }
        let labWatts = devices.reduce(0) { $0 + $1.powerWatts }
        let watts = custom ?? labWatts
        let kwhMonth = watts / 1000 * hours * 30.44
        let currency = Locale.current.currency?.identifier ?? "USD"
        HushForm {
            Section {
                HStack {
                    Text("Load")
                    Spacer()
                    TextField("W", value: Binding(get: { custom ?? labWatts }, set: { custom = $0 }), format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    Text("W").foregroundStyle(.secondary)
                }
                if custom != nil { Button("Use My Devices (\(Int(labWatts)) W)") { custom = nil } }
                Stepper("Hours per day: \(Int(hours))", value: $hours, in: 1...24)
                HStack {
                    Text("Price per kWh")
                    Spacer()
                    TextField("0.15", value: $price, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
            }
            Section("Cost") {
                ResultRow(label: "Per day", value: (kwhMonth / 30.44 * price).formatted(.currency(code: currency)))
                ResultRow(label: "Per month", value: (kwhMonth * price).formatted(.currency(code: currency)))
                ResultRow(label: "Per year", value: (kwhMonth * 12 * price).formatted(.currency(code: currency)))
                ResultRow(label: "Energy per month", value: "\(kwhMonth.formatted(.number.precision(.fractionLength(1)))) kWh")
            }
            if !devices.isEmpty {
                Section("Biggest Draws") {
                    ForEach(devices.sorted { $0.powerWatts > $1.powerWatts }.prefix(8)) { d in
                        LabeledContent(d.displayName, value: "\(Int(d.powerWatts)) W · \((d.powerWatts / 1000 * 24 * 30.44 * price).formatted(.currency(code: currency)))/mo")
                    }
                }
            }
        }
        .navigationTitle("Power & Cost")
    }
}

struct UPSCalculator: View {
    @State private var batteryWh = 300.0
    @State private var load = 150.0
    @State private var efficiency = 85.0

    var body: some View {
        let minutes = batteryWh * (efficiency / 100) / max(load, 1) * 60
        HushForm {
            Section {
                number("Battery capacity", $batteryWh, "Wh")
                number("Load", $load, "W")
                VStack(alignment: .leading) {
                    Text("Inverter efficiency: \(Int(efficiency))%")
                    Slider(value: $efficiency, in: 60...98, step: 1)
                }
            } footer: {
                Text("Tip: battery Wh ≈ voltage × amp-hours (e.g. 2 × 12 V 9 Ah = 216 Wh).")
            }
            Section("Estimated Runtime") {
                ResultRow(label: "Runtime", value: minutes >= 60 ? "\(Int(minutes / 60)) h \(Int(minutes.truncatingRemainder(dividingBy: 60))) min" : "\(Int(minutes)) min")
                ResultRow(label: "Shut down by (80% of runtime)", value: "\(Int(minutes * 0.8)) min")
            }
        }
        .navigationTitle("UPS Runtime")
    }

    private func number(_ label: String, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(unit, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct TransferCalculator: View {
    @State private var sizeGB = 500.0
    @State private var speedMbps = 1000.0
    @State private var overhead = 10.0

    var body: some View {
        let seconds = sizeGB * 8000 / max(speedMbps * (1 - overhead / 100), 0.001)
        HushForm {
            Section {
                row("Data size", $sizeGB, "GB")
                row("Link speed", $speedMbps, "Mbps")
                Stepper("Protocol overhead: \(Int(overhead))%", value: $overhead, in: 0...50, step: 5)
                HStack {
                    ForEach([("1G", 1000.0), ("2.5G", 2500.0), ("10G", 10000.0), ("Wi-Fi 6", 600.0)], id: \.0) { name, v in
                        Button(name) { speedMbps = v }.buttonStyle(.bordered)
                    }
                }
            }
            Section("Result") {
                ResultRow(label: "Time", value: format(seconds))
                ResultRow(label: "Throughput", value: "\((speedMbps * (1 - overhead / 100) / 8).formatted(.number.precision(.fractionLength(0)))) MB/s")
            }
        }
        .navigationTitle("Transfer Time")
    }

    private func format(_ s: Double) -> String {
        let t = Int(s)
        if t >= 86400 { return "\(t / 86400) d \(t % 86400 / 3600) h" }
        if t >= 3600 { return "\(t / 3600) h \(t % 3600 / 60) min" }
        if t >= 60 { return "\(t / 60) min \(t % 60) s" }
        return "\(t) s"
    }

    private func row(_ label: String, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(unit, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct UnitConverter: View {
    @State private var tb = 4.0
    @State private var mbps = 1000.0

    var body: some View {
        HushForm {
            Section("Storage") {
                HStack {
                    TextField("TB", value: $tb, format: .number).keyboardType(.decimalPad)
                    Text("TB (what drives are sold as)").foregroundStyle(.secondary)
                }
                ResultRow(label: "TiB (what your OS shows)", value: (tb * 1e12 / pow(2, 40)).formatted(.number.precision(.fractionLength(2))))
                ResultRow(label: "GB", value: (tb * 1000).formatted())
                ResultRow(label: "GiB", value: (tb * 1e12 / pow(2, 30)).formatted(.number.precision(.fractionLength(0))))
            }
            Section("Network") {
                HStack {
                    TextField("Mbps", value: $mbps, format: .number).keyboardType(.decimalPad)
                    Text("Mbps").foregroundStyle(.secondary)
                }
                ResultRow(label: "MB/s", value: (mbps / 8).formatted(.number.precision(.fractionLength(1))))
                ResultRow(label: "GB per hour", value: (mbps / 8 * 3600 / 1000).formatted(.number.precision(.fractionLength(1))))
            }
        }
        .navigationTitle("Unit Converter")
    }
}

struct PortsReference: View {
    @State private var search = ""
    var body: some View {
        let rows = CommonPorts.table.sorted { $0.key < $1.key }
            .filter { search.isEmpty || "\($0.key)".contains(search) || $0.value.localizedCaseInsensitiveContains(search) }
        List(rows, id: \.key) { port, name in
            HStack {
                Text("\(port)").font(.hush(.headline).monospaced()).frame(width: 70, alignment: .leading)
                Text(name)
            }
            .hushRow()
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search port or service…") }
        .navigationTitle("Common Ports")
    }
}

// MARK: - Generated documentation

enum LabDocs {
    @MainActor
    static func makeNote(in ctx: ModelContext, space: String?) -> Note {
        let devices = ((try? ctx.fetch(FetchDescriptor<LabDevice>())) ?? []).live(space)
        let services = ((try? ctx.fetch(FetchDescriptor<LabService>())) ?? []).live(space)
        let subnets = ((try? ctx.fetch(FetchDescriptor<LabSubnet>())) ?? []).live(space)
        let links = ((try? ctx.fetch(FetchDescriptor<LabLink>())) ?? []).live(space)
        let racks = ((try? ctx.fetch(FetchDescriptor<LabRack>())) ?? []).live(space)
        func name(_ id: UUID?) -> String { devices.first { $0.id == id }?.displayName ?? "—" }
        func cell(_ s: String) -> String { s.isEmpty ? " " : s.replacingOccurrences(of: "|", with: "/") }

        var md = "Generated \(Date().formatted(date: .abbreviated, time: .shortened)) from Hush → Homelab.\n\n"
        md += "## Devices\n| Name | Type | IP | MAC | OS | Model | Host | Power |\n|---|---|---|---|---|---|---|---|\n"
        for d in devices.sorted(by: { ($0.kind.tier, $0.displayName) < ($1.kind.tier, $1.displayName) }) {
            md += "| \(cell(d.displayName)) | \(d.kind.label) | \(cell(d.ip)) | \(cell(d.mac)) | \(cell(d.os)) | \(cell(d.model)) | \(d.hostID == nil ? " " : name(d.hostID)) | \(d.powerWatts > 0 ? "\(Int(d.powerWatts)) W" : " ") |\n"
        }
        md += "\n## Services\n| Service | Host | Ports | URL | Image | Backed up |\n|---|---|---|---|---|---|\n"
        for s in services.sorted(by: { $0.name < $1.name }) {
            md += "| \(cell(s.name)) | \(name(s.hostID)) | \(cell(s.portSummary)) | \(cell(s.url)) | \(cell(s.image)) | \(s.backedUp ? "yes" : "**no**") |\n"
        }
        if !subnets.isEmpty {
            md += "\n## Subnets & VLANs\n| Name | VLAN | CIDR | Gateway | DHCP | Purpose |\n|---|---|---|---|---|---|\n"
            for s in subnets.sorted(by: { $0.vlanID < $1.vlanID }) {
                md += "| \(cell(s.name)) | \(s.vlanID == 0 ? " " : "\(s.vlanID)") | \(s.cidr) | \(cell(s.gateway)) | \(s.dhcpStart.isEmpty ? " " : "\(s.dhcpStart)–\(s.dhcpEnd)") | \(cell(s.purpose)) |\n"
            }
        }
        if !links.isEmpty {
            md += "\n## Cabling\n| From | Port | To | Port | Type | Speed | Label |\n|---|---|---|---|---|---|---|\n"
            for l in links { md += "| \(name(l.fromID)) | \(cell(l.fromPort)) | \(name(l.toID)) | \(cell(l.toPort)) | \(l.kindLabel) | \(cell(l.speed)) | \(cell(l.label)) |\n" }
        }
        for r in racks {
            md += "\n## Rack: \(r.name) (\(r.units)U)\n"
            for d in devices.filter({ $0.rackID == r.id }).sorted(by: { $0.rackU > $1.rackU }) {
                md += "- U\(d.rackU)\(d.heightU > 1 ? "–\(d.rackU + d.heightU - 1)" : ""): \(d.displayName)\n"
            }
        }
        let dupes = NetworkMath.duplicates(devices)
        if !dupes.isEmpty {
            md += "\n## Warnings\n"
            for (ip, ds) in dupes { md += "- IP \(ip) is used by \(ds.map(\.displayName).joined(separator: ", "))\n" }
        }
        let n = Note()
        n.title = "Homelab Documentation"
        n.emoji = "server.rack"
        n.tags = ["homelab"]
        n.body = md
        ctx.insert(n)
        return n
    }

    static func csvFile(devices: [LabDevice], services: [LabService], subnets: [LabSubnet]) -> URL? {
        var rows = [["Name", "Type", "Status", "Hostname", "IP", "MAC", "VLAN", "OS", "CPU", "RAM", "Storage", "Manufacturer", "Model", "Serial",
                     "Location", "Power W", "Purchased", "Warranty", "Services"]]
        let iso = ISO8601DateFormatter()
        for d in devices {
            let svc = services.filter { $0.hostID == d.id }.map { "\($0.name) (\($0.portSummary))" }.joined(separator: "; ")
            rows.append([d.displayName, d.kind.label, d.status.label, d.hostname, d.ip, d.mac, d.vlan, d.os, d.cpu, d.ram, d.storage,
                         d.manufacturer, d.model, d.serial, d.location, d.powerWatts > 0 ? "\(d.powerWatts)" : "",
                         d.purchaseDate.map(iso.string) ?? "", d.warrantyUntil.map(iso.string) ?? "", svc])
        }
        return Exporter.write(Exporter.csv(rows), name: "Homelab Inventory.csv")
    }
}

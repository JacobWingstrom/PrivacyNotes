import SwiftUI
import SwiftData

struct NetworkList: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabSubnet.vlanID) private var subnetsStored: [LabSubnet]
    @Query private var devicesStored: [LabDevice]
    @Query private var linksStored: [LabLink]
    @State private var view = "subnets"
    @State private var newSubnet: LabSubnet?
    @State private var newLink: LabLink?

    var body: some View {
        let sp = settings.spaceFilter
        let subnets = subnetsStored.live(sp)
        let devices = devicesStored.live(nil)
        let links = linksStored.live(sp)
        let dupes = NetworkMath.duplicates(devices.filter { $0.status == .active })
        List {
            Picker("View", selection: $view) {
                Text("Subnets & VLANs").tag("subnets")
                Text("Cables").tag("cables")
                Text("All IPs").tag("ips")
            }
            .pickerStyle(.segmented)
            .plainRow(top: 12, bottom: 4)

            switch view {
            case "cables":
                ForEach(links) { l in
                    let a = devices.first { $0.id == l.fromID }, b = devices.first { $0.id == l.toID }
                    NavigationLink { LinkEditor(link: l) } label: {
                        HStack(spacing: 10) {
                            Capsule().fill(NoteColor(rawValue: l.colorName)?.color ?? .gray).frame(width: 5, height: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a?.displayName ?? "?") \(l.fromPort)  ↔  \(b?.displayName ?? "?") \(l.toPort)").lineLimit(1)
                                Text([l.kindLabel, l.speed, l.label, l.length, l.vlan.isEmpty ? "" : "VLAN \(l.vlan)"].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.hush(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions { Button(role: .destructive) { TrashActions.trash(l) } label: { Label("Delete", systemImage: "trash") } }
                    .hushRow()
                }
                if links.isEmpty { EmptyMessage(text: devices.count < 2 ? "Add at least two devices, then connect them here." : "No cables yet. Tap + to record which port goes where.") }
            case "ips":
                let withIP = devices.filter { IPv4($0.ip) != nil }.sorted { IPv4($0.ip)! < IPv4($1.ip)! }
                ForEach(withIP) { d in
                    NavigationLink { DeviceEditor(device: d) } label: {
                        HStack {
                            Text(d.ip).font(.hush(.body).monospaced()).foregroundStyle(dupes[IPv4(d.ip)!.description] != nil ? Color.red : Color.primary)
                                .frame(width: 140, alignment: .leading)
                            Image(systemName: d.kind.symbol).foregroundStyle(.tint)
                            Text(d.displayName).lineLimit(1)
                            Spacer()
                            if !d.mac.isEmpty { Text(d.mac).font(.hush(.caption2).monospaced()).foregroundStyle(.tertiary) }
                        }
                    }
                    .hushRow()
                }
                if withIP.isEmpty { EmptyMessage(text: "Give your devices IP addresses to see them here.") }
            default:
                ForEach(subnets) { s in
                    NavigationLink { SubnetDetail(subnet: s) } label: { SubnetRow(subnet: s, devices: devices) }
                        .swipeActions { Button(role: .destructive) { TrashActions.trash(s) } label: { Label("Delete", systemImage: "trash") } }
                        .hushRow()
                }
                let overlaps = overlapPairs(subnets)
                ForEach(overlaps, id: \.self) { o in
                    Label(o, systemImage: "exclamationmark.triangle.fill").font(.hush(.footnote)).foregroundStyle(.orange).hushRow()
                }
                if subnets.isEmpty { EmptyMessage(text: "No subnets yet. Tap + to add your LAN, IoT, guest or management VLANs.") }
            }
        }
        .hushList()
        .onCreate(.homelab) { add() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(action: add) { Image(systemName: "plus") }.accessibilityLabel("Add") } }
        .navigationDestination(item: $newSubnet) { SubnetEditor(subnet: $0, isNew: true) }
        .navigationDestination(item: $newLink) { LinkEditor(link: $0, isNew: true) }
    }

    private func add() {
        if view == "cables" {
            let d = devicesStored.live(nil)
            guard d.count >= 2 else { return }
            let l = LabLink(from: d[0].id, to: d[1].id)
            context.insert(l)
            newLink = l
        } else {
            let s = LabSubnet(name: "", cidr: "192.168.\(subnetsStored.count + 1).0/24")
            context.insert(s)
            newSubnet = s
        }
    }

    private func overlapPairs(_ subnets: [LabSubnet]) -> [String] {
        var out: [String] = []
        for (i, a) in subnets.enumerated() {
            for b in subnets[(i + 1)...] {
                if let x = CIDR(a.cidr), let y = CIDR(b.cidr), x.overlaps(y) {
                    out.append("\(a.name.isEmpty ? a.cidr : a.name) overlaps \(b.name.isEmpty ? b.cidr : b.name)")
                }
            }
        }
        return out
    }
}

private struct SubnetRow: View {
    let subnet: LabSubnet
    let devices: [LabDevice]
    var body: some View {
        let cidr = CIDR(subnet.cidr)
        let used = cidr.map { c in devices.filter { IPv4($0.ip).map(c.contains) ?? false }.count } ?? 0
        HStack(spacing: 12) {
            Text(subnet.vlanID > 0 ? "\(subnet.vlanID)" : "–")
                .font(.hush(.headline).monospaced())
                .frame(width: 44, height: 36)
                .background(subnet.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(subnet.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(subnet.name.isEmpty ? subnet.cidr : subnet.name).font(.hush(.headline))
                Text("\(subnet.cidr)\(subnet.purpose.isEmpty ? "" : " · \(subnet.purpose)")").font(.hush(.caption).monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if let c = cidr {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(used) used").font(.hush(.caption)).monospacedDigit()
                    Text("of \(c.usableCount)").font(.hush(.caption2)).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Label("Invalid", systemImage: "exclamationmark.triangle").font(.hush(.caption)).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }
}

/// A map of every address in the subnet: gateway, DHCP pool, devices, free.
struct SubnetDetail: View {
    @Bindable var subnet: LabSubnet
    @Environment(\.palette) private var palette
    @Query private var devicesStored: [LabDevice]
    @State private var selected: IPv4?
    @State private var editing = false
    @State private var copied = false

    var body: some View {
        let devices = devicesStored.live(nil)
        let cidr = CIDR(subnet.cidr)
        let byIP = Dictionary(grouping: devices.filter { IPv4($0.ip) != nil }) { IPv4($0.ip)! }
        let gw = IPv4(subnet.gateway)
        let dhcp: ClosedRange<UInt32>? = {
            guard let a = IPv4(subnet.dhcpStart), let b = IPv4(subnet.dhcpEnd), a <= b else { return nil }
            return a.value...b.value
        }()
        let next = NetworkMath.nextFree(in: subnet, devices: devices)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c = cidr {
                    Card(title: subnet.name.isEmpty ? "Subnet" : subnet.name, symbol: "network") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            row("Network", c.description)
                            row("Mask", c.mask.description)
                            row("Hosts", "\(c.firstHost) – \(c.lastHost)")
                            row("Usable", "\(c.usableCount)")
                            row("Broadcast", c.broadcast.description)
                            if !subnet.gateway.isEmpty { row("Gateway", subnet.gateway) }
                            if dhcp != nil { row("DHCP", "\(subnet.dhcpStart) – \(subnet.dhcpEnd)") }
                            if !subnet.dns.isEmpty { row("DNS", subnet.dns) }
                            if subnet.vlanID > 0 { row("VLAN", "\(subnet.vlanID)") }
                        }
                        if let next {
                            Button {
                                UIPasteboard.general.string = next.description
                                copied = true
                            } label: {
                                Label(copied ? "Copied \(next)" : "Next free IP: \(next)", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    let hosts = c.hosts
                    if hosts.isEmpty {
                        Text("This subnet is too large to map address by address (bigger than /20).")
                            .font(.hush(.footnote)).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 14) {
                            legend(.green, "Device")
                            legend(.purple, "Gateway")
                            legend(.blue.opacity(0.45), "DHCP")
                            legend(.red, "Conflict")
                        }
                        .font(.hush(.caption))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 16), spacing: 3) {
                            ForEach(hosts, id: \.self) { ip in
                                let users = byIP[ip] ?? []
                                let color: Color = users.count > 1 ? .red
                                    : (ip == gw ? .purple : (!users.isEmpty ? .green : ((dhcp?.contains(ip.value) ?? false) ? Color.blue.opacity(0.45) : palette.field)))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(height: 18)
                                    .overlay {
                                        if selected == ip { RoundedRectangle(cornerRadius: 3).stroke(.primary, lineWidth: 2) }
                                    }
                                    .onTapGesture { selected = ip }
                                    .accessibilityLabel("\(ip): \(users.map(\.displayName).joined(separator: ", "))")
                            }
                        }
                        if let s = selected {
                            let users = byIP[s] ?? []
                            Card(title: s.description, symbol: "number") {
                                if s == gw { Text("Gateway") }
                                if dhcp?.contains(s.value) ?? false { Text("In the DHCP pool").foregroundStyle(.secondary) }
                                ForEach(users) { d in
                                    NavigationLink { DeviceEditor(device: d) } label: { Label(d.displayName, systemImage: d.kind.symbol) }
                                }
                                if users.isEmpty && s != gw { Text("Free").foregroundStyle(.green) }
                            }
                        }
                    }
                } else {
                    Label("“\(subnet.cidr)” isn't a valid subnet. Use a form like 192.168.10.0/24.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if !subnet.notes.isEmpty { Text(subnet.notes).font(.hush(.callout)).foregroundStyle(.secondary) }
            }
            .padding()
        }
        .background(palette.background)
        .navigationTitle(subnet.name.isEmpty ? subnet.cidr : subnet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) { NavigationStack { SubnetEditor(subnet: subnet).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } } } } }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).font(.hush(.body).monospaced()).textSelection(.enabled)
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12); Text(t) }
    }
}

struct SubnetEditor: View {
    @Bindable var subnet: LabSubnet
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false

    var body: some View {
        let cidr = CIDR(subnet.cidr)
        HushForm {
            Section {
                TextField("Name (e.g. Main LAN, IoT, Guest)", text: $subnet.name).font(.hush(.headline))
                TextField("Purpose", text: $subnet.purpose)
                Picker("Color", selection: $subnet.colorName) {
                    ForEach(NoteColor.allCases.filter { $0 != .none }) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section {
                mono("Subnet (CIDR)", $subnet.cidr)
                if cidr == nil { Text("Use a form like 192.168.10.0/24").font(.hush(.footnote)).foregroundStyle(.red) }
                Stepper("VLAN ID: \(subnet.vlanID == 0 ? "none" : "\(subnet.vlanID)")", value: $subnet.vlanID, in: 0...4094)
                mono("Gateway", $subnet.gateway)
                mono("DHCP start", $subnet.dhcpStart)
                mono("DHCP end", $subnet.dhcpEnd)
                mono("DNS servers", $subnet.dns)
                TextField("Local domain (e.g. home.arpa)", text: $subnet.domain).textInputAutocapitalization(.never)
            } header: { Text("Addressing") } footer: {
                if let c = cidr { Text("\(c.usableCount) usable addresses: \(c.firstHost) to \(c.lastHost)") }
            }
            Section("Notes") { TextField("Firewall rules, mDNS, notes…", text: $subnet.notes, axis: .vertical).lineLimit(3...10) }
            Section { Button("Delete Subnet", role: .destructive) { deleting = true; dismiss() } }
        }
        .navigationTitle(isNew ? "New Subnet" : "Edit Subnet")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { if deleting { TrashActions.trash(subnet) } }
    }

    private func mono(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.hush(.body).monospaced())
        }
    }
}

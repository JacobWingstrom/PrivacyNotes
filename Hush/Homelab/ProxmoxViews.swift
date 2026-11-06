import SwiftUI
import SwiftData

// MARK: - Proxmox cluster

struct ProxmoxView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Query(sort: \LabDevice.vmid) private var stored: [LabDevice]
    @Query private var stacksStored: [ComposeStack]
    @State private var importing = false
    @State private var newDevice: LabDevice?
    @State private var choosing = false

    var body: some View {
        let devices = stored.live(settings.spaceFilter)
        let nodes = devices.filter { $0.kind == .hypervisor }.sorted { $0.displayName < $1.displayName }
        let guests = devices.filter(\.kind.isGuest)
        let stacks = stacksStored.live(nil)
        let clusters = Dictionary(grouping: nodes) { $0.clusterName.trimmed.isEmpty ? "Standalone" : $0.clusterName }
        let orphans = guests.filter { g in !nodes.contains { $0.id == g.hostID } }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button { importing = true } label: { Label("Import from Proxmox", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 38) }
                        .buttonStyle(.borderedProminent)
                    Button { choosing = true } label: { Label("Add", systemImage: "plus").frame(minHeight: 38) }
                        .buttonStyle(.bordered)
                }
                if nodes.isEmpty && guests.isEmpty {
                    Card(title: "Document your Proxmox lab", symbol: "square.stack.3d.up") {
                        Text("Run one command on any node and paste the result — every node, VM and LXC in your cluster is added with its VMID, cores, RAM and disk. Then paste each guest's compose files in Stacks.")
                            .font(.hush(.footnote)).foregroundStyle(.secondary)
                    }
                }
                ForEach(clusters.keys.sorted(), id: \.self) { cluster in
                    let members = clusters[cluster] ?? []
                    HStack {
                        Label(cluster, systemImage: members.count > 1 ? "circle.hexagongrid" : "square.stack.3d.up")
                            .font(.hush(.headline))
                        Spacer()
                        Text("\(members.count) node\(members.count == 1 ? "" : "s") · \(guests.filter { g in members.contains { $0.id == g.hostID } }.count) guests")
                            .font(.hush(.caption)).foregroundStyle(.secondary)
                    }
                    ForEach(members) { node in
                        NodeCard(node: node, guests: guests.filter { $0.hostID == node.id }.sorted { $0.vmid < $1.vmid }, stacks: stacks)
                    }
                }
                if !orphans.isEmpty {
                    Text("Not assigned to a node").font(.hush(.headline))
                    VStack(spacing: 0) {
                        ForEach(orphans) { g in GuestRow(guest: g, stackCount: stacks.filter { $0.hostID == g.id }.count) }
                    }
                    .padding(10)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
        .onCreate(.homelab) { choosing = true }
        .confirmationDialog("Add", isPresented: $choosing) {
            Button("Proxmox Node") { add(.hypervisor) }
            Button("Virtual Machine") { add(.vm) }
            Button("LXC Container") { add(.lxc) }
        }
        .sheet(isPresented: $importing) { ProxmoxImportSheet() }
        .navigationDestination(item: $newDevice) { DeviceEditor(device: $0, isNew: true) }
    }

    private func add(_ kind: DeviceKind) {
        let d = LabDevice(kind: kind)
        if kind.isGuest {
            let nodes = stored.live(nil).filter { $0.kind == .hypervisor }
            d.hostID = nodes.count == 1 ? nodes.first?.id : nil
            d.vmid = (stored.map(\.vmid).max() ?? 99) + 1
        }
        context.insert(d)
        newDevice = d
    }
}

private struct NodeCard: View {
    let node: LabDevice
    let guests: [LabDevice]
    let stacks: [ComposeStack]
    @Environment(\.palette) private var palette

    var body: some View {
        let running = guests.filter { $0.status == .active }
        let cores = running.reduce(0) { $0 + $1.cores }
        let ramGB = Double(running.reduce(0) { $0 + $1.memoryMB }) / 1024
        let nodeRAM = Double(node.memoryMB) / 1024
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { DeviceEditor(device: node) } label: {
                HStack(spacing: 12) {
                    SymbolTile(name: "square.stack.3d.up", size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.displayName).font(.hush(.headline))
                        Text([node.ip, node.os, node.cpu].filter { !$0.isEmpty }.joined(separator: " · ")).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                meter("vCPU", "\(cores)\(node.cores > 0 ? "/\(node.cores)" : "")", node.cores > 0 ? Double(cores) / Double(node.cores) : nil)
                meter("RAM", "\(ramGB.formatted(.number.precision(.fractionLength(0...1))))\(nodeRAM > 0 ? "/\(Int(nodeRAM))" : "") GB", nodeRAM > 0 ? ramGB / nodeRAM : nil)
                meter("Guests", "\(running.count)/\(guests.count)", nil)
            }
            if !guests.isEmpty {
                Rectangle().fill(palette.border).frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(guests) { g in GuestRow(guest: g, stackCount: stacks.filter { $0.hostID == g.id }.count) }
                }
            }
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.border))
    }

    private func meter(_ label: String, _ value: String, _ fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.hush(.caption2)).foregroundStyle(.secondary)
            Text(value).font(.hush(.subheadline).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let f = fraction {
                ProgressView(value: min(f, 1)).tint(f > 1 ? .red : (f > 0.85 ? .orange : .accentColor))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.field, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct GuestRow: View {
    let guest: LabDevice
    let stackCount: Int

    var body: some View {
        NavigationLink { DeviceEditor(device: guest) } label: {
            HStack(spacing: 10) {
                Text(guest.kind == .lxc ? "LXC" : "VM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background((guest.kind == .lxc ? Color.orange : Color.blue).opacity(0.2), in: Capsule())
                    .foregroundStyle(guest.kind == .lxc ? Color.orange : Color.blue)
                Text(guest.vmid > 0 ? "\(guest.vmid)" : "—").font(.hush(.caption).monospaced()).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(guest.displayName).lineLimit(1)
                        Circle().fill(guest.status.color).frame(width: 6, height: 6)
                        if guest.onBoot { Image(systemName: "power").font(.system(size: 9)).foregroundStyle(.secondary) }
                    }
                    Text(spec).font(.hush(.caption2)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if stackCount > 0 {
                    Label("\(stackCount)", systemImage: "shippingbox").font(.hush(.caption)).foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private var spec: String {
        var parts: [String] = []
        if !guest.ip.isEmpty { parts.append(guest.ip) }
        if guest.cores > 0 { parts.append("\(guest.cores) vCPU") }
        if guest.memoryMB > 0 { parts.append(guest.memoryMB >= 1024 ? "\((Double(guest.memoryMB) / 1024).formatted(.number.precision(.fractionLength(0...1)))) GB" : "\(guest.memoryMB) MB") }
        if guest.diskGB > 0 { parts.append("\(guest.diskGB.formatted()) GB disk") }
        if !guest.vlanTag.isEmpty { parts.append("VLAN \(guest.vlanTag)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Import

struct ProxmoxImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [LabDevice]
    @State private var mode = "cluster"
    @State private var text = ""
    @State private var cluster = ""
    @State private var targetGuest: UUID?
    @State private var message: String?

    static let clusterCommand = "pvesh get /cluster/resources --type vm --output-format json"

    var body: some View {
        NavigationStack {
            HushForm {
                Section {
                    Picker("Import", selection: $mode) {
                        Text("Whole Cluster").tag("cluster")
                        Text("One Guest's Config").tag("config")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    CommandRow(command: mode == "cluster" ? Self.clusterCommand : "qm config 101    # or: pct config 105")
                } header: { Text("1. Run this on any Proxmox node") } footer: {
                    Text(mode == "cluster"
                         ? "Lists every VM and LXC on every node in the cluster, with VMID, name, cores, RAM and disk."
                         : "Shows one guest's cores, memory, disk, bridge, VLAN tag, MAC and (for LXCs) IP address.")
                }
                Section("2. Paste the output") {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { s in text = s.first ?? "" }
                }
                if mode == "cluster" {
                    Section {
                        TextField("Cluster name (optional, e.g. homelab)", text: $cluster).textInputAutocapitalization(.never)
                    } footer: { Text("Nodes are created automatically. Existing guests are matched by VMID and updated.") }
                } else {
                    Section("3. Apply to") {
                        Picker("Guest", selection: $targetGuest) {
                            Text("New guest").tag(UUID?.none)
                            ForEach(devices.live(nil).filter(\.kind.isGuest).sorted { $0.vmid < $1.vmid }) { Text("\($0.vmid) · \($0.displayName)").tag(Optional($0.id)) }
                        }
                    }
                }
            }
            .navigationTitle("Import from Proxmox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import", action: run).disabled(text.trimmed.isEmpty) }
            }
            .alert("Import", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { if message?.hasPrefix("Imported") == true || message?.hasPrefix("Updated") == true { dismiss() } }
            } message: { Text(message ?? "") }
        }
    }

    private func run() {
        if mode == "cluster" {
            guard let guests = ProxmoxParser.clusterResources(text) else {
                message = "That doesn't look like the JSON from the command above. Make sure to include --output-format json."
                return
            }
            message = LabImport.applyCluster(guests, cluster: cluster.trimmed, in: context)
        } else {
            let cfg = ProxmoxParser.config(text)
            guard cfg.cores > 0 || cfg.memoryMB > 0 || !cfg.name.isEmpty else {
                message = "Couldn't read that config. Paste the full output of qm config or pct config."
                return
            }
            let g = devices.first { $0.id == targetGuest } ?? {
                let d = LabDevice(kind: cfg.isLXC ? .lxc : .vm)
                context.insert(d)
                return d
            }()
            LabImport.applyConfig(cfg, to: g)
            message = "Updated \(g.displayName)."
        }
    }
}

struct CommandRow: View {
    let command: String
    @State private var copied = false
    var body: some View {
        HStack(alignment: .top) {
            Text(command).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = command
                copied = true
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy command")
        }
    }
}

enum LabImport {
    @MainActor
    static func applyCluster(_ guests: [ProxmoxParser.Guest], cluster: String, in ctx: ModelContext) -> String {
        var all = ((try? ctx.fetch(FetchDescriptor<LabDevice>())) ?? []).filter { $0.deletedAt == nil }
        var created = 0, updated = 0
        var nodeIDs: [String: UUID] = [:]
        for nodeName in Set(guests.map(\.node)) where !nodeName.isEmpty {
            if let n = all.first(where: { $0.kind == .hypervisor && ($0.name == nodeName || $0.hostname == nodeName) }) {
                nodeIDs[nodeName] = n.id
                if !cluster.isEmpty { n.clusterName = cluster }
            } else {
                let n = LabDevice(name: nodeName, kind: .hypervisor)
                n.hostname = nodeName
                n.os = "Proxmox VE"
                n.clusterName = cluster
                ctx.insert(n)
                all.append(n)
                nodeIDs[nodeName] = n.id
                created += 1
            }
        }
        for g in guests where !g.template {
            let existing = all.first { $0.kind.isGuest && $0.vmid == g.vmid }
            let d = existing ?? {
                let x = LabDevice(name: g.name, kind: g.isLXC ? .lxc : .vm)
                ctx.insert(x)
                created += 1
                return x
            }()
            if existing != nil { updated += 1 }
            d.kind = g.isLXC ? .lxc : .vm
            d.vmid = g.vmid
            if d.name.isEmpty || existing == nil { d.name = g.name }
            d.cores = g.cores
            d.memoryMB = g.memoryMB
            d.diskGB = g.diskGB
            d.hostID = nodeIDs[g.node] ?? d.hostID
            d.status = g.running ? .active : .spare
            d.updatedAt = .now
        }
        try? ctx.save()
        return "Imported \(guests.count) guests: \(created) new, \(updated) updated."
    }

    static func applyConfig(_ c: ProxmoxParser.Config, to d: LabDevice) {
        if !c.name.isEmpty && d.name.isEmpty { d.name = c.name }
        if !c.name.isEmpty { d.hostname = c.name }
        if c.cores > 0 { d.cores = c.cores }
        if c.memoryMB > 0 { d.memoryMB = c.memoryMB }
        if c.diskGB > 0 { d.diskGB = c.diskGB }
        if !c.storage.isEmpty { d.storagePool = c.storage }
        if !c.bridge.isEmpty { d.bridge = c.bridge }
        d.vlanTag = c.vlanTag
        if !c.mac.isEmpty { d.mac = c.mac }
        if !c.ip.isEmpty { d.ip = c.ip }
        if !c.ostype.isEmpty { d.os = c.ostype }
        d.onBoot = c.onBoot
        if !c.description.isEmpty && d.notes.isEmpty { d.notes = c.description }
        if c.isLXC { d.kind = .lxc }
        d.updatedAt = .now
    }

    /// Creates or updates services for a stack from its compose file.
    @MainActor
    static func sync(_ stack: ComposeStack, in ctx: ModelContext) -> Int {
        let parsed = ComposeParser.parse(stack.yaml)
        let existing = ((try? ctx.fetch(FetchDescriptor<LabService>())) ?? []).filter { $0.stackID == stack.id && $0.deletedAt == nil }
        var byName: [String: LabService] = [:]
        for s in existing { byName[s.containerName.isEmpty ? s.name : s.containerName] = byName[s.containerName.isEmpty ? s.name : s.containerName] ?? s }
        var seen: [UUID] = []
        var created: [String: LabService] = [:]
        for p in parsed {
            let key = p.containerName.isEmpty ? p.name : p.containerName
            let s = byName[key] ?? existing.first { $0.name == p.name } ?? {
                let x = LabService(name: p.name)
                x.symbol = DiagramBuilder.guessSymbol(p.name + " " + p.image).replacingOccurrences(of: "circle.grid.2x2", with: "shippingbox")
                ctx.insert(x)
                return x
            }()
            s.stackID = stack.id
            s.hostID = stack.hostID
            s.containerName = p.containerName
            s.image = p.image
            if let tag = p.image.split(separator: ":").last, p.image.contains(":") { s.version = String(tag) }
            s.ports = p.ports
            s.volumes = p.volumes
            s.networks = p.networks.joined(separator: ", ")
            s.restartPolicy = p.restart
            s.envKeys = p.envKeys
            s.dataPath = p.volumes.first.map { String($0.split(separator: ":").first ?? "") } ?? s.dataPath
            seen.append(s.id)
            created[p.name] = s
        }
        // Wire depends_on between services of the same stack.
        for p in parsed {
            guard let s = created[p.name] else { continue }
            s.dependsOn = p.dependsOn.compactMap { created[$0]?.id }
        }
        // Services removed from the file go to the Trash.
        for s in existing where !seen.contains(s.id) { TrashActions.trash(s) }
        stack.updatedAt = .now
        return parsed.count
    }
}

// MARK: - Stacks

struct StacksList: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \ComposeStack.name) private var stored: [ComposeStack]
    @Query private var devices: [LabDevice]
    @Query private var services: [LabService]
    @State private var importing = false
    @State private var newStack: ComposeStack?

    var body: some View {
        let stacks = stored.live(settings.spaceFilter)
        let hosts = devices.live(nil)
        let groups = Dictionary(grouping: stacks) { $0.hostID }
        let hostName: (UUID?) -> String = { id in hosts.first(where: { $0.id == id }).map { "\($0.vmid > 0 ? "\($0.vmid) · " : "")\($0.displayName)" } ?? "No Host" }
        List {
            HStack(spacing: 10) {
                Button { importing = true } label: { Label("Import Compose", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 36) }
                    .buttonStyle(.borderedProminent)
                Button { add() } label: { Label("New", systemImage: "plus").frame(minHeight: 36) }
                    .buttonStyle(.bordered)
            }
            .plainRow(top: 12, bottom: 6)
            ForEach(groups.keys.sorted { hostName($0) < hostName($1) }, id: \.self) { hid in
                Section {
                    ForEach(groups[hid] ?? []) { st in
                        let svc = services.filter { $0.stackID == st.id && $0.deletedAt == nil }
                        NavigationLink { StackEditor(stack: st) } label: {
                            HStack(spacing: 12) {
                                SymbolTile(name: "shippingbox", size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(st.name.isEmpty ? "Stack" : st.name).font(.hush(.headline))
                                    Text(svc.isEmpty ? (st.path.isEmpty ? "No services yet" : st.path)
                                         : svc.map { s in s.name + (s.ports.first.map { ":\($0.port)" } ?? "") }.joined(separator: ", "))
                                        .font(.hush(.caption).monospaced()).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Text("\(svc.count)").font(.hush(.caption)).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions { Button(role: .destructive) { TrashActions.trash(st) } label: { Label("Delete", systemImage: "trash") } }
                        .hushRow()
                    }
                } header: {
                    ListHeader(title: hostName(hid))
                }
            }
            if stacks.isEmpty {
                EmptyMessage(text: "No stacks yet. Tap Import Compose and paste a compose.yaml (or every compose file on a VM at once) — services, ports, images and volumes fill in by themselves.")
            }
        }
        .hushList()
        .onCreate(.homelab) { importing = true }
        .sheet(isPresented: $importing) { ComposeImportSheet() }
        .navigationDestination(item: $newStack) { StackEditor(stack: $0) }
    }

    private func add() {
        let s = ComposeStack(name: "")
        context.insert(s)
        newStack = s
    }
}

struct ComposeImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [LabDevice]
    @Query private var stacks: [ComposeStack]
    @State private var mode = "compose"
    @State private var text = ""
    @State private var hostID: UUID?
    @State private var name = ""
    @State private var redact = true
    @State private var message: String?

    static let dumpCommand = #"for f in $(find /opt /srv /home /root -maxdepth 4 \( -name 'docker-compose.y*ml' -o -name 'compose.y*ml' \) 2>/dev/null); do echo "### $f"; cat "$f"; done"#
    static let psCommand = #"docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'"#

    var body: some View {
        let hosts = devices.live(nil).filter { $0.kind.isGuest || [.server, .nas, .sbc, .hypervisor].contains($0.kind) }
        NavigationStack {
            HushForm {
                Section {
                    Picker("From", selection: $mode) {
                        Text("Compose File(s)").tag("compose")
                        Text("docker ps").tag("ps")
                    }
                    .pickerStyle(.segmented)
                    Picker("Runs On", selection: $hostID) {
                        Text("Choose a VM or LXC").tag(UUID?.none)
                        ForEach(hosts.sorted { ($0.vmid, $0.displayName) < ($1.vmid, $1.displayName) }) { h in
                            Text("\(h.vmid > 0 ? "\(h.vmid) · " : "")\(h.displayName)").tag(Optional(h.id))
                        }
                    }
                }
                if mode == "compose" {
                    Section {
                        CommandRow(command: Self.dumpCommand)
                    } header: { Text("Grab every compose file on the guest (optional)") } footer: {
                        Text("Run it inside the VM or LXC and paste everything below. Each file becomes its own stack, named after its folder. Or just paste one compose.yaml.")
                    }
                    Section {
                        TextField("Stack name (for a single file)", text: $name)
                        Toggle("Hide Passwords & Tokens", isOn: $redact)
                    } footer: { Text("Replaces values of variables like DB_PASSWORD or API_TOKEN with *** before saving. Keep real secrets in the Vault.") }
                } else {
                    Section {
                        CommandRow(command: Self.psCommand)
                    } header: { Text("Run inside the guest") } footer: { Text("Adds each running container as a service with its image and published ports.") }
                }
                Section("Paste") {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 200)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { s in text = s.first ?? "" }
                }
            }
            .navigationTitle("Import Containers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import", action: run).disabled(text.trimmed.isEmpty) }
            }
            .alert("Import", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { if message?.hasPrefix("Added") == true { dismiss() } }
            } message: { Text(message ?? "") }
        }
    }

    private func run() {
        if mode == "ps" {
            let rows = DockerPSParser.parse(text)
            guard !rows.isEmpty else { message = "Couldn't read that. Use the docker ps command above so columns are tab-separated."; return }
            let existing = ((try? context.fetch(FetchDescriptor<LabService>())) ?? []).filter { $0.deletedAt == nil && $0.hostID == hostID }
            for r in rows {
                let s = existing.first { $0.containerName == r.name || $0.name == r.name } ?? {
                    let x = LabService(name: r.name)
                    context.insert(x)
                    return x
                }()
                s.hostID = hostID
                s.containerName = r.name
                s.image = r.image
                if !r.ports.isEmpty { s.ports = r.ports }
                s.symbol = DiagramBuilder.guessSymbol(r.name + " " + r.image).replacingOccurrences(of: "circle.grid.2x2", with: "shippingbox")
            }
            message = "Added \(rows.count) containers as services."
            return
        }
        var files = ComposeParser.splitFiles(text)
        if files.isEmpty { files = [(path: "", yaml: text)] }
        var stackCount = 0, serviceCount = 0
        for f in files {
            let yaml = redact ? ComposeParser.redactSecrets(f.yaml) : f.yaml
            guard !ComposeParser.parse(yaml).isEmpty else { continue }
            let stackName = files.count == 1 && !name.trimmed.isEmpty ? name.trimmed : (f.path.isEmpty ? (name.trimmed.isEmpty ? "Stack" : name.trimmed) : ComposeParser.stackName(fromPath: f.path))
            let st = stacks.first { $0.deletedAt == nil && $0.hostID == hostID && (($0.path == f.path && !f.path.isEmpty) || $0.name == stackName) } ?? {
                let x = ComposeStack(name: stackName)
                context.insert(x)
                return x
            }()
            st.hostID = hostID
            st.path = f.path.isEmpty ? st.path : (f.path as NSString).deletingLastPathComponent
            st.yaml = yaml
            st.lastDeployed = st.lastDeployed ?? .now
            serviceCount += LabImport.sync(st, in: context)
            stackCount += 1
        }
        message = stackCount == 0 ? "No services found. Make sure the text includes a services: section." : "Added \(stackCount) stack\(stackCount == 1 ? "" : "s") with \(serviceCount) services."
    }
}

struct StackEditor: View {
    @Bindable var stack: ComposeStack
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [LabDevice]
    @Query private var services: [LabService]
    @State private var deleting = false
    @State private var synced: Int?

    var body: some View {
        let mine = services.filter { $0.stackID == stack.id && $0.deletedAt == nil }
        let host = devices.first { $0.id == stack.hostID }
        HushForm {
            Section {
                TextField("Stack name (e.g. media, monitoring)", text: $stack.name).font(.hush(.headline))
                Picker("Runs On", selection: $stack.hostID) {
                    Text("None").tag(UUID?.none)
                    ForEach(devices.live(nil).filter { $0.kind.isGuest || [.server, .nas, .sbc, .hypervisor].contains($0.kind) }) { h in
                        Text("\(h.vmid > 0 ? "\(h.vmid) · " : "")\(h.displayName)").tag(Optional(h.id))
                    }
                }
                TextField("Folder (e.g. /opt/stacks/media)", text: $stack.path)
                    .font(.hush(.body).monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Updates", selection: $stack.updateMethod) {
                    ForEach(["", "Manual", "Watchtower", "Renovate", "Diun", "Komodo", "Portainer", "Dockge"], id: \.self) { Text($0.isEmpty ? "Not set" : $0).tag($0) }
                }
                Toggle("Deployed", isOn: Binding(get: { stack.lastDeployed != nil }, set: { stack.lastDeployed = $0 ? .now : nil }))
                if let d = stack.lastDeployed {
                    DatePicker("Last deployed", selection: Binding(get: { d }, set: { stack.lastDeployed = $0 }), displayedComponents: .date)
                }
            }
            Section {
                ForEach(mine) { s in
                    NavigationLink { ServiceEditor(service: s) } label: {
                        HStack(spacing: 10) {
                            SymbolIcon(name: s.symbol, fallback: "shippingbox").foregroundStyle(.tint).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name)
                                Text([s.image, s.portSummary].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.hush(.caption).monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                if mine.isEmpty { Text("Paste the compose file below, then tap Update Services.").foregroundStyle(.secondary) }
            } header: { Text("Services (\(mine.count))") }
            Section {
                TextEditor(text: $stack.yaml)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    synced = LabImport.sync(stack, in: context)
                } label: { Label(synced.map { "Updated \($0) services" } ?? "Update Services from File", systemImage: "arrow.triangle.2.circlepath") }
                Button { UIPasteboard.general.string = stack.yaml } label: { Label("Copy File", systemImage: "doc.on.doc") }
                    .disabled(stack.yaml.isEmpty)
            } header: { Text("compose.yaml") }
            if !stack.path.isEmpty {
                Section {
                    CommandRow(command: "cd \(stack.path) && docker compose pull && docker compose up -d")
                    CommandRow(command: "cd \(stack.path) && docker compose logs -f --tail=100")
                    if let h = host, !h.ip.isEmpty { CommandRow(command: "ssh root@\(h.ip)") }
                } header: { Text("Commands") }
            }
            Section("Notes") { TextField("Reverse proxy, backups, gotchas…", text: $stack.notes, axis: .vertical).lineLimit(3...10) }
            Section { Button("Delete Stack", role: .destructive) { deleting = true; dismiss() } }
        }
        .navigationTitle(stack.name.isEmpty ? "Stack" : stack.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if deleting {
                for s in services where s.stackID == stack.id { TrashActions.trash(s) }
                TrashActions.trash(stack)
            } else if stack.name.trimmed.isEmpty && stack.yaml.trimmed.isEmpty {
                context.delete(stack)
            } else if !stack.yaml.isEmpty {
                _ = LabImport.sync(stack, in: context)
            }
        }
    }
}

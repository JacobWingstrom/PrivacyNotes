import SwiftUI
import SwiftData

struct DiagramsList: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabDiagram.updatedAt, order: .reverse) private var stored: [LabDiagram]
    @Query private var devices: [LabDevice]
    @Query private var links: [LabLink]
    @Query private var services: [LabService]
    @Query private var subnets: [LabSubnet]
    @State private var open: LabDiagram?
    @State private var choosing = false

    var body: some View {
        let list = stored.live(settings.spaceFilter)
        List {
            Section {
                Button { make("physical") } label: { option("Physical Layout", "Devices and cables, internet at the top.", "cable.connector") }
                Button { make("network") } label: { option("Network / VLANs", "Devices grouped by subnet and VLAN.", "network") }
                Button { make("services") } label: { option("Services", "Hosts, VMs, containers and what runs on them.", "app.connected.to.app.below.fill") }
                Button { make("text") } label: { option("Diagram as Text", "Type lines like router -> switch : 10G", "text.alignleft") }
                Button { make("custom") } label: { option("Blank Canvas", "Drag boxes and draw links yourself.", "rectangle.dashed") }
            } header: { ListHeader(title: "New Diagram") } footer: {
                Text("Auto diagrams are built from your Devices, Cables, Subnets and Services, and you can rearrange them afterwards.")
            }
            if !list.isEmpty {
                Section {
                    ForEach(list) { d in
                        NavigationLink { DiagramEditor(diagram: d) } label: {
                            HStack(spacing: 12) {
                                SymbolTile(name: icon(d.layer), size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.title).font(.hush(.headline))
                                    Text("\(d.nodes.count) items · \(d.edges.count) links · \(d.updatedAt.formatted(.relative(presentation: .named)))")
                                        .font(.hush(.caption)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions { Button(role: .destructive) { TrashActions.trash(d) } label: { Label("Delete", systemImage: "trash") } }
                        .hushRow()
                    }
                } header: { ListHeader(title: "Your Diagrams") }
            }
        }
        .hushList()
        .onCreate(.homelab) { choosing = true }
        .confirmationDialog("New Diagram", isPresented: $choosing) {
            Button("Physical Layout") { make("physical") }
            Button("Network / VLANs") { make("network") }
            Button("Services") { make("services") }
            Button("Diagram as Text") { make("text") }
            Button("Blank Canvas") { make("custom") }
        }
        .navigationDestination(item: $open) { DiagramEditor(diagram: $0) }
        .onAppear { if UserDefaults.standard.bool(forKey: "demoOpenDiagram"), open == nil { open = list.first } }
    }

    private func option(_ t: String, _ d: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s).foregroundStyle(.tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(t).foregroundStyle(.primary)
                Text(d).font(.hush(.caption)).foregroundStyle(.secondary)
            }
        }
    }

    private func icon(_ layer: String) -> String {
        switch layer {
        case "physical": "cable.connector"
        case "network": "network"
        case "services":
            return ServiceTreeLayout(devices: devices, services: services).build()
        default:
            return ([], [])
        }
    }

    /// "A -> B : label", "A -- B" (dashed), "A ~> B" (wireless). Lines starting with # are comments.
    static func parse(_ text: String, keeping old: [DiagramNode] = []) -> ([DiagramNode], [DiagramEdge]) {
        var order: [String] = []
        var pairs: [(String, String, String, String)] = []
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            var main = line, label = ""
            if let colon = line.range(of: " : ") ?? line.range(of: ":") {
                main = String(line[..<colon.lowerBound]); label = String(line[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            var style = "solid"
            var parts: [String] = []
            for (arrow, s) in [("->", "solid"), ("~>", "wireless"), ("--", "dashed")] where parts.count < 2 {
                let p = main.components(separatedBy: arrow)
                if p.count == 2 { parts = p; style = s }
            }
            let names = parts.count == 2 ? parts.map { $0.trimmingCharacters(in: .whitespaces) } : [main.trimmingCharacters(in: .whitespaces)]
            for n in names where !n.isEmpty && !order.contains(n) { order.append(n) }
            if names.count == 2, !names[0].isEmpty, !names[1].isEmpty { pairs.append((names[0], names[1], label, style)) }
        }
        // Depth from roots for a top-down layout.
        var depth: [String: Int] = [:]
        let targets = Set(pairs.map(\.1))
        for n in order where !targets.contains(n) { depth[n] = 0 }
        if depth.isEmpty, let first = order.first { depth[first] = 0 }
        for _ in 0..<order.count {
            for (a, b, _, _) in pairs { if let d = depth[a], depth[b] == nil || depth[b]! < d + 1, d < 20 { depth[b] = d + 1 } }
        }
        let rows = Dictionary(grouping: order) { depth[$0] ?? 0 }
        var nodes: [DiagramNode] = []
        for (r, items) in rows.sorted(by: { $0.key < $1.key }) {
            for (i, name) in items.enumerated() {
                if let existing = old.first(where: { $0.label == name }) {
                    nodes.append(existing)
                } else {
                    nodes.append(DiagramNode(label: name, symbol: guessSymbol(name),
                                             x: (Double(i) - Double(items.count - 1) / 2) * spacingX, y: Double(r) * spacingY))
                }
            }
        }
        let id = Dictionary(uniqueKeysWithValues: nodes.map { ($0.label, $0.id) })
        let edges = pairs.compactMap { p -> DiagramEdge? in
            guard let a = id[p.0], let b = id[p.1] else { return nil }
            return DiagramEdge(from: a, to: b, label: p.2, style: p.3)
        }
        return (nodes, edges)
    }

    static func guessSymbol(_ name: String) -> String {
        let n = name.lowercased()
        let table: [(String, String)] = [("internet", "globe"), ("wan", "globe"), ("isp", "globe"), ("modem", "globe"), ("router", "wifi.router"),
            ("firewall", "shield.lefthalf.filled"), ("opnsense", "shield.lefthalf.filled"), ("pfsense", "shield.lefthalf.filled"),
            ("switch", "rectangle.connected.to.line.below"), ("access point", "antenna.radiowaves.left.and.right"), ("ap", "antenna.radiowaves.left.and.right"),
            ("wifi", "wifi"), ("nas", "externaldrive.connected.to.line.below"), ("truenas", "externaldrive.connected.to.line.below"),
            ("unraid", "externaldrive.connected.to.line.below"), ("proxmox", "square.stack.3d.up"), ("esxi", "square.stack.3d.up"),
            ("server", "server.rack"), ("pi", "cpu"), ("docker", "shippingbox"), ("container", "shippingbox"), ("vm", "macwindow"),
            ("ups", "battery.100.bolt"), ("camera", "video"), ("tv", "tv"), ("phone", "iphone"), ("laptop", "laptopcomputer"),
            ("pc", "desktopcomputer"), ("desktop", "desktopcomputer"), ("home assistant", "house"), ("pi-hole", "shield"), ("dns", "shield"),
            ("plex", "play.rectangle"), ("jellyfin", "play.rectangle"), ("vpn", "lock.shield"), ("wireguard", "lock.shield"), ("backup", "externaldrive")]
        return table.first { n.contains($0.0) }?.1 ?? "circle.grid.2x2"
    }
}

/// Lays out node → guest → container as a tree, top to bottom.
private final class ServiceTreeLayout {
    let devices: [LabDevice]
    let services: [LabService]
    var nodes: [DiagramNode] = []
    var edges: [DiagramEdge] = []
    var serviceNode: [UUID: UUID] = [:]
    var cursor: Double = 0
    let dx = DiagramBuilder.spacingX * 0.8
    let dy = DiagramBuilder.spacingY

    init(devices: [LabDevice], services: [LabService]) {
        self.devices = devices
        self.services = services
    }

    func build() -> ([DiagramNode], [DiagramEdge]) {
        let roots = devices.filter { d in
            d.hostID == nil && (devices.contains { $0.hostID == d.id } || services.contains { $0.hostID == d.id })
        }
        for r in roots.sorted(by: { $0.displayName < $1.displayName }) {
            _ = place(r, depth: 0)
            cursor += dx * 0.6
        }
        let shift = cursor / 2
        nodes = nodes.map { n in
            var m = n
            m.x -= shift
            return m
        }
        for sv in services {
            for dep in sv.dependsOn {
                if let a = serviceNode[sv.id], let b = serviceNode[dep] {
                    edges.append(DiagramEdge(from: a, to: b, label: "needs"))
                }
            }
        }
        return (nodes, edges)
    }

    private func label(for d: LabDevice) -> String {
        guard d.kind.isGuest else { return d.displayName }
        let id = d.vmid > 0 ? "\(d.vmid) " : ""
        let kind = d.kind == .lxc ? "LXC" : "VM"
        let ip = d.ip.isEmpty ? "" : " · " + d.ip
        return id + d.displayName + "\n" + kind + ip
    }

    private func place(_ d: LabDevice, depth: Int) -> UUID {
        let guests = devices.filter { $0.hostID == d.id }.sorted { a, b in a.vmid < b.vmid }
        let svc = services.filter { $0.hostID == d.id }
        var children: [UUID] = []
        let startX = cursor
        for g in guests { children.append(place(g, depth: depth + 1)) }
        for sv in svc {
            let portText = sv.ports.first.map { " :" + String($0.port) } ?? ""
            let n = DiagramNode(label: sv.name + portText, symbol: SymbolName.resolve(sv.symbol, fallback: "shippingbox"),
                                x: cursor, y: Double(depth + 1) * dy)
            nodes.append(n)
            serviceNode[sv.id] = n.id
            children.append(n.id)
            cursor += dx
        }
        let x: Double
        if children.isEmpty {
            x = cursor
            cursor += dx
        } else {
            x = (startX + cursor - dx) / 2
        }
        let color: String = d.kind == .lxc ? "orange" : (d.kind == .vm ? "blue" : "none")
        let n = DiagramNode(deviceID: d.id, label: label(for: d), symbol: d.kind.symbol, x: x, y: Double(depth) * dy, colorName: color)
        nodes.append(n)
        for c in children { edges.append(DiagramEdge(from: n.id, to: c, style: "dashed")) }
        return n.id
    }
}

// MARK: - Editor

struct DiagramEditor: View {
    @Bindable var diagram: LabDiagram
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Query private var devices: [LabDevice]
    @State private var nodes: [DiagramNode] = []
    @State private var edges: [DiagramEdge] = []
    @State private var selected: UUID?
    @State private var connectFrom: UUID?
    @State private var connecting = false
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero
    @State private var dragStart: [UUID: CGPoint] = [:]
    @State private var editingNode: DiagramNode?
    @State private var editingEdge: DiagramEdge?
    @State private var showText = false
    @State private var addingDevice = false
    @State private var share: ShareItem?
    @State private var loaded = false

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2 + pan.width, y: 90 + pan.height)
            ZStack {
                palette.background
                gridBackground
                Canvas { ctx, _ in
                    for e in edges {
                        guard let a = nodes.first(where: { $0.id == e.from }), let b = nodes.first(where: { $0.id == e.to }) else { continue }
                        let p1 = point(a, center), p2 = point(b, center)
                        var path = Path()
                        path.move(to: p1)
                        let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                        path.addQuadCurve(to: p2, control: CGPoint(x: mid.x, y: mid.y))
                        let dash: [CGFloat] = e.style == "dashed" ? [6, 5] : (e.style == "wireless" ? [2, 5] : [])
                        ctx.stroke(path, with: .color(.secondary.opacity(selectedEdgeIDs.contains(e.id) ? 1 : 0.6)),
                                   style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, dash: dash))
                        if !e.label.isEmpty {
                            let text = ctx.resolve(Text(e.label).font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.secondary))
                            let size = text.measure(in: CGSize(width: 200, height: 40))
                            let r = CGRect(x: mid.x - size.width / 2 - 4, y: mid.y - size.height / 2 - 2, width: size.width + 8, height: size.height + 4)
                            ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(palette.background))
                            ctx.draw(text, at: mid)
                        }
                    }
                }
                ForEach(nodes) { n in
                    NodeView(node: n, selected: selected == n.id || connectFrom == n.id, scale: scale)
                        .position(point(n, center))
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                if dragStart[n.id] == nil { dragStart[n.id] = CGPoint(x: n.x, y: n.y) }
                                guard let i = nodes.firstIndex(where: { $0.id == n.id }), let s = dragStart[n.id] else { return }
                                nodes[i].x = snap(s.x + v.translation.width / scale)
                                nodes[i].y = snap(s.y + v.translation.height / scale)
                            }
                            .onEnded { _ in dragStart[n.id] = nil; save() })
                        .onTapGesture { tap(n) }
                        .onTapGesture(count: 2) { editingNode = n }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { v in pan = CGSize(width: basePan.width + v.translation.width, height: basePan.height + v.translation.height) }
                .onEnded { _ in basePan = pan })
            .simultaneousGesture(MagnificationGesture()
                .onChanged { scale = min(max(baseScale * $0, 0.35), 2.5) }
                .onEnded { _ in baseScale = scale })
            .onTapGesture { selected = nil; connectFrom = nil }
            .clipped()
        }
        .overlay(alignment: .bottom) { toolbar }
        .navigationTitle($diagram.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showText = true } label: { Label("Edit as Text", systemImage: "text.alignleft") }
                    Button { resetView() } label: { Label("Fit to Screen", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                    Button { tidy() } label: { Label("Tidy Layout", systemImage: "square.grid.3x3") }
                    Button { exportImage() } label: { Label("Export Image", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            guard !loaded else { return }
            nodes = diagram.nodes
            edges = diagram.edges
            loaded = true
            if diagram.layer == "text" && diagram.source.isEmpty { showText = true }
        }
        .sheet(item: $editingNode) { n in
            NodeEditor(node: n) { updated in
                if let updated, let i = nodes.firstIndex(where: { $0.id == n.id }) { nodes[i] = updated }
                if updated == nil { delete(n.id) }
                save()
            }
        }
        .sheet(item: $editingEdge) { e in
            EdgeEditor(edge: e) { updated in
                if let i = edges.firstIndex(where: { $0.id == e.id }) {
                    if let updated { edges[i] = updated } else { edges.remove(at: i) }
                }
                save()
            }
        }
        .sheet(isPresented: $showText) {
            DiagramTextEditor(source: diagram.source.isEmpty ? DiagramText.from(nodes: nodes, edges: edges) : diagram.source) { text in
                diagram.source = text
                let parsed = DiagramBuilder.parse(text, keeping: nodes)
                nodes = parsed.0
                edges = parsed.1
                save()
            }
        }
        .sheet(isPresented: $addingDevice) {
            DevicePickerSheet(devices: devices.live(nil)) { d in
                addNode(DiagramNode(deviceID: d.id, label: d.displayName, symbol: d.kind.symbol, x: 0, y: 0))
            }
        }
        .sheet(item: $share) { item in ActivityView(items: item.urls).ignoresSafeArea() }
    }

    private var selectedEdgeIDs: Set<UUID> {
        guard let s = selected else { return [] }
        return Set(edges.filter { $0.from == s || $0.to == s }.map(\.id))
    }

    private var gridBackground: some View {
        Canvas { ctx, size in
            let step = 30 * scale
            guard step > 6 else { return }
            var p = Path()
            var x = pan.width.truncatingRemainder(dividingBy: step)
            while x < size.width { p.addRect(CGRect(x: x, y: 0, width: 0.5, height: size.height)); x += step }
            var y = pan.height.truncatingRemainder(dividingBy: step)
            while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.5)); y += step }
            ctx.fill(p, with: .color(.secondary.opacity(0.08)))
        }
        .allowsHitTesting(false)
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            Button { addNode(DiagramNode(label: "New", symbol: "circle.grid.2x2", x: 0, y: 0)) } label: { Label("Box", systemImage: "plus.rectangle") }
            Button { addingDevice = true } label: { Label("Device", systemImage: "server.rack") }
            Button {
                connecting.toggle()
                connectFrom = connecting ? selected : nil
            } label: { Label(connecting ? "Pick 2nd" : "Link", systemImage: "line.diagonal.arrow") }
                .foregroundStyle(connecting ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
            if let s = selected {
                Button { editingNode = nodes.first { $0.id == s } } label: { Label("Edit", systemImage: "pencil") }
                Menu {
                    ForEach(edges.filter { $0.from == s || $0.to == s }) { e in
                        Button(edgeName(e)) { editingEdge = e }
                    }
                } label: { Label("Links", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 16)
    }

    private func edgeName(_ e: DiagramEdge) -> String {
        let a = nodes.first { $0.id == e.from }?.label ?? "?", b = nodes.first { $0.id == e.to }?.label ?? "?"
        return "\(a.split(separator: "\n").first ?? "") → \(b.split(separator: "\n").first ?? "")\(e.label.isEmpty ? "" : " (\(e.label))")"
    }

    private func point(_ n: DiagramNode, _ center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + n.x * scale, y: center.y + n.y * scale)
    }

    private func snap(_ v: Double) -> Double { (v / 10).rounded() * 10 }

    private func tap(_ n: DiagramNode) {
        if connecting {
            if let from = connectFrom, from != n.id {
                edges.append(DiagramEdge(from: from, to: n.id))
                connectFrom = nil
                connecting = false
                save()
            } else {
                connectFrom = n.id
            }
        } else {
            selected = selected == n.id ? nil : n.id
        }
    }

    private func addNode(_ n: DiagramNode) {
        var node = n
        node.x = Double(-pan.width / scale) + Double.random(in: -30...30)
        node.y = Double((200 - pan.height) / scale) + Double.random(in: -20...20)
        nodes.append(node)
        selected = node.id
        save()
    }

    private func delete(_ id: UUID) {
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.from == id || $0.to == id }
        selected = nil
    }

    private func tidy() {
        let text = DiagramText.from(nodes: nodes, edges: edges)
        let parsed = DiagramBuilder.parse(text)
        var byLabel = Dictionary(parsed.0.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })
        nodes = nodes.map { n in
            guard let p = byLabel.removeValue(forKey: n.label) else { return n }
            var m = n; m.x = p.x; m.y = p.y; return m
        }
        save()
    }

    private func resetView() {
        withAnimation(.snappy) { scale = 1; baseScale = 1; pan = .zero; basePan = .zero }
    }

    private func save() {
        diagram.nodes = nodes
        diagram.edges = edges
    }

    @MainActor
    private func exportImage() {
        guard !nodes.isEmpty else { return }
        let minX = nodes.map(\.x).min()! - 120, maxX = nodes.map(\.x).max()! + 120
        let minY = nodes.map(\.y).min()! - 80, maxY = nodes.map(\.y).max()! + 100
        let size = CGSize(width: maxX - minX, height: maxY - minY)
        let snapshot = DiagramSnapshot(nodes: nodes, edges: edges, origin: CGPoint(x: -minX, y: -minY), background: palette.background)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, palette.isDark ? .dark : .light)
            .tint(settings.accentColor)
        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData(),
              let url = Exporter.write(data, name: Exporter.safeName(diagram.title, fallback: "Diagram") + ".png") else { return }
        share = ShareItem(urls: [url])
    }
}

private struct NodeView: View {
    let node: DiagramNode
    let selected: Bool
    let scale: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        let tint = NoteColor(rawValue: node.colorName)?.color ?? Color.accentColor
        VStack(spacing: 4 * scale) {
            Image(systemName: SymbolName.resolve(node.symbol, fallback: "circle.grid.2x2"))
                .font(.system(size: 22 * scale))
                .foregroundStyle(tint)
                .frame(width: 46 * scale, height: 46 * scale)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).stroke(selected ? tint : palette.border, lineWidth: selected ? 2.5 : 1))
            Text(node.label)
                .font(.system(size: 11 * scale, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 130 * scale)
                .padding(.horizontal, 4)
                .background(palette.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
        }
        .contentShape(Rectangle())
    }
}

/// A static copy of the diagram for exporting as an image.
private struct DiagramSnapshot: View {
    let nodes: [DiagramNode]
    let edges: [DiagramEdge]
    let origin: CGPoint
    let background: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            Canvas { ctx, _ in
                for e in edges {
                    guard let a = nodes.first(where: { $0.id == e.from }), let b = nodes.first(where: { $0.id == e.to }) else { continue }
                    var path = Path()
                    let p1 = CGPoint(x: a.x + origin.x, y: a.y + origin.y), p2 = CGPoint(x: b.x + origin.x, y: b.y + origin.y)
                    path.move(to: p1); path.addLine(to: p2)
                    let dash: [CGFloat] = e.style == "dashed" ? [6, 5] : (e.style == "wireless" ? [2, 5] : [])
                    ctx.stroke(path, with: .color(.gray), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
                    if !e.label.isEmpty {
                        ctx.draw(Text(e.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.gray),
                                 at: CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 - 8))
                    }
                }
            }
            ForEach(nodes) { n in
                NodeView(node: n, selected: false, scale: 1).position(x: n.x + origin.x, y: n.y + origin.y)
            }
        }
    }
}

enum DiagramText {
    static func from(nodes: [DiagramNode], edges: [DiagramEdge]) -> String {
        var lines: [String] = []
        for e in edges {
            guard let a = nodes.first(where: { $0.id == e.from }), let b = nodes.first(where: { $0.id == e.to }) else { continue }
            let arrow = e.style == "dashed" ? "--" : (e.style == "wireless" ? "~>" : "->")
            lines.append("\(clean(a.label)) \(arrow) \(clean(b.label))\(e.label.isEmpty ? "" : " : \(e.label)")")
        }
        let linked = Set(edges.flatMap { [$0.from, $0.to] })
        for n in nodes where !linked.contains(n.id) { lines.append(clean(n.label)) }
        return lines.joined(separator: "\n")
    }
    private static func clean(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "->", with: "→") }
}

private struct DiagramTextEditor: View {
    @State var source: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("One link per line. Use -> for a cable, -- for a dashed line, ~> for wireless, and : for a label.")
                    .font(.hush(.footnote)).foregroundStyle(.secondary)
                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding()
            .navigationTitle("Diagram as Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Draw") { onSave(source); dismiss() } }
            }
        }
    }
}

private struct NodeEditor: View {
    @State var node: DiagramNode
    var onDone: (DiagramNode?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        NavigationStack {
            HushForm {
                Section {
                    HStack {
                        Button { picking = true } label: { SymbolTile(name: node.symbol, size: 40) }.buttonStyle(.plain)
                        TextField("Label", text: $node.label, axis: .vertical)
                    }
                    Picker("Color", selection: $node.colorName) {
                        ForEach(NoteColor.allCases) { Text($0 == .none ? "Accent" : $0.label).tag($0.rawValue) }
                    }
                }
                Section { Button("Delete Box", role: .destructive) { onDone(nil); dismiss() } }
            }
            .navigationTitle("Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(node); dismiss() } } }
            .sheet(isPresented: $picking) { SymbolPicker(selection: $node.symbol, allowNone: false) }
        }
        .presentationDetents([.medium])
    }
}

private struct EdgeEditor: View {
    @State var edge: DiagramEdge
    var onDone: (DiagramEdge?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HushForm {
                Section {
                    TextField("Label (e.g. 10G, VLAN 20)", text: $edge.label)
                    Picker("Line", selection: $edge.style) {
                        Text("Cable").tag("solid")
                        Text("Dashed").tag("dashed")
                        Text("Wireless").tag("wireless")
                    }
                    .pickerStyle(.segmented)
                    Button("Reverse Direction") { let f = edge.from; edge.from = edge.to; edge.to = f }
                }
                Section { Button("Delete Link", role: .destructive) { onDone(nil); dismiss() } }
            }
            .navigationTitle("Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(edge); dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

private struct DevicePickerSheet: View {
    let devices: [LabDevice]
    var onPick: (LabDevice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(devices) { d in
                Button { onPick(d); dismiss() } label: { Label(d.displayName, systemImage: d.kind.symbol) }
            }
            .overlay { if devices.isEmpty { Text("No devices yet.").foregroundStyle(.secondary) } }
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

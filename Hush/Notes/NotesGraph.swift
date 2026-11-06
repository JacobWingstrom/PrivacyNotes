import SwiftUI
import SwiftData

/// Today's note: one per day, tagged "daily", started from the template you pick.
enum DailyNote {
    static let templateKey = "dailyNoteTemplate"

    static var title: String { Date().formatted(.dateTime.weekday(.wide).month(.wide).day().year()) }

    @MainActor
    static func open(in ctx: ModelContext) -> Note {
        let today = title
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { $0.deletedAt == nil }
        if let existing = notes.first(where: { $0.title == today && $0.tags.contains("daily") }) { return existing }
        let n = Note()
        n.title = today
        n.tags = ["daily"]
        n.emoji = "sun.max"
        let name = UserDefaults.standard.string(forKey: templateKey) ?? "Daily Journal"
        if let mine = ((try? ctx.fetch(FetchDescriptor<NoteTemplate>())) ?? []).first(where: { $0.name == name }) {
            n.body = TemplateFill.apply(mine.body)
        } else if let t = TemplateLibrary.all.first(where: { $0.name == name }) {
            n.body = TemplateFill.apply(t.body)
        }
        // Link yesterday's note so daily notes form a chain in the graph.
        let yesterday = (Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
            .formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        if notes.contains(where: { $0.title == yesterday }) { n.body += "\n\n← [[\(yesterday)]]" }
        ctx.insert(n)
        return n
    }
}

/// A map of your notes and the [[links]] between them.
struct NotesGraphView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Query private var notesStored: [Note]
    @State private var positions: [UUID: CGPoint] = [:]
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero
    @State private var open: Note?
    @State private var showOrphans = false
    @State private var tag: String?
    @State private var selected: UUID?

    private struct Graph {
        var notes: [Note]
        var edges: [(UUID, UUID)]
        var degree: [UUID: Int]
    }

    private var graph: Graph {
        let all = notesStored.live(settings.spaceFilter).filter { tag == nil || $0.tags.contains(tag!) }
        var byTitle: [String: UUID] = [:]
        for n in all { byTitle[n.displayTitle.lowercased()] = n.id }
        var edges: [(UUID, UUID)] = []
        var degree: [UUID: Int] = [:]
        for n in all where !n.isLocked {
            for target in NoteInfoView.links(in: n.body) {
                if let t = byTitle[target.lowercased()], t != n.id {
                    edges.append((n.id, t))
                    degree[n.id, default: 0] += 1
                    degree[t, default: 0] += 1
                }
            }
        }
        let shown = showOrphans ? all : all.filter { degree[$0.id] != nil }
        return Graph(notes: shown, edges: edges, degree: degree)
    }

    var body: some View {
        let g = graph
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2 + pan.width, y: geo.size.height / 2 + pan.height)
            ZStack {
                palette.background
                Canvas { ctx, _ in
                    for (a, b) in g.edges {
                        guard let p = positions[a], let q = positions[b] else { continue }
                        var path = Path()
                        path.move(to: point(p, center))
                        path.addLine(to: point(q, center))
                        let hot = selected == a || selected == b
                        ctx.stroke(path, with: .color(hot ? settings.accentColor : .secondary.opacity(0.35)), lineWidth: hot ? 2 : 1)
                    }
                }
                ForEach(g.notes) { n in
                    if let p = positions[n.id] {
                        let d = g.degree[n.id] ?? 0
                        let size = CGFloat(12 + min(d, 12) * 3) * scale
                        VStack(spacing: 3) {
                            Circle()
                                .fill(n.color ?? settings.accentColor)
                                .frame(width: size, height: size)
                                .overlay(Circle().stroke(selected == n.id ? Color.primary : .clear, lineWidth: 2))
                            if scale > 0.6 || d > 2 {
                                Text(n.displayTitle).font(.system(size: 10 * max(scale, 0.8))).lineLimit(1).frame(maxWidth: 120)
                            }
                        }
                        .position(point(p, center))
                        .onTapGesture { if selected == n.id { open = n } else { selected = n.id } }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { v in
                pan = CGSize(width: basePan.width + v.translation.width, height: basePan.height + v.translation.height)
            }.onEnded { _ in basePan = pan })
            .simultaneousGesture(MagnificationGesture().onChanged { scale = min(max(baseScale * $0, 0.3), 3) }.onEnded { _ in baseScale = scale })
        }
        .overlay {
            if g.notes.isEmpty {
                EmptyMessage(text: "No linked notes yet. Type [[Another note]] inside a note to connect them.").padding()
            }
        }
        .overlay(alignment: .bottom) {
            if let s = selected, let n = g.notes.first(where: { $0.id == s }) {
                Button { open = n } label: {
                    Label("Open “\(n.displayTitle)” · \(g.degree[s] ?? 0) links", systemImage: "arrow.up.forward.square")
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Graph")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show Unlinked Notes", isOn: $showOrphans)
                    Picker("Tag", selection: $tag) {
                        Text("All Notes").tag(String?.none)
                        ForEach(Array(Set(notesStored.flatMap(\.tags))).sorted(), id: \.self) { Text("#\($0)").tag(Optional($0)) }
                    }
                    Button("Re-arrange") { layout(g, reset: true) }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
        }
        .navigationDestination(item: $open) { NoteEditorView(note: $0) }
        .onAppear { layout(g, reset: false) }
        .onChange(of: showOrphans) { layout(graph, reset: false) }
        .onChange(of: tag) { layout(graph, reset: true) }
    }

    private func point(_ p: CGPoint, _ c: CGPoint) -> CGPoint { CGPoint(x: c.x + p.x * scale, y: c.y + p.y * scale) }

    /// A small force-directed layout: linked notes pull together, all notes push apart.
    private func layout(_ g: Graph, reset: Bool) {
        var pos = reset ? [:] : positions
        let ids = g.notes.map(\.id)
        for (i, id) in ids.enumerated() where pos[id] == nil {
            let angle = Double(i) / Double(max(ids.count, 1)) * 2 * .pi
            let r = 60 + Double(i % 7) * 25
            pos[id] = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
        }
        let edges = g.edges.filter { pos[$0.0] != nil && pos[$0.1] != nil }
        for step in 0..<220 {
            var force: [UUID: CGVector] = [:]
            for a in ids {
                guard let pa = pos[a] else { continue }
                var f = CGVector.zero
                for b in ids where b != a {
                    guard let pb = pos[b] else { continue }
                    let dx = pa.x - pb.x, dy = pa.y - pb.y
                    let d2 = max(dx * dx + dy * dy, 25)
                    let k = 2600 / d2
                    f.dx += dx * k / sqrt(d2); f.dy += dy * k / sqrt(d2)
                }
                f.dx -= pa.x * 0.01; f.dy -= pa.y * 0.01
                force[a] = f
            }
            for (a, b) in edges {
                guard let pa = pos[a], let pb = pos[b] else { continue }
                let dx = pb.x - pa.x, dy = pb.y - pa.y
                let d = max(sqrt(dx * dx + dy * dy), 1)
                let k = (d - 90) * 0.04
                force[a, default: .zero].dx += dx / d * k; force[a, default: .zero].dy += dy / d * k
                force[b, default: .zero].dx -= dx / d * k; force[b, default: .zero].dy -= dy / d * k
            }
            let cool = 1 - Double(step) / 260
            for a in ids {
                guard var p = pos[a], let f = force[a] else { continue }
                p.x += max(min(f.dx, 12), -12) * cool
                p.y += max(min(f.dy, 12), -12) * cool
                pos[a] = p
            }
        }
        withAnimation(.easeOut(duration: 0.4)) { positions = pos }
    }
}

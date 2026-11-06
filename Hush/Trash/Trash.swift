import SwiftUI
import SwiftData

enum TrashActions {
    static let keepDays = 30

    static func trash(_ item: some HushItem) {
        item.deletedAt = .now
        if let t = item as? TaskItem { Reminders.cancel("task.\(t.id.uuidString)") }
        if let e = item as? CalendarEvent { Reminders.cancel("event.\(e.id.uuidString)") }
        if let c = item as? Contact { Reminders.cancel("birthday.\(c.id.uuidString)") }
        if let h = item as? Habit { Reminders.sync(h) }
    }

    static func restore(_ item: some HushItem) {
        item.deletedAt = nil
        if let t = item as? TaskItem { Reminders.sync(t) }
        if let e = item as? CalendarEvent { Reminders.sync(e) }
        if let c = item as? Contact { Reminders.sync(c) }
        if let h = item as? Habit { Reminders.sync(h) }
    }

    static func deleteForever<T: PersistentModel & HushItem>(_ item: T, in ctx: ModelContext) {
        if let note = item as? Note {
            let id = note.id
            for v in (try? ctx.fetch(FetchDescriptor<NoteVersion>())) ?? [] where v.noteID == id { ctx.delete(v) }
            for f in (try? ctx.fetch(FetchDescriptor<StoredFile>())) ?? [] where f.noteID == id { ctx.delete(f) }
        }
        ctx.delete(item)
    }

    /// Permanently removes anything that has been in the Trash longer than 30 days.
    static func purgeExpired(_ ctx: ModelContext) {
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86400)
        func purge<T: PersistentModel & HushItem>(_ type: T.Type) {
            for item in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] {
                if let d = item.deletedAt, d < cutoff { deleteForever(item, in: ctx) }
            }
        }
        purge(Note.self); purge(TaskItem.self); purge(CalendarEvent.self); purge(JournalEntry.self)
        purge(Drawing.self); purge(StoredFile.self); purge(Contact.self); purge(Bookmark.self); purge(Habit.self)
        purge(Board.self); purge(BoardCard.self); purge(LabDevice.self); purge(LabService.self); purge(LabSubnet.self)
        purge(LabRack.self); purge(LabLink.self); purge(LabDiagram.self); purge(Runbook.self); purge(ComposeStack.self)
        try? ctx.save()
    }
}

struct TrashView: View {
    @Environment(\.modelContext) private var context
    @Query private var notes: [Note]
    @Query private var tasks: [TaskItem]
    @Query private var events: [CalendarEvent]
    @Query private var journals: [JournalEntry]
    @Query private var drawings: [Drawing]
    @Query private var files: [StoredFile]
    @Query private var contacts: [Contact]
    @Query private var bookmarks: [Bookmark]
    @Query private var habits: [Habit]
    @Query private var boards: [Board]
    @Query private var cards: [BoardCard]
    @Query private var labDevices: [LabDevice]
    @Query private var labServices: [LabService]
    @Query private var labSubnets: [LabSubnet]
    @Query private var labRacks: [LabRack]
    @Query private var labLinks: [LabLink]
    @Query private var labDiagrams: [LabDiagram]
    @Query private var runbooks: [Runbook]
    @Query private var composeStacks: [ComposeStack]
    @State private var confirmEmpty = false

    private struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let deletedAt: Date
        let restore: () -> Void
        let delete: () -> Void
    }

    private var rows: [Row] {
        var r: [Row] = []
        func add<T: PersistentModel & HushItem>(_ items: [T], _ symbol: String, _ title: (T) -> String) {
            for i in items.trashed {
                r.append(Row(id: "\(symbol)\(i.persistentModelID.hashValue)", symbol: symbol, title: title(i), deletedAt: i.deletedAt ?? .now,
                             restore: { TrashActions.restore(i) }, delete: { TrashActions.deleteForever(i, in: context) }))
            }
        }
        add(notes, "square.and.pencil") { $0.displayTitle }
        add(tasks, "checkmark.circle") { $0.title }
        add(events, "calendar") { $0.title.isEmpty ? "Event" : $0.title }
        add(journals, "book.closed") { $0.title.isEmpty ? "Journal entry" : $0.title }
        add(drawings, "scribble.variable") { $0.title }
        add(files.filter { $0.noteID == nil }, "folder") { $0.name }
        add(contacts, "person.crop.rectangle") { $0.displayName }
        add(bookmarks, "bookmark") { $0.displayTitle }
        add(habits, "flame") { $0.name }
        add(boards, "rectangle.split.3x1") { $0.title }
        add(cards, "rectangle.portrait") { $0.title }
        add(labDevices, "server.rack") { $0.displayName }
        add(labServices, "app.connected.to.app.below.fill") { $0.name }
        add(labSubnets, "network") { $0.name.isEmpty ? $0.cidr : $0.name }
        add(labRacks, "square.stack.3d.down.right") { $0.name }
        add(labLinks, "cable.connector") { _ in "Cable" }
        add(labDiagrams, "point.3.connected.trianglepath.dotted") { $0.title }
        add(runbooks, "list.bullet.clipboard") { $0.title }
        add(composeStacks, "shippingbox") { $0.name }
        return r.sorted { $0.deletedAt > $1.deletedAt }
    }

    var body: some View {
        let list = rows
        List {
            Text("Items are deleted forever after \(TrashActions.keepDays) days.")
                .font(.hush(.footnote)).foregroundStyle(.secondary)
                .plainRow(top: 12, bottom: 6)
            ForEach(list) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.symbol).foregroundStyle(.tint).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title.isEmpty ? "Untitled" : row.title).lineLimit(1)
                        Text(daysLeft(row.deletedAt)).font(.hush(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore") { withAnimation { row.restore() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .swipeActions {
                    Button(role: .destructive) { row.delete() } label: { Label("Delete Forever", systemImage: "trash.slash") }
                }
                .hushRow()
            }
            if list.isEmpty { EmptyMessage(text: "Trash is empty.") }
        }
        .hushList()
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Empty", role: .destructive) { confirmEmpty = true }.disabled(list.isEmpty)
            }
        }
        .confirmationDialog("Delete everything in the Trash forever?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) {
                for r in list { r.delete() }
                try? context.save()
            }
        }
    }

    private func daysLeft(_ deleted: Date) -> String {
        let left = TrashActions.keepDays - (Calendar.current.dateComponents([.day], from: deleted, to: .now).day ?? 0)
        return left <= 1 ? "Deleted tomorrow" : "\(left) days left"
    }
}

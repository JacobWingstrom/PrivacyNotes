import SwiftUI
import SwiftData

/// Slide-out menu with every section, item counts and note tags.
struct DrawerView: View {
    var openSettings: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(LockManager.self) private var lock
    @Environment(\.palette) private var palette
    @Query private var notesStored: [Note]
    @Environment(AppSettings.self) private var notesSpace
    private var notes: [Note] { notesStored.live(notesSpace.spaceFilter) }
    @Query private var tasksStored: [TaskItem]
    @Environment(AppSettings.self) private var tasksSpace
    private var tasks: [TaskItem] { tasksStored.live(tasksSpace.spaceFilter) }
    @Query private var drawingsStored: [Drawing]
    @Environment(AppSettings.self) private var drawingsSpace
    private var drawings: [Drawing] { drawingsStored.live(drawingsSpace.spaceFilter) }
    @Query private var filesStored: [StoredFile]
    @Environment(AppSettings.self) private var filesSpace
    private var files: [StoredFile] { filesStored.live(filesSpace.spaceFilter) }
    @Query private var journalsStored: [JournalEntry]
    @Environment(AppSettings.self) private var journalsSpace
    private var journals: [JournalEntry] { journalsStored.live(journalsSpace.spaceFilter) }
    @Query private var eventsStored: [CalendarEvent]
    @Environment(AppSettings.self) private var eventsSpace
    private var events: [CalendarEvent] { eventsStored.live(eventsSpace.spaceFilter) }
    @Query private var contactsStored: [Contact]
    @Environment(AppSettings.self) private var contactsSpace
    private var contacts: [Contact] { contactsStored.live(contactsSpace.spaceFilter) }
    @Query private var bookmarksStored: [Bookmark]
    @Environment(AppSettings.self) private var bookmarksSpace
    private var bookmarks: [Bookmark] { bookmarksStored.live(bookmarksSpace.spaceFilter) }
    @Query private var habitsStored: [Habit]
    @Query private var foldersStored: [Folder]
    @Query private var boardsStored: [Board]
    private var boards: [Board] { boardsStored.live(settings.spaceFilter).filter { !$0.archived } }
    @Query private var trashNotes: [Note]
    @Query private var trashTasks: [TaskItem]
    @Query private var trashOther: [JournalEntry]
    @State private var showTrash = false
    @Query(filter: #Predicate<FeedArticle> { !$0.isRead }) private var unreadArticles: [FeedArticle]
    private var habits: [Habit] { habitsStored.live(settings.spaceFilter) }
    @State private var dragOffset: CGFloat = 0

    private var tags: [(String, Int)] {
        var counts: [String: Int] = [:]
        for n in notes { for t in n.tags { counts[t, default: 0] += 1 } }
        return counts.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }.map { ($0.key, $0.value) }
    }

    private func count(_ s: AppSection) -> Int? {
        switch s {
        case .home, .vault:
            return nil
        case .all:
            let openTasks: Int = tasks.filter { !$0.isDone }.count
            let counts: [Int] = [notes.count, openTasks, drawings.count, journals.count, events.count, contacts.count, bookmarks.count]
            return counts.reduce(0, +)
        case .notes: return notes.count
        case .tasks: return tasks.filter { !$0.isDone }.count
        case .habits:
            let today = Date()
            return habits.filter { !$0.archived && $0.isScheduled(on: today) && !$0.isDone(on: today) }.count
        case .drawings: return drawings.count
        case .files: return files.count
        case .homelab: return nil
        case .boards: return boards.count
        case .journals: return journals.count
        case .calendar:
            let start = Calendar.current.startOfDay(for: .now)
            return events.filter { $0.end >= start }.count
        case .contacts: return contacts.count
        case .bookmarks: return bookmarks.count
        case .mail: return MailEngine.shared.hasAccounts ? MailEngine.shared.totalUnreadInbox : nil
        case .feeds: return unreadArticles.isEmpty ? nil : unreadArticles.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.hush(.title2))
                    .foregroundStyle(.tint)
                Text("Hush").font(.hush(.title2).bold())
                Spacer()
                Button { close() } label: {
                    Label("Close", systemImage: "xmark").font(.hush(.subheadline))
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Rectangle().fill(palette.border).frame(height: 1)

            SpaceSwitcher()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    header("Sections") {
                        Button { close(); openSettings() } label: { Image(systemName: "slider.horizontal.3") }
                            .accessibilityLabel("Customize sections")
                    }
                    ForEach(settings.visibleSections) { s in
                        DrawerRow(symbol: s.symbol, title: settings.title(for: s), count: count(s),
                                  selected: router.section == s) { router.go(s) }
                    }
                    let topFolders = foldersStored.live(settings.spaceFilter).filter { $0.parentID == nil }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if !topFolders.isEmpty {
                        Rectangle().fill(palette.border).frame(height: 1).padding(.vertical, 10)
                        header("Folders") { EmptyView() }
                        ForEach(topFolders) { f in
                            let ids = FolderPath.descendants(of: f.id, in: foldersStored)
                            DrawerRow(symbol: "folder", title: f.name, count: notes.filter { $0.folderID.map(ids.contains) ?? false }.count, selected: false) {
                                router.noteFolder = f.id
                                router.go(.notes)
                            }
                        }
                    }
                    if !tags.isEmpty {
                        Rectangle().fill(palette.border).frame(height: 1).padding(.vertical, 10)
                        header("Tags") { EmptyView() }
                        ForEach(tags, id: \.0) { tag, n in
                            DrawerRow(symbol: "number", title: tag, count: n, selected: false) {
                                router.noteTag = tag
                                router.go(.notes)
                            }
                        }
                    }
                }
                .padding(10)
            }

            Rectangle().fill(palette.border).frame(height: 1)
            HStack(spacing: 28) {
                Button { close(); openSettings() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                Button { showTrash = true } label: {
                    Image(systemName: trashCount > 0 ? "trash.fill" : "trash")
                        .overlay(alignment: .topTrailing) {
                            if trashCount > 0 {
                                Text("\(trashCount)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                    .padding(3).background(Circle().fill(.red)).offset(x: 10, y: -8)
                            }
                        }
                }
                .accessibilityLabel("Trash, \(trashCount) items")
                if settings.lockEnabled {
                    Button { lock.lockNow() } label: { Image(systemName: "lock") }.accessibilityLabel("Lock now")
                }
                Spacer()
                Label(OnlineCenter.isActive ? "Online only where you chose" : "Stored only on this device", systemImage: "checkmark.shield")
                    .font(.hush(.caption)).foregroundStyle(.secondary)
            }
            .font(.hush(.title3))
            .foregroundStyle(.tint)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showTrash) {
            NavigationStack {
                TrashView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showTrash = false } } }
            }
        }
        .frame(width: 310)
        .frame(maxHeight: .infinity)
        .background(palette.surface.ignoresSafeArea())
        .offset(x: min(0, dragOffset))
        .gesture(DragGesture()
            .onChanged { dragOffset = $0.translation.width }
            .onEnded { v in
                if v.translation.width < -80 { close() }
                withAnimation(.snappy) { dragOffset = 0 }
            })
    }

    private var trashCount: Int {
        trashNotes.trashed.count + trashTasks.trashed.count + trashOther.trashed.count
    }

    private func header<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.hush(.caption).weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            accessory().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) { router.drawerOpen = false }
    }
}

private struct DrawerRow: View {
    let symbol: String
    let title: String
    let count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.hush(.body).weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                Text(title).font(.hush(.body).weight(selected ? .semibold : .regular))
                Spacer()
                if let count { Text("\(count)").font(.hush(.subheadline)).foregroundStyle(.secondary).monospacedDigit() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background {
                if selected { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.18)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Personal / Work (and any spaces you add). Each space shows only its own items.
struct SpaceSwitcher: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            segment(id: "all", symbol: "square.stack", label: "All")
            ForEach(settings.spaces) { sp in segment(id: sp.id, symbol: sp.symbol, label: sp.name) }
        }
        .padding(4)
        .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border))
    }

    private func segment(id: String, symbol: String, label: String) -> some View {
        let selected = settings.currentSpace == id
        return Button {
            withAnimation(.snappy) { settings.currentSpace = id }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.hush(.body).weight(.medium))
                Text(label).font(.hush(.caption2)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .background {
                if selected { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.tint.opacity(0.18)) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) space")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

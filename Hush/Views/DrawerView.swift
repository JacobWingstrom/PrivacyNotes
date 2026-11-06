import SwiftUI
import SwiftData

/// Slide-out menu with every section, item counts and note tags.
struct DrawerView: View {
    var openSettings: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(LockManager.self) private var lock
    @Environment(\.palette) private var palette
    @Query private var notes: [Note]
    @Query private var tasks: [TaskItem]
    @Query private var drawings: [Drawing]
    @Query private var files: [StoredFile]
    @Query private var journals: [JournalEntry]
    @Query private var events: [CalendarEvent]
    @Query private var contacts: [Contact]
    @Query private var bookmarks: [Bookmark]
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
        case .drawings: return drawings.count
        case .files: return files.count
        case .journals: return journals.count
        case .calendar:
            let start = Calendar.current.startOfDay(for: .now)
            return events.filter { $0.end >= start }.count
        case .contacts: return contacts.count
        case .bookmarks: return bookmarks.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Hush").font(.title2.bold())
                Spacer()
                Button { close() } label: {
                    Label("Close", systemImage: "xmark").font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Rectangle().fill(palette.border).frame(height: 1)

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
                if settings.lockEnabled {
                    Button { lock.lockNow() } label: { Image(systemName: "lock") }.accessibilityLabel("Lock now")
                }
                Spacer()
                Label("Stored only on this iPhone", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .font(.title3)
            .foregroundStyle(.tint)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
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

    private func header<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
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
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                Text(title).font(.body.weight(selected ? .semibold : .regular))
                Spacer()
                if let count { Text("\(count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
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

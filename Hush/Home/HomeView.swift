import SwiftUI
import SwiftData
import EventKit
import UniformTypeIdentifiers

struct HomeView: View {
    let title: String
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @State private var editing = false
    @State private var choosing = false
    @State private var addingWidget = false
    @State private var choosingLayout = false
    @State private var configuring: HomeWidget?
    @State private var dragging: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if editing { editBar }
                ForEach(rows, id: \.first!.id) { row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row) { w in cell(w) }
                    }
                }
                if settings.homeWidgets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 36)).foregroundStyle(.tint)
                        Text("Your Home is empty").font(.hush(.headline))
                        Button("Add a Widget") { addingWidget = true }.buttonStyle(.borderedProminent)
                        Button("Choose a Layout") { choosingLayout = true }
                    }
                    .padding(.top, 60)
                }
            }
            .padding()
            .animation(.snappy, value: settings.homeWidgets)
        }
        .background(palette.background)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "Done" : "Edit") { withAnimation(.snappy) { editing.toggle() } }
                    .fontWeight(editing ? .semibold : .regular)
            }
        }
        .onCreate(.home) { choosing = true }
        .onAppear { if UserDefaults.standard.bool(forKey: "demoHomeEdit") { editing = true } }
        .newItemDialog(isPresented: $choosing)
        .sheet(isPresented: $addingWidget) {
            WidgetGallery { kind in
                let w = HomeWidget(kind: kind)
                settings.homeWidgets.append(w)
                editing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { configuring = w }
            }
        }
        .sheet(isPresented: $choosingLayout) { LayoutPicker() }
        .sheet(item: $configuring) { w in
            NavigationStack { WidgetSettingsView(widgetID: w.id) }
        }
    }

    /// Small widgets pair up side by side; medium and large take the full width.
    private var rows: [[HomeWidget]] {
        var out: [[HomeWidget]] = []
        var pending: HomeWidget?
        for w in settings.homeWidgets {
            if w.size == .small {
                if let p = pending { out.append([p, w]); pending = nil } else { pending = w }
            } else {
                if let p = pending { out.append([p]); pending = nil }
                out.append([w])
            }
        }
        if let p = pending { out.append([p]) }
        return out
    }

    private var editBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { addingWidget = true } label: {
                    Label("Add Widget", systemImage: "plus.square").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                Button { choosingLayout = true } label: {
                    Label("Layouts", systemImage: "square.grid.2x2").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
            Text("Drag widgets to move them. Tap a widget's gear to set it up, or the minus to remove it.")
                .font(.hush(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func cell(_ w: HomeWidget) -> some View {
        let view = HomeWidgetView(widget: w)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(!editing)
            .overlay(alignment: .topLeading) {
                if editing {
                    Button { remove(w) } label: {
                        Image(systemName: "minus.circle.fill").font(.title2).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                    .offset(x: -8, y: -8)
                    .accessibilityLabel("Remove \(w.displayTitle)")
                }
            }
            .overlay(alignment: .topTrailing) {
                if editing {
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(w.kind.allowedSizes) { s in
                                Button { update(w.id) { $0.size = s } } label: {
                                    Label(s.label, systemImage: w.size == s ? "checkmark" : "")
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.bold))
                                .frame(width: 30, height: 30).background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Resize")
                        Button { configuring = w } label: {
                            Image(systemName: "gearshape.fill").font(.caption.weight(.bold))
                                .frame(width: 30, height: 30).background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Widget settings")
                    }
                    .padding(8)
                }
            }
            .scaleEffect(dragging == w.id ? 0.96 : 1)
            .opacity(dragging == w.id ? 0.6 : 1)
            .contextMenu {
                Button { configuring = w } label: { Label("Widget Settings", systemImage: "gearshape") }
                Menu {
                    ForEach(w.kind.allowedSizes) { s in Button(s.label) { update(w.id) { $0.size = s } } }
                } label: { Label("Size", systemImage: "arrow.up.left.and.arrow.down.right") }
                Button { move(w, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                Button { move(w, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                Button { duplicate(w) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { remove(w) } label: { Label("Remove", systemImage: "minus.circle") }
            }
        if editing {
            view
                .draggable(w.id.uuidString) {
                    Label(w.displayTitle, systemImage: w.displaySymbol).padding(10).background(.regularMaterial, in: Capsule())
                        .onAppear { dragging = w.id }
                }
                .dropDestination(for: String.self) { items, _ in
                    defer { dragging = nil }
                    guard let s = items.first, let from = UUID(uuidString: s) else { return false }
                    moveWidget(from, before: w.id)
                    return true
                } isTargeted: { _ in }
        } else {
            view
        }
    }

    private func update(_ id: UUID, _ change: (inout HomeWidget) -> Void) {
        guard let i = settings.homeWidgets.firstIndex(where: { $0.id == id }) else { return }
        change(&settings.homeWidgets[i])
    }

    private func remove(_ w: HomeWidget) { settings.homeWidgets.removeAll { $0.id == w.id } }

    private func duplicate(_ w: HomeWidget) {
        guard let i = settings.homeWidgets.firstIndex(of: w) else { return }
        var copy = w
        copy.id = UUID()
        settings.homeWidgets.insert(copy, at: i + 1)
    }

    private func move(_ w: HomeWidget, by delta: Int) {
        guard let i = settings.homeWidgets.firstIndex(of: w) else { return }
        let j = min(max(i + delta, 0), settings.homeWidgets.count - 1)
        guard i != j else { return }
        settings.homeWidgets.swapAt(i, j)
    }

    private func moveWidget(_ id: UUID, before target: UUID) {
        guard id != target, let from = settings.homeWidgets.firstIndex(where: { $0.id == id }) else { return }
        var list = settings.homeWidgets
        let item = list.remove(at: from)
        let to = list.firstIndex(where: { $0.id == target }) ?? list.count
        list.insert(item, at: from <= to ? min(to + 1, list.count) : to)
        settings.homeWidgets = list
    }
}

// MARK: - Gallery

struct WidgetGallery: View {
    var onPick: (HomeWidgetKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(HomeWidgetKind.allCases) { kind in
                    Button {
                        onPick(kind)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            SymbolTile(name: kind.symbol, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.name).font(.hush(.headline)).foregroundStyle(.primary)
                                Text(kind.blurb).font(.hush(.caption)).foregroundStyle(.secondary)
                                Text(kind.allowedSizes.map(\.short).joined(separator: " · ")).font(.hush(.caption2)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(.tint).font(.title3)
                        }
                        .padding(.vertical, 4)
                    }
                    .hushRow()
                }
            }
            .hushList()
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct LayoutPicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var confirm: HomeLayouts.Preset?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(HomeLayouts.presets) { p in
                        Button { confirm = p } label: {
                            HStack(spacing: 14) {
                                SymbolTile(name: p.symbol, size: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.name).font(.hush(.headline)).foregroundStyle(.primary)
                                    Text(p.detail).font(.hush(.caption)).foregroundStyle(.secondary)
                                    Text(p.widgets().map(\.kind.name).joined(separator: ", ")).font(.hush(.caption2)).foregroundStyle(.tertiary).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .hushRow()
                    }
                } header: { ListHeader(title: "Start from a layout") }
                Section {
                    NavigationLink { HomeCustomizeView() } label: { Label("Arrange as a List", systemImage: "list.bullet") }
                        .hushRow()
                    Button(role: .destructive) { settings.homeWidgets = [] } label: { Label("Clear Home", systemImage: "trash") }
                        .hushRow()
                }
            }
            .hushList()
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Replace your Home with “\(confirm?.name ?? "")”?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
                Button("Replace") {
                    if let p = confirm { settings.homeWidgets = p.widgets() }
                    dismiss()
                }
                Button("Add Below Current Widgets") {
                    if let p = confirm { settings.homeWidgets += p.widgets() }
                    dismiss()
                }
            }
        }
    }
}

/// Reorder, remove and open settings for widgets in a plain list.
struct HomeCustomizeView: View {
    @Environment(AppSettings.self) private var settings
    @State private var configuring: HomeWidget?

    var body: some View {
        @Bindable var s = settings
        List {
            Section {
                ForEach(settings.homeWidgets) { w in
                    Button { configuring = w } label: {
                        HStack(spacing: 12) {
                            Image(systemName: w.displaySymbol).foregroundStyle(.tint).frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(w.displayTitle).foregroundStyle(.primary)
                                Text("\(w.kind.name) · \(w.size.short)").font(.hush(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "gearshape").foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { s.homeWidgets.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { s.homeWidgets.remove(atOffsets: $0) }
            } footer: {
                Text("Drag to reorder. Two small widgets in a row sit side by side.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .hushBackground()
        .navigationTitle("Arrange Home")
        .sheet(item: $configuring) { w in NavigationStack { WidgetSettingsView(widgetID: w.id) } }
    }
}

// MARK: - Per-widget settings

struct WidgetSettingsView: View {
    let widgetID: UUID
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @Query(sort: \Habit.sortIndex) private var habits: [Habit]
    @Query private var folders: [Folder]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query private var bookmarks: [Bookmark]
    @Query(sort: \Board.sortIndex) private var boards: [Board]
    @State private var pickingIcon = false

    private var index: Int? { settings.homeWidgets.firstIndex { $0.id == widgetID } }

    var body: some View {
        if let i = index {
            form(Binding(get: { settings.homeWidgets[min(i, settings.homeWidgets.count - 1)] },
                         set: { new in if let j = index { settings.homeWidgets[j] = new } }))
        } else {
            Text("This widget was removed.").foregroundStyle(.secondary)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func form(_ w: Binding<HomeWidget>) -> some View {
        HushForm {
            Section {
                HStack {
                    Button { pickingIcon = true } label: { SymbolTile(name: w.wrappedValue.displaySymbol, tint: tintColor(w.wrappedValue), size: 40) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change icon")
                    TextField(w.wrappedValue.kind.name, text: w.title)
                        .font(.hush(.headline))
                }
                if w.wrappedValue.kind.allowedSizes.count > 1 {
                    Picker("Size", selection: w.size) {
                        ForEach(w.wrappedValue.kind.allowedSizes) { Text($0.short).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Show Title Bar", isOn: w.showHeader)
                Picker("Color", selection: w.tintHex) {
                    Text("Accent").tag("")
                    ForEach(AccentPreset.all) { Text($0.name).tag($0.hex) }
                }
            } header: {
                Text(w.wrappedValue.kind.name)
            } footer: {
                Text(w.wrappedValue.kind.blurb)
            }
            kindSection(w)
        }
        .navigationTitle("Widget Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $pickingIcon) {
            SymbolPicker(selection: w.symbol, allowNone: true, title: "Widget Icon")
        }
    }

    private func tintColor(_ w: HomeWidget) -> Color { w.tintHex.isEmpty ? settings.accentColor : Color(hex: w.tintHex) }

    private func limitStepper(_ w: Binding<HomeWidget>, range: ClosedRange<Int> = 1...20) -> some View {
        Stepper("Show up to \(w.wrappedValue.limit)", value: w.limit, in: range)
    }

    @ViewBuilder
    private func kindSection(_ w: Binding<HomeWidget>) -> some View {
        switch w.wrappedValue.kind {
        case .greeting:
            Section("Greeting") {
                Toggle("Show Date", isOn: w.showDate)
                TextField("Message (optional)", text: w.message, axis: .vertical)
            }
        case .quickAdd:
            Section("Quick Add") {
                Toggle("Show Type-to-Add Field", isOn: w.showQuickField)
                ForEach([("notes", "Note"), ("tasks", "Task"), ("habits", "Habit"), ("journals", "Journal"),
                         ("calendar", "Event"), ("bookmarks", "Link"), ("contacts", "Contact"), ("drawings", "Sketch")], id: \.0) { key, label in
                    Toggle(isOn: Binding(get: { w.wrappedValue.quickKinds.contains(key) },
                                         set: { on in
                                             if on { w.wrappedValue.quickKinds.append(key) } else { w.wrappedValue.quickKinds.removeAll { $0 == key } }
                                         })) { Label(label, systemImage: AppSection(rawValue: key)?.symbol ?? "plus") }
                }
            }
        case .tasks:
            Section("Tasks") {
                Picker("Show", selection: w.taskScope) {
                    Text("Today & Overdue").tag("today")
                    Text("Upcoming").tag("upcoming")
                    Text("Overdue").tag("overdue")
                    Text("All Open").tag("all")
                    Text("No Due Date").tag("nodate")
                    Text("A List").tag("list")
                }
                if w.wrappedValue.taskScope == "list" {
                    let lists = Array(Set(tasks.map(\.list).filter { !$0.isEmpty })).sorted()
                    Picker("List", selection: w.listName) {
                        Text("None").tag("")
                        ForEach(lists, id: \.self) { Text($0).tag($0) }
                    }
                }
                Toggle("Show Tasks Finished Today", isOn: w.showCompleted)
                limitStepper(w)
            }
        case .board:
            Section("Board") {
                Picker("Board", selection: w.boardID) {
                    Text("First board").tag(UUID?.none)
                    ForEach(boards.filter { $0.deletedAt == nil }) { Text($0.title).tag(Optional($0.id)) }
                }
                let chosen = boards.first { $0.id == w.wrappedValue.boardID } ?? boards.first { $0.deletedAt == nil }
                Picker("Show", selection: w.columnID) {
                    Text("All Columns (summary)").tag(UUID?.none)
                    ForEach(chosen?.columns ?? []) { Text("Cards in \($0.name)").tag(Optional($0.id)) }
                }
                if w.wrappedValue.columnID != nil { limitStepper(w) }
            }
        case .habits:
            Section {
                Picker("Style", selection: w.habitStyle) {
                    Text("List").tag("list")
                    Text("Rings").tag("rings")
                }
                .pickerStyle(.segmented)
                ForEach(habits.filter { $0.deletedAt == nil && !$0.archived }) { h in
                    Toggle(isOn: Binding(get: { w.wrappedValue.habitIDs.contains(h.id) },
                                         set: { on in
                                             if on { w.wrappedValue.habitIDs.append(h.id) } else { w.wrappedValue.habitIDs.removeAll { $0 == h.id } }
                                         })) {
                        Label { Text(h.name) } icon: { SymbolIcon(name: h.emoji, fallback: "checkmark.circle") }
                    }
                }
            } header: {
                Text("Habits")
            } footer: {
                Text(w.wrappedValue.habitIDs.isEmpty ? "None picked: shows every habit due today." : "Shows only the habits you picked.")
            }
        case .calendar:
            Section("Calendar") {
                Picker("View", selection: w.calendarStyle) {
                    Text("Month").tag("month")
                    Text("Week").tag("week")
                }
                .pickerStyle(.segmented)
                Toggle("Mark Days with Tasks", isOn: w.includeTasks)
                Toggle("Include iPhone Calendars", isOn: w.includePhoneEvents)
            }
        case .agenda:
            Section("Agenda") {
                Stepper("Next \(w.wrappedValue.days) day\(w.wrappedValue.days == 1 ? "" : "s")", value: w.days, in: 1...60)
                Toggle("Include Tasks", isOn: w.includeTasks)
                Toggle("Include iPhone Calendars", isOn: w.includePhoneEvents)
                limitStepper(w, range: 1...30)
            }
        case .notes:
            Section("Notes") {
                Picker("Show", selection: w.noteScope) {
                    Text("Recent").tag("recent")
                    Text("Pinned").tag("pinned")
                    Text("A Folder").tag("folder")
                    Text("A Tag").tag("tag")
                }
                if w.wrappedValue.noteScope == "folder" {
                    Picker("Folder", selection: w.folderID) {
                        Text("None").tag(UUID?.none)
                        ForEach(FolderPath.flattened(folders.filter { $0.deletedAt == nil }), id: \.0.id) { f, depth in
                            Text(String(repeating: "  ", count: depth) + f.name).tag(Optional(f.id))
                        }
                    }
                }
                if w.wrappedValue.noteScope == "tag" {
                    let tags = Array(Set(notes.flatMap(\.tags))).sorted()
                    Picker("Tag", selection: w.tag) {
                        Text("None").tag("")
                        ForEach(tags, id: \.self) { Text("#\($0)").tag($0) }
                    }
                }
                Picker("Style", selection: w.noteStyle) {
                    Text("List").tag("list")
                    Text("Cards").tag("cards")
                }
                .pickerStyle(.segmented)
                limitStepper(w)
            }
        case .note:
            Section("Note") {
                Picker("Note", selection: w.noteID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(notes.filter { $0.deletedAt == nil }) { Text($0.displayTitle).tag(Optional($0.id)) }
                }
            }
        case .journal, .mood:
            EmptyView()
        case .stats:
            Section("Show") {
                ForEach(StatKind.allCases) { k in
                    Toggle(isOn: Binding(get: { w.wrappedValue.stats.contains(k.rawValue) },
                                         set: { on in
                                             if on { w.wrappedValue.stats.append(k.rawValue) } else { w.wrappedValue.stats.removeAll { $0 == k.rawValue } }
                                         })) { Label(k.label, systemImage: k.symbol) }
                }
            }
        case .bookmarks:
            Section("Bookmarks") {
                Toggle("Favorites Only", isOn: w.favoritesOnly)
                let tags = Array(Set(bookmarks.flatMap(\.tags))).sorted()
                if !tags.isEmpty {
                    Picker("Tag", selection: w.tag) {
                        Text("Any").tag("")
                        ForEach(tags, id: \.self) { Text("#\($0)").tag($0) }
                    }
                }
                limitStepper(w, range: 1...24)
            }
        case .contacts:
            Section("Contacts") {
                Toggle("Favorites Only", isOn: w.favoritesOnly)
                limitStepper(w, range: 1...12)
            }
        case .countdown:
            Section("Countdown") {
                DatePicker("Date", selection: Binding(get: { w.wrappedValue.targetDate ?? .now }, set: { w.wrappedValue.targetDate = $0 }),
                           displayedComponents: .date)
            }
        case .files:
            Section("Files") { limitStepper(w, range: 1...12) }
        }
    }
}

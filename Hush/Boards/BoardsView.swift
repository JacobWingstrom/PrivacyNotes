import SwiftUI
import SwiftData

struct BoardsView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Query(sort: \Board.sortIndex) private var stored: [Board]
    @Query private var cardsStored: [BoardCard]
    @State private var choosing = false
    @State private var open: Board?
    @State private var showArchived = false

    var body: some View {
        let boards = stored.live(settings.spaceFilter).filter { showArchived || !$0.archived }
        let cards = cardsStored.live(nil)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(boards) { b in
                    NavigationLink { BoardView(board: b) } label: { BoardTile(board: b, cards: cards.filter { $0.boardID == b.id }) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { b.archived.toggle() } label: { Label(b.archived ? "Unarchive" : "Archive", systemImage: "archivebox") }
                            Button { duplicate(b, cards: cards) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button(role: .destructive) { TrashActions.trash(b) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                Button { choosing = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.title2)
                        Text("New Board").font(.hush(.subheadline))
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .foregroundStyle(.tint)
                    .background(palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.border, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                }
                .buttonStyle(.plain)
            }
            .padding()
            if stored.live(settings.spaceFilter).contains(where: \.archived) {
                Toggle("Show Archived Boards", isOn: $showArchived).padding(.horizontal)
            }
        }
        .background(palette.background)
        .navigationTitle(title)
        .onCreate(.boards) { choosing = true }
        .sheet(isPresented: $choosing) { BoardTemplatePicker { create($0) } }
        .navigationDestination(item: $open) { BoardView(board: $0) }
        .onAppear { if UserDefaults.standard.bool(forKey: "demoOpenBoard"), open == nil { open = boards.first } }
    }

    private func create(_ t: BoardTemplates.Template) {
        let b = Board(title: t.id == "blank" ? "New Board" : t.name)
        BoardTemplates.apply(t, to: b)
        b.sortIndex = (stored.map(\.sortIndex).max() ?? 0) + 1
        context.insert(b)
        open = b
    }

    private func duplicate(_ b: Board, cards: [BoardCard]) {
        let copy = Board(title: b.title + " copy")
        copy.symbol = b.symbol; copy.colorName = b.colorName; copy.labelsData = b.labelsData
        copy.showDueDates = b.showDueDates; copy.showLabels = b.showLabels; copy.showChecklist = b.showChecklist
        copy.showNotes = b.showNotes; copy.compactCards = b.compactCards; copy.tintedCards = b.tintedCards
        copy.columnWidthRaw = b.columnWidthRaw
        var map: [UUID: UUID] = [:]
        copy.columns = b.columns.map { c in var n = c; n.id = UUID(); map[c.id] = n.id; return n }
        context.insert(copy)
        for c in cards where c.boardID == b.id {
            let n = BoardCard(boardID: copy.id, columnID: map[c.columnID] ?? c.columnID, title: c.title)
            n.notes = c.notes; n.order = c.order; n.colorName = c.colorName; n.labelIDs = c.labelIDs
            n.checklistData = c.checklistData; n.priorityRaw = c.priorityRaw; n.symbol = c.symbol
            context.insert(n)
        }
    }
}

private struct BoardTile: View {
    let board: Board
    let cards: [BoardCard]
    @Environment(\.palette) private var palette

    var body: some View {
        let tint = board.color ?? Color.accentColor
        let cols = board.columns
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SymbolTile(name: board.symbol, fallback: "rectangle.split.3x1", tint: tint, size: 36)
                Spacer()
                if board.archived { Image(systemName: "archivebox").foregroundStyle(.secondary) }
            }
            Text(board.title).font(.hush(.headline)).lineLimit(2)
            // Mini preview: one bar per column, height by card count.
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(cols) { c in
                    let n = cards.filter { $0.columnID == c.id }.count
                    RoundedRectangle(cornerRadius: 2)
                        .fill((NoteColor(rawValue: c.colorName)?.color ?? tint).opacity(0.75))
                        .frame(height: CGFloat(4 + min(n, 10) * 3))
                }
            }
            .frame(height: 34, alignment: .bottom)
            Text("\(cards.filter { $0.completedAt == nil }.count) open · \(cols.count) columns")
                .font(.hush(.caption)).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.border))
    }
}

struct BoardTemplatePicker: View {
    var onPick: (BoardTemplates.Template) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(BoardTemplates.all) { t in
                Button { onPick(t); dismiss() } label: {
                    HStack(spacing: 14) {
                        SymbolTile(name: t.symbol, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.name).font(.hush(.headline)).foregroundStyle(.primary)
                            Text(t.columns.map(\.0).joined(separator: " → ")).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .hushRow()
            }
            .hushList()
            .navigationTitle("New Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Board

struct BoardView: View {
    @Bindable var board: Board
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Query(sort: \BoardCard.order) private var cardsStored: [BoardCard]
    @State private var editingCard: BoardCard?
    @State private var showSettings = false
    @State private var labelFilter: UUID?
    @State private var search = ""
    @State private var newTitles: [UUID: String] = [:]
    @State private var targetedColumn: UUID?

    private var cards: [BoardCard] {
        cardsStored.filter { $0.boardID == board.id && $0.deletedAt == nil }
            .filter { labelFilter == nil || $0.labelIDs.contains(labelFilter!) }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let all = cards
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(board.columns) { col in
                    column(col, cards: sorted(all.filter { $0.columnID == col.id }, by: col.sort))
                }
                Button { addColumn() } label: {
                    Label("Add Column", systemImage: "plus")
                        .frame(width: 160, height: 54)
                        .background(palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(boardBackground)
        .tint(board.color ?? Color.accentColor)
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchHeader(text: $search, prompt: "Search cards…") {
                FilterButton(active: labelFilter != nil) {
                    Picker("Label", selection: $labelFilter) {
                        Text("All Cards").tag(UUID?.none)
                        ForEach(board.labels) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
        }
        .navigationTitle($board.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Board settings")
            }
        }
        .sheet(item: $editingCard) { c in NavigationStack { CardEditor(card: c, board: board) } }
        .sheet(isPresented: $showSettings) { NavigationStack { BoardSettings(board: board) } }
    }

    private var boardBackground: some View {
        ZStack {
            palette.background
            if let c = board.color { c.opacity(0.06) }
        }
        .ignoresSafeArea()
    }

    private func sorted(_ list: [BoardCard], by sort: String) -> [BoardCard] {
        switch sort {
        case "due": return list.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case "priority": return list.sorted { $0.priorityRaw > $1.priorityRaw }
        case "created": return list.sorted { $0.createdAt > $1.createdAt }
        case "title": return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        default: return list.sorted { $0.order < $1.order }
        }
    }

    @ViewBuilder
    private func column(_ col: BoardColumn, cards: [BoardCard]) -> some View {
        let tint = NoteColor(rawValue: col.colorName)?.color ?? Color.secondary
        let over = col.wipLimit > 0 && cards.count > col.wipLimit
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if SymbolName.isValid(col.symbol) {
                    Image(systemName: col.symbol).foregroundStyle(tint)
                } else {
                    Circle().fill(tint).frame(width: 9, height: 9)
                }
                Text(col.name).font(.hush(.headline)).lineLimit(1)
                Text(col.wipLimit > 0 ? "\(cards.count)/\(col.wipLimit)" : "\(cards.count)")
                    .font(.hush(.caption).monospacedDigit())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(over ? AnyShapeStyle(Color.red.opacity(0.25)) : AnyShapeStyle(palette.field), in: Capsule())
                    .foregroundStyle(over ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                Spacer(minLength: 0)
                columnMenu(col)
            }
            if !col.collapsed {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(cards) { card in
                            CardView(card: card, board: board)
                                .onTapGesture { editingCard = card }
                                .draggable(card.id.uuidString)
                                .dropDestination(for: String.self) { items, _ in
                                    move(items, to: col, before: card, in: cards)
                                }
                                .contextMenu { cardMenu(card) }
                        }
                        addField(col)
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(width: col.collapsed ? 170 : board.columnWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(targetedColumn == col.id ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.border), lineWidth: targetedColumn == col.id ? 2 : 1))
        .dropDestination(for: String.self) { items, _ in
            move(items, to: col, before: nil, in: cards)
        } isTargeted: { on in targetedColumn = on ? col.id : (targetedColumn == col.id ? nil : targetedColumn) }
    }

    private func addField(_ col: BoardColumn) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").foregroundStyle(.secondary)
            TextField("Add a card", text: Binding(get: { newTitles[col.id] ?? "" }, set: { newTitles[col.id] = $0 }))
                .submitLabel(.done)
                .onSubmit { addCard(to: col) }
        }
        .padding(10)
        .background(palette.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func columnMenu(_ col: BoardColumn) -> some View {
        Menu {
            Button { update(col.id) { $0.collapsed.toggle() } } label: { Label(col.collapsed ? "Expand" : "Collapse", systemImage: "rectangle.compress.vertical") }
            Menu {
                ForEach([("manual", "Manual"), ("due", "Due Date"), ("priority", "Priority"), ("created", "Newest"), ("title", "Title")], id: \.0) { key, label in
                    Button { update(col.id) { $0.sort = key } } label: { Label(label, systemImage: col.sort == key ? "checkmark" : "") }
                }
            } label: { Label("Sort Cards", systemImage: "arrow.up.arrow.down") }
            Button { moveColumn(col.id, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
            Button { moveColumn(col.id, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
            Button { showSettings = true } label: { Label("Edit Columns…", systemImage: "slider.horizontal.3") }
        } label: {
            Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func cardMenu(_ card: BoardCard) -> some View {
        Menu {
            ForEach(board.columns) { c in
                Button(c.name) { setColumn(card, c) }
            }
        } label: { Label("Move To", systemImage: "arrow.right.square") }
        Picker(selection: Binding(get: { card.colorName }, set: { card.colorName = $0 })) {
            ForEach(NoteColor.allCases) { Text($0.label).tag($0.rawValue) }
        } label: { Label("Color", systemImage: "paintpalette") }
        Button { sendToTasks(card) } label: { Label("Copy to Tasks", systemImage: "checkmark.circle") }
        Button(role: .destructive) { TrashActions.trash(card) } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: Actions

    private func update(_ id: UUID, _ change: (inout BoardColumn) -> Void) {
        var cols = board.columns
        guard let i = cols.firstIndex(where: { $0.id == id }) else { return }
        change(&cols[i])
        board.columns = cols
    }

    private func moveColumn(_ id: UUID, by delta: Int) {
        var cols = board.columns
        guard let i = cols.firstIndex(where: { $0.id == id }) else { return }
        let j = min(max(i + delta, 0), cols.count - 1)
        cols.swapAt(i, j)
        board.columns = cols
    }

    private func addColumn() {
        board.columns = board.columns + [BoardColumn(name: "New Column")]
        showSettings = true
    }

    private func addCard(to col: BoardColumn) {
        let title = (newTitles[col.id] ?? "").trimmed
        guard !title.isEmpty else { return }
        let c = BoardCard(boardID: board.id, columnID: col.id, title: title)
        c.order = (cardsStored.filter { $0.columnID == col.id }.map(\.order).max() ?? 0) + 1
        if col.isDone { c.completedAt = .now }
        context.insert(c)
        newTitles[col.id] = ""
        board.updatedAt = .now
    }

    private func setColumn(_ card: BoardCard, _ col: BoardColumn) {
        withAnimation(.snappy) {
            card.columnID = col.id
            card.order = (cardsStored.filter { $0.columnID == col.id }.map(\.order).max() ?? 0) + 1
            card.completedAt = col.isDone ? (card.completedAt ?? .now) : nil
        }
        board.updatedAt = .now
    }

    private func move(_ items: [String], to col: BoardColumn, before target: BoardCard?, in list: [BoardCard]) -> Bool {
        targetedColumn = nil
        guard let s = items.first, let id = UUID(uuidString: s), let card = cardsStored.first(where: { $0.id == id }) else { return false }
        withAnimation(.snappy) {
            card.columnID = col.id
            card.completedAt = col.isDone ? (card.completedAt ?? .now) : nil
            if let target, target.id != card.id {
                let others = list.filter { $0.id != card.id }
                if let i = others.firstIndex(where: { $0.id == target.id }) {
                    let before = i > 0 ? others[i - 1].order : target.order - 2
                    card.order = (before + target.order) / 2
                }
            } else if target == nil {
                card.order = (list.filter { $0.id != card.id }.map(\.order).max() ?? 0) + 1
            }
        }
        board.updatedAt = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return true
    }

    private func sendToTasks(_ card: BoardCard) {
        let t = TaskItem(title: card.title)
        t.notes = card.notes
        t.dueDate = card.dueDate
        t.priorityRaw = card.priorityRaw
        t.subtasks = card.checklist
        t.list = board.title
        context.insert(t)
    }
}

struct CardView: View {
    let card: BoardCard
    let board: Board
    @Environment(\.palette) private var palette

    var body: some View {
        let labels = board.labels.filter { card.labelIDs.contains($0.id) }
        let checklist = card.checklist
        let tint = card.color
        VStack(alignment: .leading, spacing: board.compactCards ? 4 : 7) {
            if board.showLabels && !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels) { l in
                        Text(l.name)
                            .font(.hush(.caption2).weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background((NoteColor(rawValue: l.colorName)?.color ?? .blue).opacity(0.22), in: Capsule())
                            .foregroundStyle(NoteColor(rawValue: l.colorName)?.color ?? .blue)
                    }
                }
            }
            HStack(alignment: .top, spacing: 6) {
                if SymbolName.isValid(card.symbol) { Image(systemName: card.symbol).foregroundStyle(tint ?? Color.accentColor) }
                Text(card.title)
                    .font(.hush(board.compactCards ? .subheadline : .body))
                    .strikethrough(card.completedAt != nil)
                    .foregroundStyle(card.completedAt != nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let c = card.priority.color {
                    Text(String(repeating: "!", count: card.priority.rawValue)).font(.hush(.caption).bold()).foregroundStyle(c)
                }
            }
            if board.showNotes && !board.compactCards && !card.notes.isEmpty {
                Text(Markdown.plain(card.notes)).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(3)
            }
            let showDue = board.showDueDates && card.dueDate != nil
            let showList = board.showChecklist && !checklist.isEmpty
            if showDue || showList {
                HStack(spacing: 10) {
                    if showDue, let d = card.dueDate {
                        Label(DateText.relativeDay(d), systemImage: card.remind ? "bell" : "calendar")
                            .foregroundStyle(card.isOverdue ? Color.red : Color.secondary)
                    }
                    if showList {
                        Label("\(checklist.filter(\.done).count)/\(checklist.count)", systemImage: "checklist")
                            .foregroundStyle(checklist.allSatisfy(\.done) ? Color.green : Color.secondary)
                    }
                }
                .font(.hush(.caption))
            }
        }
        .padding(board.compactCards ? 9 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(board.tintedCards && tint != nil ? AnyShapeStyle(tint!.opacity(0.16)) : AnyShapeStyle(palette.field))
        }
        .overlay(alignment: .leading) {
            if let tint { RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4).padding(.vertical, 8) }
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Card editor

struct CardEditor: View {
    @Bindable var card: BoardCard
    let board: Board
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newItem = ""
    @State private var pickingIcon = false
    @State private var deleting = false

    var body: some View {
        HushForm {
            Section {
                TextField("Title", text: $card.title, axis: .vertical).font(.hush(.headline))
                TextField("Notes (Markdown)", text: $card.notes, axis: .vertical).lineLimit(3...14)
            }
            Section {
                Picker("Column", selection: Binding(get: { card.columnID }, set: { id in
                    card.columnID = id
                    let done = board.columns.first { $0.id == id }?.isDone ?? false
                    card.completedAt = done ? (card.completedAt ?? .now) : nil
                })) {
                    ForEach(board.columns) { Text($0.name).tag($0.id) }
                }
                Picker("Priority", selection: $card.priority) { ForEach(Priority.allCases) { Text($0.label).tag($0) } }
                Picker("Color", selection: $card.colorName) { ForEach(NoteColor.allCases) { Text($0.label).tag($0.rawValue) } }
                Button { pickingIcon = true } label: {
                    HStack {
                        Text("Icon").foregroundStyle(.primary)
                        Spacer()
                        if SymbolName.isValid(card.symbol) { Image(systemName: card.symbol).foregroundStyle(.tint) } else { Text("None").foregroundStyle(.secondary) }
                    }
                }
            }
            if !board.labels.isEmpty {
                Section("Labels") {
                    ForEach(board.labels) { l in
                        Toggle(isOn: Binding(get: { card.labelIDs.contains(l.id) },
                                             set: { on in if on { card.labelIDs.append(l.id) } else { card.labelIDs.removeAll { $0 == l.id } } })) {
                            Label { Text(l.name) } icon: { Circle().fill(NoteColor(rawValue: l.colorName)?.color ?? .blue).frame(width: 12, height: 12) }
                        }
                    }
                }
            }
            Section {
                Toggle("Due Date", isOn: Binding(get: { card.dueDate != nil }, set: { card.dueDate = $0 ? Calendar.current.startOfDay(for: .now) : nil; if !$0 { card.remind = false } }))
                if card.dueDate != nil {
                    DatePicker("Date", selection: Binding(get: { card.dueDate ?? .now }, set: { card.dueDate = $0 }), displayedComponents: .date)
                    Toggle("Remind Me", isOn: $card.remind)
                }
            }
            Section("Checklist") {
                ForEach(Binding(get: { card.checklist }, set: { card.checklist = $0 })) { $item in
                    HStack {
                        CheckButton(done: item.done) { item.done.toggle() }
                        TextField("Item", text: $item.title).strikethrough(item.done)
                    }
                }
                .onDelete { card.checklist.remove(atOffsets: $0) }
                HStack {
                    Image(systemName: "plus").foregroundStyle(.tint)
                    TextField("Add item", text: $newItem).onSubmit {
                        guard !newItem.trimmed.isEmpty else { return }
                        card.checklist.append(Subtask(title: newItem.trimmed))
                        newItem = ""
                    }
                }
            }
            Section {
                LabeledContent("Created", value: card.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let d = card.completedAt { LabeledContent("Finished", value: d.formatted(date: .abbreviated, time: .shortened)) }
                Button("Delete Card", role: .destructive) { deleting = true; dismiss() }
            }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $pickingIcon) { SymbolPicker(selection: $card.symbol) }
        .onChange(of: card.remind) { _, on in if on { Task { await Reminders.requestPermission() } } }
        .onDisappear {
            if deleting { TrashActions.trash(card) } else if card.title.trimmed.isEmpty && card.notes.isEmpty { context.delete(card) }
            let id = "card.\(card.id.uuidString)"
            if card.remind, card.completedAt == nil, card.deletedAt == nil, let d = card.dueDate {
                let when = Calendar.current.startOfDay(for: d).addingTimeInterval(Double(Reminders.defaultMinutes * 60))
                Reminders.schedule(id: id, title: card.title, body: "Due on \(board.title)", at: when)
            } else {
                Reminders.cancel(id)
            }
        }
    }
}

// MARK: - Board settings

struct BoardSettings: View {
    @Bindable var board: Board
    @Environment(\.dismiss) private var dismiss
    @State private var pickingIcon = false
    @State private var newLabel = ""

    var body: some View {
        HushForm {
            Section {
                HStack {
                    Button { pickingIcon = true } label: { SymbolTile(name: board.symbol, fallback: "rectangle.split.3x1", tint: board.color ?? .accentColor, size: 40) }
                        .buttonStyle(.plain)
                    TextField("Board name", text: $board.title).font(.hush(.headline))
                }
                Picker("Color", selection: $board.colorName) { ForEach(NoteColor.allCases) { Text($0 == .none ? "Accent" : $0.label).tag($0.rawValue) } }
                Toggle("Archived", isOn: $board.archived)
            }
            Section {
                ForEach(Binding(get: { board.columns }, set: { board.columns = $0 })) { $col in
                    ColumnRow(column: $col)
                }
                .onMove { board.columns.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { board.columns.remove(atOffsets: $0) }
                Button { board.columns = board.columns + [BoardColumn(name: "New Column")] } label: { Label("Add Column", systemImage: "plus") }
            } header: {
                Text("Columns")
            } footer: {
                Text("Drag to reorder. A limit warns you when a column has too many cards. Cards moved into a “Done” column are marked finished. Deleting a column leaves its cards in Trash-safe limbo until you move them.")
            }
            Section("Cards") {
                Toggle("Show Labels", isOn: $board.showLabels)
                Toggle("Show Due Dates", isOn: $board.showDueDates)
                Toggle("Show Checklist Progress", isOn: $board.showChecklist)
                Toggle("Show Notes Preview", isOn: $board.showNotes)
                Toggle("Tint Cards with Their Color", isOn: $board.tintedCards)
                Toggle("Compact Cards", isOn: $board.compactCards)
                Picker("Column Width", selection: $board.columnWidthRaw) {
                    Text("Narrow").tag("narrow")
                    Text("Regular").tag("regular")
                    Text("Wide").tag("wide")
                }
                .pickerStyle(.segmented)
            }
            Section("Labels") {
                ForEach(Binding(get: { board.labels }, set: { board.labels = $0 })) { $l in
                    HStack {
                        Menu {
                            ForEach(NoteColor.allCases.filter { $0 != .none }) { c in Button(c.label) { l.colorName = c.rawValue } }
                        } label: { Circle().fill(NoteColor(rawValue: l.colorName)?.color ?? .blue).frame(width: 16, height: 16) }
                        TextField("Label", text: $l.name)
                    }
                }
                .onDelete { board.labels.remove(atOffsets: $0) }
                HStack {
                    TextField("New label", text: $newLabel)
                    Button("Add") {
                        guard !newLabel.trimmed.isEmpty else { return }
                        let colors = ["blue", "green", "orange", "purple", "red", "teal", "pink", "yellow"]
                        board.labels = board.labels + [BoardLabel(name: newLabel.trimmed, colorName: colors[board.labels.count % colors.count])]
                        newLabel = ""
                    }
                    .disabled(newLabel.trimmed.isEmpty)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Board Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $pickingIcon) { SymbolPicker(selection: $board.symbol, allowNone: false) }
    }
}

private struct ColumnRow: View {
    @Binding var column: BoardColumn
    @State private var pickingIcon = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { pickingIcon = true } label: {
                    SymbolIcon(name: column.symbol, fallback: "circle.fill")
                        .foregroundStyle(NoteColor(rawValue: column.colorName)?.color ?? .secondary)
                        .frame(width: 26)
                }
                .buttonStyle(.borderless)
                TextField("Column name", text: $column.name).font(.hush(.headline))
            }
            HStack(spacing: 12) {
                Menu {
                    ForEach(NoteColor.allCases) { c in Button(c == .none ? "Gray" : c.label) { column.colorName = c.rawValue } }
                } label: { Label("Color", systemImage: "paintpalette").font(.hush(.caption)) }
                Stepper(column.wipLimit == 0 ? "No limit" : "Limit \(column.wipLimit)", value: $column.wipLimit, in: 0...50)
                    .font(.hush(.caption))
            }
            Toggle("Cards here are done", isOn: $column.isDone).font(.hush(.caption))
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $pickingIcon) { SymbolPicker(selection: $column.symbol) }
    }
}

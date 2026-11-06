import SwiftUI
import SwiftData

// MARK: - Racks

struct RacksList: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabRack.name) private var stored: [LabRack]
    @Query private var devices: [LabDevice]
    @State private var newRack: LabRack?

    var body: some View {
        let racks = stored.live(settings.spaceFilter)
        List {
            ForEach(racks) { r in
                let inRack = devices.live(nil).filter { $0.rackID == r.id }
                let used = inRack.reduce(0) { $0 + max($1.heightU, 1) }
                NavigationLink { RackView(rack: r) } label: {
                    HStack(spacing: 12) {
                        SymbolTile(name: "square.stack.3d.down.right", size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.hush(.headline))
                            Text("\(used) of \(r.units)U used · \(inRack.count) devices · \(Int(inRack.reduce(0) { $0 + $1.powerWatts })) W")
                                .font(.hush(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions { Button(role: .destructive) { TrashActions.trash(r) } label: { Label("Delete", systemImage: "trash") } }
                .hushRow()
            }
            if racks.isEmpty { EmptyMessage(text: "No racks yet. Tap + to add a rack, shelf or network cabinet, then place devices by U position.") }
        }
        .hushList()
        .onCreate(.homelab) { add() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(action: add) { Image(systemName: "plus") }.accessibilityLabel("New rack") } }
        .navigationDestination(item: $newRack) { RackView(rack: $0) }
    }

    private func add() {
        let r = LabRack(name: "Rack \(stored.count + 1)", units: 12)
        context.insert(r)
        newRack = r
    }
}

struct RackView: View {
    @Bindable var rack: LabRack
    @Environment(\.palette) private var palette
    @Query private var devicesStored: [LabDevice]
    @State private var placing: Int?
    @State private var editing = false

    var body: some View {
        let devices = devicesStored.live(nil)
        let inRack = devices.filter { $0.rackID == rack.id && $0.rackU > 0 }
        let unplaced = devices.filter { $0.rackID == nil && !$0.kind.isVirtual }
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    stat("\(inRack.reduce(0) { $0 + max($1.heightU, 1) })/\(rack.units)U", "Used")
                    stat("\(Int(inRack.reduce(0) { $0 + $1.powerWatts })) W", "Power")
                    stat("\(inRack.count)", "Devices")
                }
                VStack(spacing: 0) {
                    ForEach((1...max(rack.units, 1)).reversed(), id: \.self) { u in
                        if let d = inRack.first(where: { u >= $0.rackU && u < $0.rackU + max($0.heightU, 1) }) {
                            if u == d.rackU + max(d.heightU, 1) - 1 {
                                NavigationLink { DeviceEditor(device: d) } label: { slot(u, device: d) }.buttonStyle(.plain)
                            }
                        } else {
                            Button { placing = u } label: { slot(u, device: nil) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(8)
                .background(Color.black.opacity(palette.isDark ? 0.35 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border, lineWidth: 2))
                Text("Tap an empty slot to place a device. Set a device's height in its settings.")
                    .font(.hush(.caption)).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(palette.background)
        .navigationTitle(rack.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .confirmationDialog("Place at U\(placing ?? 0)", isPresented: Binding(get: { placing != nil }, set: { if !$0 { placing = nil } })) {
            ForEach(unplaced) { d in
                Button(d.displayName) {
                    d.rackID = rack.id
                    d.rackU = placing ?? 1
                    placing = nil
                }
            }
        } message: {
            Text(unplaced.isEmpty ? "All your devices are already in a rack." : "Choose a device")
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                HushForm {
                    Section {
                        TextField("Name", text: $rack.name)
                        Stepper("Size: \(rack.units)U", value: $rack.units, in: 1...52)
                        TextField("Location", text: $rack.location)
                        TextField("Notes", text: $rack.notes, axis: .vertical)
                    }
                }
                .navigationTitle("Rack")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } } }
            }
            .presentationDetents([.medium])
        }
    }

    private func slot(_ u: Int, device: LabDevice?) -> some View {
        let h = CGFloat(max(device?.heightU ?? 1, 1))
        return HStack(spacing: 10) {
            Text("\(u)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).frame(width: 22)
            if let d = device {
                HStack {
                    Image(systemName: d.kind.symbol)
                    Text(d.displayName).font(.hush(.subheadline).weight(.semibold)).lineLimit(1)
                    Spacer()
                    if d.heightU > 1 { Text("\(d.heightU)U").font(.hush(.caption2)) }
                    Circle().fill(d.status.color).frame(width: 7, height: 7)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 26 * h - 2)
                .background(.tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint.opacity(0.6)))
            } else {
                RoundedRectangle(cornerRadius: 4).stroke(palette.border, style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.hush(.headline)).monospacedDigit()
            Text(l).font(.hush(.caption2)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Runbooks

struct RunbooksList: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Runbook.title) private var stored: [Runbook]
    @State private var newRunbook: Runbook?
    @State private var choosing = false

    var body: some View {
        let list = stored.live(settings.spaceFilter)
        List {
            ForEach(Runbook.kinds, id: \.0) { kind, label, symbol in
                let items = list.filter { $0.kindRaw == kind }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { r in
                            NavigationLink { RunbookView(runbook: r) } label: {
                                HStack(spacing: 12) {
                                    SymbolTile(name: r.symbol, fallback: symbol, tint: r.isDue ? .orange : .accentColor, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title.isEmpty ? label : r.title).font(.hush(.headline))
                                        Text(subtitle(r)).font(.hush(.caption)).foregroundStyle(r.isDue ? Color.orange : Color.secondary)
                                    }
                                }
                            }
                            .swipeActions { Button(role: .destructive) { TrashActions.trash(r) } label: { Label("Delete", systemImage: "trash") } }
                            .hushRow()
                        }
                    } header: { ListHeader(title: label) }
                }
            }
            if list.isEmpty {
                EmptyMessage(text: "No runbooks yet. Tap + for a step-by-step procedure, a repeating maintenance checklist, or a disaster-recovery plan.")
            }
        }
        .hushList()
        .onCreate(.homelab) { choosing = true }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { choosing = true } label: { Image(systemName: "plus") }.accessibilityLabel("New runbook") } }
        .confirmationDialog("New", isPresented: $choosing) {
            Button("Runbook") { add("runbook", nil) }
            Button("Monthly Maintenance (starter)") { add("maintenance", RunbookStarters.maintenance) }
            Button("Disaster Recovery (starter)") { add("recovery", RunbookStarters.recovery) }
            Button("Update Containers (starter)") { add("runbook", RunbookStarters.dockerUpdate) }
            Button("Add a New Service (starter)") { add("runbook", RunbookStarters.newService) }
        }
        .navigationDestination(item: $newRunbook) { RunbookView(runbook: $0, editingInitially: true) }
    }

    private func subtitle(_ r: Runbook) -> String {
        var parts = ["\(r.steps.count) steps"]
        if let d = r.nextDue { parts.append(r.isDue ? "Due now" : "Next \(d.formatted(date: .abbreviated, time: .omitted))") }
        if let last = r.runs.last { parts.append("Last run \(last.date.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
    }

    private func add(_ kind: String, _ starter: (String, String, [RunbookStep])?) {
        let r = Runbook(title: starter?.0 ?? "", kind: kind)
        if let s = starter {
            r.symbol = s.1
            r.steps = s.2
            if kind == "maintenance" {
                r.repeatRaw = "monthly"
                r.nextDue = Calendar.current.date(byAdding: .month, value: 1, to: .now)
            }
        }
        context.insert(r)
        newRunbook = r
    }
}

enum RunbookStarters {
    static let maintenance: (String, String, [RunbookStep]) = ("Monthly Maintenance", "wrench.and.screwdriver", [
        RunbookStep(text: "Apply OS updates on every host", command: "sudo apt update && sudo apt full-upgrade -y"),
        RunbookStep(text: "Update containers", command: "docker compose pull && docker compose up -d"),
        RunbookStep(text: "Remove unused images", command: "docker image prune -f"),
        RunbookStep(text: "Check disk health (SMART)", command: "sudo smartctl -a /dev/sda"),
        RunbookStep(text: "Check pool / RAID status", command: "zpool status"),
        RunbookStep(text: "Review backup job logs"),
        RunbookStep(text: "Test-restore one file or VM"),
        RunbookStep(text: "Check UPS battery and self-test"),
        RunbookStep(text: "Renew certificates expiring soon"),
        RunbookStep(text: "Clean dust filters and check fans"),
    ])
    static let recovery: (String, String, [RunbookStep]) = ("Disaster Recovery", "lifepreserver", [
        RunbookStep(text: "Stay calm and note what failed and when"),
        RunbookStep(text: "Get the network up: modem, router, switch"),
        RunbookStep(text: "Boot the hypervisor / main server"),
        RunbookStep(text: "Check storage pools import cleanly", command: "zpool import"),
        RunbookStep(text: "Restore VMs or containers from the latest backup"),
        RunbookStep(text: "Restore DNS / DHCP first, then core services"),
        RunbookStep(text: "Verify each service from the Services list"),
        RunbookStep(text: "Write an incident note: cause, fix, follow-ups"),
    ])
    static let dockerUpdate: (String, String, [RunbookStep]) = ("Update Containers", "shippingbox", [
        RunbookStep(text: "Read release notes for breaking changes"),
        RunbookStep(text: "Back up the data volume"),
        RunbookStep(text: "Pull new images", command: "docker compose pull"),
        RunbookStep(text: "Recreate containers", command: "docker compose up -d"),
        RunbookStep(text: "Watch the logs", command: "docker compose logs -f --tail=100"),
        RunbookStep(text: "Open the web UI and check it works"),
        RunbookStep(text: "Update the version in Hush → Services"),
    ])
    static let newService: (String, String, [RunbookStep]) = ("Add a New Service", "plus.app", [
        RunbookStep(text: "Pick a host and a free port (check Services → Port Map)"),
        RunbookStep(text: "Create the data folder", command: "mkdir -p /opt/stacks/app/data"),
        RunbookStep(text: "Write the compose file and .env"),
        RunbookStep(text: "Start it", command: "docker compose up -d"),
        RunbookStep(text: "Add a DNS record / reverse proxy entry"),
        RunbookStep(text: "Add it to backups"),
        RunbookStep(text: "Save login to the Hush Vault"),
        RunbookStep(text: "Add it to Hush → Services with its ports"),
    ])
}

struct RunbookView: View {
    @Bindable var runbook: Runbook
    var editingInitially = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var editing = false
    @State private var newStep = ""
    @State private var copiedID: UUID?
    @State private var finished = false
    @State private var pickingIcon = false

    var body: some View {
        let steps = runbook.steps
        let done = steps.filter(\.done).count
        List {
            if !editing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(done) of \(steps.count) done").font(.hush(.subheadline)).monospacedDigit()
                        Spacer()
                        if let due = runbook.nextDue {
                            Label(runbook.isDue ? "Due now" : due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .font(.hush(.caption)).foregroundStyle(runbook.isDue ? Color.orange : Color.secondary)
                        }
                    }
                    ProgressView(value: Double(done), total: Double(max(steps.count, 1)))
                }
                .plainRow(top: 12, bottom: 8)
            }
            Section {
                ForEach(steps) { step in
                    if editing {
                        StepEditRow(step: binding(step.id))
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            CheckButton(done: step.done) { toggle(step.id) }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(step.text).strikethrough(step.done).foregroundStyle(step.done ? .secondary : .primary)
                                if !step.command.isEmpty {
                                    HStack(alignment: .top) {
                                        Text(step.command)
                                            .font(.system(.footnote, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Button {
                                            UIPasteboard.general.string = step.command
                                            copiedID = step.id
                                        } label: { Image(systemName: copiedID == step.id ? "checkmark" : "doc.on.doc") }
                                            .buttonStyle(.borderless)
                                            .accessibilityLabel("Copy command")
                                    }
                                    .padding(8)
                                    .background(palette.field, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { runbook.steps.remove(atOffsets: $0) }
                .onMove { runbook.steps.move(fromOffsets: $0, toOffset: $1) }
                .hushRow()
                if editing {
                    HStack {
                        Image(systemName: "plus").foregroundStyle(.tint)
                        TextField("Add a step", text: $newStep).onSubmit(addStep)
                    }
                    .hushRow()
                }
            } header: {
                ListHeader(title: "Steps")
            }
            if editing {
                Section {
                    HStack {
                        Button { pickingIcon = true } label: { SymbolTile(name: runbook.symbol, size: 36) }.buttonStyle(.plain)
                        TextField("Title", text: $runbook.title).font(.hush(.headline))
                    }
                    Picker("Kind", selection: $runbook.kindRaw) { ForEach(Runbook.kinds, id: \.0) { Text($0.1).tag($0.0) } }
                    Picker("Repeat", selection: $runbook.repeatRaw) { ForEach(Runbook.repeats, id: \.0) { Text($0.1).tag($0.0) } }
                    if runbook.repeatRaw != "none" {
                        DatePicker("Next due", selection: Binding(get: { runbook.nextDue ?? .now }, set: { runbook.nextDue = $0 }), displayedComponents: .date)
                        Toggle("Remind Me", isOn: $runbook.remind)
                    }
                    TextField("Notes", text: $runbook.notes, axis: .vertical).lineLimit(2...8)
                } header: { ListHeader(title: "Details") }
                .hushRow()
            }
            if !editing && !runbook.runs.isEmpty {
                Section {
                    ForEach(runbook.runs.reversed()) { run in
                        LabeledContent(run.date.formatted(date: .abbreviated, time: .shortened), value: "\(run.completed)/\(run.total) steps")
                    }
                    .hushRow()
                } header: { ListHeader(title: "History") }
            }
        }
        .hushList()
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .navigationTitle(runbook.title.isEmpty ? "Runbook" : runbook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button(editing ? "Done" : "Edit") { editing.toggle(); syncReminder() } }
            if !editing && !steps.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button { finishRun() } label: { Label("Finish Run", systemImage: "checkmark.seal") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .alert("Run logged", isPresented: $finished) { Button("OK") {} } message: {
            Text(runbook.nextDue.map { "Next run is due \($0.formatted(date: .abbreviated, time: .omitted))." } ?? "Steps have been reset for next time.")
        }
        .sheet(isPresented: $pickingIcon) { SymbolPicker(selection: $runbook.symbol, allowNone: false) }
        .onAppear { if editingInitially && runbook.steps.isEmpty { editing = true } }
        .onDisappear {
            syncReminder()
            if runbook.title.trimmed.isEmpty && runbook.steps.isEmpty { context.delete(runbook) }
        }
    }

    private func binding(_ id: UUID) -> Binding<RunbookStep> {
        Binding(get: { runbook.steps.first { $0.id == id } ?? RunbookStep(text: "") },
                set: { new in if let i = runbook.steps.firstIndex(where: { $0.id == id }) { runbook.steps[i] = new } })
    }

    private func toggle(_ id: UUID) {
        guard let i = runbook.steps.firstIndex(where: { $0.id == id }) else { return }
        runbook.steps[i].done.toggle()
    }

    private func addStep() {
        let t = newStep.trimmed
        guard !t.isEmpty else { return }
        runbook.steps.append(RunbookStep(text: t))
        newStep = ""
    }

    private func finishRun() {
        let steps = runbook.steps
        runbook.runs.append(RunbookRun(date: .now, completed: steps.filter(\.done).count, total: steps.count))
        runbook.steps = steps.map { var s = $0; s.done = false; return s }
        if let next = runbook.nextDate(after: .now) { runbook.nextDue = next }
        syncReminder()
        finished = true
    }

    private func syncReminder() {
        let id = "runbook.\(runbook.id.uuidString)"
        if runbook.remind, let due = runbook.nextDue, runbook.deletedAt == nil {
            let when = Calendar.current.startOfDay(for: due).addingTimeInterval(Double(Reminders.defaultMinutes * 60))
            Reminders.schedule(id: id, title: runbook.title.isEmpty ? "Runbook due" : runbook.title, body: "Homelab maintenance is due.", at: when)
        } else {
            Reminders.cancel(id)
        }
    }
}

private struct StepEditRow: View {
    @Binding var step: RunbookStep
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Step", text: $step.text, axis: .vertical)
            TextField("Command (optional)", text: $step.command, axis: .vertical)
                .font(.system(.footnote, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 2)
    }
}

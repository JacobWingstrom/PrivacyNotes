import SwiftUI
import SwiftData

/// Everything Hush found in email: waiting for review, and what it added on its own.
struct ReviewListView: View {
    @Query(filter: #Predicate<TaskItem> { $0.reviewRaw != "" && $0.deletedAt == nil }) private var tasks: [TaskItem]
    @Query(filter: #Predicate<CalendarEvent> { $0.reviewRaw != "" && $0.deletedAt == nil }) private var events: [CalendarEvent]
    @Query(filter: #Predicate<Contact> { $0.reviewRaw != "" && $0.deletedAt == nil }) private var contacts: [Contact]
    @State private var tab = 0
    @State private var openMessage: MailMessage?

    private var pendingCount: Int { tasks.filter(\.isPendingReview).count + events.filter(\.isPendingReview).count + contacts.filter(\.isPendingReview).count }

    var body: some View {
        let state = tab == 0 ? "pending" : "auto"
        let ev = events.filter { $0.reviewRaw == state }.sorted { $0.start < $1.start }
        let ts = tasks.filter { $0.reviewRaw == state }.sorted(by: TaskItem.order)
        let cs = contacts.filter { $0.reviewRaw == state }.sorted { $0.createdAt > $1.createdAt }
        List {
            Picker("Show", selection: $tab) {
                Text("To Review (\(pendingCount))").tag(0)
                Text("Auto-added").tag(1)
            }
            .pickerStyle(.segmented)
            .plainRow()

            if ev.isEmpty && ts.isEmpty && cs.isEmpty {
                EmptyMessage(text: tab == 0
                             ? "Nothing to review. Events, tasks and contacts Hush finds in your email show up here."
                             : "Items from trusted senders, calendar invites and bookings appear here after Hush adds them.")
            }
            if tab == 0 && (ev.count + ts.count + cs.count) > 1 {
                Button {
                    for i in ev { MailScanner.confirm(i) }
                    for i in ts { MailScanner.confirm(i) }
                    for i in cs { MailScanner.confirm(i) }
                } label: { Label("Confirm All", systemImage: "checkmark.circle") }
                .plainRow(top: 0, bottom: 4)
            }
            if !ev.isEmpty {
                Section { ForEach(ev) { e in row(e) { EventRow(event: e) } edit: { EventEditorView(event: e) } } } header: { ListHeader(title: "Events") }
            }
            if !ts.isEmpty {
                Section { ForEach(ts) { t in row(t) { TaskSummaryRow(task: t) } edit: { TaskEditorView(task: t) } } } header: { ListHeader(title: "Tasks") }
            }
            if !cs.isEmpty {
                Section { ForEach(cs) { c in row(c) { ContactSummaryRow(contact: c) } edit: { ContactEditorView(contact: c) } } } header: { ListHeader(title: "Contacts") }
            }
        }
        .hushList()
        .sheet(item: $openMessage) { m in
            NavigationStack {
                MessageReaderView(message: m) { openMessage = nil }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { openMessage = nil } } }
            }
        }
    }

    private func row<Item: Reviewable, RowLabel: View, Editor: View>(_ item: Item, @ViewBuilder label: () -> RowLabel, @ViewBuilder edit: @escaping () -> Editor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { edit() } label: { label() }
            HStack(spacing: 6) {
                Image(systemName: "envelope").font(.hush(.caption2))
                Text(item.originNote).font(.hush(.caption)).lineLimit(2)
            }
            .foregroundStyle(.secondary)
            if item.isPendingReview {
                HStack(spacing: 10) {
                    Button { withAnimation { MailScanner.confirm(item) } } label: { Label("Confirm", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { withAnimation { MailScanner.dismiss(item) } } label: { Label("Dismiss", systemImage: "xmark") }
                        .buttonStyle(.bordered)
                    Spacer()
                    Menu {
                        if let sender = MailScanner.senderEmail(item.originRef) {
                            Button { withAnimation { MailScanner.trustSender(of: item) } } label: {
                                Label("Always Trust \(sender)", systemImage: "checkmark.seal")
                            }
                        }
                        if let m = message(for: item) {
                            Button { openMessage = m } label: { Label("Show Email", systemImage: "envelope.open") }
                        }
                    } label: { Image(systemName: "ellipsis.circle").font(.hush(.title3)) }
                }
                .font(.hush(.subheadline))
            } else {
                HStack {
                    Button { withAnimation { item.reviewRaw = "" } } label: { Label("Looks Good", systemImage: "checkmark") }
                        .buttonStyle(.bordered)
                    Button(role: .destructive) { withAnimation { MailScanner.dismiss(item) } } label: { Label("Remove", systemImage: "trash") }
                        .buttonStyle(.bordered)
                    Spacer()
                    if let m = message(for: item) {
                        Button { openMessage = m } label: { Image(systemName: "envelope.open") }
                    }
                }
                .font(.hush(.subheadline))
            }
        }
        .padding(.vertical, 6)
        .hushRow()
    }

    private func message(for item: any Reviewable) -> MailMessage? {
        let parts = item.originRef.components(separatedBy: "|")
        guard parts.count >= 3, let uid = Int(parts[2]) else { return nil }
        let account = parts[0], folder = parts[1]
        let d = FetchDescriptor<MailMessage>(predicate: #Predicate { $0.accountID == account && $0.folder == folder && $0.uid == uid })
        return try? Storage.shared.mainContext.fetch(d).first
    }
}

struct TaskSummaryRow: View {
    let task: TaskItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Task" : task.title)
                if let due = DateText.due(task) { Text("Due \(due)").font(.hush(.caption)).foregroundStyle(.secondary) }
                if !task.list.isEmpty { Text(task.list).font(.hush(.caption)).foregroundStyle(.secondary) }
            }
        }
    }
}

struct ContactSummaryRow: View {
    let contact: Contact
    var body: some View {
        HStack(spacing: 10) {
            Avatar(text: contact.initials, emoji: contact.emoji, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                Text((contact.emails.first?.value ?? "") + (contact.phones.first.map { " · " + $0.value } ?? ""))
                    .font(.hush(.caption)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Items found in one email, shown in the reader.
struct FoundInEmail: View {
    @Query private var tasks: [TaskItem]
    @Query private var events: [CalendarEvent]
    @Query private var contacts: [Contact]
    @Environment(\.palette) private var palette

    init(reference: String) {
        _tasks = Query(filter: #Predicate<TaskItem> { $0.originRef.contains(reference) && $0.deletedAt == nil })
        _events = Query(filter: #Predicate<CalendarEvent> { $0.originRef.contains(reference) && $0.deletedAt == nil })
        _contacts = Query(filter: #Predicate<Contact> { $0.originRef.contains(reference) && $0.deletedAt == nil })
    }

    var body: some View {
        if !(tasks.isEmpty && events.isEmpty && contacts.isEmpty) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(.tint)
                    ForEach(events) { e in chip(e, symbol: "calendar", title: e.title, detail: e.start.formatted(date: .abbreviated, time: e.isAllDay ? .omitted : .shortened)) }
                    ForEach(tasks) { t in chip(t, symbol: "checkmark.circle", title: t.title, detail: DateText.due(t) ?? "Task") }
                    ForEach(contacts) { c in chip(c, symbol: "person.crop.circle", title: c.displayName, detail: "Contact") }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .background(palette.surface)
        }
    }

    private func chip(_ item: any Reviewable, symbol: String, title: String, detail: String) -> some View {
        Menu {
            if item.isPendingReview {
                Button { MailScanner.confirm(item) } label: { Label("Confirm", systemImage: "checkmark") }
            }
            Button(role: .destructive) { MailScanner.dismiss(item) } label: { Label(item.isPendingReview ? "Dismiss" : "Remove", systemImage: "xmark") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.hush(.caption).weight(.semibold)).lineLimit(1)
                    Text(item.isPendingReview ? "\(detail) · tap to confirm" : detail).font(.hush(.caption2)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: 240)
            .background(palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: item.isPendingReview ? [4, 3] : [])).foregroundStyle(.tint))
        }
        .foregroundStyle(.primary)
    }
}

/// "3 items from email to review" at the top of Calendar, Tasks and Contacts.
struct ReviewBanner: View {
    @Query(filter: #Predicate<TaskItem> { $0.reviewRaw == "pending" && $0.deletedAt == nil }) private var tasks: [TaskItem]
    @Query(filter: #Predicate<CalendarEvent> { $0.reviewRaw == "pending" && $0.deletedAt == nil }) private var events: [CalendarEvent]
    @Query(filter: #Predicate<Contact> { $0.reviewRaw == "pending" && $0.deletedAt == nil }) private var contacts: [Contact]
    @State private var showing = false
    @Environment(\.palette) private var palette

    var body: some View {
        let n = tasks.count + events.count + contacts.count
        if n > 0 {
            Button { showing = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.badge").foregroundStyle(.tint)
                    Text("\(n) item\(n == 1 ? "" : "s") from email to review").font(.hush(.subheadline))
                    Spacer()
                    Image(systemName: "chevron.right").font(.hush(.caption)).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.tint))
            }
            .buttonStyle(.plain)
            .plainRow(top: 8, bottom: 4)
            .sheet(isPresented: $showing) {
                NavigationStack {
                    ReviewListView()
                        .navigationTitle("To Review")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
                }
            }
        }
    }
}

/// Faded look and a small "From email" tag for items waiting for review.
struct ReviewStyle: ViewModifier {
    let pending: Bool
    let auto: Bool

    func body(content: Content) -> some View {
        if pending {
            VStack(alignment: .leading, spacing: 3) {
                content.opacity(0.55)
                Label("From email · needs review", systemImage: "envelope.badge")
                    .font(.hush(.caption2)).foregroundStyle(.tint).labelStyle(.titleAndIcon)
            }
        } else if auto {
            content.overlay(alignment: .topTrailing) {
                Image(systemName: "envelope").font(.hush(.caption2)).foregroundStyle(.secondary).accessibilityLabel("Added from email")
            }
        } else {
            content
        }
    }
}

extension View {
    func reviewStyle(_ item: some Reviewable) -> some View {
        modifier(ReviewStyle(pending: item.isPendingReview, auto: item.isAutoAdded))
    }
}

// MARK: - Settings

struct ScanSettingsView: View {
    @AppStorage(ScanPrefs.autoInvitesKey) private var autoInvites = true
    @AppStorage(ScanPrefs.autoReservationsKey) private var autoReservations = true
    @AppStorage(ScanPrefs.detectKey) private var detect = true
    @AppStorage(ScanPrefs.contactsKey) private var contacts = true
    @AppStorage(ScanPrefs.recipientsKey) private var recipients = true
    @AppStorage(ScanPrefs.lookbackKey) private var lookback = 14
    @State private var trusted = ScanPrefs.trustedSenders
    @State private var rules = ScanPrefs.rules
    @State private var newTrusted = ""
    @State private var editingRule: ScanRule?

    var body: some View {
        HushForm {
            Section {
                Toggle("Calendar Invites", isOn: $autoInvites)
                Toggle("Bookings, Deliveries & Bills", isOn: $autoReservations)
            } header: {
                Text("Add Without Asking")
            } footer: {
                Text("Invites (.ics) and booking data from airlines, hotels and shops are reliable, so they can go straight in. You'll still see them under Auto-added.")
            }
            Section {
                Toggle("Dates in Personal Email", isOn: $detect)
                Toggle("New People with a Signature", isOn: $contacts)
                Toggle("People You Email", isOn: $recipients)
                Stepper("Look at the last \(lookback) days", value: $lookback, in: 1...90)
            } header: {
                Text("Suggest for Review")
            } footer: {
                Text("“Lunch Friday at 12:30” becomes an event, “please send it by June 3” a task. Newsletters are skipped. Everything is read on this device only.")
            }
            Section {
                ForEach(trusted, id: \.self) { Text($0) }
                    .onDelete { trusted.remove(atOffsets: $0); ScanPrefs.trustedSenders = trusted }
                HStack {
                    TextField("name@example.com or @example.com", text: $newTrusted)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    Button("Add") {
                        let v = newTrusted.trimmed.lowercased()
                        guard !v.isEmpty, !trusted.contains(v) else { return }
                        trusted.append(v)
                        ScanPrefs.trustedSenders = trusted
                        newTrusted = ""
                    }
                    .disabled(newTrusted.trimmed.isEmpty)
                }
            } header: {
                Text("Trusted Senders")
            } footer: {
                Text("Anything found in mail from these senders is added without asking.")
            }
            Section {
                ForEach(rules) { r in
                    Button { editingRule = r } label: {
                        HStack {
                            Text(r.summary).foregroundStyle(r.enabled ? .primary : .secondary)
                            Spacer()
                            if r.autoConfirm { Image(systemName: "checkmark.seal").foregroundStyle(.tint) }
                        }
                    }
                }
                .onDelete { rules.remove(atOffsets: $0); ScanPrefs.rules = rules }
                Button { editingRule = ScanRule() } label: { Label("Add Rule", systemImage: "plus") }
            } header: {
                Text("Your Rules")
            } footer: {
                Text("For example: From contains “school” → make a task in the School list, due 3 days after the email arrives.")
            }
        }
        .navigationTitle("Finding Items in Email")
        .sheet(item: $editingRule) { rule in
            RuleEditor(rule: rule) { saved in
                if let i = rules.firstIndex(where: { $0.id == saved.id }) { rules[i] = saved } else { rules.append(saved) }
                ScanPrefs.rules = rules
            }
        }
    }
}

private struct RuleEditor: View {
    @State var rule: ScanRule
    let onSave: (ScanRule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HushForm {
                Section("When") {
                    Picker("Field", selection: $rule.field) {
                        Text("From").tag(ScanRule.Field.from)
                        Text("Subject").tag(ScanRule.Field.subject)
                        Text("Text").tag(ScanRule.Field.body)
                        Text("Anywhere").tag(ScanRule.Field.any)
                    }
                    TextField("contains…", text: $rule.contains).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Then") {
                    Picker("Action", selection: $rule.action) {
                        Text("Make a task").tag(ScanRule.Action.task)
                        Text("Make an event (if a date is found)").tag(ScanRule.Action.event)
                        Text("Suggest sender as contact").tag(ScanRule.Action.contact)
                        Text("Add found items without asking").tag(ScanRule.Action.trust)
                        Text("Ignore this email").tag(ScanRule.Action.ignore)
                    }
                    if rule.action == .task {
                        TextField("Task list (optional)", text: $rule.taskList)
                        Picker("If no date is found", selection: $rule.dueInDays) {
                            Text("No due date").tag(-1)
                            Text("Due the same day").tag(0)
                            Text("Due the next day").tag(1)
                            Text("Due in 3 days").tag(3)
                            Text("Due in a week").tag(7)
                        }
                    }
                    if [.task, .event, .contact].contains(rule.action) {
                        Toggle("Add Without Asking", isOn: $rule.autoConfirm)
                    }
                    Toggle("Enabled", isOn: $rule.enabled)
                }
            }
            .navigationTitle("Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(rule); dismiss() }.disabled(rule.contains.trimmed.isEmpty)
                }
            }
        }
    }
}

import SwiftUI
import SwiftData

enum Mailbox: Hashable {
    case allInboxes
    case folder(account: String, path: String)
    case review

    var accountID: String? {
        if case .folder(let a, _) = self { return a }
        return nil
    }
    var path: String? {
        if case .folder(_, let p) = self { return p }
        return nil
    }
}

/// The Mail section: folders, message list and reading pane.
struct MailView: View {
    let title: String
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(Router.self) private var router
    @State private var engine = MailEngine.shared
    @State private var mailbox: Mailbox = .allInboxes
    @State private var selected: MailMessage?
    @State private var showFolders = false
    @State private var addingAccount = false
    @AppStorage("mailLastMailbox") private var lastMailbox = ""

    var body: some View {
        Group {
            if !engine.hasAccounts {
                MailOnboarding { addingAccount = true }
            } else if sizeClass == .regular {
                ThreePane {
                    MailboxSidebar(mailbox: $mailbox) { addingAccount = true }
                } list: {
                    listPane
                } reader: {
                    if let selected, selected.modelContext != nil {
                        MessageReaderView(message: selected) { self.selected = nil }
                            .id(selected.id)
                    } else {
                        PaneEmpty(symbol: "envelope.open", text: "No message selected")
                    }
                }
            } else {
                listPane
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showFolders = true } label: { Image(systemName: "folder") }
                                .accessibilityLabel("Folders")
                        }
                    }
                    .sheet(isPresented: $showFolders) {
                        NavigationStack {
                            MailboxSidebar(mailbox: Binding(get: { mailbox }, set: { mailbox = $0; showFolders = false })) {
                                showFolders = false
                                addingAccount = true
                            }
                            .navigationTitle("Mailboxes")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFolders = false } } }
                        }
                        .presentationDetents([.medium, .large])
                    }
            }
        }
        .navigationTitle(title)
        .toolbar {
            if engine.hasAccounts {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.composeRequest = ComposeRequest(mode: .new, accountID: mailbox.accountID) } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New email")
                }
            }
        }
        .onCreate(.mail) {
            if engine.hasAccounts { router.composeRequest = ComposeRequest(mode: .new, accountID: mailbox.accountID) } else { addingAccount = true }
        }
        .sheet(isPresented: $addingAccount) { AccountSetupView() }
        .onAppear {
            restoreMailbox()
            Task { await engine.syncAll(includeDAV: false) }
        }
        .onChange(of: mailbox) { _, new in
            selected = nil
            lastMailbox = Self.encode(new)
            if case .folder(let a, let p) = new {
                engine.watchedFolders[a] = p
                if let account = engine.account(a) { Task { await engine.refresh(account: account, folder: p) } }
            }
        }
    }

    @ViewBuilder private var listPane: some View {
        if mailbox == .review {
            ReviewListView()
        } else {
            MessageListView(mailbox: mailbox, selected: $selected, compact: sizeClass != .regular)
                .id(mailbox)
        }
    }

    private func restoreMailbox() {
        if let m = Self.decode(lastMailbox) {
            if case .folder(let a, _) = m, engine.account(a) == nil { return }
            mailbox = m
        } else if engine.accounts.count == 1, let a = engine.accounts.first {
            mailbox = .folder(account: a.id, path: engine.folder(a.id, role: "inbox")?.path ?? "INBOX")
        }
    }

    static func encode(_ m: Mailbox) -> String {
        switch m {
        case .allInboxes: "all"
        case .review: "review"
        case .folder(let a, let p): "f\u{1}\(a)\u{1}\(p)"
        }
    }

    static func decode(_ s: String) -> Mailbox? {
        if s == "all" { return .allInboxes }
        if s == "review" { return .review }
        let parts = s.components(separatedBy: "\u{1}")
        guard parts.count == 3, parts[0] == "f" else { return nil }
        return .folder(account: parts[1], path: parts[2])
    }
}

private struct MailOnboarding: View {
    let add: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                Text("Bring your email into Hush").font(.hush(.title2).bold())
                Text("Read and send mail from mailbox.org or any IMAP account. Hush can spot events, tasks and contacts in your email and add them for you to confirm, and keep your mailbox.org calendars, contacts and tasks in sync.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(action: add) {
                    Label("Connect mailbox.org", systemImage: "plus")
                        .font(.hush(.headline))
                        .frame(maxWidth: 320)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your iPhone connects directly to your mail provider. No other server is involved.", systemImage: "arrow.left.arrow.right")
                    Label("Your password stays in the iPhone Keychain.", systemImage: "key")
                    Label("Downloaded mail is encrypted on this device.", systemImage: "lock.shield")
                    Label("Images and trackers are blocked until you allow them.", systemImage: "eye.slash")
                }
                .font(.hush(.footnote))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .hushBackground()
    }
}

// MARK: - Folders

struct MailboxSidebar: View {
    @Binding var mailbox: Mailbox
    var addAccount: () -> Void
    @State private var engine = MailEngine.shared
    @Query private var pendingTasks: [TaskItem]
    @Query private var pendingEvents: [CalendarEvent]
    @Query private var pendingContacts: [Contact]

    init(mailbox: Binding<Mailbox>, addAccount: @escaping () -> Void) {
        _mailbox = mailbox
        self.addAccount = addAccount
        _pendingTasks = Query(filter: #Predicate<TaskItem> { $0.reviewRaw == "pending" && $0.deletedAt == nil })
        _pendingEvents = Query(filter: #Predicate<CalendarEvent> { $0.reviewRaw == "pending" && $0.deletedAt == nil })
        _pendingContacts = Query(filter: #Predicate<Contact> { $0.reviewRaw == "pending" && $0.deletedAt == nil })
    }

    var body: some View {
        let _ = engine.revision
        List {
            Section {
                if engine.accounts.count > 1 {
                    row(.allInboxes, symbol: "tray.2", title: "All Inboxes", count: engine.totalUnreadInbox)
                }
                row(.review, symbol: "checklist", title: "To Review", count: pendingTasks.count + pendingEvents.count + pendingContacts.count)
            }
            ForEach(engine.accounts) { account in
                Section {
                    ForEach(engine.folders(account.id).filter(\.isSelectable)) { f in
                        row(.folder(account: account.id, path: f.path), symbol: f.symbol, title: f.name,
                            count: f.role == "trash" || f.role == "junk" ? 0 : f.unread,
                            indent: f.role == nil ? f.depth : 0)
                    }
                    if engine.folders(account.id).isEmpty {
                        row(.folder(account: account.id, path: "INBOX"), symbol: "tray", title: "Inbox", count: 0)
                    }
                } header: {
                    HStack {
                        ListHeader(title: account.label)
                        Spacer()
                        if engine.syncing.contains(account.id) { ProgressView().controlSize(.mini) }
                    }
                } footer: {
                    if let err = engine.errors[account.id] {
                        Label(err, systemImage: "exclamationmark.triangle").font(.hush(.caption)).foregroundStyle(.orange)
                    }
                }
            }
            Section {
                Button(action: addAccount) { Label("Add Account", systemImage: "plus") }
                    .font(.hush(.subheadline))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .refreshable { await engine.syncAll() }
    }

    private func row(_ m: Mailbox, symbol: String, title: String, count: Int, indent: Int = 0) -> some View {
        Button { mailbox = m } label: {
            PaneRow(symbol: symbol, title: title, count: count, indent: indent, selected: mailbox == m)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Message list

struct MessageListView: View {
    let mailbox: Mailbox
    @Binding var selected: MailMessage?
    let compact: Bool
    @Query private var messages: [MailMessage]
    @State private var engine = MailEngine.shared
    @State private var search = ""
    @State private var filter = ListFilter.all
    @State private var loadingOlder = false
    @Environment(\.palette) private var palette

    enum ListFilter: String, CaseIterable { case all = "All", unread = "Unread", flagged = "Flagged", attachments = "Attachments" }

    init(mailbox: Mailbox, selected: Binding<MailMessage?>, compact: Bool) {
        self.mailbox = mailbox
        _selected = selected
        self.compact = compact
        switch mailbox {
        case .folder(let a, let p):
            _messages = Query(filter: #Predicate<MailMessage> { $0.accountID == a && $0.folder == p }, sort: \MailMessage.date, order: .reverse)
        default:
            _messages = Query(filter: #Predicate<MailMessage> { $0.folder == "INBOX" }, sort: \MailMessage.date, order: .reverse)
        }
    }

    private var shown: [MailMessage] {
        messages.filter { m in
            guard !m.isDeleted else { return false }
            switch filter {
            case .all: break
            case .unread: if m.isSeen { return false }
            case .flagged: if !m.isFlagged { return false }
            case .attachments: if !m.hasAttachments { return false }
            }
            guard !search.isEmpty else { return true }
            let s = m.summary
            return s.subject.localizedCaseInsensitiveContains(search) || s.fromName.localizedCaseInsensitiveContains(search)
                || s.fromEmail.localizedCaseInsensitiveContains(search) || s.snippet.localizedCaseInsensitiveContains(search)
                || s.to.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private var title: String {
        switch mailbox {
        case .allInboxes: return "All Inboxes"
        case .review: return "To Review"
        case .folder(let a, let p): return engine.folders(a).first { $0.path == p }?.name ?? (p.uppercased() == "INBOX" ? "Inbox" : ModifiedUTF7.decode(p))
        }
    }

    var body: some View {
        let _ = engine.revision
        let list = shown
        List {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.hush(.title3).bold())
                    if let a = mailbox.accountID, let account = engine.account(a) {
                        Text(account.label).font(.hush(.caption)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if engine.syncing.contains(mailbox.accountID ?? "") || (mailbox == .allInboxes && !engine.syncing.isEmpty) {
                    ProgressView().controlSize(.small)
                }
                FilterButton(active: filter != .all) {
                    Picker("Show", selection: $filter) {
                        ForEach(ListFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                .scaleEffect(0.8)
            }
            .plainRow(top: 6, bottom: 2)

            if let a = mailbox.accountID, let err = engine.errors[a] {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.hush(.footnote)).foregroundStyle(.orange).plainRow(top: 0, bottom: 6)
            }

            ForEach(list) { m in
                rowView(m)
            }
            if list.isEmpty {
                EmptyMessage(text: search.isEmpty ? (messages.isEmpty ? "No messages downloaded yet. Pull to refresh." : "Nothing here.") : "No matches.")
            } else if case .folder = mailbox, search.isEmpty, filter == .all {
                Button {
                    loadOlder()
                } label: {
                    HStack {
                        Spacer()
                        if loadingOlder { ProgressView() } else { Text("Load Older Messages").font(.hush(.subheadline)) }
                        Spacer()
                    }
                }
                .plainRow()
            }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search mail…") }
        .refreshable {
            if case .folder(let a, let p) = mailbox, let account = engine.account(a) {
                await engine.refresh(account: account, folder: p)
            } else {
                await engine.syncAll(includeDAV: false)
            }
        }
    }

    @ViewBuilder private func rowView(_ m: MailMessage) -> some View {
        Group {
            if compact {
                NavigationLink { MessageReaderView(message: m, onClose: nil) } label: {
                    MessageRow(message: m, showAccount: mailbox == .allInboxes && engine.accounts.count > 1)
                }
            } else {
                Button { selected = m } label: {
                    MessageRow(message: m, showAccount: mailbox == .allInboxes && engine.accounts.count > 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(selected?.id == m.id ? Color.accentColor.opacity(0.18) : Color.clear)
            }
        }
        .swipeActions(edge: .leading) {
            Button { engine.setSeen([m], !m.isSeen) } label: {
                Label(m.isSeen ? "Unread" : "Read", systemImage: m.isSeen ? "envelope.badge" : "envelope.open")
            }
            .tint(.blue)
            Button { engine.setFlagged([m], !m.isFlagged) } label: {
                Label(m.isFlagged ? "Unflag" : "Flag", systemImage: m.isFlagged ? "flag.slash" : "flag")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                if selected?.id == m.id { selected = nil }
                Task { await engine.delete([m]) }
            } label: { Label("Delete", systemImage: "trash") }
            if engine.folder(m.accountID, role: "archive") != nil && m.folder != engine.folder(m.accountID, role: "archive")?.path {
                Button {
                    if selected?.id == m.id { selected = nil }
                    Task { await engine.archive([m]) }
                } label: { Label("Archive", systemImage: "archivebox") }
                .tint(.indigo)
            }
        }
    }

    private func loadOlder() {
        guard case .folder(let a, let p) = mailbox, let account = engine.account(a), !loadingOlder else { return }
        loadingOlder = true
        Task {
            await engine.loadOlder(account: account, folder: p)
            loadingOlder = false
        }
    }
}

struct MessageRow: View {
    let message: MailMessage
    var showAccount = false

    var body: some View {
        let s = message.summary
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.isSeen ? Color.clear : Color.accentColor)
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.senderLabel)
                        .font(.hush(.body).weight(message.isSeen ? .regular : .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if message.isFlagged { Image(systemName: "flag.fill").font(.hush(.caption)).foregroundStyle(.orange) }
                    if message.hasAttachments { Image(systemName: "paperclip").font(.hush(.caption)).foregroundStyle(.secondary) }
                    Text(Self.when(message.date)).font(.hush(.caption)).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 4) {
                    if message.isAnswered { Image(systemName: "arrowshape.turn.up.left.fill").font(.hush(.caption2)).foregroundStyle(.secondary) }
                    Text(s.subject.isEmpty ? "(No subject)" : s.subject)
                        .font(.hush(.subheadline).weight(message.isSeen ? .regular : .medium))
                        .lineLimit(1)
                }
                if !s.snippet.isEmpty {
                    Text(s.snippet).font(.hush(.footnote)).foregroundStyle(.secondary).lineLimit(2)
                }
                if showAccount, let a = MailEngine.shared.account(message.accountID) {
                    Text(a.label).font(.hush(.caption2)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: d, to: .now).day, days < 7 { return d.formatted(.dateTime.weekday(.abbreviated)) }
        if cal.isDate(d, equalTo: .now, toGranularity: .year) { return d.formatted(.dateTime.day().month(.abbreviated)) }
        return d.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
    }
}

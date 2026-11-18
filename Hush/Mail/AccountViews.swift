import SwiftUI

/// Adds a mailbox.org (or other IMAP) account.
struct AccountSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var engine = MailEngine.shared
    @State private var provider = "mailboxorg"
    @State private var account = MailAccount.mailboxOrg(email: "")
    @State private var password = ""
    @State private var testing = false
    @State private var error: String?
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            HushForm {
                Section {
                    Picker("Provider", selection: $provider) {
                        Text("mailbox.org").tag("mailboxorg")
                        Text("Other (IMAP)").tag("custom")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: provider) { _, p in
                        let keep = account
                        account = p == "mailboxorg" ? .mailboxOrg(email: keep.email) : .custom(email: keep.email)
                        account.displayName = keep.displayName
                        showAdvanced = p == "custom"
                    }
                }
                Section {
                    TextField("Your name", text: $account.displayName).textContentType(.name)
                    TextField("Email address", text: $account.email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: account.email) { old, new in
                            if account.username.isEmpty || account.username == old { account.username = new }
                            if provider == "custom" {
                                let fresh = MailAccount.custom(email: new)
                                let oldDomain = MailAccount.custom(email: old)
                                if account.imapHost == oldDomain.imapHost { account.imapHost = fresh.imapHost }
                                if account.smtpHost == oldDomain.smtpHost { account.smtpHost = fresh.smtpHost }
                                if account.name == oldDomain.name { account.name = fresh.name }
                            }
                        }
                    SecureField("Password", text: $password).textContentType(.password)
                } footer: {
                    Text(provider == "mailboxorg"
                         ? "If you use two-factor sign-in, create an app password in mailbox.org under Settings → Security and use it here."
                         : "Use an app password if your provider offers one.")
                }

                Section {
                    Toggle("Calendars, Contacts & Tasks", isOn: $account.davEnabled)
                    Toggle("Find Events & Tasks in Email", isOn: $account.scanEnabled)
                    Toggle("New Mail Notifications", isOn: $account.notify)
                    Picker("Put Items in Space", selection: $account.spaceID) {
                        ForEach(settings.spaces) { Text($0.name).tag($0.id == Spaces.defaultID ? "" : $0.id) }
                    }
                } footer: {
                    Text("Calendars, contacts and tasks sync both ways with \(provider == "mailboxorg" ? "mailbox.org" : "your provider") (CalDAV/CardDAV). Items Hush finds in email show up faded until you confirm them.")
                }

                Section {
                    DisclosureGroup("Server Settings", isExpanded: $showAdvanced) {
                        ServerFields(account: $account)
                    }
                }

                Section {
                    Label("Hush will connect directly from this device to \(account.imapHost), \(account.smtpHost)\(account.davEnabled ? " and \(URL(string: account.caldavURL)?.host() ?? "your calendar server")" : ""). Nothing passes through any other server.", systemImage: "lock.shield")
                        .font(.hush(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if testing { ProgressView() } else {
                        Button("Connect") { Task { await connect() } }
                            .disabled(account.email.trimmed.isEmpty || password.isEmpty || account.imapHost.isEmpty)
                    }
                }
            }
            .alert("Couldn't connect", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
    }

    private func connect() async {
        account.email = account.email.trimmed
        account.username = account.username.trimmed.isEmpty ? account.email : account.username.trimmed
        if account.name.trimmed.isEmpty { account.name = account.email }
        account.connectedAt = Date()
        account.davUploadFrom = Date()
        testing = true
        defer { testing = false }
        do {
            try await MailEngine.test(account, password: password)
            engine.save(account, password: password)
            _ = await Reminders.requestPermission()
            let saved = account
            Task {
                await engine.sync(saved, includeDAV: false)
                if saved.davEnabled { await DAVSync.shared.sync(saved, force: true) }
                await MailScanner.scanPending(context: Storage.shared.mainContext)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ServerFields: View {
    @Binding var account: MailAccount

    var body: some View {
        Group {
            TextField("Account name", text: $account.name)
            TextField("User name", text: $account.username).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Incoming (IMAP)").font(.hush(.caption).weight(.semibold)).foregroundStyle(.secondary)
            TextField("IMAP server", text: $account.imapHost).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            HStack {
                TextField("Port", value: $account.imapPort, format: .number.grouping(.never)).keyboardType(.numberPad).frame(width: 70)
                Picker("Security", selection: $account.imapSecurity) { ForEach(MailSecurity.allCases) { Text($0.label).tag($0) } }
                    .onChange(of: account.imapSecurity) { _, s in account.imapPort = s == .tls ? 993 : 143 }
            }
            Text("Outgoing (SMTP)").font(.hush(.caption).weight(.semibold)).foregroundStyle(.secondary)
            TextField("SMTP server", text: $account.smtpHost).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            HStack {
                TextField("Port", value: $account.smtpPort, format: .number.grouping(.never)).keyboardType(.numberPad).frame(width: 70)
                Picker("Security", selection: $account.smtpSecurity) { ForEach(MailSecurity.allCases) { Text($0.label).tag($0) } }
                    .onChange(of: account.smtpSecurity) { _, s in account.smtpPort = s == .tls ? 465 : 587 }
            }
            Text("Calendars & Contacts").font(.hush(.caption).weight(.semibold)).foregroundStyle(.secondary)
            TextField("CalDAV URL", text: $account.caldavURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("CardDAV URL", text: $account.carddavURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        }
    }
}

// MARK: - Settings

/// Settings → Mail, Calendars & Feeds.
struct OnlineSettingsView: View {
    @State private var engine = MailEngine.shared
    @State private var adding = false
    @AppStorage(OnlineCenter.backgroundKey) private var background = true

    var body: some View {
        HushForm {
            Section {
                ForEach(engine.accounts) { a in
                    NavigationLink { AccountDetailView(accountID: a.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.label)
                            Text(a.email).font(.hush(.caption)).foregroundStyle(.secondary)
                            if let e = engine.errors[a.id] {
                                Text(e).font(.hush(.caption)).foregroundStyle(.orange).lineLimit(2)
                            }
                        }
                    }
                }
                Button { adding = true } label: { Label("Add Account", systemImage: "plus") }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Mail, calendars, contacts and tasks from mailbox.org or any IMAP / CalDAV / CardDAV provider.")
            }
            Section {
                NavigationLink { ScanSettingsView() } label: { Label("Finding Items in Email", systemImage: "sparkle.magnifyingglass") }
                NavigationLink { FeedSettingsView() } label: { Label("Feeds & Reddit", systemImage: "dot.radiowaves.up.forward") }
            }
            Section {
                Toggle("Check in the Background", isOn: $background)
                    .onChange(of: background) { _, on in if on { OnlineCenter.scheduleBackgroundRefresh() } else { OnlineCenter.cancelBackgroundRefresh() } }
            } footer: {
                Text("iOS decides when background checks run, so new-mail alerts can arrive minutes or hours late. Hush always checks when you open it.")
            }
            Section {
                Label("Hush only connects to the mail, calendar and feed servers you add here, directly from this device.", systemImage: "arrow.left.arrow.right")
                Label("Passwords stay in the Keychain. Downloaded mail is encrypted on this device and isn't included in backups or Hush Sync.", systemImage: "lock.shield")
            }
            .font(.hush(.footnote))
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Mail, Calendars & Feeds")
        .sheet(isPresented: $adding) { AccountSetupView() }
    }
}

struct AccountDetailView: View {
    let accountID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var engine = MailEngine.shared
    @State private var dav = DAVSync.shared
    @State private var account = MailAccount()
    @State private var newPassword = ""
    @State private var loaded = false
    @State private var confirmRemove = false
    @State private var confirmUpload = false

    var body: some View {
        HushForm {
            Section {
                TextField("Account name", text: $account.name)
                TextField("Your name", text: $account.displayName)
                LabeledContent("Email", value: account.email)
                SecureField("New password (optional)", text: $newPassword)
            }
            Section("Signature") {
                TextField("Signature", text: $account.signature, axis: .vertical).lineLimit(2...6)
            }
            Section {
                Toggle("New Mail Notifications", isOn: $account.notify)
                Toggle("Find Events & Tasks in Email", isOn: $account.scanEnabled)
                Picker("Put Items in Space", selection: $account.spaceID) {
                    ForEach(settings.spaces) { Text($0.name).tag($0.id == Spaces.defaultID ? "" : $0.id) }
                }
                Stepper("Keep \(account.keepRecent) recent emails per folder", value: $account.keepRecent, in: 50...2000, step: 50)
            }
            Section {
                Toggle("Sync Calendars, Contacts & Tasks", isOn: $account.davEnabled)
                if account.davEnabled {
                    let state = dav.state(accountID)
                    ForEach(state.collections) { c in
                        Toggle(isOn: Binding(get: { !account.davDisabledCollections.contains(c.href) },
                                             set: { on in
                                                 if on { account.davDisabledCollections.removeAll { $0 == c.href } }
                                                 else { account.davDisabledCollections.append(c.href) }
                                             })) {
                            Label(c.name, systemImage: c.kind.symbol)
                        }
                    }
                    if !state.collections.filter({ $0.kind == .calendar }).isEmpty {
                        Picker("New Events Go To", selection: $account.davDefaultCalendar) {
                            Text("Automatic").tag("")
                            ForEach(state.collections.filter { $0.kind == .calendar }) { Text($0.name).tag($0.href) }
                        }
                    }
                    if !state.collections.filter({ $0.kind == .tasks }).isEmpty {
                        Picker("New Tasks Go To", selection: $account.davDefaultTaskList) {
                            Text("Automatic").tag("")
                            ForEach(state.collections.filter { $0.kind == .tasks }) { Text($0.name).tag($0.href) }
                        }
                    }
                    if !state.collections.filter({ $0.kind == .addressBook }).isEmpty {
                        Picker("New Contacts Go To", selection: $account.davDefaultAddressBook) {
                            Text("Automatic").tag("")
                            ForEach(state.collections.filter { $0.kind == .addressBook }) { Text($0.name).tag($0.href) }
                        }
                    }
                    Button {
                        Task { await DAVSync.shared.sync(account, force: true) }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if dav.syncing.contains(accountID) { ProgressView() }
                        }
                    }
                    Button("Upload Items Made Before Connecting…") { confirmUpload = true }
                }
            } header: {
                Text("Calendars, Contacts & Tasks")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let last = dav.state(accountID).lastSync { Text("Last synced \(last.formatted(.relative(presentation: .named))).") }
                    if let err = dav.errors[accountID] { Text(err).foregroundStyle(.orange) }
                    Text("Events, tasks and contacts you add in Hush (in this account's space) are saved to \(account.label) too. Edits and deletions go both ways.")
                }
            }
            Section {
                DisclosureGroup("Server Settings") { ServerFields(account: $account) }
            }
            Section {
                Button("Remove Account", role: .destructive) { confirmRemove = true }
            } footer: {
                Text("Removes the account, its password and downloaded mail from this device. Events, tasks and contacts already in Hush stay, and stop syncing.")
            }
        }
        .navigationTitle(account.label)
        .onAppear {
            guard !loaded, let a = engine.account(accountID) else { return }
            account = a
            loaded = true
        }
        .onDisappear {
            guard loaded, engine.account(accountID) != nil else { return }
            engine.save(account, password: newPassword.isEmpty ? nil : newPassword)
        }
        .confirmationDialog("Remove \(account.label)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Account", role: .destructive) {
                engine.remove(account)
                loaded = false
                dismiss()
            }
        }
        .confirmationDialog("Upload existing items?", isPresented: $confirmUpload, titleVisibility: .visible) {
            Button("Upload Everything in This Space") {
                account.davUploadFrom = .distantPast
                engine.save(account, password: nil)
                let a = account
                Task { await DAVSync.shared.sync(a, force: true) }
            }
        } message: {
            Text("Events, tasks and contacts you made in Hush before connecting will be saved to \(account.label).")
        }
    }
}

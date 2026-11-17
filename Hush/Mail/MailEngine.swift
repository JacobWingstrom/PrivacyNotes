import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Lets one task at a time use an account's IMAP connection.
@MainActor
final class AsyncLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }
}

/// Downloads, caches and changes email. Talks only to the servers you added.
@MainActor
@Observable
final class MailEngine {
    static let shared = MailEngine()

    private(set) var accounts: [MailAccount] = MailAccounts.load()
    private(set) var states: [String: MailFolderState] = [:]
    private(set) var syncing: Set<String> = []
    var errors: [String: String] = [:]
    /// Bumped whenever cached mail changes, so views refresh.
    private(set) var revision = 0
    /// Folders the user is looking at, synced along with the Inbox.
    var watchedFolders: [String: String] = [:]

    @ObservationIgnored private var sessions: [String: IMAPClient] = [:]
    @ObservationIgnored private var locks: [String: AsyncLock] = [:]
    @ObservationIgnored private var lastFullSync: [String: Date] = [:]

    private init() {
        for a in accounts { states[a.id] = MailFolderState.load(a.id) }
    }

    var context: ModelContext { Storage.shared.mainContext }
    var hasAccounts: Bool { !accounts.isEmpty }
    func account(_ id: String) -> MailAccount? { accounts.first { $0.id == id } }
    func folders(_ accountID: String) -> [IMAPFolder] {
        (states[accountID]?.folders ?? []).sorted { ($0.sortRank, $0.displayPath.lowercased()) < ($1.sortRank, $1.displayPath.lowercased()) }
    }
    func folder(_ accountID: String, role: String) -> IMAPFolder? { states[accountID]?.folder(role: role) }

    var totalUnreadInbox: Int {
        accounts.reduce(0) { $0 + (states[$1.id]?.folders.first { $0.role == "inbox" }?.unread ?? 0) }
    }

    // MARK: Accounts

    func save(_ account: MailAccount, password: String?) {
        if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i] = account } else { accounts.append(account) }
        if let password { MailAccounts.setPassword(password, for: account.id) }
        MailAccounts.save(accounts)
        if states[account.id] == nil { states[account.id] = MailFolderState.load(account.id) }
        sessions[account.id]?.close()
        sessions[account.id] = nil
    }

    func remove(_ account: MailAccount) {
        sessions[account.id]?.close()
        sessions[account.id] = nil
        accounts.removeAll { $0.id == account.id }
        MailAccounts.save(accounts)
        MailAccounts.deletePassword(for: account.id)
        MailFolderState.remove(account.id)
        states[account.id] = nil
        let id = account.id
        let msgs = (try? context.fetch(FetchDescriptor<MailMessage>(predicate: #Predicate { $0.accountID == id }))) ?? []
        for m in msgs { context.delete(m) }
        try? context.save()
        DAVStore.remove(accountID: id)
        bump()
    }

    /// Signs in to IMAP and SMTP without saving anything.
    static func test(_ account: MailAccount, password: String) async throws {
        let imap = IMAPClient(host: account.imapHost, port: account.imapPort)
        try await imap.connect(security: account.imapSecurity, username: account.username, password: password)
        await imap.logout()
        let smtp = SMTPClient(host: account.smtpHost, port: account.smtpPort)
        try await smtp.connect(security: account.smtpSecurity, username: account.username, password: password)
        await smtp.quit()
    }

    // MARK: Connections

    private func lock(_ id: String) -> AsyncLock {
        if let l = locks[id] { return l }
        let l = AsyncLock()
        locks[id] = l
        return l
    }

    private func connect(_ account: MailAccount) async throws -> IMAPClient {
        guard let password = MailAccounts.password(for: account.id) else { throw MailError.auth("No password is saved for \(account.label).") }
        let c = IMAPClient(host: account.imapHost, port: account.imapPort)
        try await c.connect(security: account.imapSecurity, username: account.username, password: password)
        return c
    }

    func withIMAP<T>(_ account: MailAccount, _ body: (IMAPClient) async throws -> T) async throws -> T {
        let l = lock(account.id)
        await l.acquire()
        defer { l.release() }
        if let c = sessions[account.id], Date().timeIntervalSince(c.lastUsed) > 90 {
            c.close()
            sessions[account.id] = nil
        }
        let client: IMAPClient
        if let c = sessions[account.id] { client = c } else {
            client = try await connect(account)
            sessions[account.id] = client
        }
        do {
            return try await body(client)
        } catch let e as MailError {
            switch e {
            case .closed, .timeout, .connection:
                client.close()
                sessions[account.id] = nil
                let fresh = try await connect(account)
                sessions[account.id] = fresh
                return try await body(fresh)
            default:
                throw e
            }
        }
    }

    func disconnectAll() {
        for (_, c) in sessions { c.close() }
        sessions.removeAll()
    }

    // MARK: Sync

    /// New mail notifications collected during a background refresh.
    @ObservationIgnored var collectedNew: [(account: MailAccount, message: MailMessage)] = []

    func syncAll(includeDAV: Bool = true) async {
        for a in accounts { await sync(a, includeDAV: includeDAV) }
        await MailScanner.scanPending(context: context)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func sync(_ account: MailAccount, includeDAV: Bool = true) async {
        guard !syncing.contains(account.id) else { return }
        syncing.insert(account.id)
        defer { syncing.remove(account.id) }
        do {
            try await withIMAP(account) { c in
                var st = states[account.id] ?? MailFolderState()
                // The folder list changes rarely; refresh it every 10 minutes.
                if st.folders.isEmpty || Date().timeIntervalSince(lastFullSync[account.id] ?? .distantPast) > 600 {
                    let listed = try await c.listFolders()
                    var merged: [IMAPFolder] = []
                    for f in listed {
                        var f = f
                        if let old = st.folders.first(where: { $0.path == f.path }) { f.unread = old.unread; f.total = old.total }
                        merged.append(f)
                    }
                    st.folders = merged
                    lastFullSync[account.id] = Date()
                    for i in st.folders.indices where st.folders[i].isSelectable {
                        if let s = try? await c.status(st.folders[i].path) {
                            st.folders[i].unread = s.unread
                            st.folders[i].total = s.total
                        }
                    }
                }
                states[account.id] = st
                var paths = ["INBOX"]
                if let inbox = st.folders.first(where: { $0.role == "inbox" }) { paths = [inbox.path] }
                if let watched = watchedFolders[account.id], !paths.contains(watched) { paths.append(watched) }
                for p in paths { try await syncFolder(c, account: account, path: p) }
            }
            errors[account.id] = nil
            states[account.id]?.lastSync = Date()
            states[account.id]?.lastError = nil
        } catch {
            errors[account.id] = error.localizedDescription
            states[account.id]?.lastError = error.localizedDescription
        }
        states[account.id]?.save(account.id)
        bump()
        if includeDAV && account.davEnabled { await DAVSync.shared.syncIfDue(account) }
    }

    /// Syncs one folder now (when you open it).
    func refresh(account: MailAccount, folder: String) async {
        do {
            try await withIMAP(account) { c in try await syncFolder(c, account: account, path: folder) }
            errors[account.id] = nil
        } catch {
            errors[account.id] = error.localizedDescription
        }
        states[account.id]?.save(account.id)
        bump()
        await MailScanner.scanPending(context: context)
    }

    private func localMessages(_ accountID: String, _ folder: String) -> [MailMessage] {
        let d = FetchDescriptor<MailMessage>(predicate: #Predicate { $0.accountID == accountID && $0.folder == folder })
        return (try? context.fetch(d)) ?? []
    }

    private func syncFolder(_ c: IMAPClient, account: MailAccount, path: String) async throws {
        let info = try await c.select(path)
        var st = states[account.id] ?? MailFolderState()
        var local = localMessages(account.id, path)

        if let known = st.uidValidity[path], known != info.uidValidity {
            for m in local { context.delete(m) }
            local = []
            st.highestUID[path] = 0
        }
        st.uidValidity[path] = info.uidValidity
        let firstSync = (st.highestUID[path] ?? 0) == 0 && local.isEmpty
        if info.exists == 0 {
            for m in local { context.delete(m) }
            st.highestUID[path] = 0
            states[account.id] = st
            try? context.save()
            return
        }

        // 1. Which messages are new?
        let highest = st.highestUID[path] ?? 0
        var newUIDs: [Int]
        if highest == 0 {
            let from = max(1, info.exists - account.keepRecent + 1)
            newUIDs = try await c.fetch(sequence: "\(from):\(info.exists)", items: "UID").map(\.uid)
            let have = Set(local.map(\.uid))
            newUIDs = newUIDs.filter { !have.contains($0) }
        } else {
            newUIDs = try await c.searchUIDs("UID \(highest + 1):*").filter { $0 > highest }
        }
        newUIDs.sort()
        if newUIDs.count > account.keepRecent { newUIDs = Array(newUIDs.suffix(account.keepRecent)) }

        // 2. Headers for new messages.
        var created: [MailMessage] = []
        for chunk in newUIDs.chunked(60) {
            let fetched = try await c.fetch(uids: IMAPClient.set(chunk), items: "UID FLAGS INTERNALDATE RFC822.SIZE BODY.PEEK[HEADER]")
            for f in fetched {
                let m = MailMessage(accountID: account.id, folder: path, uid: f.uid, uidValidity: info.uidValidity)
                m.flags = Set(f.flags)
                m.size = f.size
                let headers = MIME.parseHeaders(f.header ?? Data())
                m.date = headers.raw("Date").flatMap(MIME.parseDate) ?? f.internalDate ?? Date()
                m.messageID = headers.raw("Message-ID")?.trimmed ?? ""
                m.summary = Self.summary(headers: headers, parsed: nil)
                let ct = (headers.raw("Content-Type") ?? "").lowercased()
                m.hasAttachments = ct.contains("multipart/mixed")
                context.insert(m)
                created.append(m)
            }
        }
        if let maxNew = newUIDs.max() { st.highestUID[path] = max(highest, maxNew) }
        try? context.save()

        // 3. Full messages for small ones (needed for previews and for finding events and tasks).
        let small = created.filter { $0.size <= 1_500_000 }.sorted { $0.date > $1.date }
        for chunk in Array(small.prefix(400)).chunked(15) {
            let fetched = try await c.fetch(uids: IMAPClient.set(chunk.map(\.uid)), items: "UID BODY.PEEK[]")
            for f in fetched {
                guard let body = f.body, let m = chunk.first(where: { $0.uid == f.uid }) else { continue }
                Self.store(source: body, in: m)
            }
            try? context.save()
        }

        // 4. Flag changes and deletions for messages we already had.
        if !firstSync, let lo = local.map(\.uid).min() {
            let current = try await c.fetch(uids: "\(lo):*", items: "UID FLAGS")
            var byUID: [Int: [String]] = [:]
            for f in current { byUID[f.uid] = f.flags }
            for m in local {
                if let flags = byUID[m.uid] {
                    let set = Set(flags)
                    if set != m.flags { m.flags = set }
                } else {
                    context.delete(m)
                }
            }
        }

        // 5. Keep only the most recent messages.
        let keep = max(account.keepRecent, st.keepCount[path] ?? 0)
        let all = localMessages(account.id, path).sorted { $0.uid > $1.uid }
        if all.count > keep { for m in all.dropFirst(keep) { context.delete(m) } }

        if let i = st.folders.firstIndex(where: { $0.path == path }) {
            st.folders[i].total = info.exists
            st.folders[i].unread = localMessages(account.id, path).filter { !$0.isSeen }.count
            if let s = try? await c.status(path), s.total > 0 { st.folders[i].unread = s.unread }
        }
        states[account.id] = st
        try? context.save()

        if !firstSync, path == (st.folder(role: "inbox")?.path ?? "INBOX") {
            for m in created where !m.isSeen { collectedNew.append((account, m)) }
        }
    }

    /// Downloads the next 100 older messages of a folder.
    func loadOlder(account: MailAccount, folder path: String) async {
        let local = localMessages(account.id, path)
        guard let lowest = local.map(\.uid).min(), lowest > 1 else { return }
        do {
            try await withIMAP(account) { c in
                let info = try await c.select(path)
                let older = try await c.searchUIDs("UID 1:\(lowest - 1)").filter { $0 < lowest }.sorted().suffix(100)
                guard !older.isEmpty else { return }
                var created: [MailMessage] = []
                for chunk in Array(older).chunked(50) {
                    let fetched = try await c.fetch(uids: IMAPClient.set(chunk), items: "UID FLAGS INTERNALDATE RFC822.SIZE BODY.PEEK[HEADER]")
                    for f in fetched {
                        let m = MailMessage(accountID: account.id, folder: path, uid: f.uid, uidValidity: info.uidValidity)
                        m.flags = Set(f.flags)
                        m.size = f.size
                        let headers = MIME.parseHeaders(f.header ?? Data())
                        m.date = headers.raw("Date").flatMap(MIME.parseDate) ?? f.internalDate ?? Date()
                        m.messageID = headers.raw("Message-ID")?.trimmed ?? ""
                        m.summary = Self.summary(headers: headers, parsed: nil)
                        m.hasAttachments = (headers.raw("Content-Type") ?? "").lowercased().contains("multipart/mixed")
                        m.scannedAt = Date() // older mail isn't scanned for new items
                        context.insert(m)
                        created.append(m)
                    }
                }
                for chunk in created.filter({ $0.size <= 400_000 }).chunked(15) {
                    let fetched = try await c.fetch(uids: IMAPClient.set(chunk.map(\.uid)), items: "UID BODY.PEEK[]")
                    for f in fetched {
                        guard let body = f.body, let m = chunk.first(where: { $0.uid == f.uid }) else { continue }
                        Self.store(source: body, in: m)
                    }
                }
                var st = states[account.id] ?? MailFolderState()
                st.keepCount[path] = local.count + created.count
                states[account.id] = st
                try? context.save()
            }
        } catch {
            errors[account.id] = error.localizedDescription
        }
        states[account.id]?.save(account.id)
        bump()
    }

    static func store(source: Data, in m: MailMessage) {
        let parsed = MIME.parseMessage(source)
        m.source = source
        m.summary = summary(headers: parsed.headers, parsed: parsed)
        m.hasAttachments = parsed.attachments.contains { !$0.isInline }
        if let d = parsed.date { m.date = d }
    }

    static func summary(headers: MIMEHeaders, parsed: ParsedMessage?) -> MailSummary {
        var s = MailSummary()
        let from = headers.raw("From").flatMap { MIME.parseAddresses($0).first }
        s.fromName = from?.name ?? ""
        s.fromEmail = from?.email ?? ""
        s.to = (headers.raw("To").map(MIME.parseAddresses) ?? []).map(\.full)
        s.cc = (headers.raw("Cc").map(MIME.parseAddresses) ?? []).map(\.full)
        s.replyTo = headers.raw("Reply-To").flatMap { MIME.parseAddresses($0).first?.full } ?? ""
        s.subject = headers["Subject"]?.trimmed ?? ""
        s.inReplyTo = headers.raw("In-Reply-To")?.trimmed ?? ""
        s.references = (headers.raw("References") ?? "").split(separator: " ").map(String.init)
        s.isBulk = parsed?.isBulk ?? (headers.raw("List-Unsubscribe") != nil || headers.raw("List-Id") != nil)
        s.snippet = parsed?.snippet ?? ""
        return s
    }

    // MARK: Reading

    /// The full message, downloading it if only the headers are cached.
    func source(of m: MailMessage) async throws -> Data {
        if let s = m.source { return s }
        guard let account = account(m.accountID) else { throw MailError.server("This account was removed.") }
        let uid = m.uid, folder = m.folder
        let data: Data = try await withIMAP(account) { c in
            if c.selected != folder { try await c.select(folder) }
            guard let body = try await c.fetch(uids: "\(uid)", items: "UID BODY.PEEK[]").first?.body else {
                throw MailError.server("The message is no longer on the server.")
            }
            return body
        }
        Self.store(source: data, in: m)
        try? context.save()
        bump()
        return data
    }

    // MARK: Changing messages

    func setSeen(_ messages: [MailMessage], _ seen: Bool) {
        changeFlags(messages, flag: "\\Seen", on: seen)
    }

    func setFlagged(_ messages: [MailMessage], _ flagged: Bool) {
        changeFlags(messages, flag: "\\Flagged", on: flagged)
    }

    private func changeFlags(_ messages: [MailMessage], flag: String, on: Bool) {
        let targets = messages.filter { $0.flags.contains(flag) != on }
        guard !targets.isEmpty else { return }
        for m in targets {
            var f = m.flags
            if on { f.insert(flag) } else { f.remove(flag) }
            m.flags = f
        }
        adjustUnread(targets, flag: flag, on: on)
        try? context.save()
        bump()
        for (key, group) in Dictionary(grouping: targets, by: { "\($0.accountID)\u{1}\($0.folder)" }) {
            let parts = key.components(separatedBy: "\u{1}")
            guard let account = account(parts[0]) else { continue }
            let folder = parts[1]
            let uids = group.map(\.uid)
            Task {
                do {
                    try await withIMAP(account) { c in
                        if c.selected != folder { try await c.select(folder) }
                        try await c.store(uids: uids, add: on, flags: [flag])
                    }
                } catch {
                    errors[account.id] = error.localizedDescription
                }
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func adjustUnread(_ messages: [MailMessage], flag: String, on: Bool) {
        guard flag == "\\Seen" else { return }
        for m in messages {
            guard var st = states[m.accountID], let i = st.folders.firstIndex(where: { $0.path == m.folder }) else { continue }
            st.folders[i].unread = max(0, st.folders[i].unread + (on ? -1 : 1))
            states[m.accountID] = st
        }
    }

    func move(_ messages: [MailMessage], to target: String) async {
        for (key, group) in Dictionary(grouping: messages, by: { "\($0.accountID)\u{1}\($0.folder)" }) {
            let parts = key.components(separatedBy: "\u{1}")
            guard let account = account(parts[0]), parts[1] != target else { continue }
            let folder = parts[1]
            let uids = group.map(\.uid)
            adjustUnread(group.filter { !$0.isSeen }, flag: "\\Seen", on: true)
            for m in group { context.delete(m) }
            try? context.save()
            bump()
            do {
                try await withIMAP(account) { c in
                    if c.selected != folder { try await c.select(folder) }
                    try await c.move(uids: uids, to: target)
                }
            } catch {
                errors[account.id] = error.localizedDescription
                await refresh(account: account, folder: folder)
            }
        }
    }

    func delete(_ messages: [MailMessage]) async {
        for (accountID, group) in Dictionary(grouping: messages, by: \.accountID) {
            guard let account = account(accountID) else { continue }
            if let trash = folder(accountID, role: "trash") {
                let inTrash = group.filter { $0.folder == trash.path }
                let elsewhere = group.filter { $0.folder != trash.path }
                if !elsewhere.isEmpty { await move(elsewhere, to: trash.path) }
                if !inTrash.isEmpty { await expunge(inTrash, account: account) }
            } else {
                await expunge(group, account: account)
            }
        }
    }

    private func expunge(_ messages: [MailMessage], account: MailAccount) async {
        for (folder, group) in Dictionary(grouping: messages, by: \.folder) {
            let uids = group.map(\.uid)
            for m in group { context.delete(m) }
            try? context.save()
            bump()
            do {
                try await withIMAP(account) { c in
                    if c.selected != folder { try await c.select(folder) }
                    try await c.store(uids: uids, add: true, flags: ["\\Deleted"])
                    try await c.expunge(uids: uids)
                }
            } catch {
                errors[account.id] = error.localizedDescription
            }
        }
    }

    func archive(_ messages: [MailMessage]) async {
        for (accountID, group) in Dictionary(grouping: messages, by: \.accountID) {
            guard let target = folder(accountID, role: "archive") ?? folder(accountID, role: "all") else {
                errors[accountID] = "This account has no Archive folder."
                continue
            }
            await move(group, to: target.path)
        }
    }

    // MARK: Sending

    func send(_ message: OutgoingMessage, account: MailAccount, replyingTo original: MailMessage? = nil) async throws {
        guard let password = MailAccounts.password(for: account.id) else { throw MailError.auth("No password is saved.") }
        let messageID = OutgoingMessage.newMessageID(for: account.email)
        let data = message.render(messageID: messageID)
        let smtp = SMTPClient(host: account.smtpHost, port: account.smtpPort)
        try await smtp.connect(security: account.smtpSecurity, username: account.username, password: password)
        try await smtp.send(from: account.email, to: message.recipients.map(\.email), data: data)
        await smtp.quit()

        // Keep a copy in Sent, and mark the original as answered.
        if let sent = folder(account.id, role: "sent") {
            try? await withIMAP(account) { c in try await c.append(folder: sent.path, message: data, flags: ["\\Seen"]) }
        }
        if let original {
            var f = original.flags
            f.insert("\\Answered")
            original.flags = f
            try? context.save()
            let folder = original.folder, uid = original.uid
            try? await withIMAP(account) { c in
                if c.selected != folder { try await c.select(folder) }
                try await c.store(uids: [uid], add: true, flags: ["\\Answered"])
            }
        }
        // People you write to become contact suggestions.
        MailScanner.noteRecipients(message.recipients, account: account, context: context)
        bump()
    }

    // MARK: New-mail notifications

    func postNotifications() async {
        let items = collectedNew
        collectedNew = []
        guard !items.isEmpty else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let hide = Reminders.hideText
        let notifiable = items.filter { $0.account.notify }
        if notifiable.count > 3 {
            let content = UNMutableNotificationContent()
            content.title = "Hush"
            content.body = "\(notifiable.count) new emails"
            content.sound = .default
            content.threadIdentifier = "mail"
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "mail.batch.\(UUID().uuidString)", content: content, trigger: nil))
            return
        }
        for (account, m) in notifiable {
            let content = UNMutableNotificationContent()
            if hide {
                content.title = "Hush"
                content.body = "New email"
            } else {
                content.title = m.senderLabel
                content.subtitle = m.summary.subject
                content.body = m.summary.snippet
            }
            content.sound = .default
            content.threadIdentifier = "mail.\(account.id)"
            content.userInfo = ["mail": m.reference]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "mail.\(m.id.uuidString)", content: content, trigger: nil))
        }
    }

    func bump() { revision &+= 1 }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

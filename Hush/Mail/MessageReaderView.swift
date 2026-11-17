import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook

/// Senders whose remote images you've chosen to always load.
enum RemoteContentPrefs {
    private static let key = "mailAlwaysLoadImages"
    static func allowed(_ email: String) -> Bool {
        let list = UserDefaults.standard.stringArray(forKey: key) ?? []
        return list.contains(email.lowercased())
    }
    static func allow(_ email: String) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !list.contains(email.lowercased()) { list.append(email.lowercased()) }
        UserDefaults.standard.set(list, forKey: key)
    }
}

struct MessageReaderView: View {
    let message: MailMessage
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @State private var engine = MailEngine.shared
    @State private var parsed: ParsedMessage?
    @State private var loadError: String?
    @State private var allowRemote = false
    @State private var link: URL?
    @State private var showDetails = false
    @State private var previewURL: URL?
    @State private var moving = false
    @State private var confirmDelete = false
    @State private var importMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(palette.border).frame(height: 1)
            if let parsed {
                banners(parsed)
                FoundInEmail(reference: message.reference)
                if !parsed.attachments.filter({ !$0.isInline }).isEmpty { attachmentStrip(parsed) }
                bodyView(parsed)
            } else if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                    Text(loadError).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: message.id) { await load() }
        .confirmLinks($link)
        .quickLookPreview($previewURL)
        .sheet(isPresented: $moving) {
            MoveToFolderSheet(message: message) { target in
                moving = false
                close()
                Task { await engine.move([message], to: target) }
            }
        }
        .alert("Delete this message?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                close()
                Task { await engine.delete([message]) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Added", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK") {}
        } message: { Text(importMessage ?? "") }
    }

    // MARK: Parts

    private var header: some View {
        let s = message.summary
        return VStack(alignment: .leading, spacing: 8) {
            Text(s.subject.isEmpty ? "(No subject)" : s.subject)
                .font(.hush(.title3).bold())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                Avatar(text: String(message.senderLabel.prefix(1)).uppercased(), emoji: "", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.senderLabel).font(.hush(.subheadline).weight(.semibold))
                    if !s.fromEmail.isEmpty && s.fromName != "" {
                        Text(s.fromEmail).font(.hush(.caption)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Button { withAnimation { showDetails.toggle() } } label: {
                        Text(recipientsLine(s)).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(showDetails ? nil : 1)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(message.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.hush(.caption)).foregroundStyle(.secondary)
            }
            actionBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func recipientsLine(_ s: MailSummary) -> String {
        if showDetails {
            var parts = ["To: " + s.to.joined(separator: ", ")]
            if !s.cc.isEmpty { parts.append("Cc: " + s.cc.joined(separator: ", ")) }
            if !s.replyTo.isEmpty { parts.append("Reply-To: " + s.replyTo) }
            return parts.joined(separator: "\n")
        }
        let first = s.to.first.map { MIME.parseAddresses($0).first?.display ?? $0 } ?? "—"
        let others = s.to.count + s.cc.count - 1
        return "To: " + first + (others > 0 ? " and \(others) more" : "")
    }

    private var actionBar: some View {
        HStack(spacing: 22) {
            Menu {
                Button { reply(all: false) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                Button { reply(all: true) } label: { Label("Reply All", systemImage: "arrowshape.turn.up.left.2") }
                Button { router.composeRequest = ComposeRequest(mode: .forward(message), accountID: message.accountID) } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            } primaryAction: {
                reply(all: false)
            }
            .accessibilityLabel("Reply. Hold for Reply All and Forward")
            Button { engine.setFlagged([message], !message.isFlagged) } label: {
                Image(systemName: message.isFlagged ? "flag.fill" : "flag")
            }
            .accessibilityLabel(message.isFlagged ? "Unflag" : "Flag")
            if engine.folder(message.accountID, role: "archive") != nil && engine.folder(message.accountID, role: "archive")?.path != message.folder {
                Button {
                    close()
                    Task { await engine.archive([message]) }
                } label: { Image(systemName: "archivebox") }
                .accessibilityLabel("Archive")
            }
            Button { moving = true } label: { Image(systemName: "folder") }
                .accessibilityLabel("Move to folder")
            Button { confirmDelete = true } label: { Image(systemName: "trash") }
                .accessibilityLabel("Delete")
            Spacer()
            Menu {
                Button { engine.setSeen([message], false); close() } label: { Label("Mark as Unread", systemImage: "envelope.badge") }
                if let p = parsed {
                    Button { Task { await MailScanner.rescan(message, parsed: p) } } label: { Label("Find Events & Tasks Again", systemImage: "sparkle.magnifyingglass") }
                    Button { addSenderAsContact(p) } label: { Label("Add Sender to Contacts", systemImage: "person.crop.circle.badge.plus") }
                    Button { saveAsNote(p) } label: { Label("Save as Note", systemImage: "square.and.pencil") }
                    Button { makeTask(p) } label: { Label("Make a Task", systemImage: "checkmark.circle") }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("More")
        }
        .font(.hush(.title3))
        .foregroundStyle(.tint)
        .padding(.top, 4)
    }

    @ViewBuilder private func banners(_ p: ParsedMessage) -> some View {
        let html = p.htmlBody ?? ""
        let remote = SafeHTMLView.remoteContentCount(html)
        VStack(spacing: 6) {
            if remote > 0 && !allowRemote {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash").foregroundStyle(.secondary)
                    Text("\(remote) remote image\(remote == 1 ? "" : "s") blocked").font(.hush(.footnote))
                    Spacer()
                    Menu("Load") {
                        Button("Load Once") { allowRemote = true }
                        Button("Always for \(message.summary.fromEmail)") {
                            RemoteContentPrefs.allow(message.summary.fromEmail)
                            allowRemote = true
                        }
                    }
                    .font(.hush(.footnote).weight(.semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(palette.surface)
            }
            if p.isPGPEncrypted {
                Label("This message is PGP-encrypted. Hush can't decrypt PGP yet; open it in mailbox.org webmail or another PGP app.", systemImage: "lock.doc")
                    .font(.hush(.footnote))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface)
            } else if p.isPGPSigned {
                Label("Signed with PGP (signature not checked)", systemImage: "signature")
                    .font(.hush(.caption)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func attachmentStrip(_ p: ParsedMessage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(p.attachments.filter { !$0.isInline }) { a in
                    Menu {
                        Button { previewURL = TempFiles.write(a.data, name: a.filename) } label: { Label("Open", systemImage: "eye") }
                        Button { saveToFiles(a) } label: { Label("Save to Hush Files", systemImage: "folder.badge.plus") }
                        if a.filename.lowercased().hasSuffix(".ics") || a.mimeType == "text/calendar" {
                            Button { importMessage = MailScanner.importCalendar(String(decoding: a.data, as: UTF8.self), from: message) } label: {
                                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                            }
                        }
                        if a.filename.lowercased().hasSuffix(".vcf") || a.mimeType.contains("vcard") {
                            Button { importMessage = MailScanner.importVCards(String(decoding: a.data, as: UTF8.self), from: message) } label: {
                                Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                        if let url = TempFiles.write(a.data, name: a.filename) {
                            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: Self.symbol(for: a))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(a.filename).font(.hush(.caption)).lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(a.data.count), countStyle: .file))
                                    .font(.hush(.caption2)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: 220)
                        .background(palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(palette.border))
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func bodyView(_ p: ParsedMessage) -> some View {
        var inline: [String: (Data, String)] = [:]
        for a in p.attachments { if let cid = a.contentID { inline[cid] = (a.data, a.mimeType) } }
        let isHTML = !(p.htmlBody ?? "").trimmed.isEmpty
        let html = isHTML ? p.htmlBody! : SafeHTMLView.plainTextHTML(p.textBody ?? "")
        return SafeHTMLView(html: html, allowRemote: allowRemote, inlineParts: inline, themed: !isHTML,
                            textHex: (palette.text ?? (palette.isDark ? .white : .black)).hexString,
                            backgroundHex: palette.background.hexString, accentHex: settings.accentHex) { url in
            link = url
        }
        .background(isHTML ? Color.white : palette.background)
    }

    static func symbol(for a: MailAttachment) -> String {
        let t = a.mimeType
        if t.hasPrefix("image/") { return "photo" }
        if t == "application/pdf" { return "doc.richtext" }
        if t.contains("calendar") || a.filename.hasSuffix(".ics") { return "calendar" }
        if t.contains("vcard") { return "person.crop.rectangle" }
        if t.contains("zip") { return "doc.zipper" }
        return "doc"
    }

    // MARK: Actions

    private func load() async {
        loadError = nil
        do {
            let data = try await engine.source(of: message)
            let p = MIME.parseMessage(data)
            parsed = p
            allowRemote = RemoteContentPrefs.allowed(message.summary.fromEmail)
            if !message.isSeen { engine.setSeen([message], true) }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func reply(all: Bool) {
        router.composeRequest = ComposeRequest(mode: .reply(message, all: all), accountID: message.accountID)
    }

    private func saveToFiles(_ a: MailAttachment) {
        let ctx = Storage.shared.mainContext
        let type = UTTypeLookup.identifier(for: a.filename, mime: a.mimeType)
        ctx.insert(StoredFile(name: a.filename, typeIdentifier: type, data: a.data))
        try? ctx.save()
        importMessage = "Saved \(a.filename) to Files."
    }

    private func addSenderAsContact(_ p: ParsedMessage) {
        guard let from = p.from else { return }
        importMessage = MailScanner.addContact(from, signature: p.plainText, from: message, confirmed: true)
    }

    private func saveAsNote(_ p: ParsedMessage) {
        let ctx = Storage.shared.mainContext
        let n = Note()
        n.title = p.subject.isEmpty ? "Email" : p.subject
        n.body = "From: \(p.from?.full ?? "")\nDate: \(message.date.formatted())\n\n" + p.plainText
        ctx.insert(n)
        try? ctx.save()
        importMessage = "Saved as a note."
    }

    private func makeTask(_ p: ParsedMessage) {
        let ctx = Storage.shared.mainContext
        let t = TaskItem(title: p.subject.isEmpty ? "Follow up on email" : p.subject)
        t.notes = "From \(message.senderLabel)"
        t.originRaw = "email"
        t.originRef = message.reference
        t.originNote = "\(message.senderLabel) · \(p.subject)"
        ctx.insert(t)
        try? ctx.save()
        importMessage = "Added a task."
    }
}

/// Picks a folder to move a message to.
struct MoveToFolderSheet: View {
    let message: MailMessage
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(MailEngine.shared.folders(message.accountID).filter { $0.isSelectable && $0.path != message.folder }) { f in
                Button { onPick(f.path) } label: {
                    PaneRow(symbol: f.symbol, title: f.displayPath, indent: 0)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Move to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

enum UTTypeLookup {
    static func identifier(for filename: String, mime: String) -> String {
        let ext = (filename as NSString).pathExtension
        if !ext.isEmpty, let t = UTType(filenameExtension: ext) { return t.identifier }
        if let t = UTType(mimeType: mime) { return t.identifier }
        return UTType.data.identifier
    }
}


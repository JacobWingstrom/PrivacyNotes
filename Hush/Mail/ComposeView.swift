import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ComposeRequest: Identifiable {
    enum Mode {
        case new
        case to([MailAddress], subject: String, body: String)
        case reply(MailMessage, all: Bool)
        case forward(MailMessage)
    }
    let id = UUID()
    var mode: Mode
    var accountID: String?

    init(mode: Mode, accountID: String?) {
        self.mode = mode
        self.accountID = accountID
    }

    /// From a mailto: link.
    init(mailto url: URL) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let to = MIME.parseAddresses(comps?.path.removingPercentEncoding ?? "")
        let q = comps?.queryItems ?? []
        let subject = q.first { $0.name.lowercased() == "subject" }?.value ?? ""
        let body = q.first { $0.name.lowercased() == "body" }?.value ?? ""
        mode = .to(to, subject: subject, body: body)
        accountID = nil
    }
}

struct ComposeView: View {
    let request: ComposeRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var engine = MailEngine.shared
    @State private var accountID = ""
    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var showCc = false
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var inReplyTo = ""
    @State private var references: [String] = []
    @State private var attachments: [(name: String, mimeType: String, data: Data)] = []
    @State private var sending = false
    @State private var error: String?
    @State private var importing = false
    @State private var confirmDiscard = false
    @State private var prepared = false
    @FocusState private var focus: Field?
    @Query private var contacts: [Contact]

    enum Field { case to, cc, bcc, subject, body }

    private var account: MailAccount? { engine.account(accountID) ?? engine.accounts.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if engine.accounts.count > 1 {
                        fieldRow("From") {
                            Picker("From", selection: $accountID) {
                                ForEach(engine.accounts) { Text("\($0.displayName.isEmpty ? "" : $0.displayName + " ")<\($0.email)>").tag($0.id) }
                            }
                            .labelsHidden()
                            Spacer()
                        }
                    }
                    fieldRow("To") {
                        TextField("", text: $to, axis: .vertical)
                            .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: .to)
                        Button { withAnimation { showCc.toggle() } } label: { Text("Cc/Bcc").font(.hush(.caption)) }
                    }
                    suggestions(for: .to)
                    if showCc {
                        fieldRow("Cc") {
                            TextField("", text: $cc, axis: .vertical)
                                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focus, equals: .cc)
                        }
                        suggestions(for: .cc)
                        fieldRow("Bcc") {
                            TextField("", text: $bcc, axis: .vertical)
                                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focus, equals: .bcc)
                        }
                        suggestions(for: .bcc)
                    }
                    fieldRow("Subject") {
                        TextField("", text: $subject).focused($focus, equals: .subject)
                    }
                    if !attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(attachments.indices, id: \.self) { i in
                                    HStack(spacing: 6) {
                                        Image(systemName: "paperclip")
                                        Text(attachments[i].name).lineLimit(1).font(.hush(.caption))
                                        Button { attachments.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                            .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(palette.field, in: Capsule())
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                    TextField("", text: $bodyText, axis: .vertical)
                        .focused($focus, equals: .body)
                        .lineLimit(12...)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if bodyText.trimmed.isEmpty && to.trimmed.isEmpty { dismiss() } else { confirmDiscard = true }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button { Task { await send() } } label: { Image(systemName: "paperplane.fill") }
                            .disabled(parse(to).isEmpty && parse(cc).isEmpty && parse(bcc).isEmpty)
                            .accessibilityLabel("Send")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { importing = true } label: { Label("Attach", systemImage: "paperclip") }
                }
            }
            .confirmationDialog("Discard this email?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
            .alert("Couldn't send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    attachments.append((url.lastPathComponent, mime, data))
                }
            }
        }
        .interactiveDismissDisabled(!bodyText.trimmed.isEmpty)
        .onAppear { prepare() }
    }

    private var navTitle: String {
        switch request.mode {
        case .reply: "Reply"
        case .forward: "Forward"
        default: "New Email"
        }
    }

    private func fieldRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label + ":").foregroundStyle(.secondary).frame(minWidth: 56, alignment: .leading)
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    /// Matching contacts for the address being typed.
    @ViewBuilder private func suggestions(for field: Field) -> some View {
        if focus == field {
            let text = field == .to ? to : (field == .cc ? cc : bcc)
            let token = text.components(separatedBy: CharacterSet(charactersIn: ",;")).last?.trimmed ?? ""
            if token.count >= 2 {
                let matches = contactMatches(token)
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(matches, id: \.email) { addr in
                            Button { insert(addr, into: field) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(addr.name.isEmpty ? addr.email : addr.name)
                                    if !addr.name.isEmpty { Text(addr.email).font(.hush(.caption)).foregroundStyle(.secondary) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(palette.surface)
                }
            }
        }
    }

    private func contactMatches(_ token: String) -> [MailAddress] {
        var out: [MailAddress] = []
        for c in contacts where c.deletedAt == nil {
            for e in c.emails where !e.value.isEmpty {
                if c.displayName.localizedCaseInsensitiveContains(token) || e.value.localizedCaseInsensitiveContains(token) {
                    out.append(MailAddress(name: c.displayName == "No Name" ? "" : c.displayName, email: e.value))
                }
            }
            if out.count >= 5 { break }
        }
        return out
    }

    private func insert(_ addr: MailAddress, into field: Field) {
        func replaceLast(_ s: String) -> String {
            var parts = s.components(separatedBy: ",").map { $0.trimmed }
            if !parts.isEmpty { parts.removeLast() }
            parts.append(addr.full)
            return parts.filter { !$0.isEmpty }.joined(separator: ", ") + ", "
        }
        switch field {
        case .to: to = replaceLast(to)
        case .cc: cc = replaceLast(cc)
        case .bcc: bcc = replaceLast(bcc)
        default: break
        }
    }

    private func parse(_ s: String) -> [MailAddress] { MIME.parseAddresses(s).filter { $0.email.contains("@") } }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        accountID = request.accountID ?? engine.accounts.first?.id ?? ""
        let signature = account.map { $0.signature.trimmed.isEmpty ? "" : "\n\n-- \n" + $0.signature } ?? ""
        switch request.mode {
        case .new:
            bodyText = signature
            focus = .to
        case .to(let addrs, let subj, let body):
            to = addrs.map(\.full).joined(separator: ", ")
            subject = subj
            bodyText = body + signature
            focus = addrs.isEmpty ? .to : .body
        case .reply(let m, let all):
            accountID = m.accountID
            let s = m.summary
            let me = account?.email.lowercased() ?? ""
            let replyTarget = s.replyTo.isEmpty ? MailAddress(name: s.fromName, email: s.fromEmail).full : s.replyTo
            var toList = [replyTarget]
            if all {
                toList += s.to.filter { !$0.lowercased().contains(me) }
                cc = s.cc.filter { !$0.lowercased().contains(me) }.joined(separator: ", ")
                showCc = !cc.isEmpty
            }
            to = toList.joined(separator: ", ")
            subject = s.subject.lowercased().hasPrefix("re:") ? s.subject : "Re: " + s.subject
            inReplyTo = m.messageID
            references = (s.references + [m.messageID]).filter { !$0.isEmpty }
            let original = m.source.map { MIME.parseMessage($0).plainText } ?? s.snippet
            let quoted = original.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
            bodyText = signature + "\n\nOn \(m.date.formatted(date: .abbreviated, time: .shortened)), \(m.senderLabel) wrote:\n" + quoted
            focus = .body
        case .forward(let m):
            accountID = m.accountID
            let s = m.summary
            subject = s.subject.lowercased().hasPrefix("fwd:") ? s.subject : "Fwd: " + s.subject
            if let src = m.source {
                let p = MIME.parseMessage(src)
                bodyText = signature + "\n\n---------- Forwarded message ----------\nFrom: \(p.from?.full ?? "")\nDate: \(m.date.formatted())\nSubject: \(p.subject)\nTo: \(p.to.map(\.full).joined(separator: ", "))\n\n" + p.plainText
                attachments = p.attachments.filter { !$0.isInline }.map { ($0.filename, $0.mimeType, $0.data) }
            } else {
                bodyText = signature + "\n\n---------- Forwarded message ----------\n" + s.snippet
            }
            focus = .to
        }
    }

    private func send() async {
        guard let account else { error = "Add a mail account first."; return }
        var msg = OutgoingMessage(from: account.fromAddress)
        msg.to = parse(to)
        msg.cc = parse(cc)
        msg.bcc = parse(bcc)
        msg.subject = subject
        msg.body = bodyText
        msg.inReplyTo = inReplyTo
        msg.references = references
        msg.attachments = attachments
        sending = true
        defer { sending = false }
        var original: MailMessage?
        if case .reply(let m, _) = request.mode { original = m }
        do {
            try await engine.send(msg, account: account, replyingTo: original)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

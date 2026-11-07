import SwiftUI

/// Settings > Sync. Off until you connect a server; then shows status and options.
struct SyncSettingsView: View {
    @State private var engine = SyncEngine.shared
    @State private var configured = SyncSettings.isConfigured

    var body: some View {
        Group {
            if configured {
                SyncStatusForm(onDisconnect: { configured = false })
            } else {
                SyncConnectForm(onConnected: { configured = true })
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: engine.lastSync) { configured = SyncSettings.isConfigured }
    }
}

// MARK: - Not connected

private struct SyncConnectForm: View {
    var onConnected: () -> Void
    @State private var url = SyncSettings.serverURL
    @State private var token = ""
    @State private var checking = false
    @State private var vault: SyncClient.Vault?
    @State private var serverVersion = ""
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        HushForm {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Sync with your own server", systemImage: "server.rack").font(.hush(.headline))
                    Text("Run the small Hush server on your homelab and your notes, tasks and everything else sync to it. Everything is encrypted on this iPhone with a passphrase only you know, so the server can't read it.")
                        .font(.hush(.subheadline)).foregroundStyle(.secondary)
                    Text("Without a server, Hush works exactly as before: everything stays on this iPhone.")
                        .font(.hush(.subheadline)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                NavigationLink { SyncServerGuide() } label: {
                    Label("Set up the server", systemImage: "shippingbox")
                }
            }

            Section {
                TextField("Server address", text: $url, prompt: Text(verbatim: "https://hush.your-tailnet.ts.net"))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                HStack {
                    SecureField("Pairing token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { token = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? token } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Paste token")
                }
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Text(vault == nil ? "Connect" : "Check Again")
                        if checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(url.isEmpty || token.isEmpty || checking)
            } header: {
                Text("Server")
            } footer: {
                Text("Find the token with: docker compose logs hush")
            }

            if let vault {
                if vault.initialized {
                    Section {
                        SecureField("Sync passphrase", text: $passphrase)
                        Button {
                            Task { await run { try await SyncEngine.shared.join(url: url, token: token, passphrase: passphrase) } }
                        } label: { busyLabel("Join and Sync") }
                        .disabled(passphrase.isEmpty || working)
                    } header: {
                        Text("Connected to Hush server \(serverVersion)")
                    } footer: {
                        Text("This server already has a passphrase. Enter it to sync. Anything on this iPhone is merged with what's on the server.")
                    }
                } else {
                    Section {
                        SecureField("New sync passphrase", text: $passphrase)
                        SecureField("Type it again", text: $confirm)
                        Button {
                            Task { await run { try await SyncEngine.shared.create(url: url, token: token, passphrase: passphrase) } }
                        } label: { busyLabel("Create Passphrase and Sync") }
                        .disabled(passphrase.count < 8 || passphrase != confirm || working)
                    } header: {
                        Text("Connected to Hush server \(serverVersion)")
                    } footer: {
                        Text("Choose a long passphrase (at least 8 characters; a few random words works well). It encrypts everything before it leaves this iPhone. Write it down: if you forget it, the server copy can't be opened. Your iPhone copy is never affected.")
                    }
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.hush(.subheadline))
                }
            }
        }
        .onAppear {
            if token.isEmpty { token = SyncSettings.token ?? "" }
        }
    }

    private func busyLabel(_ title: String) -> some View {
        HStack {
            Text(title)
            if working { Spacer(); ProgressView() }
        }
    }

    private func check() async {
        checking = true
        error = nil
        defer { checking = false }
        do {
            let (h, v) = try await SyncEngine.shared.test(url: url, token: token)
            serverVersion = h.version
            vault = v
        } catch {
            vault = nil
            self.error = error.localizedDescription
        }
    }

    private func run(_ action: () async throws -> Void) async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await action()
            onConnected()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Connected

private struct SyncStatusForm: View {
    var onDisconnect: () -> Void
    @State private var engine = SyncEngine.shared
    @State private var stats: SyncClient.Stats?
    @State private var interval = SyncSettings.intervalMinutes
    @State private var includeVault = SyncSettings.includeVault
    @State private var confirmDisconnect = false
    @State private var confirmErase = false
    @State private var eraseError: String?

    var body: some View {
        HushForm {
            Section {
                HStack(spacing: 14) {
                    statusIcon.font(.hush(.title2)).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(engine.phase == .syncing ? "Syncing" : engine.phase == .failed ? "Sync problem" : "Synced")
                            .font(.hush(.headline))
                        Text(detail).font(.hush(.subheadline)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Button {
                    Task { await engine.sync(); await loadStats() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(engine.phase == .syncing)
            }

            Section("Server") {
                LabeledContent("Address", value: SyncSettings.normalizedURL(SyncSettings.serverURL)?.host() ?? SyncSettings.serverURL)
                if let stats {
                    LabeledContent("Items", value: stats.records.formatted())
                    LabeledContent("Attachments", value: stats.blobs == 0 ? "None" : "\(stats.blobs) · " + ByteCountFormatter.string(fromByteCount: stats.blobBytes, countStyle: .file))
                    LabeledContent("Server version", value: stats.version)
                }
            }

            Section {
                Picker("Sync While Open", selection: $interval) {
                    Text("Every minute").tag(1)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Only on open and close").tag(0)
                }
                .onChange(of: interval) { _, v in SyncSettings.intervalMinutes = v; engine.appBecameActive() }
                Toggle("Include Vault", isOn: $includeVault)
                    .onChange(of: includeVault) { _, v in
                        SyncSettings.includeVault = v
                        if v { engine.resetPullPosition() }
                        Task { await engine.sync() }
                    }
            } header: {
                Text("Options")
            } footer: {
                Text("Hush also syncs whenever you open or leave it. Vault items are encrypted twice: once by the Vault and again for sync.")
            }

            Section {
                Button("Disconnect This iPhone") { confirmDisconnect = true }
                Button("Erase Everything on the Server", role: .destructive) { confirmErase = true }
                if let eraseError { Text(eraseError).foregroundStyle(.red).font(.hush(.footnote)) }
            } footer: {
                Text("Disconnecting stops syncing and keeps everything on this iPhone. Erasing deletes the server copy and its passphrase; this iPhone's copy is untouched.")
            }
        }
        .task { await loadStats() }
        .refreshable { await engine.sync(); await loadStats() }
        .confirmationDialog("Stop syncing this iPhone?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect") { engine.disconnect(); onDisconnect() }
        } message: {
            Text("Everything stays on this iPhone. You can connect again later with the same passphrase.")
        }
        .confirmationDialog("Erase the server copy?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase Server Data", role: .destructive) {
                Task {
                    do { try await engine.eraseServer(); onDisconnect() } catch { eraseError = error.localizedDescription }
                }
            }
        } message: {
            Text("This deletes all synced items and attachments from your server. This iPhone keeps its copy.")
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch engine.phase {
        case .syncing: ProgressView()
        case .failed: Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
        default: Image(systemName: "checkmark.icloud").foregroundStyle(.green)
        }
    }

    private var detail: String {
        if engine.phase == .syncing || engine.phase == .failed { return engine.message }
        guard let last = engine.lastSync else { return "Not synced yet" }
        let when = last.formatted(.relative(presentation: .named))
        return engine.message.isEmpty ? "Last synced \(when)" : "\(engine.message) · \(when)"
    }

    private func loadStats() async {
        stats = try? await engine.client().stats()
    }
}

// MARK: - Server setup guide

struct SyncServerGuide: View {
    @State private var variant = 0
    @State private var copied = false

    private var file: String { variant == 0 ? "compose" : "compose.lan" }
    private var yaml: String {
        guard let url = Bundle.main.url(forResource: file, withExtension: "yml"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    var body: some View {
        HushForm {
            Section {
                Picker("Reach it", selection: $variant) {
                    Text("Tailscale").tag(0)
                    Text("Home network").tag(1)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(variant == 0
                     ? "Works anywhere your iPhone has Tailscale on. Nothing is opened to the internet."
                     : "Only syncs when your iPhone is on your home Wi-Fi.")
            }

            Section("Steps") {
                if variant == 0 {
                    step(1, "In the Tailscale admin console, turn on MagicDNS and HTTPS Certificates (DNS page), then create an auth key (Settings > Keys).")
                    step(2, "On a VM or LXC with Docker, make a folder (for example ~/hush) and save the file below there as compose.yml. Paste your auth key into TS_AUTHKEY.")
                    step(3, "Run: docker compose up -d")
                    step(4, "Run: docker compose logs hush, and copy the pairing token.")
                    step(5, "Back here, enter https://hush.<your-tailnet>.ts.net and the token.")
                } else {
                    step(1, "On a VM or LXC with Docker, make a folder (for example ~/hush) and save the file below there as compose.yml.")
                    step(2, "Run: docker compose up -d")
                    step(3, "Run: docker compose logs hush, and copy the pairing token.")
                    step(4, "Back here, enter http://<server-ip>:8080 and the token.")
                }
            }

            Section {
                Text(yaml)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    UIPasteboard.general.string = yaml
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy compose.yml", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("compose.yml")
            } footer: {
                Text("Update the server later with: docker compose pull && docker compose up -d. Back up the hush-data volume (for example with Proxmox Backup Server); it only holds encrypted data.")
            }
        }
        .navigationTitle("Server Setup")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: variant) { copied = false }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.hush(.subheadline).weight(.bold)).foregroundStyle(.tint).frame(width: 18)
            Text(text).font(.hush(.subheadline))
        }
    }
}

// MARK: - CI end-to-end test hook

extension SyncEngine {
    /// Launch argument `-syncTest "url|token|passphrase"` connects without the UI (used by CI).
    func runTestIfRequested() {
        guard let spec = UserDefaults.standard.string(forKey: "syncTest"), !SyncSettings.isConfigured else { return }
        let p = spec.components(separatedBy: "|")
        guard p.count == 3 else { return }
        Task {
            do {
                let (_, v) = try await test(url: p[0], token: p[1])
                if v.initialized { try await join(url: p[0], token: p[1], passphrase: p[2]) }
                else { try await create(url: p[0], token: p[1], passphrase: p[2]) }
            } catch {
                lastError = error.localizedDescription
                phase = .failed
                message = error.localizedDescription
            }
        }
    }
}

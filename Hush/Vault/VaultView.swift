import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct VaultView: View {
    let title: String
    @Environment(LockManager.self) private var lock
    @Environment(AppSettings.self) private var settings
    @State private var hasPasscode = Passcode.vault.isSet
    @State private var settingUp = false

    var body: some View {
        Group {
            if lock.vaultUnlocked {
                VaultContentView()
            } else if hasPasscode {
                PasscodePrompt(title: "\(title) is locked", symbol: "lock.shield.fill", store: Passcode.vault,
                               allowBiometrics: settings.vaultUseBiometrics) {
                    lock.vaultUnlocked = true
                }
            } else {
                ContentUnavailableView {
                    Label("Set up your \(title)", systemImage: "lock.shield")
                } description: {
                    Text("A separately locked space with its own passcode. Everything inside is encrypted with AES-256 and it re-locks whenever you leave.")
                } actions: {
                    Button("Choose Vault Passcode") { settingUp = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(title)
        .sheet(isPresented: $settingUp) {
            PasscodeSetupView(title: "Vault Passcode") { code in
                Passcode.vault.set(code)
                hasPasscode = true
                lock.vaultUnlocked = true
            }
        }
    }
}

private struct VaultContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(LockManager.self) private var lock
    @Query(sort: \VaultItem.updatedAt, order: .reverse) private var items: [VaultItem]
    @State private var search = ""
    @State private var newItem: VaultItem?
    @State private var pickingPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []

    var body: some View {
        let rows = items.map { ($0, $0.meta) }.filter { pair in
            search.isEmpty || pair.1.title.localizedCaseInsensitiveContains(search)
                || pair.1.username.localizedCaseInsensitiveContains(search)
                || pair.1.url.localizedCaseInsensitiveContains(search)
        }
        List {
            ForEach(rows, id: \.0.id) { item, meta in
                NavigationLink { VaultItemEditor(item: item) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.kind.symbol)
                            .frame(width: 32, height: 32)
                            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meta.title.isEmpty ? item.kind.label : meta.title).lineLimit(1)
                            Text(subtitle(item, meta)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { context.delete(item) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .hushBackground()
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Vault is empty", systemImage: "lock.shield",
                                       description: Text("Add secure notes, logins or photos with +."))
            }
        }
        .searchable(text: $search, prompt: "Search vault")
        .navigationDestination(item: $newItem) { VaultItemEditor(item: $0, isNew: true) }
        .photosPicker(isPresented: $pickingPhotos, selection: $photoSelection, maxSelectionCount: 20, matching: .images)
        .onChange(of: photoSelection) { _, picked in importPhotos(picked) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { lock.vaultUnlocked = false } label: { Image(systemName: "lock") }
                    .accessibilityLabel("Lock vault")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { add(.note) } label: { Label("Secure Note", systemImage: "doc.text") }
                    Button { add(.login) } label: { Label("Login", systemImage: "key") }
                    Button { pickingPhotos = true } label: { Label("Photos", systemImage: "photo") }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add to vault")
            }
        }
    }

    private func subtitle(_ item: VaultItem, _ meta: VaultMeta) -> String {
        switch item.kind {
        case .login: return meta.username.isEmpty ? meta.url : meta.username
        case .note: return meta.body.split(separator: "\n").first.map(String.init) ?? ""
        case .photo: return item.createdAt.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func add(_ kind: VaultKind) {
        let item = VaultItem(kind: kind)
        item.meta = VaultMeta()
        context.insert(item)
        newItem = item
    }

    private func importPhotos(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        Task {
            for p in picked {
                guard let data = try? await p.loadTransferable(type: Data.self) else { continue }
                let item = VaultItem(kind: .photo)
                item.imageData = data
                item.meta = VaultMeta(title: "Photo \(Date().formatted(date: .abbreviated, time: .shortened))")
                context.insert(item)
            }
            photoSelection = []
        }
    }
}

private struct VaultItemEditor: View {
    let item: VaultItem
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var meta = VaultMeta()
    @State private var loaded = false
    @State private var deleting = false
    @State private var revealPassword = false
    @State private var image: UIImage?
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                TextField(item.kind == .login ? "Name (e.g. Bank)" : "Title", text: $meta.title).font(.headline)
            }
            switch item.kind {
            case .login:
                Section {
                    HStack {
                        TextField("Username or email", text: $meta.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        copyButton(meta.username)
                    }
                    HStack {
                        Group {
                            if revealPassword { TextField("Password", text: $meta.password) }
                            else { SecureField("Password", text: $meta.password) }
                        }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .fontDesign(.monospaced)
                        Button { revealPassword.toggle() } label: { Image(systemName: revealPassword ? "eye.slash" : "eye") }
                            .buttonStyle(.borderless)
                        copyButton(meta.password)
                    }
                    Button("Generate Strong Password") {
                        meta.password = PasswordGenerator.make()
                        revealPassword = true
                    }
                    TextField("Website", text: $meta.url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Notes") { TextField("Notes", text: $meta.body, axis: .vertical).lineLimit(3...10) }
            case .note:
                Section { TextField("Write something private…", text: $meta.body, axis: .vertical).lineLimit(8...40) }
            case .photo:
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(meta.title, image: Image(uiImage: image))) {
                            Label("Share / Save…", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView()
                    }
                }
                Section("Caption") { TextField("Caption", text: $meta.body, axis: .vertical) }
            }
            Section {
                LabeledContent("Added", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                Button("Delete", role: .destructive) {
                    deleting = true
                    dismiss()
                }
            } footer: {
                Text("Encrypted on this iPhone with AES-256-GCM.")
            }
        }
        .hushBackground()
        .navigationTitle(item.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if copied {
                Text("Copied — clears from clipboard in 60 s")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            guard !loaded else { return }
            meta = item.meta
            loaded = true
            if item.kind == .photo {
                Task { image = item.imageData.flatMap(UIImage.init(data:)) }
            }
        }
        .onDisappear {
            if deleting || (isNew && meta == VaultMeta()) {
                context.delete(item)
            } else if loaded && meta != item.meta {
                item.meta = meta
            }
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            UIPasteboard.general.setItems([[UTType.plainText.identifier: text]],
                                          options: [.expirationDate: Date().addingTimeInterval(60), .localOnly: true])
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
        } label: { Image(systemName: "doc.on.doc") }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty)
        .accessibilityLabel("Copy")
    }
}

enum PasswordGenerator {
    static func make(length: Int = 20) -> String {
        let chars = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*?-_")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }
}

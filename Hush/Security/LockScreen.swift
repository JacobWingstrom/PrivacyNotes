import SwiftUI

/// Reusable passcode prompt with optional biometrics. Used for the app lock and the Vault.
struct PasscodePrompt: View {
    let title: String
    let symbol: String
    let store: PasscodeStore
    let allowBiometrics: Bool
    let onUnlock: () -> Void

    @Environment(LockManager.self) private var lock
    @State private var code = ""
    @State private var message = ""
    @State private var failures = 0
    @State private var blockedUntil: Date?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
            Text(title).font(.hush(.title2).bold())

            SecureField("Passcode", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.hush(.title3))
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 260)
                .focused($focused)

            Button("Unlock", action: attempt)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(code.isEmpty)

            if !message.isEmpty {
                Text(message).font(.hush(.footnote)).foregroundStyle(.red)
            }

            if allowBiometrics && lock.biometryAvailable {
                Button(action: useBiometrics) {
                    Label("Use \(lock.biometryName)", systemImage: lock.biometrySymbol)
                }
            }
            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            if allowBiometrics && lock.biometryAvailable { useBiometrics() } else { focused = true }
        }
    }

    private func useBiometrics() {
        lock.authenticate(reason: "Unlock \(title)") { ok in
            if ok { onUnlock() } else { focused = true }
        }
    }

    private func attempt() {
        if let until = blockedUntil, until > .now {
            message = "Too many tries. Wait \(Int(until.timeIntervalSinceNow.rounded(.up))) seconds."
            return
        }
        if store.verify(code) {
            failures = 0
            message = ""
            onUnlock()
        } else {
            failures += 1
            if failures >= 5 {
                let wait = 30 * (failures - 4)
                blockedUntil = .now.addingTimeInterval(Double(wait))
                message = "Too many tries. Wait \(wait) seconds."
            } else {
                message = "Wrong passcode."
            }
        }
        code = ""
    }
}

struct LockScreen: View {
    @Environment(LockManager.self) private var lock
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        PasscodePrompt(title: "Hush is locked", symbol: "lock.fill", store: Passcode.app,
                       allowBiometrics: settings.useBiometrics) {
            lock.isLocked = false
        }
        .background(palette.background)
    }
}

struct PrivacyCover: View {
    @Environment(\.palette) private var palette
    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(.tint)
        }
    }
}

/// Two-step "enter, then confirm" passcode setup.
struct PasscodeSetupView: View {
    var title = "Passcode"
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var second = ""
    @State private var confirming = false
    @State private var message = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(confirming ? "Enter it again to confirm" : "Choose a passcode (4–12 digits)")
                    .font(.hush(.headline))
                SecureField("Passcode", text: confirming ? $second : $first)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.hush(.title3))
                    .padding(14)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: 260)
                    .focused($focused)
                if !message.isEmpty { Text(message).font(.hush(.footnote)).foregroundStyle(.red) }
                Button(confirming ? "Save" : "Next", action: next)
                    .buttonStyle(.borderedProminent)
                Text("If you forget it, it can't be recovered. Keep a backup.")
                    .font(.hush(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.top, 40)
            .padding(.horizontal)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
    }

    private func next() {
        if !confirming {
            guard first.allSatisfy(\.isNumber), (4...12).contains(first.count) else {
                message = "Use 4 to 12 digits."
                return
            }
            message = ""
            confirming = true
        } else if second == first {
            onSave(first)
            dismiss()
        } else {
            message = "Those didn't match. Try again."
            first = ""; second = ""; confirming = false
        }
    }
}

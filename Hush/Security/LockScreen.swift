import SwiftUI

struct LockScreen: View {
    @Environment(LockManager.self) private var lock
    @Environment(AppSettings.self) private var settings
    @State private var code = ""
    @State private var message = ""
    @State private var failures = 0
    @State private var blockedUntil: Date?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Hush is locked").font(.title2.bold())

            SecureField("Passcode", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 260)
                .focused($focused)

            Button("Unlock", action: attempt)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(code.isEmpty)

            if !message.isEmpty {
                Text(message).font(.footnote).foregroundStyle(.red)
            }

            if settings.useBiometrics && lock.biometryAvailable {
                Button {
                    lock.unlockWithBiometrics()
                } label: {
                    Label("Use \(lock.biometryName)", systemImage: lock.biometrySymbol)
                }
            }
            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.theme == .black ? Color.black : Color(.systemBackground))
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            if settings.useBiometrics && lock.biometryAvailable {
                lock.unlockWithBiometrics()
            } else {
                focused = true
            }
        }
    }

    private func attempt() {
        if let until = blockedUntil, until > .now {
            message = "Too many tries. Wait \(Int(until.timeIntervalSinceNow.rounded(.up))) seconds."
            return
        }
        if lock.unlock(with: code) {
            failures = 0
            message = ""
        } else {
            failures += 1
            if failures >= 5 {
                blockedUntil = .now.addingTimeInterval(Double(30 * (failures - 4)))
                message = "Too many tries. Wait \(30 * (failures - 4)) seconds."
            } else {
                message = "Wrong passcode."
            }
        }
        code = ""
    }
}

struct PrivacyCover: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        ZStack {
            (settings.theme == .black ? Color.black : Color(.systemBackground)).ignoresSafeArea()
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(.tint)
        }
    }
}

/// Two-step "enter, then confirm" passcode setup.
struct PasscodeSetupView: View {
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
                    .font(.headline)
                SecureField("Passcode", text: confirming ? $second : $first)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .padding(14)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: 260)
                    .focused($focused)
                if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.red) }
                Button(confirming ? "Save" : "Next", action: next)
                    .buttonStyle(.borderedProminent)
                Text("If you forget it, there is no way to recover your notes. Keep a backup.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.top, 40)
            .padding(.horizontal)
            .navigationTitle("Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
    }

    private func next() {
        let digits = first.allSatisfy(\.isNumber)
        if !confirming {
            guard digits, (4...12).contains(first.count) else {
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

import SwiftUI

/// iPhone-style unlock: Face ID scans first; if it fails or you cancel, type your passcode on the keypad.
struct PasscodePrompt: View {
    let title: String
    let symbol: String
    let store: PasscodeStore
    let allowBiometrics: Bool
    let onUnlock: () -> Void

    @Environment(LockManager.self) private var lock
    @Environment(\.scenePhase) private var phase
    @State private var code = ""
    @State private var message = ""
    @State private var failures = 0
    @State private var blockedUntil: Date?
    @State private var shake: CGFloat = 0
    @State private var triedBiometrics = false

    private var knownLength: Int? { (4...12).contains(store.length) ? store.length : nil }
    private var useFaceID: Bool { allowBiometrics && lock.biometryAvailable }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.bottom, 14)
            Text(title).font(.hush(.title3).weight(.semibold))
            Text(message.isEmpty ? "Enter Passcode" : message)
                .font(.hush(.subheadline))
                .foregroundStyle(message.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                .padding(.top, 6)
                .padding(.bottom, 22)
            PasscodeDots(count: code.count, total: knownLength)
                .modifier(Shake(animatableData: shake))
                .frame(height: 20)
            if knownLength == nil {
                Button("Unlock", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(code.count < 4)
                    .padding(.top, 16)
            }
            Spacer(minLength: 24)
            Keypad(onDigit: add, onDelete: { if !code.isEmpty { code.removeLast() } }) {
                if useFaceID {
                    Button { startBiometrics(force: true) } label: {
                        Image(systemName: lock.biometrySymbol).font(.system(size: 30))
                    }
                    .accessibilityLabel("Use \(lock.biometryName)")
                }
            }
            Spacer(minLength: 30)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startBiometrics() }
        .onChange(of: phase) { _, p in
            if p == .active { startBiometrics() }
            if p == .background { triedBiometrics = false }
        }
    }

    /// Face ID runs once each time the app comes forward. After that, the keypad is the fallback.
    private func startBiometrics(force: Bool = false) {
        guard useFaceID, phase == .active, force || !triedBiometrics else { return }
        triedBiometrics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            lock.authenticate(reason: "Unlock \(title)") { ok in
                if ok { onUnlock() }
            }
        }
    }

    private func add(_ digit: String) {
        if let until = blockedUntil, until > .now {
            message = "Try again in \(Int(until.timeIntervalSinceNow.rounded(.up))) seconds"
            return
        }
        guard code.count < 12 else { return }
        code.append(digit)
        if let n = knownLength, code.count == n { submit() }
    }

    private func submit() {
        if store.verify(code) {
            if knownLength == nil { store.rememberLength(code.count) }
            failures = 0
            message = ""
            onUnlock()
        } else {
            failures += 1
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.linear(duration: 0.35)) { shake += 1 }
            if failures >= 5 {
                let wait = 30 * (failures - 4)
                blockedUntil = .now.addingTimeInterval(Double(wait))
                message = "Too many tries. Wait \(wait) seconds"
            } else {
                message = "Wrong passcode"
            }
        }
        code = ""
    }
}

struct PasscodeDots: View {
    let count: Int
    let total: Int?

    var body: some View {
        let n = total ?? max(count, 4)
        HStack(spacing: 16) {
            ForEach(0..<n, id: \.self) { i in
                Circle()
                    .fill(i < count ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.clear))
                    .overlay(Circle().stroke(.primary.opacity(0.7), lineWidth: 1.3))
                    .frame(width: 13, height: 13)
            }
        }
        .animation(.easeOut(duration: 0.1), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) digits entered")
    }
}

/// Number pad like the iPhone's lock screen.
struct Keypad<Leading: View>: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    @ViewBuilder var leading: Leading

    private let rows: [[(String, String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
    ]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 26) {
                    ForEach(rows[r], id: \.0) { digit, letters in key(digit, letters) }
                }
            }
            HStack(spacing: 26) {
                leading.frame(width: 76, height: 76)
                key("0", "")
                Button(action: onDelete) {
                    Image(systemName: "delete.left").font(.system(size: 24))
                        .frame(width: 76, height: 76)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Delete")
            }
        }
        .foregroundStyle(.primary)
    }

    private func key(_ digit: String, _ letters: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onDigit(digit)
        } label: {
            VStack(spacing: 0) {
                Text(digit).font(.system(size: 34, weight: .regular))
                if !letters.isEmpty {
                    Text(letters).font(.system(size: 10, weight: .semibold)).tracking(2)
                }
            }
            .frame(width: 76, height: 76)
            .background(Circle().fill(.primary.opacity(0.12)))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(digit)
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// Side-to-side shake for a wrong passcode.
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

struct LockScreen: View {
    @Environment(LockManager.self) private var lock
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        PasscodePrompt(title: "Hush", symbol: "lock.fill", store: Passcode.app,
                       allowBiometrics: settings.useBiometrics) {
            lock.isLocked = false
        }
        .background(palette.background.ignoresSafeArea())
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

/// Set a passcode (enter, confirm), then offer Face ID — the same order as setting up an iPhone.
struct PasscodeSetupView: View {
    var title = "Passcode"
    var onSave: (String) -> Void
    var onBiometrics: ((Bool) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(LockManager.self) private var lock
    @Environment(\.palette) private var palette
    @State private var step: Step = .enter
    @State private var first = ""
    @State private var code = ""
    @State private var length = 6
    @State private var custom = false
    @State private var message = ""
    @State private var shake: CGFloat = 0

    private enum Step { case enter, confirm, biometrics }

    var body: some View {
        NavigationStack {
            Group {
                if step == .biometrics { biometricsStep } else { codeStep }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .biometrics ? "Skip" : "Cancel") {
                        if step == .biometrics { onBiometrics?(false) }
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(step == .biometrics)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            Text(step == .enter ? "Enter a new passcode" : "Enter it again to confirm")
                .font(.hush(.headline))
            Text(message.isEmpty ? " " : message)
                .font(.hush(.subheadline)).foregroundStyle(.red)
                .padding(.top, 6).padding(.bottom, 20)
            PasscodeDots(count: code.count, total: custom ? nil : length)
                .modifier(Shake(animatableData: shake))
                .frame(height: 20)
            if custom {
                Button(step == .enter ? "Next" : "Done", action: next)
                    .buttonStyle(.borderedProminent)
                    .disabled(code.count < 4)
                    .padding(.top, 16)
            }
            if step == .enter {
                Menu("Passcode Options") {
                    Button("4-Digit Code") { custom = false; length = 4; code = "" }
                    Button("6-Digit Code") { custom = false; length = 6; code = "" }
                    Button("Custom Length (4–12 digits)") { custom = true; code = "" }
                }
                .font(.hush(.footnote))
                .padding(.top, 18)
            }
            Spacer(minLength: 16)
            Keypad(onDigit: add, onDelete: { if !code.isEmpty { code.removeLast() } }) { EmptyView() }
            Text("If you forget it, it can't be recovered. Keep a backup.")
                .font(.hush(.caption)).foregroundStyle(.secondary)
                .padding(.top, 18)
            Spacer(minLength: 20)
        }
        .padding(.horizontal)
    }

    private var biometricsStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: lock.biometrySymbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            Text("Use \(lock.biometryName)?").font(.hush(.title2).bold())
            Text("Unlock with your face. If it doesn't recognize you, you can always type your passcode instead.")
                .font(.hush(.body)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if !message.isEmpty {
                Text(message).font(.hush(.footnote)).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                lock.authenticate(reason: "Turn on \(lock.biometryName) for \(title)") { ok in
                    if ok {
                        onBiometrics?(true)
                        dismiss()
                    } else {
                        message = "\(lock.biometryName) didn't work. Try again, or skip and turn it on later in Settings."
                    }
                }
            } label: {
                Text("Use \(lock.biometryName)").font(.hush(.headline)).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            Button("Not Now") {
                onBiometrics?(false)
                dismiss()
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
    }

    private func add(_ d: String) {
        guard code.count < (custom ? 12 : length) else { return }
        code.append(d)
        if !custom && code.count == length { next() }
    }

    private func next() {
        if step == .enter {
            guard code.count >= 4 else { return }
            first = code
            code = ""
            message = ""
            step = .confirm
        } else if code == first {
            onSave(code)
            if onBiometrics != nil && lock.biometryAvailable {
                message = ""
                step = .biometrics
            } else {
                dismiss()
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.linear(duration: 0.35)) { shake += 1 }
            message = "Passcodes didn't match. Try again."
            code = ""
            first = ""
            step = .enter
        }
    }
}

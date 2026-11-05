import SwiftUI
import LocalAuthentication

@Observable
final class LockManager {
    var isLocked: Bool
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var authenticating = false

    init() {
        isLocked = UserDefaults.standard.bool(forKey: AppSettings.lockEnabledKey) && Passcode.isSet
    }

    func didEnterBackground() {
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    func didBecomeActive(settings: AppSettings) {
        defer { backgroundedAt = nil }
        guard settings.lockEnabled, Passcode.isSet, let since = backgroundedAt else { return }
        if Date().timeIntervalSince(since) >= Double(settings.autoLock.rawValue) {
            isLocked = true
        }
    }

    func lockNow() { isLocked = true }

    func unlock(with code: String) -> Bool {
        guard Passcode.verify(code) else { return false }
        isLocked = false
        return true
    }

    // MARK: Biometrics

    var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    var biometryAvailable: Bool { biometryType != .none }

    var biometryName: String {
        switch biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Biometrics"
        }
    }

    var biometrySymbol: String {
        switch biometryType {
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "faceid"
        }
    }

    func unlockWithBiometrics() {
        guard !authenticating else { return }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Enter Passcode"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Hush") { ok, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                if ok { self.isLocked = false }
            }
        }
    }
}

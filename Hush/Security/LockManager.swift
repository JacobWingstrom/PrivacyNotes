import SwiftUI
import LocalAuthentication

@Observable
final class LockManager {
    var isLocked: Bool
    var vaultUnlocked = false
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var authenticating = false

    init() {
        isLocked = (UserDefaults.standard.bool(forKey: AppSettings.lockEnabledKey) && Passcode.app.isSet)
            || UserDefaults.standard.bool(forKey: "demoLock")
    }

    func didEnterBackground() {
        vaultUnlocked = false // the Vault always re-locks when you leave the app
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    func didBecomeActive(settings: AppSettings) {
        defer { backgroundedAt = nil }
        guard settings.lockEnabled, Passcode.app.isSet, let since = backgroundedAt else { return }
        if Date().timeIntervalSince(since) >= Double(settings.autoLock.rawValue) {
            isLocked = true
        }
    }

    func lockNow() {
        vaultUnlocked = false
        isLocked = true
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

    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        guard !authenticating else { return }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Enter Passcode"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            completion(false)
            return
        }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                completion(ok)
            }
        }
    }
}

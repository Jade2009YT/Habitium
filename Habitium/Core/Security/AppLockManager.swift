//
//  AppLockManager.swift
//  Habitium
//
//  Second, independent lock on top of Sign in with Apple: every time the
//  app comes back to the foreground, this requires Face ID/Touch ID (or
//  the device passcode as fallback) before revealing any content. Even
//  someone who has your unlocked iPhone in hand still can't open Habitium
//  without your biometrics.
//
//  Deliberately NOT tied to Apple's identity — this is purely "is the
//  person holding this phone allowed to see this data right now", which
//  is exactly what LocalAuthentication is for.
//

import LocalAuthentication
import Observation

@MainActor
@Observable
final class AppLockManager {

    private(set) var isUnlocked = false
    var errorMessage: String?

    /// Persisted in UserDefaults (not SwiftData) since it needs to be
    /// readable before the ModelContainer/UI decide whether to even show
    /// the lock screen.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "appLock.enabled"

    init() {
        // Defaults to ON — this feature exists because the user explicitly
        // asked for the app to be locked down.
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var biometryDescription: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Código del dispositivo"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Código del dispositivo"
        }
    }

    /// Called whenever the app becomes active. No-op if locking is
    /// disabled or already unlocked for this foreground session.
    func lockIfNeeded() {
        guard isEnabled else {
            isUnlocked = true
            return
        }
        isUnlocked = false
    }

    /// Called when the app leaves the foreground, so the next return to
    /// active always re-locks.
    func lockOnBackground() {
        guard isEnabled else { return }
        isUnlocked = false
    }

    func authenticate() async {
        guard isEnabled else {
            isUnlocked = true
            return
        }

        let context = LAContext()
        context.localizedFallbackTitle = "Usar código"
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics AND no passcode set on the device — nothing to
            // gate with, so don't lock the user out of their own data.
            isUnlocked = true
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Desbloquea Habitium para ver tus datos."
            )
            isUnlocked = success
            errorMessage = success ? nil : "No se pudo verificar tu identidad."
        } catch {
            isUnlocked = false
            if let laError = error as? LAError, laError.code == .userCancel {
                errorMessage = nil // Silent — they'll just see the lock screen again.
            } else {
                errorMessage = "No se pudo desbloquear: \(error.localizedDescription)"
            }
        }
    }
}

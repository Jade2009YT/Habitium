//
//  AppleSignInManager.swift
//  Habitium
//
//  Sign in with Apple — no backend, no email/password to protect, no
//  ongoing cost. Apple verifies the person (Face ID/Touch ID tied to
//  their Apple ID) and hands us a stable, per-app user identifier we
//  store in the Keychain. Licensing (StoreKit) doesn't depend on this at
//  all — it's purely "who's using this iPhone", useful if Habitium ever
//  grows a feature that needs to know that (e.g. multi-profile support).
//
//  credentialState(forUserID:) is checked on every launch so a revoked
//  "Sign in with Apple" grant (Settings → Apple ID → Sign in with Apple)
//  signs the app out too, instead of trusting a stale local flag forever.
//

import AuthenticationServices
import Observation

@MainActor
@Observable
final class AppleSignInManager: NSObject {

    private(set) var isSignedIn: Bool = false
    private(set) var userIdentifier: String?
    /// True once restoreExistingCredential() has run at least once — lets
    /// the root view show a blank screen instead of flashing the login
    /// screen while Apple confirms the stored credential is still valid.
    private(set) var hasCheckedCredential = false
    var errorMessage: String?

    /// Populated only on the very first successful authorization — Apple
    /// doesn't return these again on subsequent sign-ins for the same
    /// user/app. Callers should persist them then (see HabitiumApp).
    var lastGrantedDisplayName: String?
    var lastGrantedEmail: String?

    private static let keychainKey = "appleUserIdentifier"

    override init() {
        super.init()
    }

    /// Call on launch: restores the stored identifier and confirms with
    /// Apple that the grant is still valid.
    func restoreExistingCredential() async {
        defer { hasCheckedCredential = true }

        guard let storedID = KeychainStore.read(forKey: Self.keychainKey) else {
            isSignedIn = false
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        let state = try? await provider.credentialState(forUserID: storedID)
        switch state {
        case .authorized:
            userIdentifier = storedID
            isSignedIn = true
        default:
            // Revoked, transferred, or not found — treat as signed out.
            KeychainStore.delete(forKey: Self.keychainKey)
            userIdentifier = nil
            isSignedIn = false
        }
    }

    /// Call from SignInWithAppleButton's onCompletion.
    func handle(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Respuesta de Apple inesperada."
                return
            }
            KeychainStore.save(credential.user, forKey: Self.keychainKey)
            userIdentifier = credential.user
            isSignedIn = true
            errorMessage = nil

            if let fullName = credential.fullName {
                let formatted = PersonNameComponentsFormatter.localizedString(from: fullName, style: .default)
                if !formatted.isEmpty { lastGrantedDisplayName = formatted }
            }
            if let email = credential.email, !email.isEmpty {
                lastGrantedEmail = email
            }

        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return // User dismissed the sheet — not a real error.
            }
            errorMessage = "No se pudo iniciar sesión: \(error.localizedDescription)"
        }
    }

    func signOut() {
        KeychainStore.delete(forKey: Self.keychainKey)
        userIdentifier = nil
        isSignedIn = false
    }
}

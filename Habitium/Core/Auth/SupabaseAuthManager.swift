//
//  SupabaseAuthManager.swift
//  Habitium
//
//  Email/password registration + login via Supabase Auth — a second way
//  in, alongside Sign in with Apple (LoginView offers both). Deliberately
//  identity-only: creating an account here does NOT move any app data to
//  the cloud. Everything (meals, medication, finances, notes) still lives
//  exclusively in the local SwiftData store, exactly as before. Supabase
//  only ever sees an email address and a hashed password.
//
//  Setup: create a free project at https://supabase.com, then paste its
//  URL + anon key into Configuration/Secrets.xcconfig (see
//  Secrets.example.xcconfig). Without those, `isConfigured` is false and
//  every method below fails fast with a clear message instead of
//  crashing — the Apple sign-in path keeps working regardless.
//
//  ⚠️ API-surface disclaimer: this targets supabase-swift v2's documented
//  Auth API (SupabaseClient.auth.signUp/signIn/signOut/resend/
//  resetPasswordForEmail) from training knowledge, written without being
//  able to compile against the actual resolved package version. If Xcode
//  flags a method name here that doesn't exist, it's almost always a
//  near-identical rename (e.g. signIn -> signInWithPassword) — check the
//  autocomplete on `client.auth.` and adjust; the surrounding
//  architecture (this file's public API) shouldn't need to change.
//

import Auth
import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class SupabaseAuthManager {

    enum State: Equatable {
        case signedOut
        case pendingEmailVerification(email: String)
        case signedIn(email: String)
    }

    private(set) var state: State = .signedOut
    /// True once restoreSession() has run at least once — mirrors
    /// AppleSignInManager.hasCheckedCredential, so RootView can wait for
    /// both before deciding whether to show LoginView.
    private(set) var hasCheckedSession = false
    var errorMessage: String?
    var isLoading = false

    /// False when Configuration/Secrets.xcconfig hasn't been filled in —
    /// callers (LoginView) can hide/disable the email option instead of
    /// showing a broken form.
    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { if case .signedIn = state { return true } else { return false } }

    private let client: SupabaseClient?

    init() {
        if let url = AppConfiguration.supabaseURL, let key = AppConfiguration.supabaseAnonKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
        }
    }

    /// Call once at launch — restores a still-valid session (the SDK
    /// persists it in the Keychain itself) without any user action.
    func restoreSession() async {
        defer { hasCheckedSession = true }
        guard let client else { return }
        do {
            let session = try await client.auth.session
            updateState(from: session.user)
        } catch {
            state = .signedOut
        }
    }

    func signUp(email: String, password: String) async {
        guard let client else {
            errorMessage = "Supabase no está configurado. Añade SUPABASE_URL_HOST y SUPABASE_ANON_KEY en Configuration/Secrets.xcconfig."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                updateState(from: session.user)
            } else {
                // "Confirm email" is on (Supabase's default) — no session
                // until the user taps the link in their inbox.
                state = .pendingEmailVerification(email: email)
            }
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func signIn(email: String, password: String) async {
        guard let client else {
            errorMessage = "Supabase no está configurado. Añade SUPABASE_URL_HOST y SUPABASE_ANON_KEY en Configuration/Secrets.xcconfig."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let session = try await client.auth.signIn(email: email, password: password)
            updateState(from: session.user)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
        state = .signedOut
    }

    /// Re-sends the "confirm your email" link — shown next to the pending
    /// state so a lost/expired email doesn't strand the user.
    func resendVerificationEmail(email: String) async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.auth.resend(email: email, type: .signup)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func sendPasswordReset(email: String) async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.auth.resetPasswordForEmail(email)
            errorMessage = "Te hemos enviado un enlace para restablecer tu contraseña."
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    // MARK: - Private

    private func updateState(from user: User) {
        let email = user.email ?? ""
        state = user.emailConfirmedAt != nil ? .signedIn(email: email) : .pendingEmailVerification(email: email)
    }

    private func friendlyMessage(for error: Error) -> String {
        // Supabase's AuthError already carries a reasonably readable
        // message (e.g. "Invalid login credentials", "Email not
        // confirmed") — surfaced as-is rather than re-interpreted.
        error.localizedDescription
    }
}

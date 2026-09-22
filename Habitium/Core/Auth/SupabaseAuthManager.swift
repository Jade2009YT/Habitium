//
//  SupabaseAuthManager.swift
//  Habitium
//
//  Email/password registration + login via Supabase Auth — a second way
//  in, alongside Sign in with Apple (LoginView offers both).
//
//  Fase 2 update: signing in here is no longer identity-only. Once
//  signed in, CloudSyncService (Core/Sync/) mirrors this account's data
//  to the same Supabase project's Postgres tables (see
//  supabase/schema.sql), so it's reachable from any device/platform
//  signed into the same account — iPhone, and eventually Android/web.
//  SwiftData on this device stays the fast local read/write path and
//  keeps its own encryption (Secure Enclave, Data Protection); the cloud
//  copy is what makes "the same data everywhere" possible.
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
        /// Password accepted, second factor still pending. Supabase calls
        /// this "aal1": there IS a session, but it can't read anything
        /// protected until the TOTP code is verified. Modelling it as its
        /// own state is what stops RootView from flashing the app's
        /// contents for a split second before the code prompt appears.
        case needsSecondFactor(email: String)
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

    /// Not private: CloudSyncService reuses this exact instance (not a
    /// second SupabaseClient) so every Postgrest request it makes
    /// automatically carries the signed-in session's token, the same way
    /// client.auth already does internally.
    let client: SupabaseClient?

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
            await updateState(checkingSecondFactorFor: session.user)
        } catch {
            state = .signedOut
        }
    }

    func signUp(email: String, password: String, inviteCode: String = "") async {
        guard let client else {
            errorMessage = "Supabase no está configurado. Añade SUPABASE_URL_HOST y SUPABASE_ANON_KEY en Configuration/Secrets.xcconfig."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // El código de invitación viaja como metadato del usuario, que
            // es lo que lee el portero del servidor (el trigger
            // `habitium_check_signup` sobre auth.users, en
            // supabase/schema.sql). Quien lo quite recompilando la app no
            // se cuela: lo único que consigue es que el servidor le diga
            // que no, igual que en la web y en Android.
            let limpio = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let metadata: [String: AnyJSON]? = limpio.isEmpty ? nil : ["invite_code": .string(limpio)]

            let response = try await client.auth.signUp(email: email, password: password, data: metadata)
            if let session = response.session {
                await updateState(checkingSecondFactorFor: session.user)
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
            await updateState(checkingSecondFactorFor: session.user)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    // MARK: - Verificación en dos pasos (TOTP)
    //
    // Esto tiene que existir en el iPhone aunque se active desde la web:
    // si alguien la activa allí y aquí no estuviera, la app del móvil se
    // quedaría dando vueltas sin poder entrar en su propia cuenta.

    /// ¿Hay sesión pero a medias? `nextLevel == .aal2` quiere decir que la
    /// cuenta tiene segundo factor; `currentLevel` dice por dónde va esta
    /// sesión. Si no coinciden, falta el código.
    func needsSecondFactor() async -> Bool {
        guard let client else { return false }
        do {
            let niveles = try await client.auth.mfa.getAuthenticatorAssuranceLevel()
            return niveles.nextLevel == .aal2 && niveles.currentLevel != .aal2
        } catch {
            // Ante la duda NO se deja a nadie fuera de su propia app: si
            // esta comprobación falla (sin red, por ejemplo), se sigue
            // adelante y ya será el servidor quien rechace las consultas.
            return false
        }
    }

    /// Los factores dados de alta y confirmados.
    func secondFactors() async -> [Factor] {
        guard let client else { return [] }
        do {
            return try await client.auth.mfa.listFactors().totp
        } catch {
            return []
        }
    }

    /// El código que se pide al entrar.
    func verifySecondFactor(code: String) async -> Bool {
        guard let client else { return false }
        let digitos = code.filter(\.isNumber)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let factor = try await client.auth.mfa.listFactors().totp.first else {
                errorMessage = "No hay ningún método de verificación activo."
                return false
            }
            let reto = try await client.auth.mfa.challenge(params: .init(factorId: factor.id))
            try await client.auth.mfa.verify(
                params: .init(factorId: factor.id, challengeId: reto.id, code: digitos)
            )
            if let user = try? await client.auth.session.user {
                state = .signedIn(email: user.email ?? "")
            }
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    /// Da de alta un factor nuevo. Devuelve el secreto y el enlace
    /// `otpauth://` — en un móvil eso es mejor que un QR: el QR habría que
    /// escanearlo con OTRO aparato, mientras que el enlace lo abre la app
    /// de códigos de este mismo teléfono de un toque.
    ///
    /// Todavía NO queda activado: hace falta confirmarlo con un código
    /// (confirmSecondFactor). Si se activara de golpe y la app de códigos
    /// no hubiera guardado bien el secreto, te quedarías fuera de tu
    /// propia cuenta sin forma de volver a entrar.
    struct Enrollment: Identifiable {
        let id: String            // el factorId que devuelve Supabase
        let secret: String        // para escribirlo a mano
        let uri: String           // otpauth://… — lo abre la app de códigos
    }

    func enrollSecondFactor() async -> Enrollment? {
        guard let client else { return nil }
        errorMessage = nil
        do {
            let alta = try await client.auth.mfa.enroll(
                params: .init(issuer: "Habitium", friendlyName: "Habitium \(Date().formatted(date: .numeric, time: .omitted))")
            )
            return Enrollment(id: alta.id, secret: alta.totp?.secret ?? "", uri: alta.totp?.uri ?? "")
        } catch {
            errorMessage = friendlyMessage(for: error)
            return nil
        }
    }

    func confirmSecondFactor(factorId: String, code: String) async -> Bool {
        guard let client else { return false }
        errorMessage = nil
        do {
            let reto = try await client.auth.mfa.challenge(params: .init(factorId: factorId))
            try await client.auth.mfa.verify(
                params: .init(factorId: factorId, challengeId: reto.id, code: code.filter(\.isNumber))
            )
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func removeSecondFactor(factorId: String) async {
        guard let client else { return }
        errorMessage = nil
        do {
            try await client.auth.mfa.unenroll(params: .init(factorId: factorId))
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Cambiar la contraseña desde dentro de la app, sin pasar por el
    /// correo. Es la forma rápida de reaccionar si crees que alguien la
    /// ha visto.
    func changePassword(to nueva: String) async -> Bool {
        guard let client else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.auth.update(user: UserAttributes(password: nueva))
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
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

    /// Same as updateState, but stops at the TOTP prompt when the account
    /// has a second factor and this session hasn't cleared it yet.
    private func updateState(checkingSecondFactorFor user: User) async {
        let email = user.email ?? ""
        guard user.emailConfirmedAt != nil else {
            state = .pendingEmailVerification(email: email)
            return
        }
        state = await needsSecondFactor() ? .needsSecondFactor(email: email) : .signedIn(email: email)
    }

    /// Los errores de Supabase vienen en inglés, y alguno es directamente
    /// críptico: cuando el portero del registro rechaza a alguien, la
    /// respuesta es "Database error saving new user", que no le dice nada
    /// a nadie. Aquí se traducen los que de verdad le pueden salir a una
    /// persona; lo que no esté en la lista se enseña tal cual, que es
    /// mejor que tragárselo.
    ///
    /// Al iniciar sesión NUNCA se distingue entre "ese correo no existe" y
    /// "la contraseña no es esa": decirlo sería regalar una forma de
    /// averiguar qué correos tienen cuenta aquí.
    private func friendlyMessage(for error: Error) -> String {
        let texto = error.localizedDescription

        let traducciones: [(String, String)] = [
            ("HABITIUM_REGISTRO_CERRADO", "El registro está cerrado ahora mismo."),
            ("HABITIUM_SIN_INVITACION", "Ese correo no está invitado y el código no vale. Pide una invitación."),
            ("HABITIUM_INVITACION_CADUCADA", "Esa invitación ya ha caducado."),
            ("HABITIUM_INVITACION_AGOTADA", "Ese código de invitación ya se ha usado del todo."),
            ("HABITIUM_LIMITE_FILAS", "Has llegado al máximo de datos guardados en esa sección."),
            ("Database error saving new user", "No se ha podido crear la cuenta: comprueba la invitación o el código."),
            ("Invalid login credentials", "El correo o la contraseña no son correctos."),
            ("Email not confirmed", "Todavía no has confirmado el correo. Mira tu bandeja de entrada."),
            ("already registered", "Ya hay una cuenta con ese correo. Prueba a iniciar sesión."),
            ("rate limit", "Demasiados intentos seguidos. Espera un momento y vuelve a probar."),
            ("Invalid TOTP", "Ese código no es válido. Mira la app de códigos otra vez."),
            ("invalid code", "Ese código no es válido. Mira la app de códigos otra vez."),
            ("expired", "El código ha caducado. Pide uno nuevo en tu app."),
            ("check constraint", "Ese texto es demasiado largo. Acórtalo un poco."),
        ]

        for (patron, mensaje) in traducciones where texto.localizedCaseInsensitiveContains(patron) {
            return mensaje
        }
        return texto
    }
}

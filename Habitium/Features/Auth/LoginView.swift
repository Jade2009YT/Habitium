//
//  LoginView.swift
//  Habitium
//
//  Gate screen shown before the app is unlocked. Three independent ways
//  in, any of which satisfies RootView's "signed in" check:
//    1. Sign in with Apple — no password to protect, ever. Needs a paid
//       Apple Developer account for the entitlement, so it fails on a
//       free personal-team build.
//    2. Email/password via Supabase (SupabaseAuthManager) — the only
//       one that enables cross-device sync. Hidden entirely when
//       Secrets.xcconfig has no Supabase credentials.
//    3. No account at all (LocalAccessManager) — always shown, because
//       the first two can both be unavailable at once and the app must
//       never be unreachable.
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppleSignInManager.self) private var authManager
    @Environment(SupabaseAuthManager.self) private var emailAuth
    @Environment(LocalAccessManager.self) private var localAccess
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingEmailForm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                if case .needsSecondFactor = emailAuth.state {
                    // La contraseña ya está bien, pero la cuenta tiene
                    // verificación en dos pasos. Hasta que no entre el
                    // código no se pinta NADA más: ni el botón de Apple,
                    // ni la entrada sin cuenta. Es toda la gracia.
                    SecondFactorPrompt()
                } else if case .pendingEmailVerification(let email) = emailAuth.state {
                    EmailVerificationPendingView(email: email)
                } else {
                    VStack(spacing: 12) {
                        SignInWithAppleButton(
                            .continue,
                            onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                            },
                            onCompletion: { result in
                                authManager.handle(result: result)
                            }
                        )
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.danger)
                                .multilineTextAlignment(.center)
                        }

                        if emailAuth.isConfigured {
                            emailToggle
                            if showingEmailForm {
                                EmailAuthForm()
                            }
                        }

                        localAccessSection

                        Text(privacyNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
        .themedBackground()
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Colors.nutrition)
            Text("Habitium")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Tu cuidado personal, todo en un solo lugar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Always available, and always last — an account is the better
    /// option when one is actually usable (it's what enables sync), but
    /// the app must never be unreachable when neither other door opens.
    private var localAccessSection: some View {
        VStack(spacing: 8) {
            HStack {
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                Text("o").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            }
            .padding(.vertical, 4)

            Button {
                localAccess.continueWithoutAccount()
            } label: {
                Text("Usar sin cuenta")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("Todo se guarda solo en este iPhone. Podrás crear una cuenta más adelante desde Ajustes.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var privacyNote: String {
        emailAuth.isConfigured
            ? "Con cuenta de email, tus datos se sincronizan de forma privada para que los tengas igual en todos tus dispositivos. Sin cuenta, o con Apple, se quedan solo en este iPhone."
            : "Todos tus datos se guardan solo en este iPhone."
    }

    private var emailToggle: some View {
        VStack(spacing: 8) {
            HStack {
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                Text("o").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            }
            .padding(.vertical, 4)

            Button {
                withAnimation { showingEmailForm.toggle() }
            } label: {
                Text(showingEmailForm ? "Ocultar" : "Continuar con email")
                    .font(.subheadline.bold())
            }
        }
    }
}

private struct EmailVerificationPendingView: View {
    @Environment(SupabaseAuthManager.self) private var emailAuth
    let email: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.planner)

            Text("Confirma tu correo")
                .font(.title3.bold())

            Text("Te hemos enviado un enlace a \(email). Ábrelo para activar tu cuenta y vuelve aquí.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await emailAuth.resendVerificationEmail(email: email) }
            } label: {
                if emailAuth.isLoading {
                    ProgressView()
                } else {
                    Text("Reenviar correo")
                }
            }
            .buttonStyle(.bordered)

            Button("Ya lo confirmé, reintentar") {
                Task { await emailAuth.restoreSession() }
            }
            .font(.caption)

            if let error = emailAuth.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct EmailAuthForm: View {
    @Environment(SupabaseAuthManager.self) private var emailAuth

    private enum Mode: String, CaseIterable {
        case signIn = "Iniciar sesión"
        case signUp = "Crear cuenta"
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""

    /// Diez caracteres y nada de "una mayúscula y un símbolo". Esas reglas
    /// suenan serias pero empujan a la gente a poner "Contraseña1!", que
    /// está entre las primeras que prueba cualquier ataque, mientras que
    /// cada carácter de más sí multiplica el tiempo que cuesta romperla.
    /// La misma norma que en la web (web/seguridad.js), a propósito: una
    /// cuenta es la misma en los dos sitios.
    private var problemaContrasena: String? {
        guard mode == .signUp else { return nil }
        if password.isEmpty { return nil }
        if password.count < 10 { return "La contraseña necesita al menos 10 caracteres." }
        let usuario = email.split(separator: "@").first.map(String.init)?.lowercased() ?? ""
        if usuario.count >= 4, password.lowercased().contains(usuario) {
            return "No uses tu correo dentro de la contraseña."
        }
        if Set(password).count == 1 { return "Repetir la misma letra no es una contraseña." }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Modo", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            TextField("Correo", text: $email)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField(mode == .signUp ? "Contraseña (mínimo 10)" : "Contraseña", text: $password)
                .textFieldStyle(.roundedBorder)

            if let problema = problemaContrasena {
                Text(problema)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Solo aparece al crear cuenta. Si tu Supabase tiene el
            // registro abierto, déjalo vacío y ya está; si lo tienes por
            // invitación (ver supabase/schema.sql), aquí va el código.
            if mode == .signUp {
                TextField("Código de invitación (si te han dado uno)", text: $inviteCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            Button {
                Task {
                    if mode == .signUp {
                        await emailAuth.signUp(email: email, password: password, inviteCode: inviteCode)
                    } else {
                        await emailAuth.signIn(email: email, password: password)
                    }
                }
            } label: {
                if emailAuth.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(mode.rawValue).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                email.trimmingCharacters(in: .whitespaces).isEmpty
                    || password.count < (mode == .signUp ? 10 : 6)
                    || problemaContrasena != nil
            )

            if mode == .signIn {
                Button("¿Has olvidado tu contraseña?") {
                    Task { await emailAuth.sendPasswordReset(email: email) }
                }
                .font(.caption)
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error = emailAuth.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }
}

/// El código de seis cifras que se pide al entrar cuando la cuenta tiene
/// verificación en dos pasos.
///
/// Da igual dónde se activara —aquí o en la web—: la cuenta es la misma,
/// así que el candado es el mismo en los dos sitios. Por eso esto tiene
/// que existir en el iPhone aunque el interruptor esté en la web.
private struct SecondFactorPrompt: View {
    @Environment(SupabaseAuthManager.self) private var emailAuth
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.Colors.planner)

            Text("Un paso más")
                .font(.title2.weight(.bold))

            Text("Abre tu app de códigos y escribe el número de seis cifras que sale ahora mismo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $code)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .focused($focused)
                // Seis cifras y para: así no hace falta ni pulsar el botón.
                .onChange(of: code) { _, nuevo in
                    code = String(nuevo.filter(\.isNumber).prefix(6))
                    if code.count == 6 { Task { await verificar() } }
                }

            Button {
                Task { await verificar() }
            } label: {
                if emailAuth.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Entrar").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count < 6 || emailAuth.isLoading)

            Button("Usar otra cuenta") {
                Task { await emailAuth.signOut() }
            }
            .font(.caption)

            if let error = emailAuth.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
        .onAppear { focused = true }
    }

    private func verificar() async {
        guard code.count == 6, !emailAuth.isLoading else { return }
        let ok = await emailAuth.verifySecondFactor(code: code)
        if !ok { code = "" }
    }
}

#Preview {
    LoginView()
        .environment(AppleSignInManager())
        .environment(SupabaseAuthManager())
        .environment(LocalAccessManager())
}

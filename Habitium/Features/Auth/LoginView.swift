//
//  LoginView.swift
//  Habitium
//
//  Gate screen shown before the app is unlocked. Two independent ways in:
//  Sign in with Apple (no password to protect, ever), or email/password
//  via Supabase (SupabaseAuthManager) for people who'd rather not use
//  their Apple ID. Either one satisfies RootView's "signed in" check.
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppleSignInManager.self) private var authManager
    @Environment(SupabaseAuthManager.self) private var emailAuth
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingEmailForm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                if case .pendingEmailVerification(let email) = emailAuth.state {
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

                        Text("Todos tus datos se guardan solo en este iPhone. Iniciar sesión no envía tus comidas, finanzas ni notas a ningún servidor de Habitium — no tenemos ninguno.")
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

            SecureField("Contraseña", text: $password)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    if mode == .signUp {
                        await emailAuth.signUp(email: email, password: password)
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
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.count < 6)

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

#Preview {
    LoginView()
        .environment(AppleSignInManager())
        .environment(SupabaseAuthManager())
}

//
//  LoginView.swift
//  Habitium
//
//  Gate screen shown before the app is unlocked. Sign in with Apple only —
//  no password field, no email typed anywhere, nothing this app has to
//  protect on its own.
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppleSignInManager.self) private var authManager

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

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

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    authManager.handle(result: result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let error = authManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.danger)
                        .multilineTextAlignment(.center)
                }

                Text("Todos tus datos se guardan solo en este iPhone. Iniciar sesión con Apple no envía nada a ningún servidor de Habitium — no tenemos ninguno.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 32)
    }

    @Environment(\.colorScheme) private var colorScheme
}

#Preview {
    LoginView()
        .environment(AppleSignInManager())
}

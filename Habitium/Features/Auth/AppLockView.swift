//
//  AppLockView.swift
//  Habitium
//
//  Full-screen gate shown whenever the app is foregrounded and locked —
//  sits ON TOP of the already-signed-in MainTabView, not instead of it,
//  so returning from the background never has to re-run Sign in with
//  Apple, just Face ID/Touch ID.
//

import SwiftUI

struct AppLockView: View {
    @Environment(AppLockManager.self) private var lockManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: symbolName)
                .font(.system(size: 46))
                .foregroundStyle(Theme.Colors.nutrition)

            Text("Habitium está bloqueado")
                .font(.title3.bold())

            Text("Usa \(lockManager.biometryDescription) para continuar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = lockManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }

            Spacer()

            Button {
                Task { await lockManager.authenticate() }
            } label: {
                Label("Desbloquear", systemImage: symbolName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task {
            await lockManager.authenticate()
        }
    }

    private var symbolName: String {
        switch lockManager.biometryDescription {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock.fill"
        }
    }
}

#Preview {
    AppLockView()
        .environment(AppLockManager())
}

//
//  RootView.swift
//  Habitium
//
//  Switches between LoginView and MainTabView based on whichever sign-in
//  method succeeded — Sign in with Apple or Supabase email/password.
//  Also the single place that reacts to a *first-ever* successful Apple
//  sign-in to capture the display name/email Apple only hands over once,
//  and the first place a Supabase-signed-in account triggers a cloud
//  sync pass (see CloudSyncService) — once at launch, once more whenever
//  emailAuth.isSignedIn flips true mid-session (fresh sign-in/sign-up).
//

import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppDependencyContainer.self) private var container
    @Environment(AppleSignInManager.self) private var authManager
    @Environment(SupabaseAuthManager.self) private var emailAuth
    @Environment(LocalAccessManager.self) private var localAccess
    @Environment(AppLockManager.self) private var lockManager
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.modelContext) private var modelContext

    private var hasCheckedAllCredentials: Bool {
        authManager.hasCheckedCredential && emailAuth.hasCheckedSession
    }
    private var isSignedIn: Bool {
        authManager.isSignedIn || emailAuth.isSignedIn || localAccess.isUsingLocalOnly
    }

    var body: some View {
        Group {
            if !hasCheckedAllCredentials {
                // El fondo del tema y no Color(.systemBackground): con
                // "Noche" elegido, ese medio segundo en blanco antes de
                // que cargue la sesión se ve como un fogonazo.
                appearance.background.screenColor.ignoresSafeArea()
            } else if isSignedIn {
                MainTabView()
                    // Una sola vez, en la raíz: los avisos de XP y la
                    // celebración de subir de nivel se ven encima de
                    // cualquier pestaña, sin que cada pantalla tenga que
                    // acordarse de nada.
                    .progressionFeedback()
                    .fullScreenCover(isPresented: lockedBinding) {
                        AppLockView()
                    }
            } else {
                LoginView()
            }
        }
        // Un único sitio para todo: login, pestañas, hojas y bloqueo.
        // Con `nil` (tema "Automático") SwiftUI deja mandar al iPhone.
        .preferredColorScheme(appearance.background.colorScheme)
        .task {
            await authManager.restoreExistingCredential()
            await emailAuth.restoreSession()
            await CloudSyncService.shared.syncAll(context: modelContext)
        }
        .onChange(of: emailAuth.isSignedIn) { _, isSignedIn in
            // Covers signing in mid-session (LoginView), not just launch —
            // the .task above only runs once, at RootView's first appearance.
            guard isSignedIn else { return }
            Task { await CloudSyncService.shared.syncAll(context: modelContext) }
        }
        .onChange(of: authManager.lastGrantedDisplayName) { _, newValue in
            guard newValue != nil else { return }
            container.applyAppleIdentity(displayName: authManager.lastGrantedDisplayName, email: authManager.lastGrantedEmail)
        }
        .onChange(of: authManager.lastGrantedEmail) { _, newValue in
            guard newValue != nil else { return }
            container.applyAppleIdentity(displayName: authManager.lastGrantedDisplayName, email: authManager.lastGrantedEmail)
        }
    }

    private var lockedBinding: Binding<Bool> {
        Binding(get: { !lockManager.isUnlocked }, set: { _ in })
    }
}

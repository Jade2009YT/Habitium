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
    @Environment(AppLockManager.self) private var lockManager
    @Environment(\.modelContext) private var modelContext

    private var hasCheckedAllCredentials: Bool {
        authManager.hasCheckedCredential && emailAuth.hasCheckedSession
    }
    private var isSignedIn: Bool {
        authManager.isSignedIn || emailAuth.isSignedIn
    }

    var body: some View {
        Group {
            if !hasCheckedAllCredentials {
                Color(.systemBackground).ignoresSafeArea()
            } else if isSignedIn {
                MainTabView()
                    .fullScreenCover(isPresented: lockedBinding) {
                        AppLockView()
                    }
            } else {
                LoginView()
            }
        }
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

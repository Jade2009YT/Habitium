//
//  RootView.swift
//  Habitium
//
//  Switches between LoginView and MainTabView based on whichever sign-in
//  method succeeded — Sign in with Apple or Supabase email/password.
//  Also the single place that reacts to a *first-ever* successful Apple
//  sign-in to capture the display name/email Apple only hands over once.
//

import SwiftUI

struct RootView: View {
    @Environment(AppDependencyContainer.self) private var container
    @Environment(AppleSignInManager.self) private var authManager
    @Environment(SupabaseAuthManager.self) private var emailAuth
    @Environment(AppLockManager.self) private var lockManager

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

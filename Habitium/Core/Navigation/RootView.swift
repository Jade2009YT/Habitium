//
//  RootView.swift
//  Habitium
//
//  Switches between LoginView and MainTabView based on Sign in with Apple
//  state. Also the single place that reacts to a *first-ever* successful
//  sign-in to capture the display name/email Apple only hands over once.
//

import SwiftUI

struct RootView: View {
    @Environment(AppDependencyContainer.self) private var container
    @Environment(AppleSignInManager.self) private var authManager
    @Environment(AppLockManager.self) private var lockManager

    var body: some View {
        Group {
            if !authManager.hasCheckedCredential {
                Color(.systemBackground).ignoresSafeArea()
            } else if authManager.isSignedIn {
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

//
//  LocalAccessManager.swift
//  Habitium
//
//  A third way past LoginView: no account at all.
//
//  Why this exists: the other two doors can both be shut at the same
//  time. Sign in with Apple needs the `com.apple.developer.applesignin`
//  entitlement, which a free Apple ID can't use — it fails on a
//  personal-team build. And the email option only appears when
//  Supabase credentials are filled into Secrets.xcconfig. Someone
//  building this for themselves with a free account and no Supabase
//  project (the most likely first run, by far) was left staring at a
//  gate they couldn't open. That was a design bug, not a policy.
//
//  Since Habitium's data has always lived locally anyway, "no account"
//  costs the user nothing except cloud sync — which needs a Supabase
//  account by definition. The choice is remembered in UserDefaults, and
//  Settings can undo it if the user later wants a real account.
//

import Foundation
import Observation

@MainActor
@Observable
final class LocalAccessManager {

    private static let defaultsKey = "habitium.usesLocalOnlyAccess"

    /// True once the user has chosen to use Habitium without an account.
    /// RootView treats this like any other "signed in" state.
    private(set) var isUsingLocalOnly: Bool

    init() {
        isUsingLocalOnly = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    func continueWithoutAccount() {
        isUsingLocalOnly = true
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)
    }

    /// Sends the user back to LoginView — e.g. from Settings, to switch
    /// to a real account so their data can sync across devices.
    func exitLocalOnly() {
        isUsingLocalOnly = false
        UserDefaults.standard.set(false, forKey: Self.defaultsKey)
    }
}

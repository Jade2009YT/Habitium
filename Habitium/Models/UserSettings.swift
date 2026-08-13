//
//  UserSettings.swift
//  Habitium
//
//  App-wide preferences that don't belong to a single feature module,
//  plus the non-secret bits of the signed-in identity (display name,
//  email). The actual Sign in with Apple credential — the stable user
//  identifier StoreKit-adjacent auth relies on — lives in the Keychain
//  (see KeychainStore/AppleSignInManager), not here.
//

import Foundation
import SwiftData

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case openAI
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI (GPT-4o Vision)"
        case .claude: return "Claude"
        }
    }
}

@Model
final class UserSettings {
    var id: UUID
    var preferredAIProvider: AIProviderKind.RawValue
    var mealReminderNotificationsEnabled: Bool
    var eventNotificationsEnabled: Bool

    /// Captured from Sign in with Apple the first time it's granted (Apple
    /// only hands these over once per user/app) — display-only, never
    /// used as a secret.
    var displayName: String?
    var email: String?

    init(
        id: UUID = UUID(),
        preferredAIProvider: AIProviderKind = .openAI,
        mealReminderNotificationsEnabled: Bool = true,
        eventNotificationsEnabled: Bool = true,
        displayName: String? = nil,
        email: String? = nil
    ) {
        self.id = id
        self.preferredAIProvider = preferredAIProvider.rawValue
        self.mealReminderNotificationsEnabled = mealReminderNotificationsEnabled
        self.eventNotificationsEnabled = eventNotificationsEnabled
        self.displayName = displayName
        self.email = email
    }
}

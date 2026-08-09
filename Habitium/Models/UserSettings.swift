//
//  UserSettings.swift
//  Habitium
//
//  App-wide preferences that don't belong to a single feature module.
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

    init(
        id: UUID = UUID(),
        preferredAIProvider: AIProviderKind = .openAI,
        mealReminderNotificationsEnabled: Bool = true,
        eventNotificationsEnabled: Bool = true
    ) {
        self.id = id
        self.preferredAIProvider = preferredAIProvider.rawValue
        self.mealReminderNotificationsEnabled = mealReminderNotificationsEnabled
        self.eventNotificationsEnabled = eventNotificationsEnabled
    }
}

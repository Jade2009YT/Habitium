//
//  AppConfiguration.swift
//  Habitium
//
//  Central, typed access to build-time configuration (API keys, App Group
//  identifier). Real values live in the gitignored
//  Configuration/Secrets.xcconfig and reach the app through Info.plist
//  placeholders defined in project.yml — nothing sensitive is hardcoded or
//  committed to source control.
//

import Foundation

enum AppConfiguration {

    /// Thrown when a required configuration value is missing or still set
    /// to its placeholder, so callers can fail loudly instead of silently
    /// hitting the network with an empty key.
    enum ConfigurationError: LocalizedError {
        case missingValue(String)

        var errorDescription: String? {
            switch self {
            case .missingValue(let key):
                return "Falta configurar '\(key)'. Copia Configuration/Secrets.example.xcconfig a Secrets.xcconfig y define tu clave."
            }
        }
    }

    static var openAIAPIKey: String? {
        nonPlaceholderValue(forInfoDictionaryKey: "OPENAI_API_KEY")
    }

    static var anthropicAPIKey: String? {
        nonPlaceholderValue(forInfoDictionaryKey: "ANTHROPIC_API_KEY")
    }

    /// App Group identifier shared with the widget extension, used for both
    /// the SwiftData store's group container and the UserDefaults suite
    /// that feeds widget timelines. Defined once in Shared/AppGroup.swift
    /// so both targets agree on it.
    static var appGroupID: String { AppGroup.identifier }

    private static func nonPlaceholderValue(forInfoDictionaryKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.lowercased().contains("your_") else {
            return nil
        }
        return value
    }
}

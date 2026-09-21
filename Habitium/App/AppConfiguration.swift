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

    /// Las claves de IA ya NO se leen del Info.plist.
    ///
    /// Estaban ahí para poder compilar la app con la clave metida
    /// dentro, y eso significaba que la clave viajaba en el paquete: se
    /// descomprime la app, se abre Info.plist, y ahí está en texto
    /// plano. No hace falta romper nada.
    ///
    /// Ahora cada usuario escribe la suya en Ajustes y se guarda en el
    /// Llavero (ver `AIKeyStore`), cifrada por el sistema, ligada a este
    /// dispositivo y fuera de las copias de seguridad de iCloud.
    ///
    /// Se devuelven nil, y no se borran, para que el resto del código
    /// siga compilando sin cambios y AIKeyStore pueda seguir tratándolas
    /// como "el respaldo que ya no existe".
    static var openAIAPIKey: String? { nil }
    static var anthropicAPIKey: String? { nil }

    /// Supabase project URL, reassembled from two build settings because
    /// xcconfig treats "//" as a comment marker — see Secrets.example.xcconfig.
    /// Nil (not just empty) whenever either half is missing/placeholder, so
    /// SupabaseAuthManager can tell "not configured yet" from "configured".
    static var supabaseURL: URL? {
        guard let scheme = nonPlaceholderValue(forInfoDictionaryKey: "SUPABASE_URL_SCHEME"),
              let host = nonPlaceholderValue(forInfoDictionaryKey: "SUPABASE_URL_HOST") else {
            return nil
        }
        return URL(string: "\(scheme)://\(host)")
    }

    static var supabaseAnonKey: String? {
        nonPlaceholderValue(forInfoDictionaryKey: "SUPABASE_ANON_KEY")
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

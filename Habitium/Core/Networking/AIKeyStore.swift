//
//  AIKeyStore.swift
//  Habitium
//
//  La clave de IA de cada usuario, guardada en el Llavero.
//
//  Hasta ahora la clave solo podía venir de `Configuration/Secrets.xcconfig`,
//  es decir, de quien compila la app. Eso vale para el que la construye y
//  para nadie más: un amigo que la instale, o tú mismo desde la web, se
//  quedaban sin análisis de comidas y sin forma de arreglarlo desde
//  dentro de la app.
//
//  Tres decisiones sobre dónde vive la clave, y por qué:
//
//  1. **En el Llavero, no en UserDefaults.** UserDefaults es un plist en
//     claro dentro del contenedor de la app: cualquier copia de seguridad
//     sin cifrar lo lleva legible. El Llavero está cifrado por el sistema
//     y ligado al dispositivo.
//  2. **NUNCA en Supabase.** Es la regla que ya seguía el resto del
//     proyecto y no cambia: una clave de API en una tabla es una clave
//     que viaja por la red, se replica en copias de seguridad y acaba en
//     un volcado. Si alguien la saca, la factura la pagas tú. Por eso la
//     clave no se sincroniza entre dispositivos: hay que ponerla en cada
//     uno, y ese es el precio correcto.
//  3. **La del xcconfig sigue valiendo como respaldo.** Si compilaste la
//     app con tu clave, todo sigue funcionando sin tocar nada; la del
//     Llavero solo manda cuando existe.
//

import Foundation

enum AIKeyStore {

    private static func keychainKey(for provider: AIProviderKind) -> String {
        "habitium.aikey.\(provider.rawValue)"
    }

    /// La clave a usar: primero la que haya puesto el usuario, y si no la
    /// que venga de la compilación.
    static func key(for provider: AIProviderKind) -> String? {
        if let propia = userKey(for: provider) { return propia }
        switch provider {
        case .openAI: return AppConfiguration.openAIAPIKey
        case .claude: return AppConfiguration.anthropicAPIKey
        }
    }

    /// Solo la que ha escrito el usuario, sin el respaldo de compilación.
    static func userKey(for provider: AIProviderKind) -> String? {
        guard let valor = KeychainStore.read(forKey: keychainKey(for: provider)),
              !valor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return valor
    }

    /// Devuelve si se guardó de verdad, para que Ajustes no diga
    /// "Guardada ✓" sobre algo que el Llavero rechazó.
    @discardableResult
    static func setUserKey(_ value: String?, for provider: AIProviderKind) -> Bool {
        let limpio = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if limpio.isEmpty {
            KeychainStore.delete(forKey: keychainKey(for: provider))
            return true
        }
        return KeychainStore.save(limpio, forKey: keychainKey(for: provider))
    }

    static func hasKey(for provider: AIProviderKind) -> Bool { key(for: provider) != nil }

    /// De dónde sale la clave que se está usando — para poder decirlo en
    /// Ajustes en vez de dejar un campo vacío que no explica nada.
    enum Source {
        case user
        case build
        case none

        var explanation: String {
            switch self {
            case .user: return "Estás usando tu propia clave, guardada en el Llavero de este iPhone."
            case .build: return "Usando la clave con la que se compiló la app. Puedes poner la tuya aquí."
            case .none: return "Sin clave, el análisis por foto no funciona. Puedes apuntar las comidas a mano igual."
            }
        }
    }

    static func source(for provider: AIProviderKind) -> Source {
        if userKey(for: provider) != nil { return .user }
        switch provider {
        case .openAI: return AppConfiguration.openAIAPIKey != nil ? .build : .none
        case .claude: return AppConfiguration.anthropicAPIKey != nil ? .build : .none
        }
    }

    /// Enseña solo el principio y el final: lo justo para reconocer cuál
    /// pusiste sin dejar la clave entera a la vista de quien mire por
    /// encima del hombro.
    static func masked(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "•", count: max(key.count, 4)) }
        return "\(key.prefix(6))••••••\(key.suffix(4))"
    }

    /// Dónde conseguir la clave, para no dejar a nadie buscando a ciegas.
    static func helpURL(for provider: AIProviderKind) -> URL? {
        switch provider {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        }
    }
}

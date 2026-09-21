//
//  KeychainStore.swift
//  Habitium
//
//  Minimal Keychain wrapper. Two things live here:
//  - The Sign in with Apple stable user identifier (a String).
//  - The Secure Enclave key's Keychain reference blob (raw Data), used by
//    SecureEnclaveCrypto to protect meal photos.
//  Everything else (display name, email, preferences) lives in SwiftData
//  since it's not sensitive and benefits from being queryable with the
//  rest of the app's data.
//
//  Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly: the strongest
//  "normal" accessibility class — readable only while the device is
//  unlocked, and never included in an iCloud Keychain backup/migration to
//  another device (ThisDeviceOnly), so a restored backup on someone
//  else's device never carries these over.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.habitium.app.auth"

    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        saveData(Data(value.utf8), forKey: key)
    }

    static func read(forKey key: String) -> String? {
        guard let data = readData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Devuelve si de verdad se guardó.
    ///
    /// Antes se ignoraba el resultado de `SecItemAdd`. Un fallo del
    /// Llavero es raro pero pasa (el dispositivo bloqueado en mitad de la
    /// escritura, por ejemplo), y al ignorarlo la app decía "Guardada ✓"
    /// sobre una clave que no existía: el usuario se queda convencido de
    /// que su clave está puesta y el análisis de comidas no funciona sin
    /// que nadie entienda por qué.
    @discardableResult
    static func saveData(_ data: Data, forKey key: String) -> Bool {
        let query = baseQuery(forKey: key)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func readData(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    static func delete(forKey key: String) {
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

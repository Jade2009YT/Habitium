//
//  SecureEnclaveCrypto.swift
//  Habitium
//
//  Envelope encryption for the most sensitive blobs Habitium stores —
//  right now, meal photos (FoodEntry.imageData). The actual encryption
//  key never exists outside the Secure Enclave chip, and never leaves it,
//  which is the strongest key protection iOS offers.
//
//  How it works (standard ECIES-style pattern for Secure Enclave, since
//  the Enclave can only do elliptic-curve key agreement, not direct
//  encryption):
//  1. On first use, generate a P-256 key pair *inside* the Secure Enclave,
//     gated by biometrics (`.biometryCurrentSet`). Only a small Keychain
//     reference to it is ever touched in software.
//  2. To encrypt: create a throwaway ("ephemeral") software key pair,
//     derive a one-time AES key via ECDH with the Enclave key's *public*
//     half (public keys don't need authentication), seal the data with
//     AES-GCM, and store [ephemeral public key || ciphertext] together.
//     Saving a meal photo never prompts Face ID.
//  3. To decrypt: redo the ECDH, this time using the Enclave's *private*
//     half — which does require Face ID/Touch ID, exactly when the user
//     actually asks to see a saved photo.
//

import CryptoKit
import Foundation

enum SecureEnclaveCryptoError: LocalizedError {
    case unavailable
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Este dispositivo no tiene Secure Enclave disponible."
        case .malformedPayload: return "No se pudo leer el contenido cifrado."
        }
    }
}

final class SecureEnclaveCrypto {

    static let shared = SecureEnclaveCrypto()

    private static let keychainKey = "secureEnclave.mealPhotoKey"
    /// Uncompressed P-256 public key representation length (0x04 prefix + 32-byte X + 32-byte Y).
    private static let publicKeyByteCount = 65

    private var cachedKey: SecureEnclave.P256.KeyAgreement.PrivateKey?
    /// encrypt() runs on the caller's thread (fast, no biometric prompt);
    /// decrypt() is meant to be called from a background task (see
    /// NutritionRepository.decryptedPhoto) since the Face ID prompt it
    /// triggers blocks the calling thread until resolved. This lock just
    /// keeps `cachedKey` consistent if both happen to overlap.
    private let lock = NSLock()

    private init() {}

    /// Encrypts `plaintext`. Uses only the Enclave key's public half, so
    /// this never triggers a biometric prompt.
    func encrypt(_ plaintext: Data) throws -> Data {
        let enclaveKey = try loadOrCreateKey()
        let ephemeralKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: enclaveKey.publicKey)
        let symmetricKey = Self.deriveSymmetricKey(from: sharedSecret)

        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else { throw SecureEnclaveCryptoError.malformedPayload }

        var payload = ephemeralKey.publicKey.rawRepresentation
        payload.append(combined)
        return payload
    }

    /// Decrypts a payload produced by `encrypt(_:)`. Uses the Enclave
    /// key's private half via ECDH, which prompts Face ID/Touch ID.
    func decrypt(_ payload: Data) throws -> Data {
        guard payload.count > Self.publicKeyByteCount else { throw SecureEnclaveCryptoError.malformedPayload }

        let enclaveKey = try loadOrCreateKey()
        let ephemeralPublicKeyData = payload.prefix(Self.publicKeyByteCount)
        let combined = payload.suffix(from: payload.startIndex + Self.publicKeyByteCount)

        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKeyData)
        let sharedSecret = try enclaveKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        let symmetricKey = Self.deriveSymmetricKey(from: sharedSecret)

        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    // MARK: - Key management

    private func loadOrCreateKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        lock.lock()
        defer { lock.unlock() }

        if let cachedKey { return cachedKey }

        if let storedReference = KeychainStore.readData(forKey: Self.keychainKey) {
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: storedReference)
            cachedKey = key
            return key
        }

        guard SecureEnclave.isAvailable else { throw SecureEnclaveCryptoError.unavailable }

        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &accessError
        ) else {
            throw accessError?.takeRetainedValue() ?? SecureEnclaveCryptoError.unavailable
        }

        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: accessControl)
        KeychainStore.saveData(key.dataRepresentation, forKey: Self.keychainKey)
        cachedKey = key
        return key
    }

    private static func deriveSymmetricKey(from sharedSecret: SharedSecret) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("habitium.mealPhoto.v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }
}

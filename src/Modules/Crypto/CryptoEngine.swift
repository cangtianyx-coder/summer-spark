import Foundation
import CryptoKit

/// E2E encryption engine using ECDSA signatures + AES-256-GCM
/// Singleton: use CryptoEngine.shared
final class CryptoEngine {

    static let shared = CryptoEngine()

    private init() {}

    // MARK: - Key Generation

    /// Generate a new P-256 private key for signing
    func generateSigningKey() -> P256.Signing.PrivateKey {
        return P256.Signing.PrivateKey()
    }

    /// Derive public key from a signing private key
    func derivePublicKey(from signingKey: P256.Signing.PrivateKey) -> P256.Signing.PublicKey {
        return signingKey.publicKey
    }

    /// Generate a random AES-256 symmetric key
    func generateSymmetricKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }

    // MARK: - ECDSA Signing

    /// Sign data using ECDSA P-256 with SHA-256
    func sign(data: Data, privateKey: P256.Signing.PrivateKey) -> Data {
        guard let signature = try? privateKey.signature(for: data) else {
            return Data()
        }
        return signature.derRepresentation
    }

    /// Verify an ECDSA P-256 signature
    func verify(signature: Data, data: Data, publicKey: P256.Signing.PublicKey) -> Bool {
        guard let sig = try? P256.Signing.ECDSASignature(derRepresentation: signature) else {
            return false
        }
        return publicKey.isValidSignature(sig, for: data)
    }

    // MARK: - AES-256-GCM Encryption

    /// Encrypt data with AES-256-GCM (produces nonce+ciphertext+tag)
    func encryptAESGCM(data: Data, symmetricKey: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw CryptoEngineError.encryptionFailed
        }
        return combined
    }

    /// Decrypt data with AES-256-GCM
    func decryptAESGCM(encryptedData: Data, symmetricKey: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    // MARK: - Combined Operations: Encrypt + Sign

    /// Encrypt data with AES-256-GCM and sign the plaintext with ECDSA
    /// Returns: [ephemeralPubKey(65) || nonce(12) || ciphertext || tag(16) || signature(64)]
    func encryptAndSign(
        plaintext: Data,
        recipientPublicKey: P256.KeyAgreement.PublicKey,
        senderSigningKey: P256.Signing.PrivateKey
    ) throws -> Data {
        // Generate ephemeral symmetric key for this message
        let ephemeralKey = P256.KeyAgreement.PrivateKey()
        let ephemeralPublicKeyData = ephemeralKey.publicKey.rawRepresentation

        // Derive shared secret using ECDH
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)

        // Derive AES key from shared secret using HKDF
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "E2E-AES-256-GCM".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Encrypt plaintext with AES-256-GCM
        let encryptedData = try encryptAESGCM(data: plaintext, symmetricKey: symmetricKey)

        // Sign the plaintext
        let signature = sign(data: plaintext, privateKey: senderSigningKey)

        // Assemble: [ephemeralPubKey(65) || encryptedData || signature(64)]
        var result = Data()
        result.append(ephemeralPublicKeyData)
        result.append(encryptedData)
        result.append(signature)

        return result
    }

    /// Decrypt data and verify ECDSA signature
    /// Input: [ephemeralPubKey(65) || nonce(12) || ciphertext || tag(16) || signature(64)]
    func decryptAndVerify(
        encryptedPackage: Data,
        senderPublicKey: P256.Signing.PublicKey,
        recipientKeyAgreementKey: P256.KeyAgreement.PrivateKey
    ) throws -> Data {
        // Parse components
        // P-256 public key for key agreement is 65 bytes (uncompressed format: 04 || x || y)
        let ephemeralPubKeyData = encryptedPackage.prefix(65)
        let signatureLength = 64  // ECDSA P-256 DER signature is variable but we use raw r||s format

        guard encryptedPackage.count > 65 + 12 + 16 + 64 else {
            throw CryptoEngineError.invalidPackageFormat
        }

        let signature = encryptedPackage.suffix(64)
        let encryptedData = encryptedPackage.dropFirst(65).dropLast(64)

        // Reconstruct ephemeral public key
        guard let ephemeralPubKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: ephemeralPubKeyData) else {
            throw CryptoEngineError.invalidPublicKey
        }

        // Derive shared secret via ECDH
        let sharedSecret = try recipientKeyAgreementKey.sharedSecretFromKeyAgreement(with: ephemeralPubKey)

        // Derive AES key
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "E2E-AES-256-GCM".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Decrypt
        let plaintext = try decryptAESGCM(encryptedData: Data(encryptedData), symmetricKey: symmetricKey)

        // Verify signature on plaintext
        guard verify(signature: Data(signature), data: plaintext, publicKey: senderPublicKey) else {
            throw CryptoEngineError.signatureVerificationFailed
        }

        return plaintext
    }

    // MARK: - Key Serialization

    /// Serialize private key for storage (NOT recommended for production — use Keychain)
    func serializePrivateKey(_ key: P256.Signing.PrivateKey) -> Data {
        return key.rawRepresentation
    }

    /// Deserialize private key from storage
    func deserializeSigningPrivateKey(_ data: Data) throws -> P256.Signing.PrivateKey {
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    /// Serialize public key
    func serializePublicKey(_ key: P256.Signing.PublicKey) -> Data {
        return key.rawRepresentation
    }

    /// Deserialize public key
    func deserializePublicKey(_ data: Data) throws -> P256.Signing.PublicKey {
        return try P256.Signing.PublicKey(rawRepresentation: data)
    }

    /// Serialize key agreement private key
    func serializeKeyAgreementPrivateKey(_ key: P256.KeyAgreement.PrivateKey) -> Data {
        return key.rawRepresentation
    }

    /// Deserialize key agreement private key
    func deserializeKeyAgreementPrivateKey(_ data: Data) throws -> P256.KeyAgreement.PrivateKey {
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }
}

// MARK: - Error Types

enum CryptoEngineError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidPackageFormat
    case invalidPublicKey
    case signatureVerificationFailed
    case keyDeserializationFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Decryption failed"
        case .invalidPackageFormat: return "Invalid encrypted package format"
        case .invalidPublicKey: return "Invalid public key data"
        case .signatureVerificationFailed: return "Signature verification failed"
        case .keyDeserializationFailed: return "Key deserialization failed"
        }
    }
}
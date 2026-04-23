import Foundation
import Security

enum SecureEnclaveError: Error {
    case keyCreationFailed
    case signingFailed
    case verificationFailed
    case invalidKey
    case keyNotFound
    case unexpectedStatus(OSStatus)
}

final class SecureEnclaveManager {
    static let shared = SecureEnclaveManager()

    private let service = "com.summer.spark.secureenclave"

    private init() {}

    func createKeyPair(tag: String, ellipticCurve: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256) throws -> SecKey {
        let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            nil
        )

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
                kSecAttrAccessControl as String: access as Any
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let err = error?.takeRetainedValue() {
                Logger.shared.error("Key creation error: \(err)")
            }
            throw SecureEnclaveError.keyCreationFailed
        }

        return privateKey
    }

    func getPrivateKey(tag: String) throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw SecureEnclaveError.keyNotFound
            }
            throw SecureEnclaveError.unexpectedStatus(status)
        }

        return result as! SecKey
    }

    func sign(data: Data, tag: String) throws -> Data {
        let privateKey = try getPrivateKey(tag: tag)

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, .ecdsaSignatureMessageX962SHA256) else {
            throw SecureEnclaveError.invalidKey
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) else {
            throw SecureEnclaveError.signingFailed
        }

        return signature as Data
    }

    func verify(data: Data, signature: Data, tag: String) throws -> Bool {
        let privateKey = try getPrivateKey(tag: tag)

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecureEnclaveError.invalidKey
        }

        guard SecKeyIsAlgorithmSupported(publicKey, .verify, .ecdsaSignatureMessageX962SHA256) else {
            throw SecureEnclaveError.invalidKey
        }

        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            signature as CFData,
            &error
        )

        return result
    }

    func deleteKey(tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureEnclaveError.unexpectedStatus(status)
        }
    }

    func createKeyPairIfNeeded(tag: String) throws -> SecKey {
        do {
            return try getPrivateKey(tag: tag)
        } catch SecureEnclaveError.keyNotFound {
            return try createKeyPair(tag: tag)
        }
    }
}
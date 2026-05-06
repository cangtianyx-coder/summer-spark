import Foundation
import Security
import CryptoKit

enum KeychainError: Error {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case encodingError
    case decodingError
    case secureEnclaveNotAvailable
}

final class KeychainHelper {
    static let shared = KeychainHelper()

    private let isSecureEnclaveAvailable: Bool

    private init() {
        // Check if Secure Enclave is available (not available in simulator)
        isSecureEnclaveAvailable = SecureEnclave.isAvailable
    }

    // MARK: - Secure Enclave Key Storage (for private keys)

    /// Save private key to Secure Enclave (hardware-backed)
    /// NOTE: True Secure Enclave requires generating key IN the Secure Enclave using SecKeyCreateRandomKey
    /// This method stores the key with strong access controls for device-only protection
    func savePrivateKeyToSecureEnclave(_ privateKey: P256.Signing.PrivateKey, tag: String) throws {
        let tagData = tag.data(using: .utf8)!

        // Delete existing key with same tag
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Create access control for Secure Enclave with device-only and no-backup flags
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        ) else {
            throw KeychainError.secureEnclaveNotAvailable
        }

        // Store key data with Secure Enclave access control
        let keyData = privateKey.rawRepresentation

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.summerspark.secureenclave",
            kSecAttrAccount as String: tag,
            kSecValueData as String: keyData,
            kSecAttrAccessControl as String: accessControl,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
            kSecAttrIsSensitive as String: kCFBooleanTrue!
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Generate a new P-256 key directly in Secure Enclave (hardware-protected)
    func generateSecureEnclaveKey(tag: String) throws -> SecKey? {
        guard isSecureEnclaveAvailable else {
            return nil
        }

        let tagData = tag.data(using: .utf8)!

        // Delete existing key
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Create Secure Enclave key attributes
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeychainError.secureEnclaveNotAvailable
        }

        return privateKey
    }

    /// Load private key from Secure Enclave
    func loadPrivateKeyFromSecureEnclave(tag: String) throws -> P256.Signing.PrivateKey? {
        let tagData = tag.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.summerspark.secureenclave",
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let keyData = result as? Data else {
            throw KeychainError.decodingError
        }

        return try? P256.Signing.PrivateKey(rawRepresentation: keyData)
    }

    /// Delete private key from Secure Enclave
    func deletePrivateKeyFromSecureEnclave(tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.summerspark.secureenclave",
            kSecAttrAccount as String: tag
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Regular Keychain Storage (for non-key data)

    func save(data: Data, service: String, account: String) throws {
        // Delete any existing item first to avoid duplicates
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Save with accessibility set to WhenUnlockedThisDeviceOnly (not backed up)
        // Prevent iCloud Keychain sync to protect sensitive data
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func load(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.decodingError
        }

        return data
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func saveString(_ string: String, service: String, account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingError
        }
        try save(data: data, service: service, account: account)
    }

    func loadString(service: String, account: String) throws -> String {
        let data = try load(service: service, account: account)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingError
        }
        return string
    }
}
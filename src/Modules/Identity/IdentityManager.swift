import Foundation
import CryptoKit

/// Manages local identity: UID, username, public/private key pair, and public key fingerprint
/// Singleton: use IdentityManager.shared
final class IdentityManager {
    static let shared = IdentityManager()

    // MARK: - Stored Properties

    private(set) var uid: String?
    private(set) var username: String?

    private var signingPrivateKey: P256.Signing.PrivateKey?
    private var signingPublicKey: P256.Signing.PublicKey?

    // MARK: - Initialization

    private init() {
        loadOrCreateIdentity()
    }

    // MARK: - Identity Creation / Loading

    /// Load existing identity from Keychain or create a new one
    private func loadOrCreateIdentity() {
        // Load UID and username from UserDefaults (non-sensitive)
        uid = UserDefaults.standard.string(forKey: "identity.uid")
        username = UserDefaults.standard.string(forKey: "identity.username")

        // Load private key from Keychain (secure storage)
        do {
            let privateKeyData = try KeychainHelper.shared.load(
                service: KeychainKeys.service,
                account: KeychainKeys.privateKey
            )
            signingPrivateKey = try? P256.Signing.PrivateKey(rawRepresentation: privateKeyData)
            signingPublicKey = signingPrivateKey?.publicKey
        } catch {
            // Key not found or corrupted - will regenerate below
            signingPrivateKey = nil
            signingPublicKey = nil
        }

        // If any identity component is missing, generate new identity
        if uid == nil || signingPrivateKey == nil {
            regenerateIdentity()
        }
    }

    /// Regenerate all identity components (UID, keys)
    func regenerateIdentity() {
        // Generate new UID
        uid = UIDGenerator.shared.generateUID()

        // Generate new ECDSA P-256 key pair
        let privateKey = P256.Signing.PrivateKey()
        signingPrivateKey = privateKey
        signingPublicKey = privateKey.publicKey

        // Persist
        saveIdentity()
    }

    // MARK: - Persistence

    private func saveIdentity() {
        // UID and username (non-sensitive) in UserDefaults
        UserDefaults.standard.set(uid, forKey: "identity.uid")
        UserDefaults.standard.set(username, forKey: "identity.username")

        // Private key (sensitive) in Keychain with device-only accessibility
        if let privateKey = signingPrivateKey {
            try? KeychainHelper.shared.save(
                data: privateKey.rawRepresentation,
                service: KeychainKeys.service,
                account: KeychainKeys.privateKey
            )
        }
    }

    // MARK: - Username
    
    /// 验证并设置用户名（带格式验证）
    /// - Parameter name: 新用户名
    /// - Returns: 验证结果
    @discardableResult
    func validateAndSetUsername(_ name: String) -> UsernameValidationResult {
        let result = UsernameValidator.shared.validateFormat(name)
        guard result.isValid else {
            return result
        }
        
        username = name
        UserDefaults.standard.set(name, forKey: "identity.username")
        return .valid
    }
    
    /// 设置用户名（旧接口，保留兼容）
    func setUsername(_ name: String) {
        username = name
        UserDefaults.standard.set(name, forKey: "identity.username")
    }
    
    /// 检查用户名在Mesh网络中是否可用
    /// - Parameters:
    ///   - name: 待检查的用户名
    ///   - completion: 结果回调
    func checkUsernameAvailability(
        _ name: String,
        completion: @escaping (UsernameConflictResult) -> Void
    ) {
        UsernameValidator.shared.checkAvailability(name, completion: completion)
    }
    
    /// 获取默认用户名（萤火用户_XXXX）
    var defaultUsername: String {
        let uidPrefix = uid?.prefix(4) ?? "0000"
        return "萤火用户_\(uidPrefix)"
    }
    
    /// 确保用户名已设置（未设置则使用默认值）
    func ensureUsernameSet() {
        if username == nil || username?.isEmpty == true {
            username = defaultUsername
            UserDefaults.standard.set(username, forKey: "identity.username")
        }
    }

    // MARK: - Key Access

    /// Get the signing private key
    func getPrivateKey() -> P256.Signing.PrivateKey? {
        return signingPrivateKey
    }

    /// Get the signing public key
    func getPublicKey() -> P256.Signing.PublicKey? {
        return signingPublicKey
    }

    /// Get public key as raw Data
    func getPublicKeyData() -> Data? {
        return signingPublicKey?.rawRepresentation
    }

    /// Get public key as DER-encoded Data
    func getPublicKeyDER() -> Data? {
        guard let publicKey = signingPublicKey else { return nil }
        return publicKey.derRepresentation
    }

    // MARK: - Public Key Fingerprint

    /// Get SHA256 fingerprint of the public key (first 16 hex chars, like SSH)
    func getPublicKeyFingerprint() -> String? {
        guard let publicKeyData = getPublicKeyData() else { return nil }
        let hash = SHA256.hash(data: publicKeyData)
        let hexString = hash.map { String(format: "%02x", $0) }.joined()
        return String(hexString.prefix(16))
    }

    /// Get full SHA256 fingerprint (32 hex chars)
    func getFullPublicKeyFingerprint() -> String? {
        guard let publicKeyData = getPublicKeyData() else { return nil }
        let hash = SHA256.hash(data: publicKeyData)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Serialization

    /// Export identity as a dictionary (for sharing/profiling)
    func exportIdentity() -> [String: Any] {
        var dict: [String: Any] = [:]

        if let uid = uid { dict["uid"] = uid }
        if let username = username { dict["username"] = username }
        if let publicKeyData = getPublicKeyData() { dict["publicKey"] = publicKeyData.base64EncodedString() }
        if let fingerprint = getPublicKeyFingerprint() { dict["fingerprint"] = fingerprint }

        return dict
    }

    /// Export public identity (safe to share)
    func exportPublicIdentity() -> [String: Any] {
        var dict: [String: Any] = [:]

        if let uid = uid { dict["uid"] = uid }
        if let username = username { dict["username"] = username }
        if let publicKeyData = getPublicKeyData() { dict["publicKey"] = publicKeyData.base64EncodedString() }
        if let fingerprint = getPublicKeyFingerprint() { dict["fingerprint"] = fingerprint }

        return dict
    }

    // MARK: - Reset

    /// Clear all identity data and regenerate
    func resetIdentity() {
        UserDefaults.standard.removeObject(forKey: "identity.uid")
        UserDefaults.standard.removeObject(forKey: "identity.username")
        UserDefaults.standard.removeObject(forKey: "identity.privateKey")

        uid = nil
        username = nil
        signingPrivateKey = nil
        signingPublicKey = nil

        regenerateIdentity()
    }
}

// MARK: - Convenience Extensions

extension IdentityManager {

    /// Check if identity is complete (has UID and key pair)
    var isIdentityComplete: Bool {
        return uid != nil && signingPrivateKey != nil && signingPublicKey != nil
    }

    /// Get a short display name (username or UID prefix)
    var displayName: String {
        return username ?? uid?.prefix(8).description ?? "Unknown"
    }
}

// MARK: - Stub Methods for SummerSpark Compilation

extension IdentityManager {
    func initialize() {
        // Stub for SummerSpark compilation
    }

    func updatePushToken(_ token: String) {
        // Stub for SummerSpark compilation
        UserDefaults.standard.set(token, forKey: "identity.pushToken")
    }
}

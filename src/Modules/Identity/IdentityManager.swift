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
        // Load UID and username from Keychain (secure storage)
        do {
            if let uidData = try? KeychainHelper.shared.load(
                service: KeychainKeys.service,
                account: KeychainKeys.uid
            ) {
                uid = String(data: uidData, encoding: .utf8)
            }
        }
        
        do {
            if let usernameData = try? KeychainHelper.shared.load(
                service: KeychainKeys.service,
                account: KeychainKeys.username
            ) {
                username = String(data: usernameData, encoding: .utf8)
            }
        }

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
        // UID and username (sensitive) in Keychain for secure storage
        if let uid = uid, let uidData = uid.data(using: .utf8) {
            try? KeychainHelper.shared.save(
                data: uidData,
                service: KeychainKeys.service,
                account: KeychainKeys.uid
            )
        }
        
        if let username = username, let usernameData = username.data(using: .utf8) {
            try? KeychainHelper.shared.save(
                data: usernameData,
                service: KeychainKeys.service,
                account: KeychainKeys.username
            )
        }

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
        // 使用Keychain安全存储
        if let usernameData = name.data(using: .utf8) {
            try? KeychainHelper.shared.save(
                data: usernameData,
                service: KeychainKeys.service,
                account: KeychainKeys.username
            )
        }
        return .valid
    }
    
    /// 设置用户名（旧接口，保留兼容）
    func setUsername(_ name: String) {
        username = name
        // 使用Keychain安全存储
        if let usernameData = name.data(using: .utf8) {
            try? KeychainHelper.shared.save(
                data: usernameData,
                service: KeychainKeys.service,
                account: KeychainKeys.username
            )
        }
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
            // 使用Keychain安全存储
            if let usernameData = username?.data(using: .utf8) {
                try? KeychainHelper.shared.save(
                    data: usernameData,
                    service: KeychainKeys.service,
                    account: KeychainKeys.username
                )
            }
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
    
    // P0-FIX: 获取CA公钥用于验证证书
    /// Get CA public key for certificate verification
    /// In a mesh network, each node acts as its own CA for simplicity
    /// In production, this could be a designated CA node's public key
    func getCAPublicKey() -> P256.Signing.PublicKey? {
        // 方案1: 使用本地公钥作为CA（自签名模式）
        return getPublicKey()
        
        // 方案2: 从网络获取指定CA节点的公钥（生产环境）
        // if let caNodeId = caNodeId, let caPublicKey = MeshService.shared.getPublicKey(for: caNodeId) {
        //     return caPublicKey
        // }
        // return nil
    }
    
    /// Get public key for a specific user ID (for group key encryption)
    func getPublicKey(for uid: String) -> P256.Signing.PublicKey? {
        // 从MeshService获取该用户的公钥
        if let nodeId = UUID(uuidString: uid),
           let publicKey = MeshService.shared.getPublicKey(for: nodeId) {
            return publicKey
        }
        // 如果是本地用户，返回本地公钥
        if uid == self.uid {
            return getPublicKey()
        }
        return nil
    }
    
    // P0-FIX: 获取用于密钥协商的私钥
    /// Get private key for key agreement
    func getPrivateKeyForAgreement() -> P256.KeyAgreement.PrivateKey? {
        // 从Keychain获取私钥数据
        guard let privateKeyData = try? KeychainHelper.shared.load(
            service: "com.summerspark.identity",
            account: "privateKey"
        ) else {
            return nil
        }
        // 解析为密钥协商私钥
        return try? P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
    }
    
    // P0-FIX: 获取用于签名的私钥
    /// Get private key for signing
    func getPrivateKeyForSigning() -> P256.Signing.PrivateKey? {
        // 从Keychain获取私钥数据
        guard let privateKeyData = try? KeychainHelper.shared.load(
            service: "com.summerspark.identity",
            account: "privateKey"
        ) else {
            return nil
        }
        // 解析为签名私钥
        return try? P256.Signing.PrivateKey(rawRepresentation: privateKeyData)
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
        // 清理Keychain中的所有身份数据
        try? KeychainHelper.shared.delete(
            service: KeychainKeys.service,
            account: KeychainKeys.uid
        )
        try? KeychainHelper.shared.delete(
            service: KeychainKeys.service,
            account: KeychainKeys.username
        )
        try? KeychainHelper.shared.delete(
            service: KeychainKeys.service,
            account: KeychainKeys.privateKey
        )

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

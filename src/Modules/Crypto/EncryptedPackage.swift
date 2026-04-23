import Foundation
import CryptoKit

/// Encrypted package structure for secure message transmission
/// P1-FIX: 元数据加密保护，防止流量分析
struct EncryptedPackage {
    /// P1-FIX: 加密的发送者/接收者信息（不再明文）
    /// 格式: AES-GCM加密的JSON {senderUID, receiverUID, timestamp}
    var encryptedMetadata: Data
    
    /// Encrypted message data (AES-256-GCM encrypted content)
    var encryptedData: Data
    
    /// RSA-encrypted AES session key
    var encryptedKey: Data
    
    /// Digital signature (ECDSA over message hash)
    var signature: Data
    
    /// P1-FIX: 加密的时间戳（不再明文）
    var encryptedTimestamp: Data
    
    /// Time-to-live in seconds (非敏感，保留明文用于路由决策)
    var ttl: Int
    
    /// Whether the receiver is a group (非敏感)
    var isGroup: Bool
    
    /// P1-FIX: 加密的群组ID
    var encryptedGroupID: Data?
    
    // MARK: - 辅助方法
    
    /// 创建加密包（隐藏元数据）
    static func create(
        senderUID: String,
        receiverUID: String,
        encryptedData: Data,
        encryptedKey: Data,
        signature: Data,
        timestamp: Int64,
        ttl: Int,
        isGroup: Bool,
        groupID: String?,
        metadataKey: SymmetricKey
    ) throws -> EncryptedPackage {
        // 加密元数据
        let metadata = Metadata(
            senderUID: senderUID,
            receiverUID: receiverUID
        )
        let metadataJSON = try JSONEncoder().encode(metadata)
        let encryptedMetadata = try AES.GCM.seal(metadataJSON, using: metadataKey).combined!
        
        // 加密时间戳
        let timestampData = withUnsafeBytes(of: timestamp) { Data($0) }
        let encryptedTimestamp = try AES.GCM.seal(timestampData, using: metadataKey).combined!
        
        // 加密群组ID
        var encryptedGroupID: Data? = nil
        if let groupID = groupID {
            let groupIDData = groupID.data(using: .utf8) ?? Data()
            encryptedGroupID = try AES.GCM.seal(groupIDData, using: metadataKey).combined!
        }
        
        return EncryptedPackage(
            encryptedMetadata: encryptedMetadata,
            encryptedData: encryptedData,
            encryptedKey: encryptedKey,
            signature: signature,
            encryptedTimestamp: encryptedTimestamp,
            ttl: ttl,
            isGroup: isGroup,
            encryptedGroupID: encryptedGroupID
        )
    }
    
    /// 解密元数据
    func decryptMetadata(using key: SymmetricKey) throws -> (senderUID: String, receiverUID: String) {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedMetadata)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        let metadata = try JSONDecoder().decode(Metadata.self, from: decryptedData)
        return (metadata.senderUID, metadata.receiverUID)
    }
    
    /// 解密时间戳
    func decryptTimestamp(using key: SymmetricKey) throws -> Int64 {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedTimestamp)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        return decryptedData.withUnsafeBytes { $0.load(as: Int64.self) }
    }
    
    /// 解密群组ID
    func decryptGroupID(using key: SymmetricKey) throws -> String? {
        guard let encrypted = encryptedGroupID else { return nil }
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        return String(data: decryptedData, encoding: .utf8)
    }
    
    // MARK: - 内部类型
    
    private struct Metadata: Codable {
        let senderUID: String
        let receiverUID: String
    }
}
import Foundation

/// Encrypted package structure for secure message transmission
struct EncryptedPackage {
    /// Sender user identifier
    var senderUID: String

    /// Receiver user identifier
    var receiverUID: String

    /// Encrypted message data (AES-256-GCM encrypted content)
    var encryptedData: Data

    /// RSA-encrypted AES session key
    var encryptedKey: Data

    /// Digital signature (ECDSA over message hash)
    var signature: Data

    /// Package creation timestamp (Unix epoch milliseconds)
    var timestamp: Int64

    /// Time-to-live in seconds
    var ttl: Int

    /// Whether the receiver is a group
    var isGroup: Bool

    /// Group identifier (valid when isGroup is true)
    var groupID: String?
}
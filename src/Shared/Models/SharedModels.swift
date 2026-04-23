import Foundation
import CryptoKit

// MARK: - MeshNode

struct MeshNode: Identifiable, Equatable {
    let id: UUID
    var name: String
    var lastSeen: Date
    var rssi: Int
    var connectionState: ConnectionState
    var supportedMedia: Set<TransportMedium>
    var address: String
    // P0-FIX: 添加公钥属性用于加密通信
    var publicKey: P256.Signing.PublicKey? = nil

    enum ConnectionState: String, Codable, Equatable {
        case disconnected
        case connecting
        case connected
    }

    enum TransportMedium: String, Codable, CaseIterable {
        case bluetoothLE = "BLE"
        case wifi = "WiFi"
        case ethernet = "Ethernet"
    }

    static func == (lhs: MeshNode, rhs: MeshNode) -> Bool {
        return lhs.id == rhs.id
    }

    static func id(from uuid: UUID) -> UUID {
        return uuid
    }
}

// P0-FIX: 手动实现MeshNode的Codable
extension MeshNode: Encodable {
    enum CodingKeys: String, CodingKey {
        case id, name, lastSeen, rssi, connectionState, supportedMedia, address, publicKeyData
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encode(rssi, forKey: .rssi)
        try container.encode(connectionState, forKey: .connectionState)
        try container.encode(supportedMedia, forKey: .supportedMedia)
        try container.encode(address, forKey: .address)
        if let pk = publicKey {
            try container.encode(pk.rawRepresentation, forKey: .publicKeyData)
        }
    }
}

extension MeshNode: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        rssi = try container.decode(Int.self, forKey: .rssi)
        connectionState = try container.decode(ConnectionState.self, forKey: .connectionState)
        supportedMedia = try container.decode(Set<TransportMedium>.self, forKey: .supportedMedia)
        address = try container.decode(String.self, forKey: .address)
        if let pkData = try? container.decode(Data.self, forKey: .publicKeyData) {
            publicKey = try? P256.Signing.PublicKey(rawRepresentation: pkData)
        } else {
            publicKey = nil
        }
    }
}

// MARK: - RoutingDecision

struct RoutingDecision: Codable {
    let preferredMedium: MeshNode.TransportMedium
    let estimatedLatency: TimeInterval
    let hopCount: Int
    let reliability: Double

    init(preferredMedium: MeshNode.TransportMedium, estimatedLatency: TimeInterval, hopCount: Int, reliability: Double) {
        self.preferredMedium = preferredMedium
        self.estimatedLatency = estimatedLatency
        self.hopCount = hopCount
        self.reliability = reliability
    }
}

// MARK: - MessagePriority

/// 消息优先级
enum MessagePriority: Int, Codable, Comparable {
    case low = 1
    case normal = 2
    case high = 3
    case emergency = 4
    
    static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .emergency: return "Emergency"
        }
    }
}

// MARK: - MeshMessage

struct MeshMessage: Codable {
    let id: UUID
    let sourceNodeId: UUID
    let destinationNodeId: UUID?
    let payload: Data
    let timestamp: Date
    let nonce: Data
    let ttl: Int
    var messageType: MeshMessageType
    let priority: MessagePriority

    init(source: UUID, destination: UUID? = nil, payload: Data, ttl: Int = 64, messageType: MeshMessageType = .broadcast, priority: MessagePriority = .normal) {
        self.id = UUID()
        self.sourceNodeId = source
        self.destinationNodeId = destination
        self.payload = payload
        self.timestamp = Date()
        // Generate 16-byte random nonce for replay attack protection
        var randomBytes = Data(count: 16)
        _ = randomBytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        self.nonce = randomBytes
        self.ttl = ttl
        self.messageType = messageType
        self.priority = priority
    }
}

// MARK: - GroupMember

struct GroupMember: Codable, Equatable {
    let uid: String
    var role: GroupRole
    let joinedAt: Date

    enum GroupRole: String, Codable {
        case owner
        case admin
        case member
    }
}

// MARK: - Group

struct Group: Codable, Identifiable {
    let id: String
    var name: String
    let ownerUid: String
    var members: [GroupMember]
    var groupKey: Data?
    var encryptedGroupKey: Data?
    let createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, name: String, ownerUid: String) {
        self.id = id
        self.name = name
        self.ownerUid = ownerUid
        self.members = [GroupMember(uid: ownerUid, role: .owner, joinedAt: Date())]
        self.groupKey = nil
        self.encryptedGroupKey = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Credit Event

struct CreditEvent: Codable {
    let id: String
    let timestamp: Date
    let type: CreditEventType
    let amount: Double
    let reason: String

    enum CreditEventType: String, Codable {
        case earned
        case consumed
        case decayed
        case bonus
        case penalty
    }

    init(type: CreditEventType, amount: Double, reason: String) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.type = type
        self.amount = amount
        self.reason = reason
    }
}

// MARK: - Credit Account

struct CreditAccount: Codable {
    var balance: Double
    var lastUpdated: Date
    var tier: CreditTier
    var totalEarned: Double
    var totalConsumed: Double

    enum CreditTier: Int, Codable, Comparable {
        case bronze = 1
        case silver = 2
        case gold = 3
        case platinum = 4

        static func < (lhs: CreditTier, rhs: CreditTier) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        var multiplier: Double {
            switch self {
            case .bronze: return 1.0
            case .silver: return 1.2
            case .gold: return 1.5
            case .platinum: return 2.0
            }
        }

        var displayName: String {
            switch self {
            case .bronze: return "Bronze"
            case .silver: return "Silver"
            case .gold: return "Gold"
            case .platinum: return "Platinum"
            }
        }
    }

    init(balance: Double = 0, tier: CreditTier = .bronze, totalEarned: Double = 0, totalConsumed: Double = 0) {
        self.balance = balance
        self.lastUpdated = Date()
        self.tier = tier
        self.totalEarned = totalEarned
        self.totalConsumed = totalConsumed
    }
}

// MARK: - Credit Rule Protocol

protocol CreditRule {
    var name: String { get }
    func apply(to amount: Double, context: [String: Any]) -> Double
}

// MARK: - User Profile

struct UserProfile: Codable {
    let uid: String
    var username: String?
    var publicKeyFingerprint: String?
    var avatarData: Data?
    var bio: String?
    let createdAt: Date
    var updatedAt: Date

    init(uid: String) {
        self.uid = uid
        self.username = nil
        self.publicKeyFingerprint = nil
        self.avatarData = nil
        self.bio = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Location Data

struct LocationData: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double
    let timestamp: Date
    let speed: Double?
    let heading: Double?

    init(latitude: Double, longitude: Double, altitude: Double? = nil, accuracy: Double = 0, speed: Double? = nil, heading: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.accuracy = accuracy
        self.timestamp = Date()
        self.speed = speed
        self.heading = heading
    }
}

// MARK: - Network Connection Info

struct NetworkConnectionInfo: Codable {
    let medium: MeshNode.TransportMedium
    let isConnected: Bool
    let signalStrength: Int
    let latency: TimeInterval
    let connectedNodes: Int

    init(medium: MeshNode.TransportMedium, isConnected: Bool, signalStrength: Int = 0, latency: TimeInterval = 0, connectedNodes: Int = 0) {
        self.medium = medium
        self.isConnected = isConnected
        self.signalStrength = signalStrength
        self.latency = latency
        self.connectedNodes = connectedNodes
    }
}

// MARK: - Encrypted Package Wrapper

struct EncryptedPackageWrapper: Codable {
    let id: UUID
    let encryptedData: Data
    let nonce: Data
    let senderFingerprint: String
    let recipientFingerprint: String?
    let timestamp: Date
    let signature: Data?

    init(encryptedData: Data, nonce: Data, senderFingerprint: String, recipientFingerprint: String? = nil, signature: Data? = nil) {
        self.id = UUID()
        self.encryptedData = encryptedData
        self.nonce = nonce
        self.senderFingerprint = senderFingerprint
        self.recipientFingerprint = recipientFingerprint
        self.timestamp = Date()
        self.signature = signature
    }
}
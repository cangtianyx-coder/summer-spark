import Foundation

// MARK: - User Status

/// 用户状态
enum UserStatus: String, Codable {
    case available = "空闲"       // 可接受任务
    case busy = "忙碌"            // 暂勿打扰
    case inRescue = "救援中"      // 正在执行救援
    case needHelp = "需要帮助"    // 需要他人协助
    case emergency = "紧急求助"   // SOS激活状态
    case offline = "离线"         // 已离线
    
    var priority: Int {
        switch self {
        case .emergency: return 0
        case .needHelp: return 1
        case .inRescue: return 2
        case .busy: return 3
        case .available: return 4
        case .offline: return 5
        }
    }
}

// MARK: - Trust Level

/// 信任等级
enum TrustLevel: String, Codable {
    case highlyTrusted = "高度信任"  // 0.8-1.0
    case trusted = "信任"            // 0.6-0.8
    case neutral = "中立"            // 0.4-0.6
    case caution = "谨慎"            // 0.2-0.4
    case untrusted = "不信任"        // 0.0-0.2
    
    static func from(score: Double) -> TrustLevel {
        switch score {
        case 0.8...: return .highlyTrusted
        case 0.6..<0.8: return .trusted
        case 0.4..<0.6: return .neutral
        case 0.2..<0.4: return .caution
        default: return .untrusted
        }
    }
}

// MARK: - Trust Score

/// 信任评分
struct TrustScore: Codable {
    let userId: String
    var score: Double           // 0.0 - 1.0
    var interactionCount: Int   // 互动次数
    var rescueCount: Int        // 参与救援次数
    var reliability: Double     // 可靠性（消息送达率）
    var lastUpdated: Date
    
    var level: TrustLevel {
        return TrustLevel.from(score: score)
    }
    
    init(userId: String) {
        self.userId = userId
        self.score = 0.5  // 初始中立
        self.interactionCount = 0
        self.rescueCount = 0
        self.reliability = 0.5
        self.lastUpdated = Date()
    }
}

// MARK: - Emergency Contact

/// 紧急联系人
struct EmergencyContact: Codable, Identifiable {
    let id: UUID
    let userId: String          // 拥有此联系人的用户
    let contactId: String       // 联系人UID
    var priority: Int           // 1=最高优先
    var alias: String?          // 别名
    var notifyOnEmergency: Bool // 紧急情况是否通知
    let addedAt: Date
    
    init(userId: String, contactId: String, priority: Int = 1, alias: String? = nil) {
        self.id = UUID()
        self.userId = userId
        self.contactId = contactId
        self.priority = priority
        self.alias = alias
        self.notifyOnEmergency = true
        self.addedAt = Date()
    }
}

// MARK: - Interaction Type

/// 互动类型
enum InteractionType: String, Codable {
    case voiceCall = "语音通话"
    case messageRelay = "消息中继"
    case rescueAssist = "救援协助"
    case locationShare = "位置共享"
    case groupActivity = "群组活动"
    case sosResponse = "SOS响应"
    
    var trustWeight: Double {
        switch self {
        case .sosResponse: return 0.2      // SOS响应大幅提升信任
        case .rescueAssist: return 0.15    // 救援协助
        case .voiceCall: return 0.02       // 语音通话
        case .messageRelay: return 0.01    // 消息中继
        case .locationShare: return 0.03   // 位置共享
        case .groupActivity: return 0.02   // 群组活动
        }
    }
}

// MARK: - Interaction Record

/// 互动记录
struct InteractionRecord: Codable, Identifiable {
    let id: UUID
    let withUserId: String
    let type: InteractionType
    let timestamp: Date
    let successful: Bool
    var details: String?
    
    init(withUserId: String, type: InteractionType, successful: Bool, details: String? = nil) {
        self.id = UUID()
        self.withUserId = withUserId
        self.type = type
        self.timestamp = Date()
        self.successful = successful
        self.details = details
    }
}

// MARK: - User Status Broadcast

/// 用户状态广播消息
struct UserStatusBroadcast: Codable {
    let userId: String
    let username: String
    let status: UserStatus
    let location: LocationData?
    let timestamp: Date
    let batteryLevel: Double?
    
    init(status: UserStatus, location: LocationData? = nil) {
        self.userId = IdentityManager.shared.uid ?? ""
        self.username = IdentityManager.shared.displayName
        self.status = status
        self.location = location
        self.timestamp = Date()
        self.batteryLevel = nil  // TODO: 获取实际电池电量
    }
}

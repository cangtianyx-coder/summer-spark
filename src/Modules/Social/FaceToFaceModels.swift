import Foundation

// MARK: - FaceToFace Invite Model

/// 面对面建群邀请数据结构
struct FaceToFaceInvite: Codable {
    /// 邀请类型标识
    let type: String
    
    /// 群组ID
    let groupId: String
    
    /// 群组名称
    let groupName: String
    
    /// 创建时间
    let createdAt: Date
    
    /// 过期时间
    let expiresAt: Date
    
    /// 邀请码（6位数字）
    let numericCode: String
    
    /// 是否已过期
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    /// 邀请类型常量
    static let inviteType = "face_to_face_group"
    
    /// 邀请有效期（分钟）
    static let validityDuration: TimeInterval = 5 * 60
    
    /// 初始化
    init(groupId: String, groupName: String) {
        self.type = FaceToFaceInvite.inviteType
        self.groupId = groupId
        self.groupName = groupName
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(FaceToFaceInvite.validityDuration)
        self.numericCode = FaceToFaceInvite.generateNumericCode(for: groupId)
    }
    
    /// 从JSON初始化
    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let invite = try? JSONDecoder().decode(FaceToFaceInvite.self, from: data) else {
            return nil
        }
        self.type = invite.type
        self.groupId = invite.groupId
        self.groupName = invite.groupName
        self.createdAt = invite.createdAt
        self.expiresAt = invite.expiresAt
        self.numericCode = invite.numericCode
    }
    
    /// 转换为JSON字符串
    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// 生成6位数字邀请码
    /// 原理：使用Base36编码groupId的前8个字符，可逆解码
    static func generateNumericCode(for groupId: String) -> String {
        // 移除非字母数字字符（如UUID中的连字符）
        let cleanedId = groupId.filter { $0.isLetter || $0.isNumber }
        // 取前8个字符
        let prefix = String(cleanedId.prefix(8))
        
        // 使用Base36编码生成6位字符（只含0-9和A-Z）
        return base36Encode(prefix)
    }
    
    /// Base36编码：将字符串编码为6位字符
    private static func base36Encode(_ input: String) -> String {
        // 将字符串转换为字节数组
        var bytes: [UInt8] = []
        for char in input {
            bytes.append(UInt8(char.asciiValue ?? 0))
        }
        
        // 如果不足8字节，用0填充
        while bytes.count < 8 {
            bytes.append(0)
        }
        
        // 将8个字节（64位）转换为Base36数字
        // 由于Base36基数是36，6位Base36可以表示36^6 = 2.1B，足够表示前4个字节
        // 取前4个字节（32位）来编码
        let value = (UInt64(bytes[0]) << 24) | (UInt64(bytes[1]) << 16) | 
                    (UInt64(bytes[2]) << 8) | UInt64(bytes[3])
        
        // 转换为Base36字符串（6位）
        let base36Chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var remaining = value
        var result: [Character] = []
        
        // 只取低26位（因为26位Base36是约2.6B，小于UInt32.max）
        let maskedValue = remaining & 0x3FFFFFF // 26位掩码
        
        for _ in 0..<6 {
            let index = Int(maskedValue % 36)
            result.append(base36Chars[index])
        }
        
        return String(result.reversed())
    }
    
    /// 从数字码反向解码获取groupId前缀
    static func decodeGroupIdPrefix(from code: String) -> String? {
        guard code.count == 6 else { return nil }
        
        // 只有当code只包含0-9和A-Z时才尝试解码
        let validChars = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard code.unicodeScalars.allSatisfy({ validChars.contains($0) }) else { return nil }
        
        // 将6位Base36转换回数值
        let base36Chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var value: UInt64 = 0
        
        for char in code.uppercased() {
            if let index = base36Chars.firstIndex(of: char) {
                value = value * 36 + UInt64(index)
            } else {
                return nil
            }
        }
        
        // 数值就是groupId前缀的编码（取前4字节）
        let b0 = UInt8((value >> 24) & 0xFF)
        let b1 = UInt8((value >> 16) & 0xFF)
        let b2 = UInt8((value >> 8) & 0xFF)
        let b3 = UInt8(value & 0xFF)
        
        // 重建为字符串（使用Latin1编码以避免UTF-8解码失败）
        // P0-FIX: Latin1编码可以安全处理任何字节值（0-255）
        let prefixString = String(bytes: [b0, b1, b2, b3], encoding: .isoLatin1)?.trimmingCharacters(in: .controlCharacters) ?? String(format: "%02X%02X%02X%02X", b0, b1, b2, b3)
        return prefixString
    }
    
    /// 验证数字邀请码
    static func validateNumericCode(_ code: String, for groupId: String) -> Bool {
        guard code.count == 6 else { return false }
        // 检查code是否只包含数字和大写字母
        let validChars = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard code.unicodeScalars.allSatisfy({ validChars.contains($0) }) else { return false }
        return generateNumericCode(for: groupId) == code
    }
}

// MARK: - Join Group Request

/// 加入群组请求
struct JoinGroupRequest: Codable {
    let groupId: String
    let requesterUid: String
    let timestamp: Date
    
    init(groupId: String, requesterUid: String) {
        self.groupId = groupId
        self.requesterUid = requesterUid
        self.timestamp = Date()
    }
}

// MARK: - FaceToFace Group State

/// 面对面建群状态
enum FaceToFaceGroupState: Equatable {
    case idle                          // 空闲状态
    case creating                      // 创建中
    case waitingForJoin                // 等待加入
    case joining                       // 加入中
    case success(Group)                // 成功
    case failed(FaceToFaceGroupError)  // 失败
    
    static func == (lhs: FaceToFaceGroupState, rhs: FaceToFaceGroupState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.creating, .creating),
             (.waitingForJoin, .waitingForJoin),
             (.joining, .joining):
            return true
        case (.success(let l), .success(let r)):
            return l.id == r.id
        case (.failed(let l), .failed(let r)):
            return l.localizedDescription == r.localizedDescription
        default:
            return false
        }
    }
}

/// 面对面建群错误类型
enum FaceToFaceGroupError: Error, LocalizedError, Equatable {
    case insufficientCredits          // 积分不足
    case groupNotFound                 // 群组不存在
    case alreadyMember                 // 已在群组中
    case inviteExpired                 // 邀请码已过期
    case invalidInvite                 // 无效的邀请
    case networkError                  // 网络错误
    case unknown                       // 未知错误
    
    var errorDescription: String? {
        switch self {
        case .insufficientCredits:
            return "积分不足，需要50积分才能创建面对面群组"
        case .groupNotFound:
            return "群组不存在或已解散"
        case .alreadyMember:
            return "您已经在该群组中"
        case .inviteExpired:
            return "邀请码已过期，请重新生成"
        case .invalidInvite:
            return "无效的邀请码"
        case .networkError:
            return "网络连接失败"
        case .unknown:
            return "发生未知错误"
        }
    }
}

// MARK: - FaceToFace Mode

/// 面对面建群模式
enum FaceToFaceMode {
    case create    // 发起建群
    case join      // 加入群组
}

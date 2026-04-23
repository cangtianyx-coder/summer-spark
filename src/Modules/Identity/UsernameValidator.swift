import Foundation

// MARK: - UsernameValidationResult

/// 用户名验证结果
enum UsernameValidationResult {
    case valid
    case tooShort        // 少于2个字符
    case tooLong         // 超过16个字符
    case invalidCharacters  // 包含非法字符
    case empty
    
    var isValid: Bool {
        return self == .valid
    }
    
    var errorMessage: String? {
        switch self {
        case .valid:
            return nil
        case .tooShort:
            return "用户名至少需要2个字符"
        case .tooLong:
            return "用户名不能超过16个字符"
        case .invalidCharacters:
            return "用户名只能包含汉字、字母、数字和下划线"
        case .empty:
            return "用户名不能为空"
        }
    }
}

// MARK: - UsernameConflictResult

/// 用户名冲突检测结果
enum UsernameConflictResult: Equatable {
    case available       // 用户名可用
    case conflict(String)  // 冲突，返回冲突的节点UID
    case checking        // 正在检测中
    case error(String)   // 检测错误
    
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

// MARK: - UsernameValidator

/// 用户名验证器
/// 负责验证用户名格式和检测Mesh网络中的重名
final class UsernameValidator {
    
    // MARK: - Singleton
    
    static let shared = UsernameValidator()
    
    // MARK: - Constants
    
    /// 最小用户名长度
    static let minLength = 2
    
    /// 最大用户名长度
    static let maxLength = 16
    
    /// 允许的字符正则：汉字、字母、数字、下划线
    /// 汉字范围：\u4e00-\u9fff
    private let validPattern = "^[\\u4e00-\\u9fff\\u3400-\\u4dbf\\ua000-\\ua48f\\w]+$"
    
    // MARK: - Properties
    
    private var meshService: MeshServiceProtocol?
    private var pendingChecks: [String: [(UsernameConflictResult) -> Void]] = [:]
    private let queue = DispatchQueue(label: "com.summerspark.usernamevalidator")
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Configuration
    
    /// 配置Mesh服务引用（用于网络检测）
    func configure(meshService: MeshServiceProtocol) {
        self.meshService = meshService
    }
    
    // MARK: - Format Validation
    
    /// 验证用户名格式
    /// - Parameter username: 待验证的用户名
    /// - Returns: 验证结果
    func validateFormat(_ username: String) -> UsernameValidationResult {
        // 检查空
        guard !username.isEmpty else {
            return .empty
        }
        
        // 检查长度
        let length = username.count
        guard length >= Self.minLength else {
            return .tooShort
        }
        guard length <= Self.maxLength else {
            return .tooLong
        }
        
        // 检查字符
        let regex = try? NSRegularExpression(pattern: validPattern, options: [])
        let range = NSRange(location: 0, length: length)
        
        if let regex = regex {
            let matches = regex.matches(in: username, options: [], range: range)
            if matches.isEmpty {
                return .invalidCharacters
            }
        }
        
        return .valid
    }
    
    /// 快速验证用户名是否有效
    /// - Parameter username: 待验证的用户名
    /// - Returns: 是否有效
    func isValid(_ username: String) -> Bool {
        return validateFormat(username).isValid
    }
    
    // MARK: - Network Conflict Detection
    
    /// 检测用户名在Mesh网络中是否可用
    /// - Parameters:
    ///   - username: 待检测的用户名
    ///   - timeout: 超时时间（秒）
    ///   - completion: 检测结果回调
    func checkAvailability(
        _ username: String,
        timeout: TimeInterval = 5.0,
        completion: @escaping (UsernameConflictResult) -> Void
    ) {
        // 先验证格式
        let formatResult = validateFormat(username)
        guard formatResult.isValid else {
            completion(.error(formatResult.errorMessage ?? "格式无效"))
            return
        }
        
        // 如果没有Mesh服务，直接返回可用
        guard let meshService = meshService else {
            completion(.available)
            return
        }
        
        // 检查是否在检测中
        queue.sync {
            if pendingChecks[username] != nil {
                // 添加到等待队列
                pendingChecks[username]?.append(completion)
                return
            }
            pendingChecks[username] = [completion]
        }
        
        // 广播用户名检查请求
        broadcastUsernameCheck(username, meshService: meshService, timeout: timeout)
    }
    
    /// 同步检测用户名可用性（阻塞当前线程）
    /// - Parameters:
    ///   - username: 待检测的用户名
    ///   - timeout: 超时时间（秒）
    /// - Returns: 检测结果
    func checkAvailabilitySync(_ username: String, timeout: TimeInterval = 5.0) -> UsernameConflictResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: UsernameConflictResult = .checking
        
        checkAvailability(username, timeout: timeout) { r in
            result = r
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + timeout + 1.0)
        return result
    }
    
    // MARK: - Private Methods
    
    /// 广播用户名检查请求到Mesh网络
    private func broadcastUsernameCheck(
        _ username: String,
        meshService: MeshServiceProtocol,
        timeout: TimeInterval
    ) {
        // 构建检查消息
        let checkMessage = UsernameCheckMessage(
            username: username,
            requesterUID: IdentityManager.shared.uid ?? "",
            timestamp: Date()
        )
        
        // 广播消息 - 使用sendMessage
        guard let payload = try? JSONEncoder().encode(checkMessage),
              let sourceUUID = UUID(uuidString: IdentityManager.shared.uid ?? "") else {
            handleCheckTimeout(username)
            return
        }
        
        let message = MeshMessage(
            source: sourceUUID,
            payload: payload,
            messageType: .usernameCheck
        )
        meshService.sendMessage(message, via: nil)
        
        // 设置超时
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.handleCheckTimeout(username)
        }
    }
    
    /// 处理检查超时
    private func handleCheckTimeout(_ username: String) {
        queue.sync {
            guard let callbacks = pendingChecks[username] else { return }
            pendingChecks.removeValue(forKey: username)
            
            // P2-FIX: 超时返回错误状态而非可用，让用户重试
            for callback in callbacks {
                callback(.error("检查超时，请重试"))
            }
        }
    }
    
    /// 处理收到的用户名冲突响应
    /// - Parameters:
    ///   - username: 用户名
    ///   - conflictingUID: 冲突节点的UID
    func handleConflictResponse(username: String, conflictingUID: String) {
        queue.sync {
            guard let callbacks = pendingChecks[username] else { return }
            pendingChecks.removeValue(forKey: username)
            
            for callback in callbacks {
                callback(.conflict(conflictingUID))
            }
        }
    }
}

// MARK: - UsernameCheckMessage

/// 用户名检查消息
struct UsernameCheckMessage: Codable {
    let username: String
    let requesterUID: String
    let timestamp: Date
}

// MARK: - UsernameCheckResponse

/// 用户名检查响应
struct UsernameCheckResponse: Codable {
    let username: String
    let conflictingUID: String  // 如果冲突，返回自己的UID
    let responderUID: String
    let timestamp: Date
}

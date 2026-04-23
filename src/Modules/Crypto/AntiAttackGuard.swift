import Foundation
import CryptoKit

/// AntiAttackGuard - 防攻击模块
/// 提供身份伪造检测、篡改检测、恶意节点处理、黑名单和DoS防护功能
public final class AntiAttackGuard {
    static let shared = AntiAttackGuard()

    private init() {
        setupBlocklistTimer()
    }

    public func enable() {
        // AntiAttackGuard is always enabled via its singleton initialization
        // This method exists for API consistency and explicit enable calls
    }

    // MARK: - Configuration
    public struct Config {
        public var maxRequestsPerWindow: Int = 100
        public var windowDurationSeconds: TimeInterval = 60
        public var blockDurationSeconds: TimeInterval = 300
        public var maxBlacklistSize: Int = 10000
        public var enableDoSProtection: Bool = true
        public var enableTamperDetection: Bool = true
        
        public init() {}
    }
    
    public var config = Config()
    
    // MARK: - Blacklist
    private var blacklist: Set<String> = []
    private let blacklistLock = NSLock()
    
    /// 黑名单节点ID列表
    public var blacklistedNodes: [String] {
        blacklistLock.lock()
        defer { blacklistLock.unlock() }
        return Array(blacklist)
    }
    
    // MARK: - Request Tracking (DoS Protection)
    private var requestTracker: [String: RequestWindow] = [:]
    private let trackerLock = NSLock()
    
    private struct RequestWindow {
        var timestamps: [Date]
        var blockedUntil: Date?
    }
    
    // MARK: - Tamper Detection
    private var messageSignatures: [String: String] = [:]
    private let signatureLock = NSLock()
    
    // MARK: - Node Reputation
    private var nodeReputation: [String: NodeReputation] = [:]
    private let reputationLock = NSLock()
    
    private struct NodeReputation {
        var score: Int
        var lastReportTime: Date
        var violationCount: Int
    }
    
    // MARK: - Replay Attack Protection
    private var replayCache: [Data: Date] = [:]
    private var replayCacheOrder: [Data] = [] // 维护LRU顺序
    private let replayCacheLock = NSLock()
    private let replayCacheMaxSize = 10000
    private let replayMessageMaxAge: TimeInterval = 300 // 5 minutes
    
    // MARK: - Tamper Detection
    
    /// 检测消息是否被篡改
    public func detectTampering(nodeId: String, messageId: String, signature: String, payload: Data) -> TamperResult {
        guard config.enableTamperDetection else {
            return TamperResult(isTampered: false, confidence: 0, reason: nil)
        }
        
        signatureLock.lock()
        let storedSignature = messageSignatures[messageId]
        signatureLock.unlock()
        
        if let stored = storedSignature {
            // 已有签名，进行验证
            if stored != signature {
                recordViolation(nodeId: nodeId, type: .tampering)
                return TamperResult(
                    isTampered: true,
                    confidence: 0.95,
                    reason: "签名不匹配，消息可能被篡改"
                )
            }
            return TamperResult(isTampered: false, confidence: 0.1, reason: nil)
        }
        
        // 记录新签名
        signatureLock.lock()
        messageSignatures[messageId] = signature
        if messageSignatures.count > 100000 {
            // 清理旧签名
            messageSignatures = [:]
        }
        signatureLock.unlock()
        
        return TamperResult(isTampered: false, confidence: 0, reason: nil)
    }
    
    public struct TamperResult {
        public let isTampered: Bool
        public let confidence: Double
        public let reason: String?
    }
    
    // MARK: - Identity Forgery Detection
    
    /// 检测身份伪造
    public func detectIdentityForgery(nodeId: String, claimedIdentity: String, certificate: String?) -> ForgeryResult {
        // 验证节点ID格式
        guard isValidNodeId(nodeId) else {
            recordViolation(nodeId: nodeId, type: .identityForgery)
            return ForgeryResult(
                isForged: true,
                confidence: 0.9,
                reason: "无效的节点ID格式"
            )
        }
        
        // 如果提供了证书，验证证书
        if let cert = certificate {
            if !verifyCertificate(cert, forNodeId: nodeId) {
                recordViolation(nodeId: nodeId, type: .identityForgery)
                return ForgeryResult(
                    isForged: true,
                    confidence: 0.85,
                    reason: "证书验证失败"
                )
            }
        }
        
        return ForgeryResult(isForged: false, confidence: 0, reason: nil)
    }
    
    public struct ForgeryResult {
        public let isForged: Bool
        public let confidence: Double
        public let reason: String?
    }
    
    // MARK: - Replay Attack Protection
    
    /// 检测重放攻击
    /// - Parameters:
    ///   - nonce: 消息的随机数
    ///   - timestamp: 消息的时间戳
    ///   - nodeId: 发送节点ID（用于记录违规）
    /// - Returns: 检测结果
    public func replayAttackCheck(nonce: Data, timestamp: Date, nodeId: String) -> ReplayCheckResult {
        let now = Date()
        
        // 检查消息是否过期（超过5分钟）
        let messageAge = now.timeIntervalSince(timestamp)
        if messageAge > replayMessageMaxAge {
            recordViolation(nodeId: nodeId, type: .replayAttack)
            return ReplayCheckResult(
                isReplay: true,
                reason: "消息已过期，时间差: \(Int(messageAge))秒"
            )
        }
        
        // 检查消息时间是否在未来（时钟漂移检测）
        if timestamp > now.addingTimeInterval(60) { // 允许60秒的时钟漂移
            recordViolation(nodeId: nodeId, type: .replayAttack)
            return ReplayCheckResult(
                isReplay: true,
                reason: "消息时间戳异常（未来时间）"
            )
        }
        
        replayCacheLock.lock()
        defer { replayCacheLock.unlock() }
        
        // 检查nonce是否已存在（重复消息）
        if replayCache[nonce] != nil {
            recordViolation(nodeId: nodeId, type: .replayAttack)
            return ReplayCheckResult(
                isReplay: true,
                reason: "检测到重复的nonce，可能的重放攻击"
            )
        }
        
        // 添加到缓存
        replayCache[nonce] = timestamp
        replayCacheOrder.append(nonce)
        
        // LRU清理：如果缓存超过最大大小，移除最老的条目
        while replayCache.count > replayCacheMaxSize {
            if let oldestKey = replayCacheOrder.first {
                replayCacheOrder.removeFirst()
                replayCache.removeValue(forKey: oldestKey)
            } else {
                break
            }
        }
        
        return ReplayCheckResult(isReplay: false, reason: nil)
    }
    
    public struct ReplayCheckResult {
        public let isReplay: Bool
        public let reason: String?
    }
    
    /// 处理恶意节点
    public func handleMaliciousNode(nodeId: String, evidence: String) -> HandlingAction {
        reputationLock.lock()
        var reputation = nodeReputation[nodeId] ?? NodeReputation(score: 100, lastReportTime: Date(), violationCount: 0)
        
        reputation.score = max(0, reputation.score - 20)
        reputation.lastReportTime = Date()
        reputation.violationCount += 1
        nodeReputation[nodeId] = reputation
        
        reputationLock.unlock()
        
        if reputation.score < 30 || reputation.violationCount >= 3 {
            addToBlacklist(nodeId: nodeId)
            return .blocked
        }
        
        return .warning
    }
    
    public enum HandlingAction {
        case warning
        case rateLimited
        case blocked
    }
    
    private enum ViolationType {
        case tampering
        case identityForgery
        case dosAttack
        case malicious
        case replayAttack
    }
    
    private func recordViolation(nodeId: String, type: ViolationType) {
        reputationLock.lock()
        var reputation = nodeReputation[nodeId] ?? NodeReputation(score: 100, lastReportTime: Date(), violationCount: 0)
        reputation.score = max(0, reputation.score - 15)
        reputation.violationCount += 1
        reputation.lastReportTime = Date()
        nodeReputation[nodeId] = reputation
        reputationLock.unlock()
    }
    
    // MARK: - Blacklist Management
    
    /// 添加节点到黑名单
    public func addToBlacklist(nodeId: String) {
        blacklistLock.lock()
        defer { blacklistLock.unlock() }
        
        if blacklist.count >= config.maxBlacklistSize {
            // 移除最老的条目
            if let first = blacklist.popFirst() {
                blacklist.remove(first)
            }
        }
        blacklist.insert(nodeId)
    }
    
    /// 从黑名单移除
    public func removeFromBlacklist(nodeId: String) {
        blacklistLock.lock()
        defer { blacklistLock.unlock() }
        blacklist.remove(nodeId)
    }
    
    /// 检查节点是否在黑名单
    public func isBlacklisted(nodeId: String) -> Bool {
        blacklistLock.lock()
        defer { blacklistLock.unlock() }
        return blacklist.contains(nodeId)
    }
    
    /// 清空黑名单
    public func clearBlacklist() {
        blacklistLock.lock()
        defer { blacklistLock.unlock() }
        blacklist.removeAll()
    }
    
    // MARK: - DoS Protection
    
    /// 检查请求是否允许
    public func checkRequest(nodeId: String) -> RequestDecision {
        guard config.enableDoSProtection else {
            return .allowed
        }
        
        // 检查是否在黑名单
        if isBlacklisted(nodeId: nodeId) {
            return .blocked(reason: "节点在黑名单中")
        }
        
        trackerLock.lock()
        defer { trackerLock.unlock() }
        
        var window = requestTracker[nodeId] ?? RequestWindow(timestamps: [], blockedUntil: nil)
        
        // 检查是否被临时阻止
        if let blockedUntil = window.blockedUntil, blockedUntil > Date() {
            return .blocked(reason: "请求频率超限")
        }
        
        // 清理过期时间戳
        let now = Date()
        let windowStart = now.addingTimeInterval(-config.windowDurationSeconds)
        window.timestamps = window.timestamps.filter { $0 > windowStart }
        
        // 检查频率
        if window.timestamps.count >= config.maxRequestsPerWindow {
            window.blockedUntil = now.addingTimeInterval(config.blockDurationSeconds)
            requestTracker[nodeId] = window
            return .blocked(reason: "请求频率超限，已临时阻止 \(config.blockDurationSeconds) 秒")
        }
        
        window.timestamps.append(now)
        requestTracker[nodeId] = window
        
        return .allowed
    }
    
    public enum RequestDecision {
        case allowed
        case blocked(reason: String)
    }
    
    // MARK: - Helper Methods
    
    private func isValidNodeId(_ nodeId: String) -> Bool {
        // 基本格式验证：非空，长度合理
        guard !nodeId.isEmpty, nodeId.count <= 128 else { return false }
        // 允许字母、数字、冒号和短横线
        let pattern = "^[a-zA-Z0-9:-]+$"
        return nodeId.range(of: pattern, options: .regularExpression) != nil
    }
    
    // P0-FIX: 实现真正的证书验证
    private func verifyCertificate(_ certificate: String, forNodeId nodeId: String) -> Bool {
        // 方案1: 验证证书签名
        guard let certData = Data(base64Encoded: certificate) else {
            Logger.shared.warn("AntiAttackGuard: Invalid certificate encoding for node \(nodeId)")
            return false
        }
        
        // 证书格式: [原始数据(变长) || 签名(64字节)]
        guard certData.count > 64 else {
            Logger.shared.warn("AntiAttackGuard: Certificate too short for node \(nodeId)")
            return false
        }
        
        let signatureData = certData.suffix(64)
        let originalData = certData.dropLast(64)
        
        // 从IdentityManager获取CA公钥验证证书
        if let caPublicKey = IdentityManager.shared.getCAPublicKey() {
            return CryptoEngine.shared.verify(
                signature: signatureData,
                data: originalData,
                publicKey: caPublicKey
            )
        }
        
        // 方案2: 检查证书格式和内容（降级验证）
        // 检查证书是否包含节点ID（基础验证）
        guard certificate.contains(nodeId) else {
            Logger.shared.warn("AntiAttackGuard: Certificate doesn't contain node ID")
            return false
        }
        
        return true
    }
    
    // P0-FIX: 使用DispatchSourceTimer替代while true无限循环
    private var cleanupTimer: DispatchSourceTimer?
    
    private func setupBlocklistTimer() {
        // 定期清理过期数据
        cleanupTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        cleanupTimer?.schedule(deadline: .now() + 3600, repeating: 3600) // 每小时
        cleanupTimer?.setEventHandler { [weak self] in
            self?.cleanupExpiredData()
        }
        cleanupTimer?.resume()
    }
    
    // P0-FIX: 添加deinit清理
    deinit {
        cleanupTimer?.cancel()
        cleanupTimer = nil
    }
    
    private func cleanupExpiredData() {
        // 清理过期请求记录
        trackerLock.lock()
        let cutoff = Date().addingTimeInterval(-config.windowDurationSeconds * 2)
        for (nodeId, var window) in requestTracker {
            window.timestamps = window.timestamps.filter { $0 > cutoff }
            if window.timestamps.isEmpty && window.blockedUntil == nil {
                requestTracker.removeValue(forKey: nodeId)
            } else {
                requestTracker[nodeId] = window
            }
        }
        trackerLock.unlock()
        
        // 清理低信誉节点
        reputationLock.lock()
        let now = Date()
        nodeReputation = nodeReputation.filter { _, rep in
            rep.lastReportTime > now.addingTimeInterval(-86400 * 7) // 保留7天内活跃
        }
        reputationLock.unlock()
        
        // 清理过期重放攻击缓存
        replayCacheLock.lock()
        let replayCutoff = now.addingTimeInterval(-replayMessageMaxAge)
        var keysToRemove: [Data] = []
        for (nonce, timestamp) in replayCache {
            if timestamp < replayCutoff {
                keysToRemove.append(nonce)
            }
        }
        for key in keysToRemove {
            replayCache.removeValue(forKey: key)
            replayCacheOrder.removeAll { $0 == key }
        }
        replayCacheLock.unlock()
    }
    
    /// 获取节点信誉分数
    public func getNodeReputation(nodeId: String) -> Int {
        reputationLock.lock()
        defer { reputationLock.unlock() }
        return nodeReputation[nodeId]?.score ?? 100
    }
    
    /// 重置节点信誉
    public func resetNodeReputation(nodeId: String) {
        reputationLock.lock()
        defer { reputationLock.unlock() }
        nodeReputation[nodeId] = nil
    }
    
    /// 获取当前统计信息
    public func getStatistics() -> Statistics {
        blacklistLock.lock()
        let blacklistCount = blacklist.count
        blacklistLock.unlock()
        
        trackerLock.lock()
        let trackedNodes = requestTracker.count
        trackerLock.unlock()
        
        reputationLock.lock()
        let totalNodes = nodeReputation.count
        reputationLock.unlock()
        
        return Statistics(
            blacklistSize: blacklistCount,
            trackedNodes: trackedNodes,
            totalMonitoredNodes: totalNodes
        )
    }
    
    public struct Statistics {
        public let blacklistSize: Int
        public let trackedNodes: Int
        public let totalMonitoredNodes: Int
    }
}

// MARK: - Convenience Extensions

public extension AntiAttackGuard {
    /// 快捷方法：验证消息安全性
    func validateMessage(nodeId: String, messageId: String, signature: String, payload: Data) -> SecurityValidationResult {
        // 检查DoS
        let dosCheck = checkRequest(nodeId: nodeId)
        if case .blocked = dosCheck {
            return SecurityValidationResult(
                isSafe: false,
                issues: [.dosDetected],
                confidence: 1.0
            )
        }
        
        // 检查篡改
        let tamperResult = detectTampering(nodeId: nodeId, messageId: messageId, signature: signature, payload: payload)
        
        var issues: [SecurityIssue] = []
        var maxConfidence: Double = 0
        
        if tamperResult.isTampered {
            issues.append(.tamperingDetected)
            maxConfidence = max(maxConfidence, tamperResult.confidence)
        }
        
        return SecurityValidationResult(
            isSafe: issues.isEmpty,
            issues: issues,
            confidence: maxConfidence
        )
    }
    
    public struct SecurityValidationResult {
        public let isSafe: Bool
        public let issues: [SecurityIssue]
        public let confidence: Double
    }
    
    public enum SecurityIssue {
        case dosDetected
        case tamperingDetected
        case identityForged
        case blacklistedNode
    }
}
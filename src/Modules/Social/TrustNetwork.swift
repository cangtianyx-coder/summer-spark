import Foundation

// MARK: - Trust Network

/// 信任网络管理器
final class TrustNetwork {
    static let shared = TrustNetwork()
    
    private var trustScores: [String: TrustScore] = [:]
    private let queue = DispatchQueue(label: "com.summerspark.trustnetwork", attributes: .concurrent)
    
    // 信任评分权重
    private let interactionWeight = 0.3
    private let rescueWeight = 0.4
    private let reliabilityWeight = 0.3
    
    weak var delegate: TrustNetworkDelegate?
    
    private init() {}
    
    // MARK: - Public API
    
    /// 获取用户信任评分
    func getTrustScore(for userId: String) -> TrustScore {
        return queue.sync {
            if let score = trustScores[userId] {
                return score
            }
            return TrustScore(userId: userId)
        }
    }
    
    /// 获取信任等级
    func getTrustLevel(for userId: String) -> TrustLevel {
        let score = getTrustScore(for: userId)
        return score.level
    }
    
    /// 记录互动并更新信任度
    func recordInteraction(_ record: InteractionRecord) {
        queue.sync(flags: .barrier) {
            let userId = record.withUserId
            var score = trustScores[userId] ?? TrustScore(userId: userId)
            
            score.interactionCount += 1
            
            // 根据互动类型和成功与否更新评分
            if record.successful {
                let delta = record.type.trustWeight
                score.score = min(1.0, score.score + delta)
            } else {
                let delta = record.type.trustWeight * 0.5
                score.score = max(0.0, score.score - delta)
            }
            
            // 如果是救援相关，增加救援计数
            if record.type == .rescueAssist || record.type == .sosResponse {
                score.rescueCount += 1
            }
            
            score.lastUpdated = Date()
            trustScores[userId] = score
            
            Logger.shared.info("TrustNetwork: Updated trust for \(userId), score: \(score.score), level: \(score.level.rawValue)")
        }
    }
    
    /// 更新可靠性（消息送达率）
    func updateReliability(for userId: String, successRate: Double) {
        queue.sync(flags: .barrier) {
            var score = trustScores[userId] ?? TrustScore(userId: userId)
            score.reliability = successRate
            score.lastUpdated = Date()
            trustScores[userId] = score
        }
    }
    
    /// 救援行为大幅提升信任度
    func rewardRescueAction(for userId: String) {
        queue.sync(flags: .barrier) {
            var score = trustScores[userId] ?? TrustScore(userId: userId)
            
            score.rescueCount += 1
            score.score = min(1.0, score.score + 0.2)  // 救援行为+0.2
            score.lastUpdated = Date()
            trustScores[userId] = score
            
            Logger.shared.info("TrustNetwork: Rewarded rescue action for \(userId), new score: \(score.score)")
        }
    }
    
    /// 惩罚恶意行为
    func penalize(for userId: String, severity: Double = 0.1) {
        queue.sync(flags: .barrier) {
            var score = trustScores[userId] ?? TrustScore(userId: userId)
            
            score.score = max(0.0, score.score - severity)
            score.lastUpdated = Date()
            trustScores[userId] = score
            
            Logger.shared.info("TrustNetwork: Penalized \(userId), new score: \(score.score)")
        }
    }
    
    /// 获取可信任用户列表
    func getTrustedUsers(minLevel: TrustLevel = .trusted) -> [TrustScore] {
        return queue.sync {
            trustScores.values
                .filter { $0.level.rawValue.count >= minLevel.rawValue.count }
                .sorted { $0.score > $1.score }
        }
    }
    
    /// 获取不信任用户列表
    func getUntrustedUsers() -> [TrustScore] {
        return queue.sync {
            trustScores.values
                .filter { $0.level == .untrusted || $0.level == .caution }
                .sorted { $0.score < $1.score }
        }
    }
    
    /// 计算综合信任评分
    func calculateOverallScore(for userId: String) -> Double {
        let score = getTrustScore(for: userId)
        
        // 综合评分 = 互动贡献 + 救援贡献 + 可靠性贡献
        let interactionComponent = min(1.0, Double(score.interactionCount) / 100.0) * interactionWeight
        let rescueComponent = min(1.0, Double(score.rescueCount) / 10.0) * rescueWeight
        let reliabilityComponent = score.reliability * reliabilityWeight
        
        return interactionComponent + rescueComponent + reliabilityComponent
    }
    
    /// 重置用户信任评分
    func resetScore(for userId: String) {
        queue.sync(flags: .barrier) {
            trustScores[userId] = TrustScore(userId: userId)
        }
        Logger.shared.info("TrustNetwork: Reset trust score for \(userId)")
    }
    
    /// 清理缓存
    func clearCache() {
        queue.sync(flags: .barrier) {
            // 保留最近更新的100个用户
            let sorted = trustScores.values.sorted { $0.lastUpdated > $1.lastUpdated }
            let toKeep = Set(sorted.prefix(100).map { $0.userId })
            trustScores = trustScores.filter { toKeep.contains($0.key) }
        }
        Logger.shared.info("TrustNetwork: Cache cleared")
    }
}

// MARK: - Delegate

protocol TrustNetworkDelegate: AnyObject {
    func trustNetwork(_ network: TrustNetwork, didUpdateScore score: TrustScore, for userId: String)
}

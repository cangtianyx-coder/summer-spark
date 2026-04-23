import Foundation

// MARK: - Interaction History

/// 互动历史管理器
final class InteractionHistory {
    static let shared = InteractionHistory()
    
    private var records: [InteractionRecord] = []
    private let queue = DispatchQueue(label: "com.summerspark.interactionhistory", attributes: .concurrent)
    
    private let maxRecords = 1000
    private let storageKey = "interaction.history"
    
    weak var delegate: InteractionHistoryDelegate?
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Recording
    
    /// 记录互动
    func record(
        withUserId: String,
        type: InteractionType,
        successful: Bool,
        details: String? = nil
    ) -> InteractionRecord {
        let record = InteractionRecord(withUserId: withUserId, type: type, successful: successful, details: details)
        
        queue.sync(flags: .barrier) {
            records.append(record)
            if records.count > maxRecords {
                records.removeFirst(records.count - maxRecords)
            }
        }
        
        // 更新信任网络
        TrustNetwork.shared.recordInteraction(record)
        
        saveHistory()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.interactionHistory(self, didRecord: record)
        }
        
        Logger.shared.info("InteractionHistory: Recorded \(type.rawValue) with \(withUserId), success: \(successful)")
        return record
    }
    
    /// 记录语音通话
    func recordVoiceCall(with userId: String, successful: Bool, duration: TimeInterval? = nil) {
        let details = duration.map { "Duration: \($0)s" }
        record(withUserId: userId, type: .voiceCall, successful: successful, details: details)
    }
    
    /// 记录消息中继
    func recordMessageRelay(for userId: String, successful: Bool) {
        record(withUserId: userId, type: .messageRelay, successful: successful)
    }
    
    /// 记录救援协助
    func recordRescueAssist(with userId: String, details: String? = nil) {
        record(withUserId: userId, type: .rescueAssist, successful: true, details: details)
        
        // 救援协助额外奖励信任度
        TrustNetwork.shared.rewardRescueAction(for: userId)
    }
    
    /// 记录SOS响应
    func recordSOSResponse(for userId: String) {
        record(withUserId: userId, type: .sosResponse, successful: true)
        
        // SOS响应大幅奖励信任度
        TrustNetwork.shared.rewardRescueAction(for: userId)
    }
    
    /// 记录位置共享
    func recordLocationShare(with userId: String, successful: Bool) {
        record(withUserId: userId, type: .locationShare, successful: successful)
    }
    
    /// 记录群组活动
    func recordGroupActivity(with userId: String, groupId: String) {
        record(withUserId: userId, type: .groupActivity, successful: true, details: "Group: \(groupId)")
    }
    
    // MARK: - Query
    
    /// 获取所有历史记录
    func getAllRecords(limit: Int = 100) -> [InteractionRecord] {
        return queue.sync {
            Array(records.suffix(limit))
        }
    }
    
    /// 获取与指定用户的互动记录
    func getRecords(with userId: String, limit: Int = 50) -> [InteractionRecord] {
        return queue.sync {
            records.filter { $0.withUserId == userId }
                .suffix(limit)
        }
    }
    
    /// 获取指定类型的互动记录
    func getRecords(ofType type: InteractionType, limit: Int = 50) -> [InteractionRecord] {
        return queue.sync {
            records.filter { $0.type == type }
                .suffix(limit)
        }
    }
    
    /// 获取指定时间范围的记录
    func getRecords(from start: Date, to end: Date) -> [InteractionRecord] {
        return queue.sync {
            records.filter { $0.timestamp >= start && $0.timestamp <= end }
        }
    }
    
    /// 获取最近的互动
    func getRecentInteractions(hours: Int = 24) -> [InteractionRecord] {
        let threshold = Date().addingTimeInterval(-Double(hours) * 3600)
        return queue.sync {
            records.filter { $0.timestamp >= threshold }
        }
    }
    
    // MARK: - Statistics
    
    /// 获取互动统计
    func getStatistics(with userId: String) -> InteractionStatistics {
        return queue.sync {
            let userRecords = records.filter { $0.withUserId == userId }
            
            let totalInteractions = userRecords.count
            let successfulInteractions = userRecords.filter { $0.successful }.count
            let successRate = totalInteractions > 0 ? Double(successfulInteractions) / Double(totalInteractions) : 0
            
            let typeCounts = Dictionary(grouping: userRecords, by: { $0.type })
                .mapValues { $0.count }
            
            let lastInteraction = userRecords.last?.timestamp
            
            return InteractionStatistics(
                userId: userId,
                totalInteractions: totalInteractions,
                successfulInteractions: successfulInteractions,
                successRate: successRate,
                typeCounts: typeCounts,
                lastInteraction: lastInteraction
            )
        }
    }
    
    /// 获取最常互动的用户
    func getMostFrequentContacts(limit: Int = 10) -> [(userId: String, count: Int)] {
        return queue.sync {
            let counts = Dictionary(grouping: records, by: { $0.withUserId })
                .mapValues { $0.count }
            
            return counts.sorted { $0.value > $1.value }
                .prefix(limit)
                .map { (userId: $0.key, count: $0.value) }
        }
    }
    
    /// 获取救援贡献统计
    func getRescueStatistics() -> RescueInteractionStats {
        return queue.sync {
            let rescueRecords = records.filter { $0.type == .rescueAssist || $0.type == .sosResponse }
            
            let uniqueUsersHelped = Set(rescueRecords.map { $0.withUserId }).count
            let totalRescueCount = rescueRecords.count
            
            return RescueInteractionStats(
                totalRescues: totalRescueCount,
                uniqueUsersHelped: uniqueUsersHelped,
                sosResponses: rescueRecords.filter { $0.type == .sosResponse }.count,
                rescueAssists: rescueRecords.filter { $0.type == .rescueAssist }.count
            )
        }
    }
    
    // MARK: - Persistence
    
    private func saveHistory() {
        let recordsToSave = queue.sync { Array(records.suffix(maxRecords)) }
        
        guard let data = try? JSONEncoder().encode(recordsToSave) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loadedRecords = try? JSONDecoder().decode([InteractionRecord].self, from: data) else {
            return
        }
        
        queue.sync(flags: .barrier) {
            records = loadedRecords
        }
    }
    
    /// 清除历史
    func clearHistory(olderThan days: Int? = nil) {
        queue.sync(flags: .barrier) {
            if let days = days {
                let threshold = Date().addingTimeInterval(-Double(days) * 86400)
                records = records.filter { $0.timestamp >= threshold }
            } else {
                records.removeAll()
            }
        }
        saveHistory()
        Logger.shared.info("InteractionHistory: History cleared")
    }
}

// MARK: - Statistics Models

struct InteractionStatistics: Codable {
    let userId: String
    let totalInteractions: Int
    let successfulInteractions: Int
    let successRate: Double
    let typeCounts: [String: Int]
    let lastInteraction: Date?
}

struct RescueInteractionStats: Codable {
    let totalRescues: Int
    let uniqueUsersHelped: Int
    let sosResponses: Int
    let rescueAssists: Int
}

// MARK: - Delegate

protocol InteractionHistoryDelegate: AnyObject {
    func interactionHistory(_ history: InteractionHistory, didRecord record: InteractionRecord)
}

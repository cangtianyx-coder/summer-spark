import Foundation

// MARK: - 节点信誉追踪器
// 依赖文件：CreditEngine.swift, CreditCalculator.swift, SharedModels.swift

// MARK: - 行为类型
enum BehaviorType: String, Codable {
    // 正面行为
    case trafficForwarding = "traffic_forwarding"        // 流量转发
    case dataSharing = "data_sharing"                     // 数据分享
    case routeContribution = "route_contribution"         // 路由贡献
    case stabilityContribution = "stability_contribution" // 稳定性贡献
    case voicePacketRelay = "voice_packet_relay"          // 语音包中继

    // 负面行为
    case packetDrop = "packet_drop"                       // 丢包
    case dataTampering = "data_tampering"                 // 数据篡改
    case fakeReporting = "fake_reporting"                 // 伪造报告
    case spamBehavior = "spam_behavior"                   // 垃圾行为
    case routeManipulation = "route_manipulation"         // 路由操纵
    case creditFraud = "credit_fraud"                     // 积分欺诈
    case sybilAttack = "sybil_attack"                      // 女巫攻击
    case eclipseAttack = "eclipse_attack"                  // 日食攻击
}

// MARK: - 行为记录
struct BehaviorRecord: Codable {
    let id: String
    let nodeId: String
    let type: BehaviorType
    let timestamp: Date
    let weight: Double          // 行为权重
    let details: String?        // 详情描述
    let evidence: Data?         // 证据数据
    let sourceNodeId: String?   // 检测到该行为的节点

    var isPositive: Bool {
        switch type {
        case .trafficForwarding, .dataSharing, .routeContribution,
             .stabilityContribution, .voicePacketRelay:
            return true
        default:
            return false
        }
    }
}

// MARK: - 贡献量记录
struct ContributionRecord: Codable {
    let nodeId: String
    let periodStart: Date
    let periodEnd: Date
    var trafficForwardedBytes: UInt64 = 0
    var dataSharedBytes: UInt64 = 0
    var routesProvided: Int = 0
    var voicePacketsRelayed: Int = 0
    var successfulTransactions: Int = 0
    var totalTransactions: Int = 0

    var totalContribution: Double {
        let trafficScore = Double(trafficForwardedBytes) / 1024.0 / 1024.0  // MB
        let dataScore = Double(dataSharedBytes) / 1024.0 / 1024.0           // MB
        let routeScore = Double(routesProvided) * 10.0
        let voiceScore = Double(voicePacketsRelayed) * 0.1

        return trafficScore + dataScore + routeScore + voiceScore
    }

    var successRate: Double {
        guard totalTransactions > 0 else { return 1.0 }
        return Double(successfulTransactions) / Double(totalTransactions)
    }
}

// MARK: - 恶意行为记录
struct MaliciousBehaviorRecord: Codable {
    let id: String
    let nodeId: String
    let behaviorType: BehaviorType
    let timestamp: Date
    let severity: Severity
    let evidence: Data?
    let reportedBy: String
    var isConfirmed: Bool
    var isDismissed: Bool

    enum Severity: Int, Codable {
        case minor = 1
        case moderate = 2
        case severe = 3
        case critical = 4

        var penaltyWeight: Double {
            switch self {
            case .minor: return 0.1
            case .moderate: return 0.25
            case .severe: return 0.5
            case .critical: return 1.0
            }
        }
    }
}

// MARK: - 信誉状态
struct ReputationState {
    let nodeId: String
    var score: Double                    // 0-100
    var tier: ReputationTier
    var lastActivityDate: Date
    var lastUpdated: Date
    var totalPositiveBehaviors: Int
    var totalNegativeBehaviors: Int
    var consecutivePositiveEvents: Int
    var consecutiveNegativeEvents: Int
    var isOnBlacklist: Bool
    var blacklistReason: String?
    var blacklistExpiresAt: Date?

    enum ReputationTier: Int, Comparable {
        case unknown = 0
        case veryLow = 1
        case low = 2
        case medium = 3
        case high = 4
        case veryHigh = 5

        static func < (lhs: ReputationTier, rhs: ReputationTier) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        static func from(score: Double) -> ReputationTier {
            switch score {
            case 80...100: return .veryHigh
            case 60..<80: return .high
            case 40..<60: return .medium
            case 20..<40: return .low
            case 1..<20: return .veryLow
            default: return .unknown
            }
        }

        var displayName: String {
            switch self {
            case .unknown: return "Unknown"
            case .veryLow: return "Very Low"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .veryHigh: return "Very High"
            }
        }
    }

    mutating func updateTier() {
        tier = ReputationTier.from(score: score)
    }
}

// MARK: - 信誉统计
struct ReputationStatistics {
    var totalNodesTracked: Int = 0
    var nodesOnBlacklist: Int = 0
    var averageReputationScore: Double = 0
    var totalMaliciousBehaviorsDetected: Int = 0
    var totalPositiveBehaviorsRecorded: Int = 0

    mutating func reset() {
        totalNodesTracked = 0
        nodesOnBlacklist = 0
        averageReputationScore = 0
        totalMaliciousBehaviorsDetected = 0
        totalPositiveBehaviorsRecorded = 0
    }
}

// MARK: - 衰减配置
struct DecayConfiguration {
    var enabled: Bool = true
    var decayRatePerDay: Double = 0.5           // 每天衰减0.5分
    var inactivityThresholdDays: Int = 7        // 7天不活跃开始衰减
    var maxDecayScore: Double = 20.0            // 最大衰减20分
    var minScore: Double = 0                    // 最低分数
}

// MARK: - ReputationTracker 委托协议
protocol ReputationTrackerDelegate: AnyObject {
    func reputationTracker(_ tracker: ReputationTracker, didUpdateReputation nodeId: String, newScore: Double, oldScore: Double)
    func reputationTracker(_ tracker: ReputationTracker, didAddToBlacklist nodeId: String, reason: String)
    func reputationTracker(_ tracker: ReputationTracker, didRemoveFromBlacklist nodeId: String)
    func reputationTracker(_ tracker: ReputationTracker, didRecordBehavior record: BehaviorRecord)
    func reputationTracker(_ tracker: ReputationTracker, didDetectMaliciousBehavior record: MaliciousBehaviorRecord)
}

// MARK: - 默认实现
extension ReputationTrackerDelegate {
    func reputationTracker(_ tracker: ReputationTracker, didUpdateReputation nodeId: String, newScore: Double, oldScore: Double) {}
    func reputationTracker(_ tracker: ReputationTracker, didAddToBlacklist nodeId: String, reason: String) {}
    func reputationTracker(_ tracker: ReputationTracker, didRemoveFromBlacklist nodeId: String) {}
    func reputationTracker(_ tracker: ReputationTracker, didRecordBehavior record: BehaviorRecord) {}
    func reputationTracker(_ tracker: ReputationTracker, didDetectMaliciousBehavior record: MaliciousBehaviorRecord) {}
}

// MARK: - ReputationTracker 主类
final class ReputationTracker {
    static let shared = ReputationTracker()

    // MARK: - 属性
    private let creditEngine: CreditEngine
    private let creditCalculator: CreditCalculator

    private var nodeStates: [String: ReputationState] = [:]
    private let nodeStatesLock = NSLock()

    private var behaviorRecords: [String: [BehaviorRecord]] = [:]  // nodeId -> records
    private let behaviorRecordsLock = NSLock()

    private var contributionRecords: [String: [ContributionRecord]] = [:]
    private let contributionRecordsLock = NSLock()

    private var maliciousBehaviorRecords: [MaliciousBehaviorRecord] = []
    private let maliciousRecordsLock = NSLock()

    private var decayConfig = DecayConfiguration()
    private let decayConfigLock = NSLock()

    private var statistics = ReputationStatistics()
    private let statisticsLock = NSLock()

    private var decayTimer: DispatchSourceTimer?
    private let decayQueue = DispatchQueue(label: "com.summerspark.reputation.decay", qos: .background)

    private var behaviorWeightConfig: BehaviorWeightConfig = BehaviorWeightConfig()

    weak var delegate: ReputationTrackerDelegate?

    // MARK: - 行为权重配置
    struct BehaviorWeightConfig {
        var trafficForwarding: Double = 1.0
        var dataSharing: Double = 1.2
        var routeContribution: Double = 1.5
        var stabilityContribution: Double = 2.0
        var voicePacketRelay: Double = 0.8

        var packetDrop: Double = -5.0
        var dataTampering: Double = -10.0
        var fakeReporting: Double = -8.0
        var spamBehavior: Double = -3.0
        var routeManipulation: Double = -10.0
        var creditFraud: Double = -15.0
        var sybilAttack: Double = -20.0
        var eclipseAttack: Double = -20.0

        func weight(for behaviorType: BehaviorType) -> Double {
            switch behaviorType {
            case .trafficForwarding: return trafficForwarding
            case .dataSharing: return dataSharing
            case .routeContribution: return routeContribution
            case .stabilityContribution: return stabilityContribution
            case .voicePacketRelay: return voicePacketRelay
            case .packetDrop: return packetDrop
            case .dataTampering: return dataTampering
            case .fakeReporting: return fakeReporting
            case .spamBehavior: return spamBehavior
            case .routeManipulation: return routeManipulation
            case .creditFraud: return creditFraud
            case .sybilAttack: return sybilAttack
            case .eclipseAttack: return eclipseAttack
            }
        }
    }

    // MARK: - 初始化
    init(creditEngine: CreditEngine = .shared, creditCalculator: CreditCalculator = .shared) {
        self.creditEngine = creditEngine
        self.creditCalculator = creditCalculator
        loadPersistedData()
    }

    deinit {
        stopDecayTimer()
    }

    // MARK: - 生命周期
    func start() {
        startDecayTimer()
    }

    func stop() {
        stopDecayTimer()
    }

    private func startDecayTimer() {
        decayTimer?.cancel()

        decayTimer = DispatchSource.makeTimerSource(queue: decayQueue)
        decayTimer?.schedule(deadline: .now() + 3600, repeating: 3600)  // 每小时检查一次
        decayTimer?.setEventHandler { [weak self] in
            self?.processDecay()
        }
        decayTimer?.resume()
    }

    private func stopDecayTimer() {
        decayTimer?.cancel()
        decayTimer = nil
    }

    // MARK: - 节点状态管理
    func getReputationState(for nodeId: String) -> ReputationState? {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }
        return nodeStates[nodeId]
    }

    func getReputationScore(for nodeId: String) -> Double {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        return nodeStates[nodeId]?.score ?? 50.0  // 默认50分
    }

    func getReputationTier(for nodeId: String) -> ReputationState.ReputationTier {
        let score = getReputationScore(for: nodeId)
        return ReputationState.ReputationTier.from(score: score)
    }

    func registerNode(_ nodeId: String, initialScore: Double = 50.0) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if nodeStates[nodeId] == nil {
            let now = Date()
            var state = ReputationState(
                nodeId: nodeId,
                score: initialScore,
                tier: ReputationState.ReputationTier.from(score: initialScore),
                lastActivityDate: now,
                lastUpdated: now,
                totalPositiveBehaviors: 0,
                totalNegativeBehaviors: 0,
                consecutivePositiveEvents: 0,
                consecutiveNegativeEvents: 0,
                isOnBlacklist: false,
                blacklistReason: nil,
                blacklistExpiresAt: nil
            )
            state.updateTier()
            nodeStates[nodeId] = state
        }
    }

    // MARK: - 行为记录
    func recordBehavior(
        nodeId: String,
        type: BehaviorType,
        details: String? = nil,
        evidence: Data? = nil,
        sourceNodeId: String? = nil
    ) {
        // 确保节点已注册
        registerNode(nodeId)

        let weight = behaviorWeightConfig.weight(for: type)

        let record = BehaviorRecord(
            id: UUID().uuidString,
            nodeId: nodeId,
            type: type,
            timestamp: Date(),
            weight: weight,
            details: details,
            evidence: evidence,
            sourceNodeId: sourceNodeId
        )

        // 存储记录
        behaviorRecordsLock.lock()
        if behaviorRecords[nodeId] == nil {
            behaviorRecords[nodeId] = []
        }
        behaviorRecords[nodeId]?.append(record)
        // 保留最近1000条记录
        if let count = behaviorRecords[nodeId]?.count, count > 1000 {
            behaviorRecords[nodeId]?.removeFirst(count - 1000)
        }
        behaviorRecordsLock.unlock()

        // 更新信誉分数
        updateReputation(for: nodeId, behaviorWeight: weight, isPositive: record.isPositive)

        // 更新贡献量
        if record.isPositive {
            updateContribution(for: nodeId, behaviorType: type)
        }

        delegate?.reputationTracker(self, didRecordBehavior: record)

        statisticsLock.lock()
        if record.isPositive {
            statistics.totalPositiveBehaviorsRecorded += 1
        }
        statisticsLock.unlock()
    }

    private func updateContribution(for nodeId: String, behaviorType: BehaviorType) {
        contributionRecordsLock.lock()
        defer { contributionRecordsLock.unlock() }

        let now = Date()
        let periodStart = Calendar.current.startOfDay(for: now)
        let periodEnd = Calendar.current.date(byAdding: .day, value: 1, to: periodStart) ?? periodStart.addingTimeInterval(86400)

        if contributionRecords[nodeId] == nil {
            contributionRecords[nodeId] = []
        }

        // 找到当前周期的记录或创建新记录
        var currentPeriod: ContributionRecord?
        if let existing = contributionRecords[nodeId]?.first(where: { $0.periodStart == periodStart }) {
            currentPeriod = existing
        }

        var record: ContributionRecord
        if var existing = currentPeriod {
            switch behaviorType {
            case .trafficForwarding:
                existing.trafficForwardedBytes += 1024  // 默认增加1KB
            case .dataSharing:
                existing.dataSharedBytes += 1024
            case .routeContribution:
                existing.routesProvided += 1
            case .voicePacketRelay:
                existing.voicePacketsRelayed += 1
            default:
                break
            }
            record = existing
        } else {
            record = ContributionRecord(
                nodeId: nodeId,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
            switch behaviorType {
            case .trafficForwarding:
                record.trafficForwardedBytes = 1024
            case .dataSharing:
                record.dataSharedBytes = 1024
            case .routeContribution:
                record.routesProvided = 1
            case .voicePacketRelay:
                record.voicePacketsRelayed = 1
            default:
                break
            }
        }

        // 更新或添加记录
        if let index = contributionRecords[nodeId]?.firstIndex(where: { $0.periodStart == periodStart }) {
            contributionRecords[nodeId]?[index] = record
        } else {
            contributionRecords[nodeId]?.append(record)
        }

        // 保留最近30天的记录
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)
        contributionRecords[nodeId]?.removeAll { $0.periodStart < thirtyDaysAgo }
    }

    // MARK: - 信誉更新
    private func updateReputation(for nodeId: String, behaviorWeight: Double, isPositive: Bool) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        guard var state = nodeStates[nodeId] else { return }

        let oldScore = state.score

        if isPositive {
            // 正面行为：加分（递减奖励）
            let bonusMultiplier = 1.0 - (Double(state.consecutivePositiveEvents) * 0.1)
            let scoreIncrease = behaviorWeight * max(0.1, min(1.0, bonusMultiplier))
            state.score = min(100, state.score + scoreIncrease)

            state.totalPositiveBehaviors += 1
            state.consecutivePositiveEvents += 1
            state.consecutiveNegativeEvents = 0
        } else {
            // 负面行为：减分
            let penaltyMultiplier = 1.0 + (Double(state.consecutiveNegativeEvents) * 0.2)
            let scoreDecrease = abs(behaviorWeight) * max(1.0, penaltyMultiplier)
            state.score = max(0, state.score - scoreDecrease)

            state.totalNegativeBehaviors += 1
            state.consecutiveNegativeEvents += 1
            state.consecutivePositiveEvents = 0

            // 检查是否加入黑名单
            if state.score < 10 {
                addToBlacklist(nodeId: nodeId, reason: "Reputation score below threshold", expiresAt: nil)
            }
        }

        state.lastActivityDate = Date()
        state.lastUpdated = Date()
        state.updateTier()
        nodeStates[nodeId] = state

        if oldScore != state.score {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.reputationTracker(self, didUpdateReputation: nodeId, newScore: state.score, oldScore: oldScore)
            }
        }
    }

    // MARK: - 恶意行为检测
    func reportMaliciousBehavior(
        nodeId: String,
        behaviorType: BehaviorType,
        severity: MaliciousBehaviorRecord.Severity,
        evidence: Data? = nil,
        reportedBy: String
    ) {
        let record = MaliciousBehaviorRecord(
            id: UUID().uuidString,
            nodeId: nodeId,
            behaviorType: behaviorType,
            timestamp: Date(),
            severity: severity,
            evidence: evidence,
            reportedBy: reportedBy,
            isConfirmed: false,
            isDismissed: false
        )

        maliciousRecordsLock.lock()
        maliciousBehaviorRecords.append(record)
        maliciousRecordsLock.unlock()

        // 记录负面行为
        let weight = behaviorWeightConfig.weight(for: behaviorType)
        recordBehavior(nodeId: nodeId, type: behaviorType, evidence: evidence, sourceNodeId: reportedBy)

        delegate?.reputationTracker(self, didDetectMaliciousBehavior: record)

        statisticsLock.lock()
        statistics.totalMaliciousBehaviorsDetected += 1
        statisticsLock.unlock()

        // 根据严重程度立即降级或加入黑名单
        if severity == .critical {
            addToBlacklist(nodeId: nodeId, reason: "Critical malicious behavior: \(behaviorType.rawValue)", expiresAt: Date().addingTimeInterval(86400 * 7))
        } else if severity == .severe {
            // 大幅降低信誉分
            let score = getReputationScore(for: nodeId)
            nodeStatesLock.lock()
            if var state = nodeStates[nodeId] {
                state.score = max(0, score - 30)
                state.updateTier()
                nodeStates[nodeId] = state
            }
            nodeStatesLock.unlock()
        }
    }

    func confirmMaliciousBehavior(recordId: String) {
        maliciousRecordsLock.lock()
        defer { maliciousRecordsLock.unlock() }

        if let index = maliciousBehaviorRecords.firstIndex(where: { $0.id == recordId }) {
            maliciousBehaviorRecords[index].isConfirmed = true
        }
    }

    func dismissMaliciousBehavior(recordId: String) {
        maliciousRecordsLock.lock()
        defer { maliciousRecordsLock.unlock() }

        if let index = maliciousBehaviorRecords.firstIndex(where: { $0.id == recordId }) {
            maliciousBehaviorRecords[index].isDismissed = true
        }
    }

    // MARK: - 黑名单管理
    func addToBlacklist(nodeId: String, reason: String, expiresAt: Date?) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if var state = nodeStates[nodeId] {
            state.isOnBlacklist = true
            state.blacklistReason = reason
            state.blacklistExpiresAt = expiresAt
            state.score = 0  // 黑名单节点分数归零
            nodeStates[nodeId] = state
        }

        delegate?.reputationTracker(self, didAddToBlacklist: nodeId, reason: reason)

        statisticsLock.lock()
        statistics.nodesOnBlacklist += 1
        statisticsLock.unlock()
    }

    func removeFromBlacklist(nodeId: String) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if var state = nodeStates[nodeId] {
            state.isOnBlacklist = false
            state.blacklistReason = nil
            state.blacklistExpiresAt = nil
            state.score = 20  // 恢复时给予最低分数
            state.updateTier()
            nodeStates[nodeId] = state
        }

        delegate?.reputationTracker(self, didRemoveFromBlacklist: nodeId)

        statisticsLock.lock()
        statistics.nodesOnBlacklist = max(0, statistics.nodesOnBlacklist - 1)
        statisticsLock.unlock()
    }

    func isOnBlacklist(_ nodeId: String) -> Bool {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        guard let state = nodeStates[nodeId] else { return false }

        if !state.isOnBlacklist {
            return false
        }

        // 检查是否过期
        if let expiresAt = state.blacklistExpiresAt, Date() >= expiresAt {
            return false
        }

        return true
    }

    // MARK: - 衰减处理
    private func processDecay() {
        decayConfigLock.lock()
        guard decayConfig.enabled else {
            decayConfigLock.unlock()
            return
        }
        let config = decayConfig
        decayConfigLock.unlock()

        nodeStatesLock.lock()
        let nodeIds = Array(nodeStates.keys)
        nodeStatesLock.unlock()

        let now = Date()

        for nodeId in nodeIds {
            nodeStatesLock.lock()
            guard var state = nodeStates[nodeId] else {
                nodeStatesLock.unlock()
                continue
            }

            // 跳过黑名单节点
            if state.isOnBlacklist {
                nodeStatesLock.unlock()
                continue
            }

            // 检查是否不活跃
            let daysSinceActivity = Calendar.current.dateComponents([.day], from: state.lastActivityDate, to: now).day ?? 0

            if daysSinceActivity >= config.inactivityThresholdDays {
                // 计算衰减
                let decayAmount = min(config.decayRatePerDay * Double(daysSinceActivity), config.maxDecayScore)
                state.score = max(config.minScore, state.score - decayAmount)
                state.lastUpdated = now
                state.updateTier()
                nodeStates[nodeId] = state
            }

            // 处理过期黑名单
            if state.isOnBlacklist, let expiresAt = state.blacklistExpiresAt, now >= expiresAt {
                state.isOnBlacklist = false
                state.blacklistReason = nil
                state.blacklistExpiresAt = nil
                state.score = 20
                state.updateTier()
                nodeStates[nodeId] = state

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.reputationTracker(self, didRemoveFromBlacklist: nodeId)
                }
            }

            nodeStatesLock.unlock()
        }
    }

    // MARK: - 贡献量查询
    func getTotalContribution(for nodeId: String) -> Double {
        contributionRecordsLock.lock()
        defer { contributionRecordsLock.unlock() }

        return contributionRecords[nodeId]?.reduce(0) { $0 + $1.totalContribution } ?? 0
    }

    func getContributionHistory(for nodeId: String, days: Int = 7) -> [ContributionRecord] {
        contributionRecordsLock.lock()
        defer { contributionRecordsLock.unlock() }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date().addingTimeInterval(-Double(days) * 86400)

        return contributionRecords[nodeId]?.filter { $0.periodStart >= cutoffDate } ?? []
    }

    // MARK: - 行为历史查询
    func getBehaviorHistory(for nodeId: String, limit: Int = 100) -> [BehaviorRecord] {
        behaviorRecordsLock.lock()
        defer { behaviorRecordsLock.unlock() }

        let records = behaviorRecords[nodeId] ?? []
        return Array(records.suffix(limit))
    }

    func getRecentBehaviors(for nodeId: String, since: Date) -> [BehaviorRecord] {
        behaviorRecordsLock.lock()
        defer { behaviorRecordsLock.unlock() }

        return behaviorRecords[nodeId]?.filter { $0.timestamp >= since } ?? []
    }

    // MARK: - 配置
    func updateDecayConfiguration(_ config: DecayConfiguration) {
        decayConfigLock.lock()
        decayConfig = config
        decayConfigLock.unlock()
    }

    func updateBehaviorWeights(_ config: BehaviorWeightConfig) {
        behaviorWeightConfig = config
    }

    // MARK: - 统计
    func getStatistics() -> ReputationStatistics {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }

        var stats = statistics

        nodeStatesLock.lock()
        stats.totalNodesTracked = nodeStates.count
        nodeStatesLock.unlock()

        return stats
    }

    func resetStatistics() {
        statisticsLock.lock()
        statistics.reset()
        statisticsLock.unlock()
    }

    // MARK: - 持久化
    private func loadPersistedData() {
        // 加载节点状态
        if let data = UserDefaults.standard.data(forKey: "ReputationNodeStates"),
           let states = try? JSONDecoder().decode([String: ReputationState].self, from: data) {
            nodeStatesLock.lock()
            nodeStates = states
            nodeStatesLock.unlock()
        }

        // 加载恶意行为记录
        if let data = UserDefaults.standard.data(forKey: "MaliciousBehaviorRecords"),
           let records = try? JSONDecoder().decode([MaliciousBehaviorRecord].self, from: data) {
            maliciousRecordsLock.lock()
            maliciousBehaviorRecords = records.filter { !$0.isDismissed }
            maliciousRecordsLock.unlock()
        }
    }

    func persistData() {
        nodeStatesLock.lock()
        let statesToSave = nodeStates
        nodeStatesLock.unlock()

        if let data = try? JSONEncoder().encode(statesToSave) {
            UserDefaults.standard.set(data, forKey: "ReputationNodeStates")
        }

        maliciousRecordsLock.lock()
        let recordsToSave = maliciousBehaviorRecords
        maliciousRecordsLock.unlock()

        if let data = try? JSONEncoder().encode(recordsToSave) {
            UserDefaults.standard.set(data, forKey: "MaliciousBehaviorRecords")
        }
    }

    // MARK: - 信誉恢复
    func requestReputationRecovery(nodeId: String, additionalInfo: [String: Any] = [:]) -> Bool {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        guard let state = nodeStates[nodeId] else { return false }

        // 验证条件：必须在黑名单外，有足够的正面行为记录
        guard !state.isOnBlacklist else { return false }
        guard state.consecutivePositiveEvents >= 10 else { return false }

        // 信誉慢慢恢复
        var mutableState = state
        mutableState.score = min(100, mutableState.score + 10)
        mutableState.updateTier()
        nodeStates[nodeId] = mutableState

        return true
    }

    // MARK: - 批量查询
    func getAllNodeReputations() -> [String: Double] {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        var result: [String: Double] = [:]
        for (nodeId, state) in nodeStates {
            result[nodeId] = state.score
        }
        return result
    }

    func getNodesByTier(_ tier: ReputationState.ReputationTier) -> [String] {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        return nodeStates.filter { $0.value.tier == tier }.map { $0.key }
    }

    func getTopReputableNodes(limit: Int = 10) -> [(nodeId: String, score: Double)] {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        return nodeStates
            .map { ($0.key, $0.value.score) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { ($0.0, $0.1) }
    }
}

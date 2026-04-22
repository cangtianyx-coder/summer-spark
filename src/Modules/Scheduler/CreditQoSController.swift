import Foundation

// MARK: - 积分 QoS 控制器
// 依赖文件：CreditEngine.swift, PriorityScheduler.swift, QoSModels.swift, SharedModels.swift

// MARK: - QoS 权限级别
enum QoSPermissionLevel: Int, Comparable {
    case restricted = 0    // 受限：最低优先级，限流
    case basic = 1         // 基本：普通优先级
    case priority = 2      // 优先：高优先级，较多带宽
    case premium = 3       // 高级：最高优先级，最优路由

    static func < (lhs: QoSPermissionLevel, rhs: QoSPermissionLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .restricted: return "Restricted"
        case .basic: return "Basic"
        case .priority: return "Priority"
        case .premium: return "Premium"
        }
    }
}

// MARK: - 流量整形配置
struct TrafficShapingConfig {
    var maxTokensPerSecond: Double = 10.0      // 每秒最大令牌数
    var bucketSize: Double = 50.0               // 令牌桶大小
    var burstAllowance: Double = 1.5            // 突发允许倍数
    var cooldownPeriod: TimeInterval = 60.0     // 限流冷却期

    static let `default` = TrafficShapingConfig()

    static let restricted = TrafficShapingConfig(
        maxTokensPerSecond: 1.0,
        bucketSize: 5.0,
        burstAllowance: 1.1,
        cooldownPeriod: 120.0
    )

    static let basic = TrafficShapingConfig(
        maxTokensPerSecond: 10.0,
        bucketSize: 50.0,
        burstAllowance: 1.5,
        cooldownPeriod: 60.0
    )

    static let priority = TrafficShapingConfig(
        maxTokensPerSecond: 50.0,
        bucketSize: 200.0,
        burstAllowance: 2.0,
        cooldownPeriod: 30.0
    )

    static let premium = TrafficShapingConfig(
        maxTokensPerSecond: Double.greatestFiniteMagnitude,
        bucketSize: Double.greatestFiniteMagnitude,
        burstAllowance: 3.0,
        cooldownPeriod: 0.0
    )
}

// MARK: - 节点 QoS 状态
struct NodeQoSState {
    let nodeId: String
    var permissionLevel: QoSPermissionLevel
    var trafficShapingConfig: TrafficShapingConfig
    var currentTokenBalance: Double
    var lastTokenRefillTime: Date
    var activeFlows: Set<String>
    var totalBandwidthAllocated: Double
    var currentBandwidthUsed: Double
    var isRateLimited: Bool
    var rateLimitExpiresAt: Date?
    var creditFrozenAmount: Double
    var frozenReason: String?

    init(nodeId: String, permissionLevel: QoSPermissionLevel = .basic) {
        self.nodeId = nodeId
        self.permissionLevel = permissionLevel
        self.trafficShapingConfig = TrafficShapingConfig.basic
        self.currentTokenBalance = 50.0
        self.lastTokenRefillTime = Date()
        self.activeFlows = []
        self.totalBandwidthAllocated = 0
        self.currentBandwidthUsed = 0
        self.isRateLimited = false
        self.rateLimitExpiresAt = nil
        self.creditFrozenAmount = 0
        self.frozenReason = nil
    }

    mutating func updatePermission(_ level: QoSPermissionLevel) {
        permissionLevel = level
        switch level {
        case .restricted:
            trafficShapingConfig = TrafficShapingConfig.restricted
        case .basic:
            trafficShapingConfig = TrafficShapingConfig.basic
        case .priority:
            trafficShapingConfig = TrafficShapingConfig.priority
        case .premium:
            trafficShapingConfig = TrafficShapingConfig.premium
        }
    }

    mutating func applyRateLimit(duration: TimeInterval) {
        isRateLimited = true
        rateLimitExpiresAt = Date().addingTimeInterval(duration)
    }

    mutating func clearRateLimit() {
        isRateLimited = false
        rateLimitExpiresAt = nil
    }

    mutating func freezeCredits(amount: Double, reason: String) {
        creditFrozenAmount = amount
        frozenReason = reason
    }

    mutating func unfreezeCredits() {
        creditFrozenAmount = 0
        frozenReason = nil
    }
}

// MARK: - 积分冻结记录
struct CreditFreezeRecord: Codable {
    let id: String
    let nodeId: String
    let amount: Double
    let reason: String
    let frozenAt: Date
    let frozenBy: String
    let expiresAt: Date?
    var unfrozenAt: Date?

    var isActive: Bool {
        return unfrozenAt == nil && (expiresAt == nil || Date() < expiresAt!)
    }
}

// MARK: - QoS 路由决策
struct QoSRoutingDecision {
    let flowId: String
    let nodeId: String
    let qosClass: QoSClass
    let permissionLevel: QoSPermissionLevel
    let allocatedBandwidth: Double
    let priority: MessagePriority
    let estimatedLatency: TimeInterval
    let routeStability: Double
    let creditCost: Double
    let timestamp: Date

    var isHighPriority: Bool {
        return permissionLevel >= .priority
    }
}

// MARK: - QoS 统计
struct QoSStatistics {
    var totalFlowsProcessed: Int = 0
    var totalBandwidthAllocated: Double = 0
    var totalCreditsCharged: Double = 0
    var restrictedNodesCount: Int = 0
    var premiumNodesCount: Int = 0
    var frozenCreditsTotal: Double = 0
    var rateLimitedRequests: Int = 0
    var rejectedRequests: Int = 0

    mutating func reset() {
        totalFlowsProcessed = 0
        totalBandwidthAllocated = 0
        totalCreditsCharged = 0
        restrictedNodesCount = 0
        premiumNodesCount = 0
        frozenCreditsTotal = 0
        rateLimitedRequests = 0
        rejectedRequests = 0
    }
}

// MARK: - CreditQoSController 委托协议
protocol CreditQoSControllerDelegate: AnyObject {
    func qosController(_ controller: CreditQoSController, didUpdatePermission nodeId: String, level: QoSPermissionLevel)
    func qosController(_ controller: CreditQoSController, didApplyRateLimit nodeId: String, duration: TimeInterval)
    func qosController(_ controller: CreditQoSController, didFreezeCredits nodeId: String, amount: Double, reason: String)
    func qosController(_ controller: CreditQoSController, didUnfreezeCredits nodeId: String)
    func qosController(_ controller: CreditQoSController, didRejectFlow flowId: String, reason: String)
}

// MARK: - 默认实现
extension CreditQoSControllerDelegate {
    func qosController(_ controller: CreditQoSController, didUpdatePermission nodeId: String, level: QoSPermissionLevel) {}
    func qosController(_ controller: CreditQoSController, didApplyRateLimit nodeId: String, duration: TimeInterval) {}
    func qosController(_ controller: CreditQoSController, didFreezeCredits nodeId: String, amount: Double, reason: String) {}
    func qosController(_ controller: CreditQoSController, didUnfreezeCredits nodeId: String) {}
    func qosController(_ controller: CreditQoSController, didRejectFlow flowId: String, reason: String) {}
}

// MARK: - CreditQoSController 主类
final class CreditQoSController {
    static let shared = CreditQoSController()

    // MARK: - 属性
    private let creditEngine: CreditEngine
    private let priorityScheduler: PriorityScheduler

    private var nodeStates: [String: NodeQoSState] = [:]
    private let nodeStatesLock = NSLock()

    private var creditFreezeRecords: [CreditFreezeRecord] = []
    private let freezeRecordsLock = NSLock()

    private var statistics = QoSStatistics()
    private let statisticsLock = NSLock()

    private var updateTimer: DispatchSourceTimer?
    private let updateQueue = DispatchQueue(label: "com.summerspark.creditqos.updater", qos: .utility)

    weak var delegate: CreditQoSControllerDelegate?

    // 信用阈值配置
    private var creditThresholds: CreditThresholds = CreditThresholds()

    struct CreditThresholds {
        var premiumMinCredits: Double = 5000
        var priorityMinCredits: Double = 1000
        var basicMinCredits: Double = 100
        var restrictedMaxCredits: Double = 10
    }

    // 路由权重配置
    private var routingWeights: RoutingWeights = RoutingWeights()

    struct RoutingWeights {
        var creditWeight: Double = 0.4
        var stabilityWeight: Double = 0.3
        var bandwidthWeight: Double = 0.2
        var latencyWeight: Double = 0.1
    }

    // MARK: - 初始化
    init(creditEngine: CreditEngine = .shared, priorityScheduler: PriorityScheduler = .shared) {
        self.creditEngine = creditEngine
        self.priorityScheduler = priorityScheduler
        loadCreditFreezeRecords()
    }

    deinit {
        stopUpdates()
    }

    // MARK: - 生命周期
    func start() {
        startUpdateTimer()
    }

    func stop() {
        stopUpdates()
    }

    private func startUpdateTimer() {
        updateTimer?.cancel()

        updateTimer = DispatchSource.makeTimerSource(queue: updateQueue)
        updateTimer?.schedule(deadline: .now() + 1.0, repeating: 1.0)
        updateTimer?.setEventHandler { [weak self] in
            self?.processPeriodicUpdates()
        }
        updateTimer?.resume()
    }

    private func stopUpdates() {
        updateTimer?.cancel()
        updateTimer = nil
    }

    // MARK: - 节点状态管理
    func getNodeState(_ nodeId: String) -> NodeQoSState? {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }
        return nodeStates[nodeId]
    }

    func registerNode(_ nodeId: String, initialPermission: QoSPermissionLevel = .basic) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if nodeStates[nodeId] == nil {
            var state = NodeQoSState(nodeId: nodeId, permissionLevel: initialPermission)
            state.updatePermission(initialPermission)
            nodeStates[nodeId] = state
        }
    }

    func unregisterNode(_ nodeId: String) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }
        nodeStates.removeValue(forKey: nodeId)
    }

    // MARK: - QoS 权限计算
    func calculatePermissionLevel(for nodeId: String) -> QoSPermissionLevel {
        let balance = creditEngine.getBalance()

        // 检查是否有冻结记录
        if isCreditsFrozen(for: nodeId) {
            return .restricted
        }

        if balance >= creditThresholds.premiumMinCredits {
            return .premium
        } else if balance >= creditThresholds.priorityMinCredits {
            return .priority
        } else if balance >= creditThresholds.basicMinCredits {
            return .basic
        } else {
            return .restricted
        }
    }

    func updateNodePermission(_ nodeId: String) {
        let newLevel = calculatePermissionLevel(for: nodeId)

        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if var state = nodeStates[nodeId] {
            state.updatePermission(newLevel)
            nodeStates[nodeId] = state
            delegate?.qosController(self, didUpdatePermission: nodeId, level: newLevel)
        }
    }

    func updateAllNodePermissions() {
        nodeStatesLock.lock()
        let nodeIds = Array(nodeStates.keys)
        nodeStatesLock.unlock()

        for nodeId in nodeIds {
            updateNodePermission(nodeId)
        }
    }

    // MARK: - 流量整形
    func checkTokenBucket(nodeId: String, tokensRequired: Double) -> Bool {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        guard var state = nodeStates[nodeId] else { return false }

        // 检查是否被限流
        if state.isRateLimited {
            if let expiresAt = state.rateLimitExpiresAt, Date() >= expiresAt {
                state.clearRateLimit()
            } else {
                statisticsLock.lock()
                statistics.rateLimitedRequests += 1
                statisticsLock.unlock()
                return false
            }
        }

        // 重新填充令牌
        refillTokens(&state)

        // 检查令牌是否足够
        if state.currentTokenBalance >= tokensRequired {
            state.currentTokenBalance -= tokensRequired
            nodeStates[nodeId] = state
            return true
        } else {
            nodeStates[nodeId] = state
            return false
        }
    }

    func consumeTokens(nodeId: String, amount: Double) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        guard var state = nodeStates[nodeId] else { return }

        refillTokens(&state)
        state.currentTokenBalance = max(0, state.currentTokenBalance - amount)
        nodeStates[nodeId] = state
    }

    private func refillTokens(_ state: inout NodeQoSState) {
        let now = Date()
        let elapsed = now.timeIntervalSince(state.lastTokenRefillTime)
        let tokensToAdd = elapsed * state.trafficShapingConfig.maxTokensPerSecond

        state.currentTokenBalance = min(
            state.trafficShapingConfig.bucketSize,
            state.currentTokenBalance + tokensToAdd
        )
        state.lastTokenRefillTime = now
    }

    // MARK: - 路由决策
    func makeRoutingDecision(
        flowId: String,
        nodeId: String,
        qosClass: QoSClass,
        availableRoutes: [(routeId: String, bandwidth: Double, latency: TimeInterval, stability: Double)]
    ) -> QoSRoutingDecision? {
        let permissionLevel = calculatePermissionLevel(for: nodeId)
        let account = creditEngine.getAccount()

        // 根据权限级别筛选路由
        let eligibleRoutes: [(routeId: String, bandwidth: Double, latency: TimeInterval, stability: Double)]

        if permissionLevel == .premium {
            // Premium 节点可以使用所有路由
            eligibleRoutes = availableRoutes
        } else if permissionLevel == .priority {
            // Priority 节点可以使用良好的路由
            eligibleRoutes = availableRoutes.filter { $0.stability >= 0.5 }
        } else if permissionLevel == .basic {
            // Basic 节点只能使用稳定的路由
            eligibleRoutes = availableRoutes.filter { $0.stability >= 0.7 }
        } else {
            // Restricted 节点只能使用最好的路由
            eligibleRoutes = availableRoutes.filter { $0.stability >= 0.8 && $0.latency < 100 }
        }

        guard !eligibleRoutes.isEmpty else {
            delegate?.qosController(self, didRejectFlow: flowId, reason: "No eligible routes")
            statisticsLock.lock()
            statistics.rejectedRequests += 1
            statisticsLock.unlock()
            return nil
        }

        // 计算最佳路由
        let bestRoute = selectBestRoute(routes: eligibleRoutes, permissionLevel: permissionLevel)

        // 计算分配的带宽
        let allocatedBandwidth = calculateAllocatedBandwidth(
            route: bestRoute,
            permissionLevel: permissionLevel,
            qosClass: qosClass
        )

        // 计算积分费用
        let creditCost = calculateRoutingCost(
            bandwidth: allocatedBandwidth,
            qosClass: qosClass,
            permissionLevel: permissionLevel
        )

        statisticsLock.lock()
        statistics.totalFlowsProcessed += 1
        statistics.totalBandwidthAllocated += allocatedBandwidth
        statistics.totalCreditsCharged += creditCost
        statisticsLock.unlock()

        return QoSRoutingDecision(
            flowId: flowId,
            nodeId: nodeId,
            qosClass: qosClass,
            permissionLevel: permissionLevel,
            allocatedBandwidth: allocatedBandwidth,
            priority: qosClassToPriority(qosClass, permissionLevel: permissionLevel),
            estimatedLatency: bestRoute.latency,
            routeStability: bestRoute.stability,
            creditCost: creditCost,
            timestamp: Date()
        )
    }

    private func selectBestRoute(
        routes: [(routeId: String, bandwidth: Double, latency: TimeInterval, stability: Double)],
        permissionLevel: QoSPermissionLevel
    ) -> (routeId: String, bandwidth: Double, latency: TimeInterval, stability: Double) {
        // 根据权限级别使用不同的选择策略
        switch permissionLevel {
        case .premium:
            // Premium：选择最低延迟
            return routes.min { $0.latency < $1.latency } ?? routes[0]
        case .priority:
            // Priority：平衡稳定性和延迟
            return routes.max { ($0.stability / ($0.latency + 1)) < ($1.stability / ($1.latency + 1)) } ?? routes[0]
        case .basic:
            // Basic：优先稳定性
            return routes.max { $0.stability < $1.stability } ?? routes[0]
        case .restricted:
            // Restricted：只选最稳定的
            return routes.max { $0.stability < $1.stability } ?? routes[0]
        }
    }

    private func calculateAllocatedBandwidth(
        route: (routeId: String, bandwidth: Double, latency: TimeInterval, stability: Double),
        permissionLevel: QoSPermissionLevel,
        qosClass: QoSClass
    ) -> Double {
        let baseBandwidth = route.bandwidth

        // QoS 类别调整
        let qosMultiplier: Double
        switch qosClass {
        case .critical: qosMultiplier = 1.0
        case .streaming: qosMultiplier = 0.8
        case .interactive: qosMultiplier = 0.6
        case .bestEffort: qosMultiplier = 0.4
        case .background: qosMultiplier = 0.2
        }

        // 权限级别调整
        let permissionMultiplier: Double
        switch permissionLevel {
        case .premium: permissionMultiplier = 1.0
        case .priority: permissionMultiplier = 0.7
        case .basic: permissionMultiplier = 0.4
        case .restricted: permissionMultiplier = 0.2
        }

        return baseBandwidth * qosMultiplier * permissionMultiplier
    }

    private func calculateRoutingCost(
        bandwidth: Double,
        qosClass: QoSClass,
        permissionLevel: QoSPermissionLevel
    ) -> Double {
        // Base cost per KB
        let baseCost: Double

        switch qosClass {
        case .critical: baseCost = 2.0
        case .streaming: baseCost = 1.5
        case .interactive: baseCost = 1.0
        case .bestEffort: baseCost = 0.5
        case .background: baseCost = 0.1
        }

        // Permission discount (higher permission = lower cost)
        let discount: Double
        switch permissionLevel {
        case .premium: discount = 0.5
        case .priority: discount = 0.75
        case .basic: discount = 1.0
        case .restricted: discount = 1.5
        }

        return (bandwidth / 1024.0) * baseCost * discount
    }

    private func qosClassToPriority(_ qosClass: QoSClass, permissionLevel: QoSPermissionLevel) -> MessagePriority {
        if permissionLevel == .premium {
            return .critical
        }

        switch qosClass {
        case .critical: return .critical
        case .streaming: return .high
        case .interactive: return .normal
        case .bestEffort: return .low
        case .background: return .background
        }
    }

    // MARK: - 限流管理
    func applyRateLimit(to nodeId: String, duration: TimeInterval) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if var state = nodeStates[nodeId] {
            state.applyRateLimit(duration: duration)
            nodeStates[nodeId] = state
            delegate?.qosController(self, didApplyRateLimit: nodeId, duration: duration)
        }
    }

    func clearRateLimit(for nodeId: String) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if var state = nodeStates[nodeId] {
            state.clearRateLimit()
            nodeStates[nodeId] = state
        }
    }

    // MARK: - 积分冻结
    func freezeCredits(for nodeId: String, amount: Double, reason: String, expiresAt: Date? = nil) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if var state = nodeStates[nodeId] {
            state.freezeCredits(amount: amount, reason: reason)
            nodeStates[nodeId] = state
        }

        let record = CreditFreezeRecord(
            id: UUID().uuidString,
            nodeId: nodeId,
            amount: amount,
            reason: reason,
            frozenAt: Date(),
            frozenBy: "CreditQoSController",
            expiresAt: expiresAt
        )

        freezeRecordsLock.lock()
        creditFreezeRecords.append(record)
        saveCreditFreezeRecords()
        freezeRecordsLock.unlock()

        delegate?.qosController(self, didFreezeCredits: nodeId, amount: amount, reason: reason)

        statisticsLock.lock()
        statistics.frozenCreditsTotal += amount
        statisticsLock.unlock()

        // 降级权限
        updateNodePermission(nodeId)
    }

    func unfreezeCredits(for nodeId: String) {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        if var state = nodeStates[nodeId] {
            state.unfreezeCredits()
            nodeStates[nodeId] = state
        }

        freezeRecordsLock.lock()
        if let index = creditFreezeRecords.firstIndex(where: { $0.nodeId == nodeId && $0.isActive }) {
            creditFreezeRecords[index].unfrozenAt = Date()
            saveCreditFreezeRecords()
        }
        freezeRecordsLock.unlock()

        delegate?.qosController(self, didUnfreezeCredits: nodeId)

        // 恢复权限
        updateNodePermission(nodeId)
    }

    func isCreditsFrozen(for nodeId: String) -> Bool {
        freezeRecordsLock.lock()
        defer { freezeRecordsLock.unlock() }

        return creditFreezeRecords.contains { $0.nodeId == nodeId && $0.isActive }
    }

    func getFrozenAmount(for nodeId: String) -> Double {
        freezeRecordsLock.lock()
        defer { freezeRecordsLock.unlock() }

        return creditFreezeRecords
            .filter { $0.nodeId == nodeId && $0.isActive }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - 定期更新
    private func processPeriodicUpdates() {
        // 更新所有节点权限
        updateAllNodePermissions()

        // 处理过期的冻结记录
        processExpiredFreezes()

        // 清理过期的限流
        cleanupExpiredRateLimits()
    }

    private func processExpiredFreezes() {
        freezeRecordsLock.lock()
        let now = Date()

        for index in creditFreezeRecords.indices {
            if let expiresAt = creditFreezeRecords[index].expiresAt,
               expiresAt <= now,
               creditFreezeRecords[index].unfrozenAt == nil {
                creditFreezeRecords[index].unfrozenAt = now

                let nodeId = creditFreezeRecords[index].nodeId
                nodeStatesLock.lock()
                if var state = nodeStates[nodeId] {
                    state.unfreezeCredits()
                    nodeStates[nodeId] = state
                }
                nodeStatesLock.unlock()

                delegate?.qosController(self, didUnfreezeCredits: nodeId)
            }
        }

        saveCreditFreezeRecords()
        freezeRecordsLock.unlock()
    }

    private func cleanupExpiredRateLimits() {
        nodeStatesLock.lock()
        defer { nodeStatesLock.unlock() }

        for (nodeId, var state) in nodeStates {
            if state.isRateLimited, let expiresAt = state.rateLimitExpiresAt, Date() >= expiresAt {
                state.clearRateLimit()
                nodeStates[nodeId] = state
            }
        }
    }

    // MARK: - 持久化
    private func loadCreditFreezeRecords() {
        freezeRecordsLock.lock()
        defer { freezeRecordsLock.unlock() }

        guard let data = UserDefaults.standard.data(forKey: "CreditFreezeRecords"),
              let records = try? JSONDecoder().decode([CreditFreezeRecord].self, from: data) else {
            return
        }

        creditFreezeRecords = records.filter { $0.isActive }
    }

    private func saveCreditFreezeRecords() {
        guard let data = try? JSONEncoder().encode(creditFreezeRecords) else { return }
        UserDefaults.standard.set(data, forKey: "CreditFreezeRecords")
    }

    // MARK: - 配置
    func updateCreditThresholds(_ thresholds: CreditThresholds) {
        creditThresholds = thresholds
    }

    func updateRoutingWeights(_ weights: RoutingWeights) {
        routingWeights = weights
    }

    // MARK: - 统计
    func getStatistics() -> QoSStatistics {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }

        var stats = statistics
        stats.restrictedNodesCount = nodeStates.values.filter { $0.permissionLevel == .restricted }.count
        stats.premiumNodesCount = nodeStates.values.filter { $0.permissionLevel == .premium }.count

        return stats
    }

    func resetStatistics() {
        statisticsLock.lock()
        statistics.reset()
        statisticsLock.unlock()
    }
}

import Foundation
import UIKit

final class CreditEngine {
    static let shared = CreditEngine()
    private var account: CreditAccount
    private var eventHistory: [CreditEvent] = []
    private let queue = DispatchQueue(label: "com.summerspark.creditengine", attributes: .concurrent)

    // MARK: - Rate Limiting for earn()
    private var earnRequestLog: [String: [Date]] = [:]  // keyed by UID or device identifier
    private let rateLimitLock = NSLock()
    private let rateLimitConfig = RateLimitConfiguration()

    struct RateLimitConfiguration {
        var maxEarnRequestsPerMinute: Int = 10   // max earn() calls per minute
        var maxEarnRequestsPerHour: Int = 50      // max earn() calls per hour
        var cooldownSeconds: Int = 60             // cooldown after limit exceeded
    }

    // Lightweight transaction record for UI consumption
    struct TransactionRecord {
        let id: String
        let description: String
        let amount: Double
        let date: Date
    }

    // Decay configuration - per yanfa.md 3.9.3
    private var decayConfig: DecayConfiguration = DecayConfiguration()

    struct DecayConfiguration {
        var enabled: Bool = true
        // yanfa.md 3.9.3: 7天无操作衰减20%, 15天无操作衰减50%
        var tier1ThresholdDays: Int = 7
        var tier1DecayRate: Double = 0.20
        var tier2ThresholdDays: Int = 15
        var tier2DecayRate: Double = 0.50
        var offlineClearThresholdHours: Int = 24  // 离线≥24小时清零
    }

    private init() {
        account = CreditAccount(
            balance: 0,
            tier: .bronze,
            totalEarned: 0,
            totalConsumed: 0
        )
    }

    // MARK: - Lifecycle

    /// Start the CreditEngine and restore any persisted state
    func start() {
        queue.sync {
            // Load persisted account data if available
            if let savedAccount = loadPersistedAccount() {
                self.account = savedAccount
            }
            // Start decay timer if enabled
            if decayConfig.enabled {
                startDecayTimer()
            }
        }
        Logger.shared.info("[CreditEngine] Started")
    }

    /// Persist account to storage
    private func loadPersistedAccount() -> CreditAccount? {
        // Placeholder for persistence loading - returns nil to use default init
        return nil
    }

    /// Start the credit decay timer
    private func startDecayTimer() {
        // Decay check runs hourly
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3600) { [weak self] in
            self?.applyDecayIfNeeded()
            self?.startDecayTimer() // Reschedule
        }
    }

    // MARK: - Public API

    func getBalance() -> Double {
        return queue.sync { account.balance }
    }

    func getAccount() -> CreditAccount {
        return queue.sync { account }
    }

    /// Direct account access for SwiftUI bindings
    var currentAccount: CreditAccount {
        return queue.sync { account }
    }

    func getEventHistory(limit: Int = 50) -> [CreditEvent] {
        return queue.sync {
            Array(eventHistory.suffix(limit))
        }
    }

    func getTransactionHistory() -> [TransactionRecord] {
        let events = getEventHistory(limit: 100)
        return events.map { event in
            TransactionRecord(
                id: event.id,
                description: event.reason,
                amount: event.type == .earned ? event.amount : -event.amount,
                date: event.timestamp
            )
        }
    }

    // MARK: - Credit Earning (yanfa.md 3.9.1)

    /// Earn credits with rate limiting protection
    /// - Returns: (success: Bool, reason: String)
    func earn(_ amount: Double, reason: String, context: [String: Any] = [:]) -> (success: Bool, reason: String) {
        guard amount > 0 else { return (false, "Invalid amount") }

        // Rate Limiting check
        let rateLimitResult = checkRateLimit()
        if !rateLimitResult.allowed {
            return (false, "Rate limit exceeded: \(rateLimitResult.message)")
        }

        return queue.sync(flags: .barrier) {
            // Record this earn request for rate limiting
            self.recordEarnRequest()

            // Determine credit type from context
            let creditType = CreditType.from(context: context)
            var earnedAmount = amount

            // Apply earning rules per yanfa.md 3.9.1
            switch creditType {
            case .basicDataRelay:
                // 基础数据转发: +1/次
                earnedAmount = 1.0
            case .wifiRelay:
                // WiFi中继转发: +2/次
                earnedAmount = 2.0
            case .criticalRelay:
                // 唯一关键中继: +3/次
                earnedAmount = 3.0
            case .standbyOnline:
                // 待机稳定在线: +5/5分钟 (日上限100)
                earnedAmount = 5.0
            case .mapSharing:
                // 地图包转发共享: +1/次
                earnedAmount = 1.0
            case .pathPlanning:
                // 有效路径规划导航: +5/次
                earnedAmount = 5.0
            case .defaultEarning:
                earnedAmount = amount
            }

            // Apply tier multiplier based on yanfa.md 3.9.4
            earnedAmount *= account.tier.multiplier

            account.balance += earnedAmount
            account.totalEarned += earnedAmount
            account.lastUpdated = Date()

            let event = CreditEvent(
                type: .earned,
                amount: earnedAmount,
                reason: reason
            )
            eventHistory.append(event)

            updateTier()

            return (true, "Earned \(earnedAmount) credits for \(reason)")
        }
    }

    // MARK: - Credit Consumption (yanfa.md 3.9.2)

    func consume(_ amount: Double, reason: String, context: [String: Any] = [:]) -> Bool {
        guard amount > 0 else { return false }

        return queue.sync(flags: .barrier) {
            var consumedAmount = amount

            // Determine consumption type from context
            let consumeType = ConsumeType.from(context: context)

            switch consumeType {
            case .voiceCall:
                // 语音通话: -2/10分钟
                consumedAmount = 2.0
            case .locationSharing:
                // 位置共享: -1/10分钟
                consumedAmount = 1.0
            case .groupCreation:
                // 面对面建群: -50/次
                consumedAmount = 50.0
            case .mapDownload:
                // 大地图包下载: -5/次
                consumedAmount = 5.0
            case .navReplanning:
                // 导航重规划: -2/次
                consumedAmount = 2.0
            case .defaultConsume:
                consumedAmount = amount
            }

            guard account.balance >= consumedAmount else {
                return false
            }

            account.balance -= consumedAmount
            account.totalConsumed += consumedAmount
            account.lastUpdated = Date()

            let event = CreditEvent(
                type: .consumed,
                amount: consumedAmount,
                reason: reason
            )
            eventHistory.append(event)

            return true
        }
    }

    // MARK: - Decay & Penalty (yanfa.md 3.9.3)

    func applyDecay() -> Double {
        guard decayConfig.enabled else { return 0 }

        return queue.sync(flags: .barrier) {
            let hoursSinceUpdate = Calendar.current.dateComponents(
                [.hour],
                from: account.lastUpdated,
                to: Date()
            ).hour ?? 0

            let daysSinceUpdate = hoursSinceUpdate / 24

            // Offline >= 24 hours: full decay to zero
            if hoursSinceUpdate >= decayConfig.offlineClearThresholdHours {
                let penalty = account.balance
                account.balance = 0

                let event = CreditEvent(
                    type: .decayed,
                    amount: penalty,
                    reason: "Offline \(hoursSinceUpdate) hours, credits cleared"
                )
                eventHistory.append(event)
                return penalty
            }

            // 7 days no activity: 20% decay
            if daysSinceUpdate >= decayConfig.tier1ThresholdDays {
                let penaltyRatio: Double
                let reason: String

                if daysSinceUpdate >= decayConfig.tier2ThresholdDays {
                    // 15 days no activity: 50% decay
                    penaltyRatio = decayConfig.tier2DecayRate
                    reason = "Inactivity decay after \(daysSinceUpdate) days (50%)"
                } else {
                    // 7 days no activity: 20% decay
                    penaltyRatio = decayConfig.tier1DecayRate
                    reason = "Inactivity decay after \(daysSinceUpdate) days (20%)"
                }

                let penalty = account.balance * penaltyRatio
                account.balance -= penalty
                account.lastUpdated = Date()

                let event = CreditEvent(
                    type: .decayed,
                    amount: penalty,
                    reason: reason
                )
                eventHistory.append(event)

                return penalty
            }

            return 0
        }
    }

    func applyPenalty(_ amount: Double, reason: String) -> Bool {
        guard amount > 0 else { return false }

        return queue.sync(flags: .barrier) {
            // 恶意发包/伪造身份: 积分清零+拉黑
            if reason.contains("malicious") || reason.contains("forged") {
                account.balance = 0

                let event = CreditEvent(
                    type: .penalty,
                    amount: account.balance,
                    reason: "Malicious activity: \(reason) - credits cleared"
                )
                eventHistory.append(event)
                return true
            }

            let actualPenalty = min(amount, account.balance)
            account.balance -= actualPenalty
            account.lastUpdated = Date()

            let event = CreditEvent(
                type: .penalty,
                amount: actualPenalty,
                reason: reason
            )
            eventHistory.append(event)

            return true
        }
    }

    func reset() {
        queue.sync(flags: .barrier) {
            account = CreditAccount(
                balance: 0,
                tier: .bronze,
                totalEarned: 0,
                totalConsumed: 0
            )
            eventHistory.removeAll()
        }
    }

    // MARK: - Configuration

    func updateDecayConfig(_ config: DecayConfiguration) {
        queue.sync(flags: .barrier) {
            self.decayConfig = config
        }
    }

    /// Apply decay if needed (called by decay timer)
    func applyDecayIfNeeded() {
        _ = applyDecay()
    }

    // MARK: - Private Methods

    private func updateTier() {
        // Per yanfa.md 3.9.4: 积分优先级按balance分级
        // 黄金节点: >200 最高优先级
        // 白银节点: 100~200 中优先级
        // 青铜节点: <100 低优先级

        let balance = account.balance

        if balance > 200 {
            account.tier = .gold
        } else if balance >= 100 {
            account.tier = .silver
        } else {
            account.tier = .bronze
        }
    }

    // MARK: - Rate Limiting Implementation

    private func checkRateLimit() -> (allowed: Bool, message: String) {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }

        let now = Date()
        let key = getDeviceKey()
        let requests = earnRequestLog[key] ?? []

        // Clean old entries
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let oneHourAgo = now.addingTimeInterval(-3600)

        let recentRequests = requests.filter { $0 > oneMinuteAgo }
        let recentHourlyRequests = requests.filter { $0 > oneHourAgo }

        // Check per-minute limit
        if recentRequests.count >= rateLimitConfig.maxEarnRequestsPerMinute {
            return (false, "Too many requests in the last minute. Try again later.")
        }

        // Check per-hour limit
        if recentHourlyRequests.count >= rateLimitConfig.maxEarnRequestsPerHour {
            return (false, "Hourly limit exceeded. Please wait before earning more credits.")
        }

        return (true, "")
    }

    private func recordEarnRequest() {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }

        let key = getDeviceKey()
        var requests = earnRequestLog[key] ?? []

        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)

        // Keep only recent requests (within last hour)
        requests = requests.filter { $0 > oneHourAgo }
        requests.append(now)

        earnRequestLog[key] = requests
    }

    private func getDeviceKey() -> String {
        // Use device identifier for rate limiting
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}

// MARK: - Credit Types (for earning)

enum CreditType {
    case basicDataRelay     // 基础数据转发: +1/次
    case wifiRelay          // WiFi中继转发: +2/次
    case criticalRelay      // 唯一关键中继: +3/次
    case standbyOnline      // 待机稳定在线: +5/5分钟
    case mapSharing         // 地图包转发共享: +1/次
    case pathPlanning       // 有效路径规划导航: +5/次
    case defaultEarning     // 默认

    static func from(context: [String: Any]) -> CreditType {
        guard let typeString = context["creditType"] as? String else {
            return .defaultEarning
        }

        switch typeString.lowercased() {
        case "basic_data_relay", "basicrelay":
            return .basicDataRelay
        case "wifi_relay", "wifirelay":
            return .wifiRelay
        case "critical_relay", "criticalrelay":
            return .criticalRelay
        case "standby_online", "standbyonline":
            return .standbyOnline
        case "map_sharing", "mapsharing":
            return .mapSharing
        case "path_planning", "pathplanning":
            return .pathPlanning
        default:
            return .defaultEarning
        }
    }
}

// MARK: - Consume Types (for consumption)

enum ConsumeType {
    case voiceCall          // 语音通话: -2/10分钟
    case locationSharing     // 位置共享: -1/10分钟
    case groupCreation       // 面对面建群: -50/次
    case mapDownload         // 大地图包下载: -5/次
    case navReplanning       // 导航重规划: -2/次
    case defaultConsume      // 默认

    static func from(context: [String: Any]) -> ConsumeType {
        guard let typeString = context["consumeType"] as? String else {
            return .defaultConsume
        }

        switch typeString.lowercased() {
        case "voice_call", "voicecall":
            return .voiceCall
        case "location_sharing", "locationsharing":
            return .locationSharing
        case "group_creation", "groupcreation":
            return .groupCreation
        case "map_download", "mapdownload":
            return .mapDownload
        case "nav_replanning", "navreplanning":
            return .navReplanning
        default:
            return .defaultConsume
        }
    }
}





// MARK: - Activity Bonus Rule

struct ActivityBonusRule: CreditRule {
    let name = "ActivityBonus"

    func apply(to amount: Double, context: [String: Any]) -> Double {
        guard let activityType = context["activityType"] as? String else {
            return amount
        }

        switch activityType {
        case "premium":
            return amount * 1.5
        case "referral":
            return amount * 2.0
        case "promotion":
            return amount * 1.25
        default:
            return amount
        }
    }
}

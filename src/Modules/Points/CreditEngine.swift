import Foundation

final class CreditEngine {
    static let shared = CreditEngine()
    private var account: CreditAccount
    private var eventHistory: [CreditEvent] = []
    private var rules: [CreditRule] = []
    private let queue = DispatchQueue(label: "com.summmerspark.creditengine", attributes: .concurrent)

    // Decay configuration
    private var decayConfig: DecayConfiguration = DecayConfiguration()

    struct DecayConfiguration {
        var enabled: Bool = true
        var decayRate: Double = 0.05 // 5% per period
        var decayInterval: TimeInterval = 86400 // daily
        var inactiveThresholdDays: Int = 30
        var maxPenaltyRatio: Double = 0.5
    }

    private init() {
        account = CreditAccount(
            balance: 0,
            tier: .bronze,
            totalEarned: 0,
            totalConsumed: 0
        )
        setupDefaultRules()
    }

    // MARK: - Stub Methods

    func start() {
        // Stub for SummerSpark compilation
    }

    // MARK: - Public API

    func getBalance() -> Double {
        return queue.sync { account.balance }
    }

    func getAccount() -> CreditAccount {
        return queue.sync { account }
    }

    func getEventHistory(limit: Int = 50) -> [CreditEvent] {
        return queue.sync {
            Array(eventHistory.suffix(limit))
        }
    }

    func earn(_ amount: Double, reason: String, context: [String: Any] = [:]) -> Bool {
        guard amount > 0 else { return false }

        return queue.sync(flags: .barrier) {
            var earnedAmount = amount

            // Apply tier multiplier
            earnedAmount *= account.tier.multiplier

            // Apply all earning rules
            for rule in rules {
                earnedAmount = rule.apply(to: earnedAmount, context: context)
            }

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

            return true
        }
    }

    func consume(_ amount: Double, reason: String, context: [String: Any] = [:]) -> Bool {
        guard amount > 0 else { return false }

        return queue.sync(flags: .barrier) {
            var consumedAmount = amount

            // Apply consumption rules
            for rule in rules {
                consumedAmount = rule.apply(to: consumedAmount, context: context)
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

    func applyDecay() -> Double {
        guard decayConfig.enabled else { return 0 }

        return queue.sync(flags: .barrier) {
            let daysSinceUpdate = Calendar.current.dateComponents(
                [.day],
                from: account.lastUpdated,
                to: Date()
            ).day ?? 0

            guard daysSinceUpdate >= decayConfig.inactiveThresholdDays else {
                return 0
            }

            let penaltyRatio = min(
                Double(daysSinceUpdate - decayConfig.inactiveThresholdDays) * decayConfig.decayRate,
                decayConfig.maxPenaltyRatio
            )

            let penalty = account.balance * penaltyRatio
            account.balance -= penalty
            account.lastUpdated = Date()

            let event = CreditEvent(
                type: .decayed,
                amount: penalty,
                reason: "Inactivity decay after \(daysSinceUpdate) days"
            )
            eventHistory.append(event)

            return penalty
        }
    }

    func applyPenalty(_ amount: Double, reason: String) -> Bool {
        guard amount > 0 else { return false }

        return queue.sync(flags: .barrier) {
            let actualPenalty = min(amount, account.balance * decayConfig.maxPenaltyRatio)
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

    func addRule(_ rule: CreditRule) {
        queue.sync(flags: .barrier) {
            rules.append(rule)
        }
    }

    func removeRule(named name: String) {
        queue.sync(flags: .barrier) {
            rules.removeAll { $0.name == name }
        }
    }

    // MARK: - Private Methods

    private func setupDefaultRules() {
        // Default earning multiplier rule
        let earningRule = BasicEarningRule()
        rules.append(earningRule)

        // Default consumption rule
        let consumptionRule = BasicConsumptionRule()
        rules.append(consumptionRule)
    }

    private func updateTier() {
        let totalEarned = account.totalEarned

        if totalEarned >= 10000 {
            account.tier = .platinum
        } else if totalEarned >= 5000 {
            account.tier = .gold
        } else if totalEarned >= 1000 {
            account.tier = .silver
        } else {
            account.tier = .bronze
        }
    }
}

// MARK: - Default Rules

struct BasicEarningRule: CreditRule {
    let name = "BasicEarning"

    func apply(to amount: Double, context: [String: Any]) -> Double {
        // Base 1.0 multiplier, can be extended
        return amount
    }
}

struct BasicConsumptionRule: CreditRule {
    let name = "BasicConsumption"

    func apply(to amount: Double, context: [String: Any]) -> Double {
        // Base consumption amount
        return amount
    }
}

// MARK: - Bonus Rule Example

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

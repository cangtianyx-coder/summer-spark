import Foundation

// MARK: - Routing Priority
enum RoutingPriority: Int, Comparable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    static func < (lhs: RoutingPriority, rhs: RoutingPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var weightMultiplier: Double {
        switch self {
        case .low: return 0.5
        case .medium: return 1.0
        case .high: return 1.5
        case .critical: return 2.0
        }
    }
}

// MARK: - Credit Weight Configuration
struct CreditWeightConfig {
    var baseWeight: Double = 1.0
    var activityMultiplier: Double = 1.0
    var timeDecayFactor: Double = 1.0
    var trustScoreFactor: Double = 1.0
    var tierBonus: Double = 1.0

    var priority: RoutingPriority = .medium
}

// MARK: - Credit Routing Decision
struct CreditRoutingDecision {
    let routeId: String
    let weight: Double
    let priority: RoutingPriority
    let creditCost: Double
    let estimatedGain: Double
    let timestamp: Date

    var netValue: Double {
        return estimatedGain - creditCost
    }
}

// MARK: - Credit Calculator
final class CreditCalculator {
    static let shared = CreditCalculator()

    // Weight formula coefficients
    private var coefficients: WeightCoefficients = WeightCoefficients()

    struct WeightCoefficients {
        var activityWeight: Double = 0.3
        var timeWeight: Double = 0.2
        var trustWeight: Double = 0.25
        var priorityWeight: Double = 0.25
    }

    private init() {}

    // MARK: - Stub Methods for SummerSpark Compilation

    func setup() {
        // Stub for SummerSpark compilation
    }

    func start() {
        // Stub for SummerSpark compilation
    }

    func calculateWeight(config: CreditWeightConfig) -> Double {
        let activityComponent = config.activityMultiplier * coefficients.activityWeight
        let timeComponent = config.timeDecayFactor * coefficients.timeWeight
        let trustComponent = config.trustScoreFactor * coefficients.trustWeight
        let priorityComponent = config.priority.weightMultiplier * coefficients.priorityWeight

        let weightedSum = activityComponent + timeComponent + trustComponent + priorityComponent
        let baseSum = coefficients.activityWeight + coefficients.timeWeight +
                      coefficients.trustWeight + coefficients.priorityWeight

        return (weightedSum / baseSum) * config.baseWeight * config.tierBonus
    }

    func calculateWeight(
        activityMultiplier: Double,
        timeDecay: Double,
        trustScore: Double,
        priority: RoutingPriority,
        tierMultiplier: Double,
        baseWeight: Double = 1.0
    ) -> Double {
        let config = CreditWeightConfig(
            baseWeight: baseWeight,
            activityMultiplier: activityMultiplier,
            timeDecayFactor: timeDecay,
            trustScoreFactor: trustScore,
            tierBonus: tierMultiplier,
            priority: priority
        )
        return calculateWeight(config: config)
    }

    // MARK: - Routing Priority

    func determinePriority(
        creditAmount: Double,
        urgency: Double,
        trustScore: Double,
        isPremium: Bool
    ) -> RoutingPriority {
        if isPremium || trustScore >= 0.9 {
            return .critical
        }

        if urgency >= 0.8 && creditAmount > 100 {
            return .high
        }

        if urgency >= 0.5 && creditAmount > 50 {
            return .medium
        }

        return .low
    }

    func getQueuePosition(priority: RoutingPriority, currentQueueSize: Int) -> Int {
        let basePosition = Int(Double(currentQueueSize) * (1.0 - priority.weightMultiplier / 2.0))
        return max(0, basePosition)
    }

    // MARK: - Routing Decision

    func evaluateRoute(
        routeId: String,
        creditCost: Double,
        estimatedGain: Double,
        priority: RoutingPriority,
        config: CreditWeightConfig
    ) -> CreditRoutingDecision {
        let weight = calculateWeight(config: config)

        return CreditRoutingDecision(
            routeId: routeId,
            weight: weight,
            priority: priority,
            creditCost: creditCost,
            estimatedGain: estimatedGain,
            timestamp: Date()
        )
    }

    func selectBestRoute(decisions: [CreditRoutingDecision]) -> CreditRoutingDecision? {
        guard !decisions.isEmpty else { return nil }

        return decisions.max { $0.weight < $1.weight }
    }

    func sortByPriority(decisions: [CreditRoutingDecision]) -> [CreditRoutingDecision] {
        return decisions.sorted { $0.priority > $1.priority }
    }

    // MARK: - Cost Estimation

    func estimateCost(
        baseAmount: Double,
        priority: RoutingPriority,
        tierMultiplier: Double
    ) -> Double {
        return baseAmount * priority.weightMultiplier * tierMultiplier
    }

    func estimateGain(
        baseAmount: Double,
        activityMultiplier: Double,
        trustScore: Double
    ) -> Double {
        return baseAmount * activityMultiplier * trustScore
    }

    // MARK: - Configuration

    func updateCoefficients(_ newCoefficients: WeightCoefficients) {
        coefficients = newCoefficients
    }

    func getCoefficients() -> WeightCoefficients {
        return coefficients
    }

    func resetCoefficients() {
        coefficients = WeightCoefficients()
    }

    // MARK: - Time Decay

    func calculateTimeDecay(lastActivityTimestamp: Date, decayRate: Double = 0.1) -> Double {
        let secondsSinceActivity = Date().timeIntervalSince(lastActivityTimestamp)
        let daysSinceActivity = secondsSinceActivity / 86400

        let decay = 1.0 - (decayRate * daysSinceActivity)
        return max(0.1, decay) // Minimum 10% weight
    }

    // MARK: - Trust Score

    func calculateTrustScore(
        successfulTransactions: Int,
        totalTransactions: Int,
        accountAge: TimeInterval
    ) -> Double {
        guard totalTransactions > 0 else { return 0.5 }

        let successRate = Double(successfulTransactions) / Double(totalTransactions)
        let ageFactor = min(accountAge / (365 * 86400), 1.0) // Normalize to max 1 year

        return (successRate * 0.7) + (ageFactor * 0.3)
    }
}

// MARK: - Route Evaluator

final class RouteEvaluator {
    private let calculator: CreditCalculator

    init(calculator: CreditCalculator = .shared) {
        self.calculator = calculator
    }

    func evaluateMultipleRoutes(
        routes: [(id: String, cost: Double, gain: Double)],
        priorities: [RoutingPriority]
    ) -> [CreditRoutingDecision] {
        var decisions: [CreditRoutingDecision] = []

        for (index, route) in routes.enumerated() {
            let priority = index < priorities.count ? priorities[index] : .medium

            let config = CreditWeightConfig(
                baseWeight: 1.0,
                activityMultiplier: 1.0,
                timeDecayFactor: 1.0,
                trustScoreFactor: 1.0,
                tierBonus: 1.0,
                priority: priority
            )

            let decision = calculator.evaluateRoute(
                routeId: route.id,
                creditCost: route.cost,
                estimatedGain: route.gain,
                priority: priority,
                config: config
            )

            decisions.append(decision)
        }

        return decisions
    }

    func getOptimalRoute(from decisions: [CreditRoutingDecision]) -> CreditRoutingDecision? {
        return calculator.selectBestRoute(decisions: decisions)
    }
}

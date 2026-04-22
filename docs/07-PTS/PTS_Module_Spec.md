# PTS Module Specification

## 1. Module Overview

The PTS (Points/Credit) module provides a complete credit economy system for the Summer Spark mesh networking application. It manages user balances, transaction history, tier-based multipliers, credit decay, and synchronizes credit state across the mesh network.

**Directory**: `src/Modules/Points/`

### Components

| Component | File | Description |
|-----------|------|-------------|
| CreditEngine | CreditEngine.swift | Core credit operations, balance, tiers, earning/consuming |
| CreditCalculator | CreditCalculator.swift | Weight calculation for routing decisions |
| CreditSyncManager | CreditSyncManager.swift | P2P sync, transaction validation, double-spend detection |

---

## 2. Credit Tiers

### Tier Levels

| Tier | Value | Multiplier |
|------|-------|------------|
| Bronze | 1 | 1.0x |
| Silver | 2 | 1.2x |
| Gold | 3 | 1.5x |
| Platinum | 4 | 2.0x |

### Tier Comparison

Tiers are compared by their raw integer value (Comparable protocol).

---

## 3. CreditEngine API

### CreditEvent

```swift
struct CreditEvent {
    let id: String
    let timestamp: Date
    let type: CreditEventType
    let amount: Double
    let reason: String
    
    enum CreditEventType {
        case earned
        case consumed
        case decayed
        case bonus
        case penalty
    }
}
```

### CreditAccount

```swift
struct CreditAccount {
    var balance: Double
    var lastUpdated: Date
    var tier: CreditTier
    var totalEarned: Double
    var totalConsumed: Double
}
```

### CreditRule Protocol

```swift
protocol CreditRule {
    var name: String { get }
    func apply(to amount: Double, context: [String: Any]) -> Double
}
```

### DecayConfiguration

```swift
struct DecayConfiguration {
    var enabled: Bool = true
    var decayRate: Double = 0.05        // 5% per period
    var decayInterval: TimeInterval = 86400  // daily
    var inactiveThresholdDays: Int = 30
    var maxPenaltyRatio: Double = 0.5
}
```

### Class: CreditEngine (Singleton)

```swift
final class CreditEngine {
    static let shared = CreditEngine()
    
    // Public API
    func getBalance() -> Double
    func getAccount() -> CreditAccount
    func getEventHistory(limit: Int = 50) -> [CreditEvent]
    
    func earn(_ amount: Double, reason: String, context: [String: Any] = [:]) -> Bool
    func consume(_ amount: Double, reason: String, context: [String: Any] = [:]) -> Bool
    
    func applyDecay() -> Double
    func resetDecayTimer()
    
    func registerRule(_ rule: CreditRule)
    func removeRule(named name: String)
}
```

### Tier Update Rules

Tiers are automatically updated based on totalEarned:
- **Platinum**: Total earned >= 10000
- **Gold**: Total earned >= 5000
- **Silver**: Total earned >= 1000
- **Bronze**: Default

---

## 4. CreditCalculator API

### RoutingPriority

```swift
enum RoutingPriority: Int, Comparable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    var weightMultiplier: Double {
        case .low: 0.5
        case .medium: 1.0
        case .high: 1.5
        case .critical: 2.0
    }
}
```

### CreditWeightConfig

```swift
struct CreditWeightConfig {
    var baseWeight: Double = 1.0
    var activityMultiplier: Double = 1.0
    var timeDecayFactor: Double = 1.0
    var trustScoreFactor: Double = 1.0
    var tierBonus: Double = 1.0
    var priority: RoutingPriority = .medium
}
```

### RoutingDecision

```swift
struct RoutingDecision {
    let routeId: String
    let weight: Double
    let priority: RoutingPriority
    let creditCost: Double
    let estimatedGain: Double
    let timestamp: Date
    
    var netValue: Double { estimatedGain - creditCost }
}
```

### Class: CreditCalculator (Singleton)

```swift
final class CreditCalculator {
    static let shared = CreditCalculator()
    
    // Weight Coefficients (default)
    struct WeightCoefficients {
        var activityWeight: Double = 0.3
        var timeWeight: Double = 0.2
        var trustWeight: Double = 0.25
        var priorityWeight: Double = 0.25
    }
    
    // Methods
    func calculateWeight(config: CreditWeightConfig) -> Double
    func calculateWeight(
        baseWeight: Double,
        activity: Double,
        timeDecay: Double,
        trustScore: Double,
        tierBonus: Double,
        priority: RoutingPriority
    ) -> Double
}
```

### Weight Formula

```
weight = (weightedSum / baseSum) * baseWeight * tierBonus

where weightedSum = 
    (activityMultiplier * activityWeight) +
    (timeDecayFactor * timeWeight) +
    (trustScoreFactor * trustWeight) +
    (priority.weightMultiplier * priorityWeight)

and baseSum = activityWeight + timeWeight + trustWeight + priorityWeight
```

---

## 5. CreditSyncManager API

### CreditTransaction

```swift
struct CreditTransaction: Codable, Identifiable {
    let id: UUID
    let fromNodeId: UUID
    let toNodeId: UUID
    let amount: Int64
    let timestamp: Date
    let signature: Data
    let prevTransactionId: UUID?  // For chain validation
}
```

### LedgerEntry

```swift
struct LedgerEntry: Codable {
    let transactionId: UUID
    let nodeId: UUID
    let balanceChange: Int64
    let balanceAfter: Int64
    let timestamp: Date
}
```

### CreditError

```swift
enum CreditError: Error, LocalizedError {
    case insufficientBalance
    case duplicateTransaction
    case invalidSignature
    case doubleSpendAttempt(transactionId: UUID)
    case databaseError(String)
    case syncFailed(String)
    case nodeNotFound(nodeId: UUID)
}
```

### Delegate Protocol

```swift
protocol CreditSyncManagerDelegate: AnyObject {
    func creditSyncManager(_ manager: CreditSyncManager, didUpdateBalance balance: Int64, for nodeId: UUID)
    func creditSyncManager(_ manager: CreditSyncManager, didReceiveTransaction transaction: CreditTransaction)
    func creditSyncManager(_ manager: CreditSyncManager, didFailWithError error: Error)
    func creditSyncManager(_ manager: CreditSyncManager, didDetectDoubleSpend transactionId: UUID)
}
```

### Class: CreditSyncManager (Singleton)

```swift
final class CreditSyncManager {
    static let shared = CreditSyncManager()
    
    weak var delegate: CreditSyncManagerDelegate?
    
    // Methods
    func createTransaction(from: UUID, to: UUID, amount: Int64, signature: Data) throws -> CreditTransaction
    func validateTransaction(_ transaction: CreditTransaction) -> Bool
    func syncWithNode(_ nodeId: UUID) async throws
    func getTransactionHistory(for nodeId: UUID, limit: Int) -> [CreditTransaction]
    func getLedgerEntries(for nodeId: UUID, limit: Int) -> [LedgerEntry]
}
```

---

## 6. Default Rules

CreditEngine initializes with default rules (empty in current implementation). Custom rules can be registered via:

```swift
creditEngine.registerRule(SomeCreditRule())
```

---

## 7. Configuration Defaults

| Parameter | Default Value |
|-----------|---------------|
| Decay Enabled | true |
| Decay Rate | 5% per period |
| Decay Interval | 86400 seconds (daily) |
| Inactive Threshold | 30 days |
| Max Penalty Ratio | 50% |
| Event History Limit | 50 |

---

## 8. Thread Safety

CreditEngine uses a concurrent DispatchQueue with barrier flags for write operations:

```swift
private let queue = DispatchQueue(label: "com.summerspark.creditengine", attributes: .concurrent)
```

- Read operations (`getBalance`, `getAccount`, `getEventHistory`): `queue.sync`
- Write operations (`earn`, `consume`, `applyDecay`): `queue.sync(flags: .barrier)`

---

## 9. Dependencies

- **Framework**: Foundation
- **Internal Dependencies**: None (standalone module)
- **External Dependencies**: None

---

## 10. Error Handling

All errors are reported via appropriate mechanisms:

- CreditEngine: Returns `false` for failed operations, no exception thrown
- CreditSyncManager: Throws `CreditError` exceptions for validation failures
- Delegate methods for async notification of sync status
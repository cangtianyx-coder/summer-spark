# V3.0 积分优先级调度模块规格文档

## 概述

V3.0 积分优先级调度模块是 SummerSpark 项目的核心组件，负责基于积分的消息调度、信用等级与 QoS 联动、以及节点信誉追踪。该模块与积分引擎（CreditEngine）、积分计算器（CreditCalculator）和 QoS 模型（QoSModels）紧密集成。

## 模块结构

```
src/Modules/Scheduler/
├── PriorityScheduler.swift      # 积分优先级消息调度器
├── CreditQoSController.swift    # 积分 QoS 控制器
├── ReputationTracker.swift      # 节点信誉追踪器
└── docs/07-PTS/
    └── V3_CreditScheduler_Spec.md # 本规格文档
```

---

## 1. PriorityScheduler.swift（积分优先级消息调度器）

### 1.1 功能说明

基于积分的消息调度队列，实现优先级调度、积分扣除、延迟调度和动态优先级调整。

### 1.2 核心组件

#### 1.2.1 调度周期配置（SchedulerCycle）

| 枚举值 | 周期 | 用途 |
|--------|------|------|
| `.fast` | 10ms | 高优先级任务 |
| `.normal` | 50ms | 普通任务（默认） |
| `.slow` | 100ms | 后台任务 |

#### 1.2.2 调度任务状态（ScheduledTaskState）

- `pending`：等待调度
- `delayed`：延迟等待
- `ready`：准备执行
- `executing`：执行中
- `completed`：已完成
- `failed(reason)`：失败
- `cancelled`：已取消

#### 1.2.3 优先级队列（PriorityTaskQueue）

线程安全的优先级队列实现，支持：
- 按动态优先级自动排序
- O(log n) 插入和删除
- 按节点 ID 过滤任务

### 1.3 SchedulableTask 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `id` | String | 任务唯一标识 |
| `taskType` | TaskType | 任务类型（mapTileRequest 等） |
| `priority` | MessagePriority | 基础优先级（0-4） |
| `creditCost` | Int | 积分费用 |
| `dynamicPriority` | Double | 动态优先级（运行时计算） |
| `creditTier` | CreditTier | 节点信用等级 |
| `retryCount` | Int | 当前重试次数 |
| `maxRetries` | Int | 最大重试次数（默认3） |

### 1.4 动态优先级计算

```
dynamicPriority = (basePriority + waitTimeBonus) * tierMultiplier * balanceFactor

其中：
- basePriority = MessagePriority.rawValue
- waitTimeBonus = min(elapsedTime / 60.0, 1.0) * 0.5
- tierMultiplier: platinum=1.5, gold=1.3, silver=1.1, bronze=1.0
- balanceFactor: >=1000=1.2, >=500=1.0, >=100=0.8, <100=0.5
```

### 1.5 积分不足处理流程

1. 检查积分余额
2. 若不足，记录延迟次数
3. 若 retryCount >= maxDelayAttempts，标记失败
4. 否则延迟 `insufficientCreditDelay` 秒后重试

### 1.6 对外 API

| 方法 | 说明 |
|------|------|
| `start()` / `stop()` | 生命周期管理 |
| `setSchedulerCycle(_:)` | 配置调度周期 |
| `scheduleTask(...)` | 调度单个任务 |
| `scheduleBatch(tasks:)` | 批量调度 |
| `cancelTask(taskId:)` | 取消任务 |
| `boostPriority(taskId:boostAmount:)` | 提升优先级 |
| `scheduleUrgentTask(...)` | 紧急任务调度 |

### 1.7 委托协议（PrioritySchedulerDelegate）

```swift
protocol PrioritySchedulerDelegate: AnyObject {
    func scheduler(_ scheduler:, didScheduleTask:)
    func scheduler(_ scheduler:, didExecuteTask:)
    func scheduler(_ scheduler:, didFailTask:reason:)
    func scheduler(_ scheduler:, didDelayTask:delay:reason:)
    func scheduler(_ scheduler:, didCancelTask:)
    func schedulerDidUpdateStatistics(_ scheduler:statistics:)
}
```

### 1.8 验收标准

- [x] 能按优先级调度（基于 MessagePriority 和动态优先级）
- [x] 能扣除积分（通过 CreditEngine.consume）
- [x] 能处理积分不足（延迟重试机制）
- [x] 支持 10ms/50ms/100ms 调度周期配置
- [x] 支持动态优先级调整
- [x] 线程安全实现

---

## 2. CreditQoSController.swift（积分 QoS 控制器）

### 2.1 功能说明

根据节点信用等级授予不同 QoS 权限，实现流量整形、优先路由和积分冻结机制。

### 2.2 QoS 权限级别（QoSPermissionLevel）

| 级别 | 积分要求 | 说明 |
|------|----------|------|
| `premium` | >= 5000 | 最高优先级，最优路由 |
| `priority` | >= 1000 | 高优先级，较多带宽 |
| `basic` | >= 100 | 普通优先级 |
| `restricted` | < 10 | 受限，限流 |

### 2.3 流量整形配置（TrafficShapingConfig）

| 参数 | restricted | basic | priority | premium |
|------|------------|------|----------|---------|
| `maxTokensPerSecond` | 1.0 | 10.0 | 50.0 | ∞ |
| `bucketSize` | 5.0 | 50.0 | 200.0 | ∞ |
| `burstAllowance` | 1.1 | 1.5 | 2.0 | 3.0 |
| `cooldownPeriod` | 120s | 60s | 30s | 0s |

### 2.4 令牌桶算法

```
refillTokens():
    elapsed = now - lastTokenRefillTime
    tokensToAdd = elapsed * maxTokensPerSecond
    currentTokenBalance = min(bucketSize, currentTokenBalance + tokensToAdd)

checkTokenBucket(tokensRequired):
    if rateLimited: return false
    refillTokens()
    if currentTokenBalance >= tokensRequired:
        currentTokenBalance -= tokensRequired
        return true
    return false
```

### 2.5 路由决策策略

根据权限级别选择路由：

| 权限级别 | 路由选择策略 |
|----------|--------------|
| `premium` | 最低延迟 |
| `priority` | 平衡稳定性和延迟 |
| `basic` | 优先稳定性（>= 0.7） |
| `restricted` | 最稳定且低延迟（>= 0.8, < 100ms） |

### 2.6 积分冻结机制

- 冻结触发条件：检测到欺诈行为
- 冻结期间权限降级为 `restricted`
- 支持设置过期时间
- 自动解冻或手动解冻

### 2.7 对外 API

| 方法 | 说明 |
|------|------|
| `start()` / `stop()` | 生命周期管理 |
| `registerNode(_:initialPermission:)` | 注册节点 |
| `calculatePermissionLevel(for:)` | 计算权限级别 |
| `updateNodePermission(_:)` | 更新节点权限 |
| `checkTokenBucket(nodeId:tokensRequired:)` | 检查令牌桶 |
| `makeRoutingDecision(...)` | 做出路由决策 |
| `freezeCredits(for:amount:reason:)` | 冻结积分 |
| `unfreezeCredits(for:)` | 解冻积分 |
| `applyRateLimit(to:duration:)` | 应用限流 |

### 2.8 委托协议（CreditQoSControllerDelegate）

```swift
protocol CreditQoSControllerDelegate: AnyObject {
    func qosController(_ controller:, didUpdatePermission:level:)
    func qosController(_ controller:, didApplyRateLimit:duration:)
    func qosController(_ controller:, didFreezeCredits:amount:reason:)
    func qosController(_ controller:, didUnfreezeCredits:)
    func qosController(_ controller:, didRejectFlow:reason:)
}
```

### 2.9 验收标准

- [x] 能根据积分调整 QoS（premium/priority/basic/restricted）
- [x] 能限流低信用节点（令牌桶算法）
- [x] 高信用节点优先路由选择权
- [x] 积分冻结机制
- [x] 流量整形配置

---

## 3. ReputationTracker.swift（节点信誉追踪器）

### 3.1 功能说明

追踪节点行为信誉，记录贡献量和恶意行为，计算信誉分数并实施衰减和黑名单机制。

### 3.2 行为类型

#### 正面行为（加分）

| 行为 | 权重 | 说明 |
|------|------|------|
| `trafficForwarding` | 1.0 | 流量转发 |
| `dataSharing` | 1.2 | 数据分享 |
| `routeContribution` | 1.5 | 路由贡献 |
| `stabilityContribution` | 2.0 | 稳定性贡献 |
| `voicePacketRelay` | 0.8 | 语音包中继 |

#### 负面行为（减分）

| 行为 | 权重 | 说明 |
|------|------|------|
| `packetDrop` | -5.0 | 丢包 |
| `dataTampering` | -10.0 | 数据篡改 |
| `fakeReporting` | -8.0 | 伪造报告 |
| `spamBehavior` | -3.0 | 垃圾行为 |
| `routeManipulation` | -10.0 | 路由操纵 |
| `creditFraud` | -15.0 | 积分欺诈 |
| `sybilAttack` | -20.0 | 女巫攻击 |
| `eclipseAttack` | -20.0 | 日食攻击 |

### 3.3 信誉等级（ReputationTier）

| 等级 | 分值范围 | displayName |
|------|----------|-------------|
| `veryHigh` | 80-100 | Very High |
| `high` | 60-79 | High |
| `medium` | 40-59 | Medium |
| `low` | 20-39 | Low |
| `veryLow` | 1-19 | Very Low |
| `unknown` | 0 | Unknown |

### 3.4 信誉计算算法

```
正面行为：
    bonusMultiplier = 1.0 - (consecutivePositiveEvents * 0.1)
    scoreIncrease = weight * max(0.1, min(1.0, bonusMultiplier))
    score = min(100, score + scoreIncrease)
    consecutivePositiveEvents += 1
    consecutiveNegativeEvents = 0

负面行为：
    penaltyMultiplier = 1.0 + (consecutiveNegativeEvents * 0.2)
    scoreDecrease = abs(weight) * max(1.0, penaltyMultiplier)
    score = max(0, score - scoreDecrease)
    consecutiveNegativeEvents += 1
    consecutivePositiveEvents = 0

黑名单触发：score < 10
```

### 3.5 衰减机制（DecayConfiguration）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `enabled` | true | 是否启用 |
| `decayRatePerDay` | 0.5 | 每天衰减分数 |
| `inactivityThresholdDays` | 7 | 不活跃阈值（天） |
| `maxDecayScore` | 20.0 | 最大衰减分数 |
| `minScore` | 0 | 最低分数 |

### 3.6 贡献量记录（ContributionRecord）

按日记录：
- `trafficForwardedBytes`：流量转发字节数
- `dataSharedBytes`：数据分享字节数
- `routesProvided`：提供的路由数
- `voicePacketsRelayed`：中继的语音包数
- `successfulTransactions`：成功交易数
- `totalTransactions`：总交易数

### 3.7 对外 API

| 方法 | 说明 |
|------|------|
| `start()` / `stop()` | 生命周期管理 |
| `registerNode(_:initialScore:)` | 注册节点 |
| `getReputationScore(for:)` | 获取信誉分 |
| `getReputationTier(for:)` | 获取信誉等级 |
| `recordBehavior(nodeId:type:details:)` | 记录行为 |
| `reportMaliciousBehavior(...)` | 举报恶意行为 |
| `addToBlacklist(nodeId:reason:expiresAt:)` | 加入黑名单 |
| `removeFromBlacklist(nodeId:)` | 移出黑名单 |
| `isOnBlacklist(_:)` | 检查黑名单状态 |
| `getTotalContribution(for:)` | 获取总贡献量 |
| `getContributionHistory(for:days:)` | 获取贡献历史 |
| `requestReputationRecovery(nodeId:)` | 请求信誉恢复 |

### 3.8 委托协议（ReputationTrackerDelegate）

```swift
protocol ReputationTrackerDelegate: AnyObject {
    func reputationTracker(_ tracker:, didUpdateReputation:newScore:oldScore:)
    func reputationTracker(_ tracker:, didAddToBlacklist:reason:)
    func reputationTracker(_ tracker:, didRemoveFromBlacklist:)
    func reputationTracker(_ tracker:, didRecordBehavior:)
    func reputationTracker(_ tracker:, didDetectMaliciousBehavior:)
}
```

### 3.9 验收标准

- [x] 能计算信誉分（0-100）
- [x] 能记录正面行为（加分）
- [x] 能记录负面行为（减分）
- [x] 信誉衰减机制（基于不活跃时间）
- [x] 信誉黑名单机制
- [x] 贡献量追踪

---

## 4. 模块间依赖关系

```
CreditEngine
    ├── PriorityScheduler（调度时扣除积分）
    ├── CreditQoSController（计算权限级别）
    └── ReputationTracker（用于信誉计算）

CreditCalculator
    └── ReputationTracker（权重计算）

QoSModels
    ├── PriorityScheduler（MessagePriority, ScheduledTask）
    └── CreditQoSController（QoSClass, LinkQuality）

PriorityScheduler
    └── CreditQoSController（可选集成）

ReputationTracker
    └── CreditEngine（积分冻结时通知）
```

---

## 5. 数据持久化

| 数据 | 存储方式 | 键名 |
|------|----------|------|
| 信用冻结记录 | UserDefaults | `CreditFreezeRecords` |
| 节点信誉状态 | UserDefaults | `ReputationNodeStates` |
| 恶意行为记录 | UserDefaults | `MaliciousBehaviorRecords` |

---

## 6. 配置参数汇总

### 6.1 PriorityScheduler

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `schedulerCycle` | `.normal` (50ms) | 调度周期 |
| `insufficientCreditDelay` | 5.0s | 积分不足延迟 |
| `maxDelayAttempts` | 3 | 最大延迟次数 |

### 6.2 CreditQoSController

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `premiumMinCredits` | 5000 | Premium 门槛 |
| `priorityMinCredits` | 1000 | Priority 门槛 |
| `basicMinCredits` | 100 | Basic 门槛 |
| `restrictedMaxCredits` | 10 | Restricted 上限 |

### 6.3 ReputationTracker

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `decayRatePerDay` | 0.5 | 每日衰减分数 |
| `inactivityThresholdDays` | 7 | 不活跃阈值 |
| `maxDecayScore` | 20.0 | 最大衰减 |
| `blacklistThreshold` | 10 | 黑名单阈值 |

---

## 7. 线程安全

所有模块使用 `NSLock` 或 `DispatchQueue` 确保线程安全：

- `PriorityScheduler`：调度队列和延迟任务列表分别加锁
- `CreditQoSController`：节点状态和冻结记录分别加锁
- `ReputationTracker`：节点状态、行为记录、贡献记录分别加锁

---

## 8. 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| V3.0 | 2026-04-23 | 初始版本，实现积分优先级调度、信用 QoS、信誉追踪 |

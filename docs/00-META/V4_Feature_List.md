# V4.0 版本功能清单

**版本代号**: 救援增强版 (Rescue Enhancement)
**研发启动**: 2026-04-23
**目标交付**: 完整的应急救援和社会协作功能

---

## 一、功能模块清单

### 1. Emergency 紧急救援模块 [P0]

| 功能 | 文件 | 描述 | 负责人 |
|------|------|------|--------|
| SOS紧急求救 | SOSManager.swift | 一键求救、全网广播、优先路由 | Agent-E1 |
| 救援协调系统 | RescueCoordinator.swift | 救援队角色、任务分配、区域划分 | Agent-E2 |
| 伤员标记系统 | VictimMarker.swift | 伤员位置标记、伤情等级、救援状态 | Agent-E1 |
| 撤离路线规划 | EvacuationPlanner.swift | 撤离集合点、路线广播、人员清点 | Agent-E2 |
| 紧急通道 | EmergencyChannel.swift | 应急指挥频道、优先级队列 | Agent-E3 |

### 2. Social 社会协作模块 [P0]

| 功能 | 文件 | 描述 | 负责人 |
|------|------|------|--------|
| 信任网络 | TrustNetwork.swift | 用户信任评分、历史互动记录 | Agent-S1 |
| 紧急联系人 | ContactPriority.swift | 优先联系人列表、一键呼叫 | Agent-S2 |
| 用户状态广播 | UserStatus.swift | 空闲/忙碌/紧急求助状态 | Agent-S1 |
| 互动历史 | InteractionHistory.swift | 通话记录、协作历史、信任积累 | Agent-S2 |

### 3. Integration 集成增强模块 [P0]

| 功能 | 修改文件 | 描述 | 负责人 |
|------|----------|------|--------|
| 消息优先级队列 | MeshService.swift | 紧急消息优先路由 | Agent-I1 |
| 紧急呼叫打断 | VoiceService.swift | 紧急呼叫强插机制 | Agent-I2 |
| 位置有效性验证 | LocationManager.swift | 位置可信度验证、异常检测 | Agent-I1 |
| 救援激励体系 | CreditEngine.swift | 救援行为额外积分 | Agent-I2 |

### 4. UI 用户体验模块 [P1]

| 功能 | 文件 | 描述 | 负责人 |
|------|------|------|--------|
| SOS按钮组件 | SOSButton.swift | 主界面一键求救按钮 | Agent-U1 |
| 救援仪表盘 | RescueDashboard.swift | 救援态势总览界面 | Agent-U1 |
| 信任度显示 | TrustIndicator.swift | 用户信任度可视化 | Agent-U2 |
| 网络拓扑图 | NetworkTopologyView.swift | Mesh网络可视化 | Agent-U2 |

---

## 二、技术规格

### 2.1 SOS消息格式

```swift
struct EmergencySOS: Codable {
    let id: UUID
    let senderId: String
    let senderName: String
    let location: LocationData
    let timestamp: Date
    let emergencyType: EmergencyType
    let severity: Severity
    let message: String?
    let batteryLevel: Double
    let signalStrength: Int
    let ttl: Int  // 时间敏感，默认60秒
}

enum EmergencyType: String, Codable {
    case injury = "受伤"      // 身体受伤
    case lost = "迷路"        // 迷路需要指引
    case trapped = "被困"     // 被困需要救援
    case medical = "医疗"     // 医疗急救
    case fire = "火灾"        // 火灾
    case flood = "水灾"       // 水灾
    case earthquake = "地震"  // 地震
    case other = "其他"       // 其他紧急情况
}

enum Severity: Int, Codable {
    case low = 1       // 轻度：需要帮助但不紧急
    case medium = 2    // 中度：尽快需要帮助
    case high = 3      // 重度：紧急需要救援
    case critical = 4  // 危急：生命危险
}
```

### 2.2 消息优先级

```swift
enum MessagePriority: Int, Codable, Comparable {
    case emergency = 0   // SOS消息，最高优先，打断一切
    case rescue = 1      // 救援协调消息
    case command = 2     // 指挥消息
    case normal = 3      // 普通消息
    case background = 4  // 后台同步消息
    
    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
```

### 2.3 用户状态

```swift
enum UserStatus: String, Codable {
    case available = "空闲"      // 可接受任务
    case busy = "忙碌"           // 暂勿打扰
    case inRescue = "救援中"     // 正在执行救援
    case needHelp = "需要帮助"   // 需要他人协助
    case emergency = "紧急求助"  // SOS激活状态
    case offline = "离线"        // 已离线
}
```

### 2.4 信任评分

```swift
struct TrustScore: Codable {
    let userId: String
    var score: Double           // 0.0 - 1.0
    var interactionCount: Int   // 互动次数
    var rescueCount: Int        // 参与救援次数
    var reliability: Double     // 可靠性（消息送达率）
    var lastUpdated: Date
    
    var level: TrustLevel {
        switch score {
        case 0.8...: return .highlyTrusted
        case 0.6..<0.8: return .trusted
        case 0.4..<0.6: return .neutral
        case 0.2..<0.4: return .caution
        default: return .untrusted
        }
    }
}
```

---

## 三、验收标准

### 3.1 SOS功能验收
- [ ] 主界面有醒目的SOS按钮
- [ ] 长按3秒触发SOS（防误触）
- [ ] SOS消息在3秒内广播到所有可达节点
- [ ] SOS消息优先于所有其他消息路由
- [ ] 接收方收到SOS有明显的声音+震动提醒
- [ ] SOS消息显示发送者位置、伤情、时间
- [ ] 可以标记SOS为"已响应"/"已解决"

### 3.2 救援协调验收
- [ ] 可以创建救援队并指定队员
- [ ] 可以分配救援任务给队员
- [ ] 可以划分搜索区域
- [ ] 救援队位置实时显示在地图
- [ ] 任务状态实时更新

### 3.3 伤员标记验收
- [ ] 可以在地图上标记伤员位置
- [ ] 可以设置伤情等级
- [ ] 可以指派救援人员
- [ ] 救援状态可追踪

### 3.4 信任网络验收
- [ ] 用户有信任度评分
- [ ] 互动影响信任度
- [ ] 救援行为大幅提升信任度
- [ ] 信任度可视化显示

### 3.5 消息优先级验收
- [ ] 紧急消息优先路由
- [ ] 紧急通话可打断普通通话
- [ ] 后台消息不影响紧急消息

---

## 四、文件结构

```
src/Modules/Emergency/
├── SOSManager.swift
├── RescueCoordinator.swift
├── VictimMarker.swift
├── EvacuationPlanner.swift
└── EmergencyChannel.swift

src/Modules/Social/
├── TrustNetwork.swift
├── ContactPriority.swift
├── UserStatus.swift
└── InteractionHistory.swift

src/Modules/UI/
├── SOSButton.swift
├── RescueDashboard.swift
├── TrustIndicator.swift
└── NetworkTopologyView.swift

src/Shared/Models/
└── EmergencyModels.swift (新增)
└── SocialModels.swift (新增)
```

---

## 五、里程碑

| 阶段 | 功能 | 预计时间 | 状态 |
|------|------|----------|------|
| Phase 1 | SOS系统 + 消息优先级 | 0-30分钟 | 待开始 |
| Phase 2 | 救援协调 + 伤员标记 | 30-60分钟 | 待开始 |
| Phase 3 | 信任网络 + 紧急联系人 | 60-90分钟 | 待开始 |
| Phase 4 | UI组件 + 集成测试 | 90-120分钟 | 待开始 |
| Phase 5 | 代码审计 + Bug修复 | 120-150分钟 | 待开始 |

---

*文档创建时间: 2026-04-23 21:15*

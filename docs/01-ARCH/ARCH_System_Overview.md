# ARCH_System_Overview.md — 系统架构总览
> 版本：V1.0 | 更新日期：2026-04-22 | 负责 Agent：iOS-Architect

---

## 1. 系统整体架构分层

系统采用**四层架构**，从下至上依次为：

```
┌─────────────────────────────────────────┐
│           Layer 4: App Layer            │  ← SwiftUI App 入口、SceneDelegate
│         (SummerSparkApp.swift)          │
├─────────────────────────────────────────┤
│        Layer 3: Business Modules        │  ← Identity / Mesh / Crypto / Voice
│        (7 个业务模块 + 1 个 App 模块)    │    / Map / Points / Storage
├─────────────────────────────────────────┤
│         Layer 2: Shared Layer           │  ← Models / Protocols / Utils
├─────────────────────────────────────────┤
│        Layer 1: System Services         │  ← CoreBluetooth / MultipeerConnectivity
│     (蓝牙/WiFi P2P / 硬件能力抽象)       │    / Security Enclave / CoreLocation
└─────────────────────────────────────────┘
```

### 分层职责定义

| 层级 | 名称 | 职责 | 调用方向 |
|------|------|------|----------|
| L4 | App Layer | 应用生命周期管理、入口编排、视图路由 | 向下调用所有模块 |
| L3 | Business Modules | 各业务域的核心逻辑实现 | 向上暴露接口、横向互调 |
| L2 | Shared Layer | 跨模块数据模型、公共协议、工具函数 | 被所有上层模块依赖 |
| L1 | System Services | 底层系统能力抽象（蓝牙/WiFi/加密/定位） | 被 Mesh/Crypto/Identity 等模块调用 |

---

## 2. 12个模块职责与边界

### 2.1 模块总览

```
SummerSpark (App)
├── App                          [L4] 应用入口与生命周期
├── Modules/
│   ├── Identity                 [L3] 一机一ID身份体系
│   ├── Mesh                     [L3] 无线Mesh自组织网络
│   ├── Crypto                   [L3] 端到端加密与验签
│   ├── Voice                    [L3] 点对点/群组语音通讯
│   ├── Map                      [L3] 离线地图与导航
│   ├── Points                   [L3] 积分激励体系
│   └── Storage                  [L3] 本地加密存储
└── Shared/
    ├── Models                   [L2] 跨模块数据模型
    ├── Protocols                [L2] 接口协议定义
    └── Utils                    [L2] 公共工具函数
```

### 2.2 模块职责详述

#### 模块 1：App（应用入口）
- **职责**：应用生命周期管理、状态机驱动、视图导航编排、依赖注入容器
- **边界**：不直接参与 Mesh/Crypto/Voice 业务逻辑，仅协调和路由
- **关键类型**：`SummerSparkApp`、`AppCoordinator`

```swift
// App/ SummerSparkApp.swift
@main
struct SummerSparkApp: App {
    @StateObject private var appState = AppStateManager()
    @StateObject private var modeController = DualModeController()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(modeController)
        }
    }
}
```

---

#### 模块 2：Identity（身份体系）
- **职责**：UID 生成与管理、用户名注册、公钥私钥对生成与 Secure Enclave 存储、Keychain 管理
- **边界**：私钥永不离开 Secure Enclave；公钥对外暴露供其他节点验签
- **关键类型**：`IdentityManager`、`UIDGenerator`、`KeychainService`

```swift
// Modules/Identity/ IdentityManager.swift
/// 身份管理器 — 负责一机一ID的完整生命周期
public final class IdentityManager: ObservableObject {
    
    /// 当前设备身份（持久化）
    @Published private(set) var currentIdentity: DeviceIdentity?
    
    /// 生成新的设备身份（首次启动时调用）
    public func generateNewIdentity(username: String) async throws -> DeviceIdentity {
        let uid = UIDGenerator.generate()
        let keyPair = try await SecureEnclaveManager.generateKeyPair()
        
        let identity = DeviceIdentity(
            uid: uid,
            username: username,
            publicKey: keyPair.publicKey,
            createdAt: Date()
        )
        
        try KeychainService.save(identity: identity)
        return identity
    }
}
```

---

#### 模块 3：Mesh（Mesh 网络）
- **职责**：蓝牙/WiFi P2P 连接管理、节点发现、多跳路由表维护、中继转发、拓扑感知
- **边界**：与 Crypto 边界在加密后转发；与 Voice 边界在音频数据路由；与 Connectivity 无独立模块
- **关键类型**：`MeshNetworkService`、`RouteTable`、`NodeDiscovery`

```swift
// Modules/Mesh/ MeshNetworkService.swift
/// Mesh网络服务 — 负责无线自组织网络的全部生命周期
public final class MeshNetworkService: ObservableObject {
    
    /// 当前连接模式
    @Published var connectionMode: ConnectionMode = .bluetooth
    
    /// 节点路由表
    @Published private(set) var routeTable: RouteTable = RouteTable()
    
    /// 发现的邻居节点
    @Published private(set) var neighbors: [MeshNode] = []
    
    /// 启动Mesh网络
    public func startMesh() async throws {
        switch connectionMode {
        case .bluetooth:
            try await startBluetoothMesh()
        case .wifi:
            try await startWiFiMesh()
        case .dual:
            try await startDualModeMesh()
        }
    }
}
```

---

#### 模块 4：Crypto（加密体系）
- **职责**：E2E 加密、消息签名与验签、防伪造机制、密钥派生
- **边界**：仅负责加解密和验签，不参与传输；私钥操作需通过 Identity 模块的 Secure Enclave
- **关键类型**：`E2EEncryptionService`、`SignerService`

```swift
// Modules/Crypto/ E2EEncryptionService.swift
/// 端到端加密服务 — 负责所有业务数据的加解密
public struct E2EEncryptionService {
    
    /// 使用公钥加密数据（用于向对方发送加密消息）
    public static func encrypt(data: Data, publicKey: PublicKey) throws -> Data
    
    /// 使用私钥解密数据（仅 Secure Enclave 内操作）
    public static func decrypt(encryptedData: Data, privateKey: PrivateKey) throws -> Data
    
    /// 对消息体签名（用于防伪造）
    public static func sign(message: Data, privateKey: PrivateKey) throws -> Data
    
    /// 验证签名（用于接收方验签）
    public static func verify(message: Data, signature: Data, publicKey: PublicKey) throws -> Bool
}
```

---

#### 模块 5：Voice（语音通讯）
- **职责**：点对点语音通话、群组语音、音频编解码（Opus/iLBC）、后台通话支持、音量控制
- **边界**：音频数据来源是麦克风，目的地是网络；编解码在 Voice 模块内部完成
- **关键类型**：`VoiceService`、`AudioSessionManager`、`P2PConnection`、`GroupChannel`

```swift
// Modules/Voice/ VoiceService.swift
/// 语音服务 — 负责语音通话的发起、接收与管理
public final class VoiceService: ObservableObject {
    
    /// 当前通话状态
    @Published private(set) var callState: CallState = .idle
    
    /// 当前通话的远程节点
    @Published private(set) var remoteNode: MeshNode?
    
    /// 发起点对点语音通话
    public func startP2PCall(to node: MeshNode) async throws {
        try await AudioSessionManager.configure(for: .voiceChat)
        let audioData = try await captureAudio()
        let encrypted = try E2EEncryptionService.encrypt(data: audioData, publicKey: node.publicKey)
        try await MeshNetworkService.send(data: encrypted, to: node)
    }
}
```

---

#### 模块 6：Map（地图导航）
- **职责**：离线地图加载与渲染、等高线绘制（DEM）、路径规划、导航引擎、位置共享
- **边界**：定位数据来源于 Shared/Utils/LocationManager；地图数据存储在 Storage 模块
- **关键类型**：`OfflineMapEngine`、`PathPlanner`、`LocationSharer`

```swift
// Modules/Map/ OfflineMapEngine.swift
/// 离线地图引擎 — 负责地图的加载、渲染与导航
public final class OfflineMapEngine: ObservableObject {
    
    /// 当前地图区域
    @Published private(set) var currentRegion: MapRegion?
    
    /// 已下载的地图瓦片
    @Published private(set) var cachedTiles: [TileCoord: Data] = [:]
    
    /// 加载指定区域的离线地图
    public func loadRegion(_ region: MapRegion) async throws {
        let tiles = try await StorageService.fetchMapTiles(for: region)
        for tile in tiles {
            cachedTiles[tile.coord] = tile.data
        }
    }
}
```

---

#### 模块 7：Points（积分体系）
- **职责**：积分生成规则、激励权重计算、路由优先级调度、积分交易记录
- **边界**：积分计算依赖 Mesh 路由信息；积分存储在 Storage 模块；不影响核心通讯功能
- **关键类型**：`CreditCalculator`、`IncentiveEngine`、`RoutingWeightManager`

```swift
// Modules/Points/ CreditCalculator.swift
/// 积分计算器 — 负责根据行为计算积分奖励
public struct CreditCalculator {
    
    /// 中继转发积分（每跳 × 基础积分）
    public static func relayCredit(hops: Int, baseRate: Double) -> Double {
        return Double(hops) * baseRate
    }
    
    /// 语音通话积分（按时长）
    public static func voiceCallCredit(duration: TimeInterval, rate: Double) -> Double {
        return duration * rate
    }
    
    /// 地图共享积分（按共享面积）
    public static func mapShareCredit(tileCount: Int, rate: Double) -> Double {
        return Double(tileCount) * rate
    }
}
```

---

#### 模块 8：Storage（本地存储）
- **职责**：SQLite 数据库管理、Keychain 封装、加密缓存、数据迁移、隐私保护
- **边界**：被所有需要持久化的模块调用；不参与业务逻辑
- **关键类型**：`DatabaseManager`、`KeychainWrapper`、`EncryptedCache`

```swift
// Modules/Storage/ DatabaseManager.swift
/// 数据库管理器 — 负责所有本地数据的持久化
public final class DatabaseManager {
    
    /// 单例访问
    public static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    
    /// 初始化数据库
    public func initialize() throws {
        db = try SQLiteConnection.connect(path: dbPath())
        try createTables()
    }
    
    /// 保存消息记录
    public func saveMessage(_ message: Message) throws {
        try db?.execute(
            sql: "INSERT INTO messages (id, sender, content, timestamp) VALUES (?, ?, ?, ?)",
            parameters: [message.id, message.sender, message.content, message.timestamp]
        )
    }
}
```

---

#### 模块 9：Shared/Models（跨模块数据模型）
- **职责**：定义所有跨模块共享的数据结构，如 `Message`、`MeshNode`、`NodeIdentity`、`Location` 等
- **边界**：纯数据结构，无业务逻辑；所有模块可见
- **关键类型**：`Message`、`MeshNode`、`DeviceIdentity`、`Location`、`MapRegion`

```swift
// Shared/Models/ Message.swift
/// 跨模块共享消息模型
public struct Message: Identifiable, Codable {
    public let id: UUID
    public let sender: UID
    public let content: Data           // 加密后的内容
    public let timestamp: Date
    public let messageType: MessageType
    public let signature: Data          // 签名用于验签
    
    public init(id: UUID = UUID(), sender: UID, content: Data, timestamp: Date = Date(), messageType: MessageType, signature: Data) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.messageType = messageType
        self.signature = signature
    }
}
```

---

#### 模块 10：Shared/Protocols（接口协议定义）
- **职责**：定义模块间交互的接口协议，确保模块边界清晰、依赖反向可控
- **边界**：所有业务模块均应遵循协议定义进行交互
- **关键类型**：`MeshNetworkProtocol`、`CryptoServiceProtocol`、`StorageServiceProtocol`

```swift
// Shared/Protocols/ MeshNetworkProtocol.swift
/// Mesh网络接口协议 — 所有网络传输均通过此协议
public protocol MeshNetworkProtocol {
    /// 发送数据到指定节点
    func send(data: Data, to node: MeshNode) async throws
    
    /// 从指定节点接收数据
    var incomingData: AsyncStream<(Data, MeshNode)> { get }
    
    /// 发现新节点
    var nodeDiscovery: AsyncStream<MeshNode> { get }
    
    /// 当前连接状态
    var connectionState: ConnectionState { get }
}
```

---

#### 模块 11：Shared/Utils（公共工具函数）
- **职责**：通用工具函数，包括日志、断言、日期格式化、并发抽象、错误类型定义
- **边界**：无业务逻辑，所有模块可用
- **关键类型**：`Logger`、`AsyncEventBus`、`AppError`

```swift
// Shared/Utils/ Logger.swift
/// 统一日志工具 — 根据环境控制日志级别
public enum Logger {
    
    public enum Level: Int {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
    }
    
    public static var currentLevel: Level = .debug
    
    public static func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard level.rawValue >= currentLevel.rawValue else { return }
        print("[\(level)][\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(function) - \(message)")
    }
}
```

---

#### 模块 12：Shared/Models/Connectivity（连接模式枚举）
- **职责**：定义蓝牙/WiFi 双模态连接模式及其切换策略
- **边界**：被 Mesh 模块使用，属于 Shared 层的枚举定义
- **关键类型**：`ConnectionMode`、`ConnectionState`、`SwitchPolicy`

```swift
// Shared/Models/ Connectivity.swift
/// 连接模式枚举
public enum ConnectionMode: String, Codable {
    case bluetooth = "BLUETOOTH"
    case wifi = "WIFI"
    case dual = "DUAL"           // 同时监听蓝牙和WiFi
}

/// 连接状态枚举
public enum ConnectionState: String, Codable {
    case disconnected = "DISCONNECTED"
    case scanning = "SCANNING"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case meshFormed = "MESH_FORMED"
}

/// 切换策略枚举
public enum SwitchPolicy: String, Codable {
    case manual = "MANUAL"           // 手动切换
    case automatic = "AUTOMATIC"     // 根据信号强度自动切换
    case preferBluetooth = "PREFER_BT"
    case preferWiFi = "PREFER_WIFI"
}
```

---

## 3. 模块调用关系

### 3.1 调用依赖矩阵

```
调用方 → 被调用方：

App ──────────┬──→ Identity
              ├──→ Mesh
              ├──→ Voice
              ├──→ Map
              ├──→ Points
              └──→ Storage

Identity ─────┐         │──→ Storage (Keychain)
              │         │
Mesh ─────────┼─────────┼──→ Crypto (加密后转发)
              │         │
Voice ────────┼─────────┼──→ Mesh (发送音频数据)
              │         ├──→ Crypto (加密音频)
              │         │
Map ──────────┼─────────┼──→ Storage (地图瓦片)
              │         │
Points ───────┴─────────┴──→ Storage (积分记录)

所有模块 ─────┐
              ├──→ Shared/Models
              ├──→ Shared/Protocols
              └──→ Shared/Utils
```

### 3.2 关键调用流程代码示例

#### 发送加密语音消息的完整调用链

```swift
// 1. Voice 模块发起通话
public func startP2PCall(to node: MeshNode) async throws {
    // 2. 配置音频会话
    try await AudioSessionManager.configure(for: .voiceChat)
    
    // 3. 捕获音频数据
    let audioData = try await captureAudio()
    
    // 4. 调用 Crypto 模块加密
    let encryptedAudio = try E2EEncryptionService.encrypt(
        data: audioData,
        publicKey: node.publicKey
    )
    
    // 5. 调用 Mesh 模块发送
    try await MeshNetworkService.send(data: encryptedAudio, to: node)
    
    // 6. 积分模块记录（中继贡献）
    let relayCredit = CreditCalculator.relayCredit(hops: 1, baseRate: 0.1)
    PointsEngine.record(relayCredit, for: node)
}
```

#### 发现新节点并建立连接的调用链

```swift
// Mesh 模块：节点发现 → 身份验证 → 路由表更新
public func onNodeDiscovered(_ node: MeshNode) async throws {
    // 1. 通过 Identity 验签确认身份
    let isValid = try await IdentityManager.verifyNode(node)
    
    guard isValid else {
        Logger.log("节点验签失败，拒绝连接", level: .warning)
        return
    }
    
    // 2. 更新路由表
    routeTable.addEntry(for: node)
    
    // 3. 通知 Points 模块更新积分权重
    PointsEngine.updateNodeWeight(node)
    
    // 4. 持久化节点信息
    try StorageService.saveNode(node)
}
```

---

## 4. 双模态状态机

### 4.1 双模态定义

系统支持两种运行模态（Mode），定义于 `DualModeController`：

| 模态 | 名称 | 描述 | 可用功能 |
|------|------|------|----------|
| `Standby` | 待机模态 | 仅保持身份，无 Mesh 连接；节省电量 | 查看本地身份、查看已缓存地图 |
| `Mesh` | 组网模态 | 主动参与 Mesh 网络；可发现/中继/通话 | 节点发现、语音通话、地图共享、积分获取 |

### 4.2 状态机定义

```swift
// App/ DualModeController.swift
/// 双模态状态控制器
public final class DualModeController: ObservableObject {
    
    /// 当前模态
    @Published private(set) var currentMode: AppMode = .standby
    
    /// 当前模态下的子状态
    @Published private(set) var subState: AppSubState = .idle
    
    /// 状态变更事件（用于触发 UI 更新）
    public var stateChanged: AnyPublisher<(AppMode, AppSubState), Never>
}

// AppMode — 主模态枚举
public enum AppMode: String, Codable {
    case standby = "STANDBY"     // 待机模态
    case mesh = "MESH"           // 组网模态
}

// AppSubState — 子状态枚举
public enum AppSubState: String, Codable {
    // Standby 模态子状态
    case idle = "IDLE"                    // 空闲
    case identityRegistered = "IDENTITY_OK" // 身份已注册
    
    // Mesh 模态子状态
    case scanning = "SCANNING"             // 正在扫描节点
    case connecting = "CONNECTING"         // 正在连接
    case connected = "CONNECTED"            // 已连接（单跳）
    case meshFormed = "MESH_FORMED"         // Mesh网络已形成（多跳）
    case voiceActive = "VOICE_ACTIVE"      // 语音通话中
    case mapSharing = "MAP_SHARING"         // 地图共享中
}
```

### 4.3 状态转换图

```
                    ┌─────────────────────────────────────────────────┐
                    │                                                 │
                    ▼                                                 │
┌──────────┐    ┌──────────────────────────────────────────────┐    │
│          │    │            AppMode.Standby                    │    │
│  START   │───→│                                              │    │
│          │    │  IDLE ──────────→ IDENTITY_REGISTERED        │    │
└──────────┘    │    │                    │                     │    │
                 └────┼────────────────────┼─────────────────────┘    │
                      │                    │                          │
                      │ 「启动组网」         │ 「进入组网模态」           │
                      │                    │                          │
                      ▼                    ▼                          │
┌───────────────────────────────────────────────────────────────┐    │
│                    AppMode.Mesh                                │    │
│                                                               │    │
│  ┌─────────┐    ┌──────────┐    ┌───────────┐    ┌────────┐ │    │
│  │         │───→│          │───→│           │───→│        │ │    │
│  │ SCANNING│    │CONNECTING│    │ CONNECTED │    │ MESH_   │ │    │
│  │         │←───│          │←───│           │←───│FORMED   │ │    │
│  └─────────┘    └──────────┘    └───────────┘    └────────┘ │    │
│      │               │              │               │        │    │
│      │               │              │               │        │    │
│      │               │              ▼               │        │    │
│      │               │        ┌──────────┐         │        │    │
│      │               │        │ VOICE_   │←────────┼────────┘    │
│      │               │        │ ACTIVE   │                  │    │
│      │               │        └──────────┘                  │    │
│      │               │                                       │    │
│      │               │        ┌────────────┐                │    │
│      │               │        │ MAP_      │←───────────────┘    │
│      │               │        │ SHARING   │                     │
│      │               │        └────────────┘                     │
│      │               │                                       │    │
│      └───────────────┴───────────────────────────────────────┘    │
│            │                            ▲                         │
│            │「返回待机」                  │「完成退出」             │
│            │                            │                         │
└────────────┼────────────────────────────┼─────────────────────────┘
             │                            │
             ▼                            │
      ┌──────────────┐                   │
      │ AppMode.     │←──────────────────┘
      │ Standby      │   「重新进入组网」
      │ (IDLE)       │
      └──────────────┘
```

### 4.4 状态转换代码

```swift
// App/ DualModeController.swift
public final class DualModeController: ObservableObject {
    
    /// 切换到组网模态
    public func enterMeshMode() async throws {
        guard currentMode == .standby else { return }
        
        // 1. 验证身份是否已注册
        guard let identity = IdentityManager.shared.currentIdentity else {
            throw AppError.identityNotFound
        }
        
        // 2. 更新模态
        currentMode = .mesh
        subState = .scanning
        
        // 3. 启动 Mesh 网络
        try await MeshNetworkService.startMesh()
        
        // 4. 开始节点发现
        subState = .connecting
        try await MeshNetworkService.startDiscovery()
        
        Logger.log("已进入组网模态", level: .info)
    }
    
    /// 切换到待机模态
    public func enterStandbyMode() async {
        guard currentMode == .mesh else { return }
        
        // 1. 关闭 Mesh 网络
        await MeshNetworkService.stopMesh()
        
        // 2. 更新状态
        currentMode = .standby
        subState = .idle
        
        Logger.log("已切换到待机模态", level: .info)
    }
    
    /// 节点连接成功回调
    public func onNodeConnected(_ node: MeshNode) {
        if routeTable.hops > 1 {
            subState = .meshFormed
        } else {
            subState = .connected
        }
    }
    
    /// 发起语音通话
    public func startVoiceCall(with node: MeshNode) async throws {
        guard currentMode == .mesh else {
            throw AppError.invalidModeForAction
        }
        
        subState = .voiceActive
        try await VoiceService.startP2PCall(to: node)
    }
}
```

---

## 5. 蓝牙/WiFi 切换流转

### 5.1 切换策略

| 策略 | 描述 | 适用场景 |
|------|------|----------|
| `MANUAL` | 用户手动在蓝牙/WiFi 之间切换 | 调试、特殊网络环境 |
| `AUTOMATIC` | 系统根据信号强度自动切换 | 常规使用（默认） |
| `PREFER_BLUETOOTH` | 优先使用蓝牙，仅蓝牙断开时切 WiFi | 低功耗优先 |
| `PREFER_WIFI` | 优先使用 WiFi，仅 WiFi 不可用时切蓝牙 | 高速率需求 |

### 5.2 切换决策流程图

```
                    ┌────────────────────┐
                    │   SwitchPolicy      │
                    │   决策触发点        │
                    └────────┬───────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                    │
    MANUAL             AUTOMATIC           PREFER_XXX
         │                   │                    │
         ▼                   ▼                    ▼
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ 等待用户操作    │  │ 检查信号强度   │  │ 检查首选通道   │
│ onManualSwitch │  │ RSSI / SNR     │  │ 连接状态       │
└───────┬────────┘  └───────┬────────┘  └───────┬────────┘
        │                    │                    │
        │            ┌──────┴──────┐            │
        │            │             │            │
        ▼            ▼             ▼            ▼
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ 当前为 Bluetooth│  │ RSSI < 阈值？ │  │ 首选通道可用？ │
│    切换到WiFi   │  │               │  │               │
└────────────────┘  └───────┬────────┘  └───────┬────────┘
                           │                    │
                    ┌──────┴──────┐             │
                    │             │             │
                    ▼             ▼             ▼
              ┌──────────┐  ┌────────────────┐ ┌──────────┐
              │   YES    │  │     NO         │ │   YES    │ NO
              │ 切换到WiFi│  │ 保持当前连接   │ │使用首选  │ 切换到备选
              └──────────┘  └────────────────┘ └──────────┘
```

### 5.3 切换策略代码实现

```swift
// Modules/Mesh/ ConnectivitySwitchManager.swift
/// 连接切换管理器 — 负责蓝牙/WiFi 的智能切换
public final class ConnectivitySwitchManager: ObservableObject {
    
    /// 当前活跃的连接模式
    @Published private(set) var activeMode: ConnectionMode = .bluetooth
    
    /// 切换策略
    @Published var switchPolicy: SwitchPolicy = .automatic
    
    /// 蓝牙信号阈值（dBm）
    private let bluetoothThreshold: Int = -70
    
    /// WiFi信号阈值（dBm）
    private let wifiThreshold: Int = -75
    
    /// 执行模式切换
    public func switchTo(_ mode: ConnectionMode) async throws {
        guard activeMode != mode else { return }
        
        Logger.log("开始切换连接模式: \(activeMode) → \(mode)", level: .info)
        
        // 1. 断开当前连接
        try await disconnectCurrent()
        
        // 2. 切换到新模式
        switch mode {
        case .bluetooth:
            try await connectBluetooth()
        case .wifi:
            try await connectWiFi()
        case .dual:
            try await connectDual()
        }
        
        activeMode = mode
        Logger.log("连接模式切换完成: \(mode)", level: .info)
    }
    
    /// 根据信号强度自动决策
    func evaluateAndAutoSwitch() async throws {
        guard switchPolicy == .automatic else { return }
        
        let bluetoothRSSI = await getBluetoothRSSI()
        let wifiSNR = await getWiFiSNR()
        
        // 蓝牙信号过弱，切换到 WiFi
        if bluetoothRSSI < bluetoothThreshold && wifiSNR > wifiThreshold {
            Logger.log("蓝牙信号弱（RSSI: \(bluetoothRSSI)），自动切换到WiFi", level: .info)
            try await switchTo(.wifi)
        }
        // WiFi 信号过弱，切换到蓝牙
        else if wifiSNR < wifiThreshold && bluetoothRSSI > bluetoothThreshold {
            Logger.log("WiFi信号弱（SNR: \(wifiSNR)），自动切换到蓝牙", level: .info)
            try await switchTo(.bluetooth)
        }
    }
    
    // MARK: - 私有方法
    
    private func disconnectCurrent() async throws {
        switch activeMode {
        case .bluetooth:
            try await BluetoothManager.shared.stop()
        case .wifi:
            try await WiFiManager.shared.stop()
        case .dual:
            try await BluetoothManager.shared.stop()
            try await WiFiManager.shared.stop()
        }
    }
    
    private func connectBluetooth() async throws {
        try await BluetoothManager.shared.start()
    }
    
    private func connectWiFi() async throws {
        try await WiFiManager.shared.start()
    }
    
    private func connectDual() async throws {
        try await BluetoothManager.shared.start()
        try await WiFiManager.shared.start()
    }
    
    private func getBluetoothRSSI() async -> Int {
        return await BluetoothManager.shared.currentRSSI()
    }
    
    private func getWiFiSNR() async -> Int {
        return await WiFiManager.shared.currentSNR()
    }
}
```

### 5.4 连接状态流转（完整生命周期）

```
蓝牙连接生命周期：
                              ┌──────────────┐
                              │  DISCONNECTED│
                              └──────┬───────┘
                                     │ startBluetooth()
                                     ▼
                              ┌──────────────┐
                         ┌────│   SCANNING   │←────────────┐
                         │    └──────┬───────┘             │
                         │           │ 发现设备             │
                         │           ▼                     │
                         │    ┌──────────────┐             │
                         │    │ DISCOVERING  │             │
                         │    └──────┬───────┘             │
                         │           │ 选择并发起连接       │
                         │           ▼                     │
                         │    ┌──────────────┐             │
                         │    │ CONNECTING  │──────────────┘
                         │    └──────┬───────┘  超时/失败
                         │           │ 连接成功
                         │           ▼
                         │    ┌──────────────┐
                         └────│  CONNECTED   │
                              └──────┬───────┘
                                     │ 主动断开/异常断开
                                     ▼
                              ┌──────────────┐
                              │  DISCONNECTED│
                              └──────────────┘

WiFi P2P 连接生命周期（类似）：
  DISCONNECTED → SCANNING → DISCOVERING → CONNECTING → CONNECTED → DISCONNECTED
```

---

## 6. 关键类型索引

| 文件路径 | 类型名 | 所属模块 | 说明 |
|---------|--------|----------|------|
| `App/SummerSparkApp.swift` | `SummerSparkApp` | App | 应用入口 |
| `App/DualModeController.swift` | `DualModeController` | App | 双模态控制器 |
| `Modules/Identity/IdentityManager.swift` | `IdentityManager` | Identity | 身份管理器 |
| `Modules/Identity/UIDGenerator.swift` | `UIDGenerator` | Identity | UID生成器 |
| `Modules/Mesh/MeshNetworkService.swift` | `MeshNetworkService` | Mesh | Mesh网络服务 |
| `Modules/Mesh/ConnectivitySwitchManager.swift` | `ConnectivitySwitchManager` | Mesh | 连接切换管理 |
| `Modules/Crypto/E2EEncryptionService.swift` | `E2EEncryptionService` | Crypto | 端到端加密服务 |
| `Modules/Voice/VoiceService.swift` | `VoiceService` | Voice | 语音服务 |
| `Modules/Map/OfflineMapEngine.swift` | `OfflineMapEngine` | Map | 离线地图引擎 |
| `Modules/Points/CreditCalculator.swift` | `CreditCalculator` | Points | 积分计算器 |
| `Modules/Storage/DatabaseManager.swift` | `DatabaseManager` | Storage | 数据库管理器 |
| `Shared/Models/Message.swift` | `Message` | Models | 消息模型 |
| `Shared/Models/Connectivity.swift` | `ConnectionMode` | Models | 连接模式枚举 |
| `Shared/Protocols/MeshNetworkProtocol.swift` | `MeshNetworkProtocol` | Protocols | Mesh网络接口协议 |
| `Shared/Utils/Logger.swift` | `Logger` | Utils | 日志工具 |

---

*本文档为《夏日萤火》系统架构总览 V1.0*
*是 iOS-Architect 的首个交付物，定义了系统骨架，供所有下游 Agent 参考*

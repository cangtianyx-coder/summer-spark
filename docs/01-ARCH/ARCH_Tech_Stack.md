# ARCH_Tech_Stack.md
## 夏日萤火 / A-Single-Spark
### iOS 技术栈选型文档 · V1.0

---

## 1. iOS 层选型

### 1.1 核心框架

| 组件 | 选型 | 版本要求 | 选型理由 |
|------|------|---------|---------|
| UI框架 | SwiftUI | iOS 16.0+ | 声明式UI，状态驱动，适合Mesh网络状态变化频繁的场景；减少UIKit模板代码 |
| 基础框架 | UIKit | iOS 16.0+ | 地图渲染、WebView、复杂手势等场景降级使用 |
| 语音通话 | CallKit + PushKit | iOS 16.0+ | 系统级VoIP通话集成，支持来电界面和后台通话 |
| 本地存储 | SQLite.swift | ~> 0.14 | 轻量、Swift原生、类型安全；适合Mesh路由表、积分等结构化数据 |
| Keychain | Security.framework | 系统自带 | 私钥、公钥、UID等敏感凭据存储 |
| 并发模型 | Swift Concurrency (async/await) | iOS 16.0+ | 替代GCD，避免回调地狱；Mesh事件处理链路的异步流程 |

### 1.2 架构模式

- **MVVM + Coordinator**
  - View：SwiftUI View，纯展示，@StateObject/@ObservedObject 绑定 ViewModel
  - ViewModel：@MainActor 类，管理状态和业务逻辑
  - Model：Codable struct，定义数据边界
  - Coordinator：导航流控制，App层级一个RootCoordinator，子模块按场景划分

### 1.3 目录结构约定

```
src/
├── App/                    # App入口、SceneDelegate、RootCoordinator
├── Modules/                # 按功能模块划分（Identity/Mesh/Crypto/Voice/Map/Points/Storage）
│   ├── Identity/
│   │   ├── Models/
│   │   ├── ViewModels/
│   │   ├── Views/
│   │   └── Services/
│   ├── Mesh/
│   │   ├── Models/
│   │   ├── ViewModels/
│   │   ├── Views/
│   │   └── Services/
│   └── ...
├── Shared/
│   ├── Models/             # 跨模块共享数据模型
│   ├── Protocols/          # 接口协议（MeshServiceProtocol、CryptoServiceProtocol等）
│   ├── Utils/              # 工具函数（Data+Hex、Date+Unix等）
│   └── Extensions/         # Swift扩展
└── Resources/
```

---

## 2. 通信层

### 2.1 传输层选型

| 能力 | 技术方案 | 关键API/框架 | 备注 |
|------|---------|------------|------|
| 蓝牙发现 | Multipeer Connectivity | `MCPeerID`、`MCSession`、`MCNearbyServiceBrowser` | iOS原生P2P发现，支持WiFi P2P fallback |
| WiFi P2P | 同上 | Multipeer Connectivity | 自动选择蓝牙或WiFi，开发者无感知 |
| 数据收发 | Stream API | `InputStream`/`OutputStream` via MCSession | 可靠数据流，带拥塞控制 |
| 语音流 | UDP/RTP | `GCDAsyncUdpSocket`（第三方库） | 实时语音，低延迟，允许丢包 |
| Mesh路由 | 应用层自定义 | `MESH_Route_Table.swift` | 按Phase节奏实现，单跳→多跳 |

### 2.2 协议栈层次

```
┌─────────────────────────────────┐
│     应用层：语音/地图/积分/指令     │  ← 业务数据
├─────────────────────────────────┤
│     加密层：E2E加密 + 验签         │  ← CRYPTO模块
├─────────────────────────────────┤
│     Mesh路由层：多跳转发/路由表     │  ← MESH模块
├─────────────────────────────────┤
│     传输层：Multipeer Connectivity │  ← 蓝牙/WiFi P2P
├─────────────────────────────────┤
│     物理层：蓝牙4.0+ / WiFi Direct  │
└─────────────────────────────────┘
```

### 2.3 通信模式

| 模式 | 适用场景 | 实现方式 |
|------|---------|---------|
| 单播 | 点对点语音、私信 | MCSession send Data |
| 广播 | 节点发现、announce | MCNearbyServiceAdvertiser |
| 多跳转发 | 跨节点语音/地图包 | 应用层路由表，查表转发 |

---

## 3. 安全层

### 3.1 加密体系

| 层级 | 算法/方案 | 用途 |
|------|----------|------|
| 身份签名 | ECDSA P-256 | 私钥在Secure Enclave生成，对数据签名验签 |
| 密钥交换 | ECDH P-256 | 双方协商会话密钥，不传输原始私钥 |
| 语音/数据传输 | AES-256-GCM | 实时数据对称加密，支持关联数据（AEAD） |
| 摘要算法 | SHA-256 | 完整性校验，消息指纹 |

### 3.2 密钥管理

- **私钥存储**：始终驻留在 Secure Enclave，绝不导出
- **公钥分发**：通过Mesh网络传播，带签名
- **会话密钥**：每次通信协商生成，用完即弃（Forward Secrecy）
- **Keychain属性**：`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

### 3.3 防伪造机制

- 所有消息携带发送者ECDSA签名
- 接收方验签后再处理，拒绝不明消息
- 时间戳 + 序列号防重放攻击
- 节点UID与公钥绑定，广播时携带证书链

---

## 4. 地图层

### 4.1 地图引擎

| 组件 | 选型 | 备注 |
|------|------|------|
| 离线矢量地图 | Mapbox iOS SDK / 纯自研Metal渲染 | V1.0 MVP使用预渲染瓦片；V2.0考虑Mapbox离线包 |
| 地图数据格式 | GeoJSON + MBTiles | 离线地图包格式，支持本地存储和分享 |
| 当前位置 | CoreLocation | GPS + 陀螺仪惯导，无网络时使用 |
| 离线等高线 | DEM → 矢量等高线 | V2.0引入，V1.0暂不支持 |
| 路径规划 | A* 算法自研 | V1.0基础路径，V2.0离线A* |

### 4.2 地图数据流

```
离线地图包（.mbtiles）
    ↓
SQLite 读取瓦片数据
    ↓
Metal/CoreGraphics 渲染
    ↓
SwiftUI MapView（UIViewRepresentable 包装）
    ↓
叠加层：用户位置 / 队友位置 / 路径规划
```

### 4.3 地图包中继（V3.0）

- 地图包通过Mesh多跳传输
- 支持分片下载、断点续传
- 校验和验证完整性

---

## 5. 数据层

### 5.1 存储层次

| 存储类型 | 技术方案 | 适用数据 |
|---------|---------|---------|
| 敏感凭据 | Keychain + Secure Enclave | 私钥、UID、证书 |
| 结构化业务数据 | SQLite.swift | 路由表、积分、用户资料、群组信息 |
| 地图缓存 | SQLite BLOB / 文件系统 | 离线地图瓦片包 |
| 用户配置 | UserDefaults | 偏好设置、开关选项 |
| 临时缓存 | NSCache + FileManager | 好友列表、消息草稿 |

### 5.2 SQLite Schema 核心表

```sql
-- 节点路由表
CREATE TABLE mesh_route (
    uid TEXT PRIMARY KEY,
    pubkey BLOB NOT NULL,
    last_seen INTEGER NOT NULL,
    hop_count INTEGER DEFAULT 0,
    is_direct INTEGER NOT NULL
);

-- 积分表
CREATE TABLE points_balance (
    uid TEXT PRIMARY KEY,
    balance INTEGER NOT NULL DEFAULT 0,
    last_updated INTEGER NOT NULL
);

-- 群组成员表
CREATE TABLE group_members (
    group_id TEXT,
    uid TEXT,
    joined_at INTEGER,
    PRIMARY KEY (group_id, uid)
);
```

### 5.3 数据安全

- SQLite 数据库文件加密（AES-256），密钥由Keychain托管
- 敏感字段（余额、群组关系）额外字段级加密
- 数据库操作全部走 WAL 模式，避免写阻塞

---

## 6. 第三方库白名单

> **原则**：白名单制度，未列入清单的库禁止引入。所有库需安全审计后入库。

| 库名 | 版本 | 用途 | 引入理由 | 安全风险 |
|------|------|------|---------|---------|
| SQLite.swift | ~> 0.14 | SQLite封装 | 官方维护、类型安全、纯Swift | 低（纯本地存储） |
| SnapKit | ~> 5.6 | Auto Layout约束 | 代码UI场景必备，语法简洁 | 低（仅布局） |
| CryptoSwift | ~> 1.8 | AES-256-GCM辅助 | 加密实现辅助，检查AEAD实现 | 中（需审计） |
| GCDAsyncUdpSocket | ~> 2.1 | UDP语音流 | 实时语音低延迟，成熟开源 | 低（CocoaAsyncSocket维护良好） |
| Kingfisher | ~> 7.0 | 离线地图瓦片缓存 | 瓦片图片下载缓存 | 中（网络请求，需校验） |

**禁止使用**：
- 任何未在白名单内的第三方库
- 未维护超过2年的库（最后commit > 2年）
- 有已知CVE未修复的库版本

---

## 7. 后台模式 Info.plist 配置

### 7.1 必需的后台模式

```xml
<!-- Voice over IP：后台语音通话 -->
<key>UIBackgroundModes</key>
<array>
    <string>voip</string>          <!-- PushKit来电唤醒 -->
    <string>audio</string>         <!-- 语音通话、背景音乐 -->
    <string>bluetooth-central</string>  <!-- 蓝牙Mesh发现 -->
    <string>bluetooth-peripheral</string><!-- 蓝牙Mesh广播 -->
    <string>location</string>      <!-- 持续定位（地图导航场景） -->
</array>
```

### 7.2 隐私权限描述（Privacy Descriptions）

```xml
<!-- 蓝牙 -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>夏日萤火使用蓝牙发现附近的队友，实现无网络语音通话和位置共享。</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>夏日萤火使用蓝牙广播您的身份，实现Mesh自组网。</string>

<!-- 位置 -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>夏日萤火需要您的位置来在离线地图上显示您的位置，并分享给队友。</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>夏日萤火需要在地图上显示您的当前位置。</string>

<!-- 麦克风 -->
<key>NSMicrophoneUsageDescription</key>
<string>夏日萤火需要麦克风来实现语音通话功能。</string>

<!-- 多播组网 -->
<key>NSLocalNetworkUsageDescription</key>
<string>夏日萤火使用本地网络发现和连接附近设备。</string>

<key>NSBonjourServices</key>
<array>
    <string>_summerspark._tcp</string>
    <string>_summerspark._udp</string>
</array>
```

### 7.3 完整 Info.plist 关键键值（后台相关）

```xml
<key>UIBackgroundModes</key>
<array>
    <string>voip</string>
    <string>audio</string>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
    <string>location</string>
</array>

<key>NSBonjourServices</key>
<array>
    <string>_summerspark._tcp</string>
    <string>_summerspark._udp</string>
</array>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>SummersparkMesh</string>
</array>

<key>UIRequiresFullScreen</key>
<false/>

<key>UILaunchStoryboardName</key>
<string>LaunchScreen</string>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.summerspark.meshrefresh</string>
    <string>com.summerspark.mapdownload</string>
</array>
```

### 7.4 后台任务调度

| 任务ID | 类型 | 用途 | 触发时机 |
|--------|------|------|---------|
| `com.summerspark.meshrefresh` | BGAppRefreshTask | Mesh路由表更新 | 系统按策略调度 |
| `com.summerspark.mapdownload` | BGProcessingTask | 离线地图包下载 | 连接WiFi时 |

---

## 8. 依赖管理

- **包管理器**：Swift Package Manager（SPM）优先，Pod 作为降级
- **CocoaPods Podfile**：`use_frameworks!` + 明确版本号
- **SPM Package.resolved**：提交到Git，确保构建可复现
- **安全审计**：每季度使用 `CocoaPods trunk pod ipc tree` 和 `swift package audit` 检查依赖漏洞

---

*本文档为《夏日萤火》技术栈选型说明，版本 V1.0*
*更新日期：2026-04-22*

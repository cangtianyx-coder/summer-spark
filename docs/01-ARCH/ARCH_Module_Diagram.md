# ARCH_Module_Diagram — 模块依赖树与接口规范

## 1. 模块依赖树（文字缩进表示）

```
夏日萤火 / A-Single-Spark
└── App（应用入口）
    ├── Identity（身份体系）
    │   ├── UID 生成器
    │   ├── 密钥管理器（Keychain / Secure Enclave）
    │   └── 用户信息存储
    ├── Mesh（Mesh 网络）
    │   ├── 蓝牙服务
    │   ├── WiFi P2P 服务
    │   ├── 节点发现
    │   ├── 路由表
    │   └── 中继转发
    ├── Crypto（加密安全）
    │   ├── E2E 加密引擎
    │   ├── 签名验签
    │   └── 防伪造机制
    ├── Voice（语音通讯）
    │   ├── P2P 语音
    │   ├── 群组语音
    │   ├── 编解码器
    │   └── 后台通话管理
    ├── Map（地图导航）
    │   ├── 离线地图引擎
    │   ├── 等高线渲染
    │   ├── 路径规划
    │   └── 导航引擎
    ├── Points（积分体系）
    │   ├── 积分规则
    │   ├── 权重计算
    │   └── 激励调度
    └── Storage（本地存储）
        ├── SQLite 数据库
        └── 加密缓存
```

---

## 2. 各模块输入/输出接口表格

### 2.1 Identity（身份体系）

| 输入 | 说明 | 输出 | 说明 |
|------|------|------|------|
| 设备标识 | 硬件 UUID | UID | 唯一身份标识（字符串） |
| 用户名 | 用户设置 | 公钥/私钥对 | ECDH P-256 椭圆曲线密钥 |
| 设备信息 | 系统版本等 | 身份凭证 | Keychain 安全存储 |

**核心接口：**
- `IdentityManager.generateUID() -> String`
- `IdentityManager.generateKeyPair() -> (publicKey, privateKey)`
- `IdentityManager.storeInKeychain(key: String, value: Data)`
- `IdentityManager.retrieveFromKeychain(key: String) -> Data?`

---

### 2.2 Mesh（Mesh 网络）

| 输入 | 说明 | 输出 | 说明 |
|------|------|------|------|
| 蓝牙扫描结果 | 周围节点列表 | Mesh 拓扑 | 节点连接关系图 |
| WiFi P2P 发现 | 对等节点信息 | 路由表 | 路径信息（下一跳/跳数） |
| 上层业务数据 | 待发送数据 | 中继数据 | 转发至目标节点 |
| Identity UID | 节点标识 | 连接状态 | 在线/离线/漫游中 |

**核心接口：**
- `MeshService.startBluetoothScan() -> [DiscoveredNode]`
- `MeshService.startWiFiP2P() -> [DiscoveredNode]`
- `MeshService.buildRoute(from: UID, to: UID) -> Route?`
- `MeshService.relay(data: Data, via: Route) -> Bool`
- `MeshService.onNodeDiscovered(handler: (DiscoveredNode) -> Void)`

---

### 2.3 Crypto（加密安全）

| 输入 | 说明 | 输出 | 说明 |
|------|------|------|------|
| 明文数据 | 业务数据 | 密文数据 | 加密后的字节流 |
| 对方公钥 | 来自 Identity | E2E 加密包 | 包含 IV + 密文 + 签名 |
| 本地私钥 | 来自 Identity | 签名结果 | 用于验签 |
| 接收数据包 | 含签名 | 验签结果 | true/false + 明文 |

**核心接口：**
- `CryptoEngine.encrypt(data: Data, recipientPublicKey: Data) -> EncryptedPackage`
- `CryptoEngine.decrypt(package: EncryptedPackage, privateKey: Data) -> Data?`
- `CryptoEngine.sign(data: Data, privateKey: Data) -> Signature`
- `CryptoEngine.verify(data: Data, signature: Signature, publicKey: Data) -> Bool`

---

### 2.4 Voice（语音通讯）

| 输入 | 说明 | 输出 | 说明 |
|------|------|------|
| 麦克风音频流 | PCM 原始数据 | 编码语音包 | Opus/AAC 编码后数据 |
| 对方音频数据 | 来自 Mesh | 播放音频流 | 解码后 PCM |
| 目标 UID | 通话对方 | 通话状态 | 呼叫中/通话中/挂断 |
| 网络带宽信息 | Mesh 提供 | 码率自适应 | 调整编码参数 |

**核心接口：**
- `VoiceEngine.startP2PCall(peerUID: UID) -> CallSession`
- `VoiceEngine.startGroupCall(peerUIDs: [UID]) -> CallSession`
- `VoiceEngine.encodeAudio(pcmData: Data) -> EncodedFrame`
- `VoiceEngine.decodeAudio(encodedData: Data) -> Data?`
- `VoiceEngine.endCall(session: CallSession)`

---

### 2.5 Map（地图导航）

| 输入 | 说明 | 输出 | 说明 |
|------|------|------|
| 用户位置 | 经纬度坐标 | 地图瓦片 | 离线矢量/栅格图 |
| 目的地坐标 | 导航终点 | 路径结果 | 路径点序列 |
| 地图区域 | 区域边界 | 等高线数据 | 地形可视化 |
| Mesh 拓扑 | 节点分布 | 中继地图 | 节点接力范围 |

**核心接口：**
- `MapEngine.loadRegion(minLat, maxLat, minLon, maxLon) -> MapRegion`
- `MapEngine.renderContour(region: MapRegion) -> UIImage`
- `MapEngine.calculateRoute(start: Coordinate, end: Coordinate) -> Route`
- `MapEngine.startNavigation(route: Route, onUpdate: (Coordinate) -> Void)`
- `MapEngine.shareMapRegion(region: MapRegion, via: MeshService)`

---

### 2.6 Points（积分体系）

| 输入 | 说明 | 输出 | 说明 |
|------|------|------|
| 节点贡献数据 | 带宽/存储/计算 | 积分余额 | 用户积分总数 |
| Mesh 拓扑 | 路由权重 | 调度优先级 | 高积分节点优先路由 |
| 时间戳 | 数据新鲜度 | 激励规则 | 本周期积分奖励 |
| 路由成功率 | 传输质量 | 权重更新 | 动态调整 |

**核心接口：**
- `PointsCalculator.calculateReward(contribution: Contribution) -> Points`
- `PointsCalculator.getRoutingPriority(nodeUID: UID) -> Float`
- `PointsCalculator.applyIncentiveRule(contribution: Contribution, timestamp: Date) -> Int`
- `PointsManager.syncCredits() -> Bool`

---

### 2.7 Storage（本地存储）

| 输入 | 说明 | 输出 | 说明 |
|------|------|------|------|
| 用户数据 | 业务数据 | SQLite 记录 | 结构化存储 |
| 密钥材料 | Identity 产生 | 加密存储 | Keychain/SQLite |
| 地图瓦片 | 离线数据 | 文件系统 | 缓存目录 |
| 配置参数 | App 设置 | UserDefaults | 轻量配置 |

**核心接口：**
- `StorageManager.saveUserData(_ data: Data, key: String) -> Bool`
- `StorageManager.loadUserData(key: String) -> Data?`
- `StorageManager.saveEncrypted(_ data: Data, key: String) -> Bool`
- `StorageManager.loadEncrypted(key: String) -> Data?`
- `StorageManager.saveMapTile(tileID: String, data: Data)`
- `StorageManager.loadMapTile(tileID: String) -> Data?`

---

## 3. 数据流向描述

### 3.1 整体数据流图

```
[用户操作] --> [App 层]
                │
                ├──> [Identity] ──> [Keychain/Secure Enclave]
                │                  └──> [Crypto] ──> [Mesh]（传输加密数据）
                │
                ├──> [Voice] ──> [Crypto]（编码加密） ──> [Mesh]（发送）
                │     │
                │     └──> [Storage]（通话记录）
                │
                ├──> [Map] ──> [Storage]（地图缓存）
                │     │
                │     └──> [Mesh]（地图共享/中继）
                │
                └──> [Points] ──> [Storage]（积分记录）
                              └──> [Mesh]（权重调度）
```

### 3.2 P2P 语音数据流

```
麦克风采集 PCM
    ↓
[VoiceEngine.encodeAudio] → Opus/AAC 编码帧
    ↓
[CryptoEngine.encrypt] → E2E 加密包（公钥加密）
    ↓
[MeshService.relay] → 多跳中继转发
    ↓
[MeshService.recv] → 解密
    ↓
[CryptoEngine.decrypt] → 解密出编码帧
    ↓
[VoiceEngine.decodeAudio] → PCM 原始音频
    ↓
扬声器播放
```

### 3.3 地图下载与共享数据流

```
[用户请求区域地图]
    ↓
[MapEngine.checkCache] → 命中？→ 直接加载
    ↓（未命中）
[MapEngine.downloadTiles] → 网络请求瓦片
    ↓
[StorageManager.saveMapTile] → 本地 SQLite 缓存
    ↓
[MapEngine.renderContour] → UIImage 显示
```

### 3.4 积分激励数据流

```
[MeshService 统计节点贡献]
    ↓（带宽中继量、存储贡献、计算贡献）
[PointsCalculator.计算奖励] → 积分增加
    ↓
[PointsManager 更新余额]
    ↓
[StorageManager 持久化] → SQLite
    ↓
[MeshService 路由调度] → 高积分节点优先路由
```

### 3.5 身份与加密数据流

```
[App 启动]
    ↓
[IdentityManager 检查本地 UID]
    ↓（不存在）
[generateUID] → 生成唯一标识
    ↓
[generateKeyPair] → ECDH P-256 密钥对
    ↓
[storeInKeychain] → Secure Enclave 保护私钥
    ↓
[导出公钥] → 分发至其他节点
```

---

## 4. 模块依赖关系矩阵

| 模块 | Identity | Mesh | Crypto | Voice | Map | Points | Storage |
|------|:--------:|:----:|:------:|:-----:|:---:|:------:|:-------:|
| **Identity** | - | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Mesh** | ✓ | - | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Crypto** | ✓ | ✓ | - | ✓ | - | - | ✓ |
| **Voice** | ✓ | ✓ | ✓ | - | - | - | ✓ |
| **Map** | - | ✓ | - | - | - | - | ✓ |
| **Points** | - | ✓ | - | - | - | - | ✓ |
| **Storage** | ✓ | - | ✓ | - | ✓ | ✓ | - |

**依赖说明**：行依赖列，例如 Identity ✓ Mesh 表示 Identity 模块依赖 Mesh 模块。

---

## 5. 跨模块调用示例

### 5.1 发送加密语音

```swift
// Voice 模块调用 Crypto + Mesh
func sendEncryptedVoice(pcmData: Data, to recipientUID: UID) {
    // 1. 编码
    let encoded = VoiceEngine.encodeAudio(pcmData: pcmData)
    
    // 2. 获取对方公钥（Identity）
    guard let recipientPublicKey = IdentityManager.getPublicKey(uid: recipientUID) else {
        return
    }
    
    // 3. 加密（Crypto）
    let encrypted = CryptoEngine.encrypt(data: encoded, recipientPublicKey: recipientPublicKey)
    
    // 4. 发送（Mesh）
    MeshService.send(data: encrypted, to: recipientUID)
}
```

### 5.2 地图区域共享（Map → Mesh → Storage）

```swift
func shareMapRegion(_ region: MapRegion, via meshService: MeshService) {
    // 1. 获取区域数据
    let mapData = MapEngine.getRegionData(region: region)
    
    // 2. 通过 Mesh 中继广播
    meshService.broadcast(mapData, ttl: 3)
    
    // 3. 存储到本地（Storage）
    StorageManager.saveMapTile(tileID: region.id, data: mapData)
}
```

---

*本文档为《夏日萤火》架构文档 · 模块依赖树与接口规范 · V1.0*
*更新日期：2026-04-22*
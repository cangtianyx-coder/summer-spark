# FINAL_Installation_Guide.md — 夏日萤火 / A-Single-Spark
## 安装说明与真机调试步骤 · V1.0

> 版本：V1.0 | 更新日期：2026-04-22 | 负责：文档组

---

## 1. 环境要求

### 1.1 开发环境

| 项目 | 要求 |
|------|------|
| Xcode | 15.0+ |
| iOS 部署目标 | iOS 16.0+ |
| Swift 版本 | Swift 5.9+ |
| 设备 | iPhone（蓝牙 + WiFi 支持） |
| 测试设备数量 | 至少 2 台（Mesh 网络需多设备验证） |
| macOS 版本 | Sonoma 14.0+ |

### 1.2 必需能力（测试真机需开启）

- **蓝牙**：全程开启，用于节点发现和 Mesh 组网
- **定位**：始终允许（离线地图 + 位置共享）
- **本地网络**：允许发现和对等连接
- **后台刷新**：开启（积分同步、路由表维护）

---

## 2. 项目结构

```
~/summer-spark/
├── docs/
│   └── 99-FINAL/
│       ├── FINAL_Installation_Guide.md  ← 本文档
│       └── FINAL_Quick_Start.md
├── src/
│   ├── App/                    # 应用入口 SummerSparkApp.swift
│   ├── Modules/
│   │   ├── Identity/           # 一机一ID身份体系
│   │   ├── Mesh/               # 蓝牙/WiFi P2P Mesh 网络
│   │   ├── Crypto/             # E2E 加密与验签
│   │   ├── Voice/              # 语音通话（PTT）
│   │   ├── Map/                # 离线地图
│   │   ├── Points/             # 积分激励
│   │   └── Storage/            # SQLite + Keychain
│   ├── Shared/
│   │   ├── Models/             # 跨模块数据模型
│   │   ├── Protocols/          # 接口协议
│   │   └── Utils/              # 工具函数（Logger等）
│   └── Resources/
├── configs/
│   ├── Info.plist              # 隐私权限 + 后台模式
│   └── SummerSpark.entitlements
└── Podfile                     # 第三方依赖
```

---

## 3. 安装步骤

### 3.1 首次克隆

```bash
# 克隆项目
git clone ~/summer-spark/
cd summer-spark

# 查看项目结构
ls -la
```

### 3.2 安装第三方依赖

> 依赖管理：Swift Package Manager（SPM）优先

#### 方案A：SPM（推荐）

Xcode 打开项目后会自动解析 `Package.swift`（如有），或通过：
**File → Add Package Dependencies → 搜索并添加以下包**

| 包名 | 版本 | 用途 |
|------|------|------|
| SQLite.swift | ~> 0.14 | SQLite 数据库封装 |
| SnapKit | ~> 5.6 | Auto Layout 约束 |

#### 方案B：CocoaPods（如使用）

```bash
cd ~/summer-spark
pod install
open *.xcworkspace   # 注意：用 workspace 不是 xcodeproj
```

### 3.3 配置签名（真机调试必需）

1. 打开 `summer-spark.xcodeproj` 或 `.xcworkspace`
2. 选择项目根节点 → **Signing & Capabilities**
3. 勾选 **Automatically manage signing**
4. 选择 **Team**（你的 Apple Developer 账号）
5. Bundle Identifier 确认：`com.summerspark.mesh`（如被占用自行修改）
6. 确保 **Target** 为 `SummerSpark`（不是 Pods）

### 3.4 配置隐私权限

文件：`src/App/Info.plist`（或 Xcode 项目设置）

以下权限**必须填写描述文字**，否则提交 App Store 会被拒：

| Key | 描述（可自行精简） |
|-----|------------------|
| `NSBluetoothAlwaysUsageDescription` | 夏日萤火使用蓝牙发现附近的队友，实现无网络语音通话。 |
| `NSBluetoothPeripheralUsageDescription` | 夏日萤火使用蓝牙广播您的身份，实现Mesh自组网。 |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | 夏日萤火需要您的位置来显示在离线地图上并共享给队友。 |
| `NSLocationWhenInUseUsageDescription` | 夏日萤火需要在地图上显示您的当前位置。 |
| `NSMicrophoneUsageDescription` | 夏日萤火需要麦克风来实现语音通话功能。 |
| `NSLocalNetworkUsageDescription` | 夏日萤火使用本地网络发现和连接附近设备。 |

后台模式（`UIBackgroundModes`）：
```
voip, audio, bluetooth-central, bluetooth-peripheral, location
```

---

## 4. 真机调试步骤

### 4.1 连接测试设备

1. 用 USB 线连接 iPhone 和 Mac
2. iPhone 弹出"信任此电脑？"→ 点击**信任**，输入解锁密码
3. Xcode 顶部导航栏选择目标设备（你的 iPhone）
4. 点击 ▶️（Run）按钮

### 4.2 运行验证清单

启动后检查控制台（Console）日志：

```
[SummerSpark] All modules initialized
[SummerSpark] Background modes configured
```

确认没有以下错误：
- ❌ `Bluetooth is not powered on`
- ❌ `Location services are not enabled`
- ❌ `Keychain error`
- ❌ `Database initialization failed`

### 4.3 多设备 Mesh 测试（至少 2 台）

1. 设备 A：安装 SummerSpark，保持前台运行
2. 设备 B：同样安装，连接同一 WiFi 或蓝牙范围重叠
3. 在设备 A 的界面观察是否发现设备 B（节点列表更新）
4. 测试 PTT 语音：长按 PTT 按钮 → 说话 → 释放 → 对方听到

### 4.4 控制台调试命令

在 Xcode Console（底部调试区）可以使用日志过滤：

```
tag:SummerSpark                    # 只看本项目日志
tag:BluetoothService              # 只看蓝牙模块
tag:MeshService                   # 只看Mesh模块
```

---

## 5. 常见问题排查

### Q1: 蓝牙一直搜不到对方设备

**检查项**：
- 双方蓝牙都已开启（设置中确认，非 App 内）
- 双方 WiFi 都已开启（MultipeerConnectivity 会在蓝牙弱时 fallback 到 WiFi P2P）
- 距离不要太远（建议 3 米内初次测试）
- 检查设备是否已经被其他 App 连接占用蓝牙

### Q2: 编译报错 "Module 'xxx' not found"

**解决方案**：
```bash
# 清理缓存
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# 重新打开 Xcode
open summer-spark.xcodeproj
# 或（如果用 CocoaPods）
open summer-spark.xcworkspace
```

### Q3: 无法安装到真机（提示签名错误）

**解决方案**：
- 确认 Apple Developer 账号已加入团队（苹果官网）
- Bundle Identifier 确认唯一（不能与其他人的 App 重名）
- 检查 iPhone 是否启用"开发者模式"（设置 → 隐私与安全性 → 开发者模式）

### Q4: 语音通话无声音

**检查项**：
- 麦克风权限已授权（第一次启动会弹框）
- iPhone 静音开关是否打开（侧边静音拨杆）
- 检查是否被其他 App 占用音频会话（音乐 App 等）

### Q5: 地图加载不出来

- 确认已下载离线地图包（V1.0 需要手动放置测试数据）
- 检查 CoreLocation 权限是否"始终允许"（不只是"使用App时"）

---

## 6. 调试架构图

```
┌──────────────────────────────────────────────────────┐
│                     iPhone 设备                       │
│                                                      │
│  ┌──────────────┐     ┌──────────────┐              │
│  │   Summer     │────▶│  Mesh 网络   │              │
│  │   Spark App  │     │ (蓝牙/WiFi)  │              │
│  └──────┬───────┘     └──────┬───────┘              │
│         │                    │                       │
│  ┌─────▼───────┐     ┌──────▼──────┐              │
│  │   语音/地图  │     │  加密/验签   │              │
│  │   模块       │     │             │              │
│  └─────────────┘     └─────────────┘              │
│                                                      │
│  ┌──────────────┐     ┌──────────────┐              │
│  │   积分引擎   │     │  本地存储    │              │
│  │              │     │ (SQLite/Key) │              │
│  └──────────────┘     └──────────────┘              │
└──────────────────────────────────────────────────────┘
         │                        ▲
         │   USB / WiFi           │
         ▼                        │
    ┌────────────────┐            │
    │   Xcode 调试    │            │
    │   (Mac 电脑)    │────────────┘
    └────────────────┘
```

---

## 7. 测试账号说明

- **无需登录**：V1.0 MVP 无用户系统，完全基于设备身份（UID）
- **设备身份**：首次启动自动生成 UUID 保存在 Keychain
- **公私钥对**：自动在 Secure Enclave 生成，私钥永不离开设备

---

## 8. 后续步骤

安装完成后，请阅读 `FINAL_Quick_Start.md` 快速上手指南。

---

*本文档为《夏日萤火》安装说明与调试指南，版本 V1.0*
*更新日期：2026-04-22*
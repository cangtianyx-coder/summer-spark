# 夏日萤火 / Summer Spark

**去中心化离线 Mesh 自组网通讯 App / Decentralized Offline Mesh Networking App**

---

## [中文版]

### 项目简介

夏日萤火（Summer Spark）是一款基于 iPhone 构建的**去中心化离线 Mesh 自组织网络**通讯应用。无需互联网即可实现语音通话、地图导航、位置共享，适用于户外探险、灾害应急等无网络场景。

### 核心特性

- **无网通信**：完全依赖蓝牙/WiFi P2P，不走互联网
- **Mesh 自组网**：多设备自动发现、多跳中继转发
- **端到端加密**：所有通信使用 ECDSA P-256 + AES-256-GCM 加密
- **离线地图**：支持预下载地图瓦片，无网也可导航
- **积分激励**：中继转发贡献可获得积分，优先路由

### 项目结构

```
summer-spark/
├── docs/               # 项目文档
│   ├── 00-PROJECT-CHARTER.md      # 项目章程
│   ├── 01-ARCH/                  # 架构文档
│   ├── 10-SEC/                   # 安全审计
│   └── 99-FINAL/                 # 最终交付
├── src/                # 源代码
│   ├── App/            # 应用入口
│   ├── Modules/        # 功能模块
│   │   ├── Identity/   # 身份体系
│   │   ├── Mesh/       # Mesh 网络
│   │   ├── Crypto/     # 端到端加密
│   │   ├── Voice/      # 语音通话
│   │   ├── Map/        # 离线地图
│   │   ├── Points/     # 积分激励
│   │   └── Storage/    # 本地存储
│   └── Shared/         # 跨模块共享
└── configs/            # 配置文件
```

### 模块说明

| 模块 | 职责 |
|------|------|
| **Identity** | 设备唯一身份（UID）、公私钥对、Keychain 管理 |
| **Mesh** | 蓝牙/WiFi 发现、多跳路由、节点发现与连接 |
| **Crypto** | E2E 加密、消息签名与验签、防伪造机制 |
| **Voice** | PTT 语音通话、音频编解码、后台通话 |
| **Map** | 离线地图加载、等高线渲染、路径规划 |
| **Points** | 积分生成、中继激励、路由权重调度 |
| **Storage** | SQLite 数据库、加密缓存、隐私数据保护 |

### 环境要求

| 项目 | 要求 |
|------|------|
| Xcode | 15.0+ |
| iOS | 16.0+ |
| 设备 | iPhone（蓝牙 + WiFi） |
| 测试设备 | 至少 2 台（Mesh 需多设备验证） |

### 快速开始

```bash
cd ~/summer-spark
open SummerSpark.xcodeproj
```

在 Xcode 中选择目标 iPhone，点击 ▶️ 运行。

### 技术栈

| 层级 | 技术 |
|------|------|
| UI | SwiftUI + UIKit |
| 通信 | CoreBluetooth + Network.framework |
| 加密 | ECDSA P-256 + AES-256-GCM |
| 存储 | SQLite + Keychain |
| 语音 | AVAudioEngine + Opus |
| 地图 | Mapbox iOS SDK |
| 并发 | Swift Concurrency |

### 安全原则

- 私钥**永不离开** Secure Enclave
- 所有消息**必须验签**后才处理
- 敏感数据**不上日志**
- 传输数据**不暴露明文**

### 版本历史

| 版本 | 阶段 | 说明 |
|------|------|------|
| V1.0 | MVP | 核心骨架：身份体系 + Mesh 单跳 + 基础语音 + 离线地图 |
| V2.0 | 增强 | 面对面建群、群组语音、完整积分体系 |
| V3.0 | 完整 | 自动路径寻址、多跳稳定路由、地图包中继共享 |

---

## [English Version]

### Project Overview

Summer Spark is a **decentralized offline Mesh networking** communication app built for iPhone. It enables voice calls, map navigation, and location sharing without internet connectivity, ideal for outdoor adventures, disaster response, and other offline scenarios.

### Core Features

- **Offline Communication**: Entirely relies on Bluetooth/WiFi P2P, no internet required
- **Mesh Networking**: Multi-device auto-discovery, multi-hop relay forwarding
- **End-to-End Encryption**: All communications use ECDSA P-256 + AES-256-GCM encryption
- **Offline Maps**: Pre-download map tiles for navigation without network
- **Credit Incentive**: Earn credits through relay contributions for priority routing

### Project Structure

```
summer-spark/
├── docs/               # Documentation
│   ├── 00-PROJECT-CHARTER.md      # Project charter
│   ├── 01-ARCH/                  # Architecture docs
│   ├── 10-SEC/                   # Security audit
│   └── 99-FINAL/                 # Final delivery
├── src/                # Source code
│   ├── App/            # App entry
│   ├── Modules/        # Feature modules
│   │   ├── Identity/   # Identity system
│   │   ├── Mesh/       # Mesh network
│   │   ├── Crypto/     # E2E encryption
│   │   ├── Voice/      # Voice calls
│   │   ├── Map/        # Offline maps
│   │   ├── Points/     # Credit system
│   │   └── Storage/    # Local storage
│   └── Shared/         # Cross-module shared
└── configs/            # Configuration files
```

### Module Description

| Module | Responsibility |
|--------|----------------|
| **Identity** | Device unique identity (UID), key pairs, Keychain management |
| **Mesh** | Bluetooth/WiFi discovery, multi-hop routing, node connection |
| **Crypto** | E2E encryption, message signing/verification, anti-forgery |
| **Voice** | PTT voice calls, audio codec, background calls |
| **Map** | Offline map loading, contour rendering, route planning |
| **Points** | Credit generation, relay incentives, routing priority |
| **Storage** | SQLite database, encrypted cache, privacy protection |

### Requirements

| Item | Requirement |
|------|-------------|
| Xcode | 15.0+ |
| iOS | 16.0+ |
| Device | iPhone (Bluetooth + WiFi) |
| Test Devices | At least 2 (Mesh requires multi-device verification) |

### Quick Start

```bash
cd ~/summer-spark
open SummerSpark.xcodeproj
```

Select target iPhone in Xcode, click ▶️ to run.

### Tech Stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI + UIKit |
| Communication | CoreBluetooth + Network.framework |
| Encryption | ECDSA P-256 + AES-256-GCM |
| Storage | SQLite + Keychain |
| Voice | AVAudioEngine + Opus |
| Maps | Mapbox iOS SDK |
| Concurrency | Swift Concurrency |

### Security Principles

- Private keys **never leave** Secure Enclave
- All messages **must be verified** before processing
- Sensitive data **never logged**
- Transmitted data **never exposed in plaintext**

### Security Audit Results

After three rounds of security audits, 21 issues were identified and fixed:

| Round | P0 (Critical) | P1 (Important) | P2 (Moderate) | Total |
|-------|---------------|----------------|---------------|-------|
| Round 1 | 2 | 4 | 2 | 8 |
| Round 2 | 1 | 3 | 2 | 6 |
| Round 3 | 1 | 3 | 3 | 7 |
| **Total** | **4** | **10** | **7** | **21** |

Key security improvements:
- **Encryption**: Per-message unique salt, verify-then-decrypt pattern
- **Protocol**: Replay attack protection, route validation
- **Privacy**: Device token masking, BLE anonymous broadcast
- **Data**: Keychain storage, file protection, SQL injection prevention
- **Concurrency**: Array bounds fix, Timer leak fix, @MainActor annotations

### Version History

| Version | Stage | Description |
|---------|-------|-------------|
| V1.0 | MVP | Core skeleton: Identity + Single-hop Mesh + Basic Voice + Offline Maps |
| V2.0 | Enhanced | Face-to-face groups, group voice, complete credit system |
| V3.0 | Complete | Auto path-finding, stable multi-hop routing, map relay sharing |

---

### Documentation

| Document | Description |
|----------|-------------|
| [Project Charter](./docs/00-PROJECT-CHARTER.md) | Project goals, team, phase planning |
| [System Architecture](./docs/01-ARCH/ARCH_System_Overview.md) | Module boundaries, call relations, state machines |
| [Tech Stack](./docs/01-ARCH/ARCH_Tech_Stack.md) | Framework selection, dependencies, background config |
| [Security Guidelines](./docs/10-SEC/SEC_Security_Guidelines.md) | Security requirements, encryption specs |
| [Installation Guide](./docs/99-FINAL/FINAL_Installation_Guide.md) | Environment setup, device debugging steps |
| [Quick Start](./docs/99-FINAL/FINAL_Quick_Start.md) | First-time usage instructions |

---

*夏日萤火 / Summer Spark*
*Version V3.0 | 2026-04-23*

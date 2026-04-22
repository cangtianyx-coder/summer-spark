# 夏日萤火 / A-Single-Spark

**去中心化离线 Mesh 自组网通讯 App**

---

## 项目简介

夏日萤火（A-Single-Spark）是一款基于 iPhone 构建的**去中心化离线 Mesh 自组织网络**通讯应用。无需互联网即可实现语音通话、地图导航、位置共享，适用于户外探险、灾害应急等无网络场景。

### 核心特性

- **无网通信**：完全依赖蓝牙/WiFi P2P，不走互联网
- **Mesh 自组网**：多设备自动发现、多跳中继转发
- **端到端加密**：所有通信使用 ECDSA P-256 + AES-256-GCM 加密
- **离线地图**：支持预下载地图瓦片，无网也可导航
- **积分激励**：中继转发贡献可获得积分，优先路由

---

## 项目结构

```
summer-spark/
├── docs/               # 项目文档
│   ├── 00-PROJECT-CHARTER.md      # 项目章程
│   ├── 01-ARCH/                  # 架构文档
│   │   ├── ARCH_System_Overview.md
│   │   ├── ARCH_Module_Diagram.md
│   │   └── ARCH_Tech_Stack.md
│   ├── 10-SEC/                   # 安全审计
│   └── 99-FINAL/                 # 最终交付
│       ├── FINAL_Installation_Guide.md  # 安装调试指南
│       └── FINAL_Quick_Start.md        # 快速上手
├── src/                # 源代码
│   ├── App/            # 应用入口
│   ├── Modules/        # 功能模块
│   │   ├── Identity/   # 身份体系（UID/公私钥）
│   │   ├── Mesh/      # Mesh 网络（蓝牙/WiFi P2P）
│   │   ├── Crypto/    # 端到端加密
│   │   ├── Voice/     # 语音通话
│   │   ├── Map/       # 离线地图
│   │   ├── Points/    # 积分激励
│   │   └── Storage/   # 本地存储
│   └── Shared/        # 跨模块共享
│       ├── Models/     # 数据模型
│       ├── Protocols/ # 接口协议
│       └── Utils/     # 工具函数
└── configs/           # 配置文件
    ├── Info.plist
    └── SummerSpark.entitlements
```

---

## 模块说明

| 模块 | 职责 |
|------|------|
| **Identity** | 设备唯一身份（UID）、公私钥对、Keychain 管理 |
| **Mesh** | 蓝牙/WiFi 发现、多跳路由、节点发现与连接 |
| **Crypto** | E2E 加密、消息签名与验签、防伪造机制 |
| **Voice** | PTT 语音通话、音频编解码、后台通话 |
| **Map** | 离线地图加载、等高线渲染、路径规划 |
| **Points** | 积分生成、中继激励、路由权重调度 |
| **Storage** | SQLite 数据库、加密缓存、隐私数据保护 |

---

## 环境要求

| 项目 | 要求 |
|------|------|
| Xcode | 15.0+ |
| iOS | 16.0+ |
| 设备 | iPhone（蓝牙 + WiFi） |
| 测试设备 | 至少 2 台（Mesh 需多设备验证） |

---

## 快速开始

### 1. 编译运行

```bash
cd ~/summer-spark
open summer-spark.xcodeproj   # 或 .xcworkspace
```

在 Xcode 中选择目标 iPhone，点击 ▶️ 运行。

### 2. 安装调试

详细步骤见：[FINAL_Installation_Guide.md](./docs/99-FINAL/FINAL_Installation_Guide.md)

### 3. 快速上手

详细操作见：[FINAL_Quick_Start.md](./docs/99-FINAL/FINAL_Quick_Start.md)

---

## 技术栈

| 层级 | 技术 |
|------|------|
| UI | SwiftUI（声明式）+ UIKit（降级） |
| 通信 | MultipeerConnectivity（蓝牙/WiFi P2P） |
| 加密 | ECDSA P-256 + AES-256-GCM |
| 存储 | SQLite.swift + Keychain |
| 语音 | CallKit + PushKit + Opus |
| 地图 | Mapbox / 自研 Metal 渲染 |
| 并发 | Swift Concurrency（async/await） |

---

## 安全原则

- 私钥**永不离开** Secure Enclave
- 所有消息**必须验签**后才处理
- 敏感数据**不上日志**
- 传输数据**不暴露明文**

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [项目章程](./docs/00-PROJECT-CHARTER.md) | 项目目标、团队、阶段规划 |
| [系统架构](./docs/01-ARCH/ARCH_System_Overview.md) | 模块边界、调用关系、状态机 |
| [技术栈](./docs/01-ARCH/ARCH_Tech_Stack.md) | 框架选型、第三方库、后台配置 |
| [安全指南](./docs/10-SEC/SEC_Security_Guidelines.md) | 安全要求、加密规范 |
| [UX 设计](./docs/09-UX/UX_Design_Guidelines.md) | 界面规范、交互设计 |
| [安装指南](./docs/99-FINAL/FINAL_Installation_Guide.md) | 环境配置、真机调试步骤 |
| [快速上手](./docs/99-FINAL/FINAL_Quick_Start.md) | 首次使用操作说明 |

---

## 版本历史

| 版本 | 阶段 | 说明 |
|------|------|------|
| V1.0 | MVP | 核心骨架：身份体系 + Mesh 单跳 + 基础语音 + 离线地图 |

---

*夏日萤火 / A-Single-Spark*
*版本 V1.0 | 2026-04-22*
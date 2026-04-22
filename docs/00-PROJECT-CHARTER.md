# 夏 日 萤 火 / A-Single-Spark
## iPhone 去中心化离线 Mesh 自组网通讯 App
### 项目章程 Project Charter · V1.0

---

## 1. 项目信息

| 字段 | 内容 |
|------|------|
| 项目名称 | 夏 日 萤 火 / A-Single-Spark |
| 项目类型 | iOS 原生应用（Swift/SwiftUI） |
| 核心定位 | 无网络环境下，基于 iPhone 构建纯本地无线 Mesh 自组织网络，实现语音/地图/位置共享 |
| 研发周期 | V1.0 MVP → V2.0 → V3.0（按阶段迭代） |
| 交付时间 | 按阶段里程碑交付 |
| 代码仓库 | ~/summer-spark/ |
| 文档仓库 | ~/summer-spark/docs/ |

---

## 2. 团队结构与 Agent 角色

```
Orchestrator（主调度师 / 项目经理）
├── iOS-Architect          系统架构师
│  职责：整体架构设计、技术选型、模块边界定义
├── Identity-Engineer     身份体系工程师
│  职责：UID生成、用户名、公钥私钥、Keychain、Secure Enclave
├── Mesh-Networker        Mesh网络工程师
│  职责：蓝牙/WiFi P2P、节点发现、多跳路由、中继转发
├── Crypto-Officer        加密安全工程师
│  职责：E2E加密体系、验签流程、防伪造机制
├── Voice-Engineer        语音通讯工程师
│  职责：点对点/群组语音、编解码、后台通话
├── Map-Navigator         地图导航工程师
│  职责：离线等高线地图、路径规划、导航引擎
├── Points-Economist      积分经济学家
│  职责：积分体系、激励规则、权重调度
├── Storage-Engineer      存储工程师
│   职责：SQLite本地存储、加密存储、数据管理
├── UX-Blind-Tester       盲测用户体验师
│   职责：非业务背景视角、UI可理解性、操作流程验证
└── Security-Auditor      代码安全审计师
    职责：代码安全审计、威胁建模、漏洞修复
```

---

## 3. 阶段规划（Phase）

### Phase 1：V1.0 MVP（第1阶段）
**目标**：完成核心骨架，可演示基本功能

1. 身份体系（UID + 用户名 + 公钥私钥）
2. 待机/组网双模态基础框架
3. 蓝牙/WiFi 基础连接（手动切换）
4. 简单 Mesh 单跳中继（暂不实现多跳）
5. 公钥私钥验签加密（基础流程）
6. 基础点对点语音（组网模态）
7. 基础离线地图（单区域，暂不等高线）
8. 本地加密存储（Keychain + SQLite）

### Phase 2：V2.0（第2阶段）
**目标**：完善功能链路，用户可用版本

1. 完整多跳 Mesh 路由（A→B→C→D）
2. 面对面建群 + 群组语音
3. 完整积分体系上线
4. 等高线地图渲染（DEM + 矢量等高线）
5. 路径规划与路径式地图下载
6. 积分优先级调度路由

### Phase 3：V3.0（第3阶段）
**目标**：优化体验，量产准备

1. 自动路径寻址与离线导航
2. 多跳稳定路由优化
3. 地图包中继共享
4. 完整积分优先级调度
5. 低功耗后台优化
6. TestFlight 发布准备

---

## 4. 文件协作规范

### 4.1 文件命名规范

| Agent | 输出文件前缀 | 示例 |
|-------|------------|------|
| iOS-Architect | `ARCH_` | `ARCH_Module_Map.md`、`ARCH_SwiftUI_Conventions.md` |
| Identity-Engineer | `IDN_` | `IDN_UID_Generator.swift`、`IDN_Keychain_Manager.swift` |
| Mesh-Networker | `MESH_` | `MESH_Bluetooth_Service.swift`、`MESH_Route_Table.swift` |
| Crypto-Officer | `CRYPTO_` | `CRYPTO_E2E_Encryption.swift`、`CRYPTO_Signer.swift` |
| Voice-Engineer | `VOICE_` | `VOICE_P2P_Codec.swift`、`VOICE_Group_Audio.swift` |
| Map-Navigator | `MAP_` | `MAP_Offline_Engine.swift`、`MAP_Path_Planner.swift` |
| Points-Economist | `PTS_` | `PTS_Credit_Rules.swift`、`PTS_Weight_Calculator.swift` |
| Storage-Engineer | `STOR_` | `STOR_SQLite_Schema.swift`、`STOR_Encrypted_Cache.swift` |
| UX-Blind-Tester | `UX_` | `UX_Blind_Test_Report.md`、`UX_UI_Checklist.md` |
| Security-Auditor | `SEC_` | `SEC_Audit_Report.md`、`SEC_Threat_Model.md` |

### 4.2 目录结构

```
~/summer-spark/
├── docs/                          # 所有文档交付物
│   ├── 00-PROJECT-CHARTER.md       # 本文件，项目总章程
│   ├── 01-ARCH/                    # 架构文档
│   │   ├── ARCH_System_Overview.md
│   │   ├── ARCH_Module_Diagram.md
│   │   └── ARCH_Tech_Stack.md
│   ├── 02-IDN/                     # 身份体系文档
│   ├── 03-MESH/                    # Mesh网络文档
│   ├── 04-CRYPTO/                  # 加密体系文档
│   ├── 05-VOICE/                   # 语音通讯文档
│   ├── 06-MAP/                     # 地图导航文档
│   ├── 07-PTS/                     # 积分体系文档
│   ├── 08-STOR/                    # 存储体系文档
│   ├── 09-UX/                      # UX测试报告
│   ├── 10-SEC/                     # 安全审计报告
│   └── 99-FINAL/                   # 最终交付文档
│       ├── FINAL_Installation_Guide.md
│       ├── FINAL_Quick_Start.md
│       └── FINAL_Changelog.md
├── src/                           # 所有源代码交付物
│   ├── App/                       # App入口、SceneDelegate
│   │   └── SummerSparkApp.swift
│   ├── Modules/                   # 按功能模块划分
│   │   ├── Identity/              # 一机一ID + 用户名
│   │   ├── Mesh/                  # Mesh网络 + 路由
│   │   ├── Crypto/                # E2E加密
│   │   ├── Voice/                 # 语音
│   │   ├── Map/                   # 地图导航
│   │   ├── Points/                # 积分激励
│   │   └── Storage/               # 本地存储
│   ├── Shared/                    # 跨模块共享
│   │   ├── Models/                # 数据模型
│   │   ├── Protocols/             # 接口协议
│   │   └── Utils/                 # 工具函数
│   └── Resources/                 # 资源文件（Assets等）
├── configs/                       # 配置文件
│   ├── Info.plist
│   └── SummerSpark.entitlements
└── tests/                         # 测试代码
    └── UnitTests/
```

### 4.3 上游下游文件依赖关系（读取规范）

| Agent（下游） | 必须先读取的上游交付物 |
|-------------|----------------------|
| Mesh-Networker | `docs/01-ARCH/ARCH_System_Overview.md` + `docs/02-IDN/IDN_UID_Spec.md` |
| Crypto-Officer | `docs/01-ARCH/ARCH_System_Overview.md` + `docs/02-IDN/IDN_Crypto_Key_Spec.md` |
| Voice-Engineer | `docs/01-ARCH/ARCH_System_Overview.md` + `docs/04-CRYPTO/CRYPTO_E2E_Spec.md` |
| Map-Navigator | `docs/01-ARCH/ARCH_System_Overview.md` + `docs/06-MAP/MAP_Offline_Spec.md` |
| Points-Economist | `docs/01-ARCH/ARCH_System_Overview.md` |
| Storage-Engineer | `docs/01-ARCH/ARCH_System_Overview.md` + 所有模块数据模型 |
| UX-Blind-Tester | `docs/00-PROJECT-CHARTER.md` + `docs/01-ARCH/ARCH_System_Overview.md` + 所有UI源文件 |
| Security-Auditor | 全部源文件 + `docs/00-PROJECT-CHARTER.md` |

---

## 5. 质量要求

### 5.1 代码质量
- 所有代码文件头部必须注释：功能说明 + 依赖文件列表
- 主要逻辑节点必须标注注释（模块/选择节点/状态变更）
- 禁止使用未经验证的第三方库
- SwiftLint / SwiftFormat 格式化通过

### 5.2 安全要求
- 私钥永不离开 Secure Enclave
- 网络传输数据必须验签，不明文泄露
- 所有输入必须做边界检查
- 敏感数据不上日志

### 5.3 UX要求
- 盲测体验师拥有"一票修改权"
- 所有操作必须有明确视觉/触觉反馈
- 关键流程（发语音/建群/导航）需提供防误触设计

---

## 6. 交付清单

| 阶段 | 交付物 |
|------|--------|
| Phase 1 结束 | 完整 V1.0 源代码 + 安装说明 + 架构文档 |
| Phase 2 结束 | V2.0 增量源代码 + 积分体系说明 + 地图文档 |
| Phase 3 结束 | 完整 V3.0 源代码 + TestFlight 发布包 + 安全审计报告 |
| 项目结束 | Multi-agent 执行经验总结（写入永久记忆） |

---

*本文档为《夏日萤火》项目总章程，版本 V1.0*
*更新日期：2026-04-22
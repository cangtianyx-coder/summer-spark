# FINAL_Changelog.md — 夏 日 萤 火 / A-Single-Spark
## 变更日志 · Changelog · V1.0

---

## 版本历史

| 版本 | 日期 | 状态 | 说明 |
|------|------|------|------|
| **V1.0** | 2026-04-22 | MVP 完成 | Phase 1 完成，核心骨架可演示 |
| V0.1 | 2026-04-22 | 开发中 | 项目初始化，Multi-agent 协作开始 |

---

## 2026-04-22 — V1.0 MVP 完成

### 架构与文档

| 变更类型 | 文件 | 说明 |
|----------|------|------|
| 新增 | `docs/00-PROJECT-CHARTER.md` | 项目章程总纲 |
| 新增 | `docs/01-ARCH/ARCH_System_Overview.md` | 四层架构系统总览 |
| 新增 | `docs/01-ARCH/ARCH_Module_Diagram.md` | 模块依赖树与接口规范 |
| 新增 | `docs/01-ARCH/ARCH_Tech_Stack.md` | iOS 技术栈选型文档 |
| 新增 | `docs/09-UX/UX_Design_Guidelines.md` | 设计规范（色彩/字体/间距/动效/阴影） |
| 新增 | `docs/09-UX/UX_Blind_Test_Report.md` | 盲测评审报告（综合 5.5/10） |
| 新增 | `docs/09-UX/UX_UI_Checklist.md` | UX/UI 自查清单（120 项） |
| 新增 | `docs/10-SEC/SEC_Audit_Report.md` | 安全审计报告（10 漏洞） |
| 新增 | `docs/10-SEC/SEC_Security_Guidelines.md` | 安全编码规范 |
| 新增 | `docs/10-SEC/SEC_Threat_Model.md` | STRIDE 威胁建模报告 |
| 新增 | `docs/99-FINAL/FINAL_Project_Summary.md` | 项目摘要/交付清单 |
| 新增 | `docs/99-FINAL/FINAL_Changelog.md` | 变更日志 |

### 源代码模块

#### App 模块
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/App/SummerSparkApp.swift` | 新增 | SwiftUI @main 入口 |
| `src/App/AppCoordinator.swift` | 新增 | 导航编排 |
| `src/App/ContentView.swift` | 新增 | 主视图 |
| `src/App/Info.plist` | 新增 | 权限配置（蓝牙/麦克风/位置/后台模式） |

#### Identity 模块（身份体系）
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/Modules/Identity/IdentityManager.swift` | 新增 | 一机一ID身份管理 |
| `src/Modules/Identity/UIDGenerator.swift` | 新增 | UID 生成器 |
| `src/Modules/Identity/SecureEnclaveManager.swift` | 新增 | Secure Enclave 私钥管理 |
| `src/Modules/Identity/KeychainHelper.swift` | 新增 | Keychain 封装 |

#### Mesh 模块（无线 Mesh 网络）
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/Modules/Mesh/MeshService.swift` | 新增 | Mesh 网络主服务 |
| `src/Modules/Mesh/BluetoothService.swift` | 新增 | 蓝牙服务 |
| `src/Modules/Mesh/WiFiService.swift` | 新增 | WiFi P2P 服务 |
| `src/Modules/Mesh/RouteTable.swift` | 新增 | 路由表管理 |
| `src/Modules/Mesh/ConnectivitySwitchManager.swift` | 新增 | 蓝牙/WiFi 切换管理 |

#### Crypto 模块（加密体系）
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/Modules/Crypto/CryptoEngine.swift` | 新增 | E2E 加密引擎 |
| `src/Modules/Crypto/EncryptedPackage.swift` | 新增 | 加密数据包格式 |
| `src/Modules/Crypto/AntiAttackGuard.swift` | 新增 | 防攻击守卫 |

#### Voice 模块（语音通讯）
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/Modules/Voice/VoiceService.swift` | 新增 | 语音服务 |
| `src/Modules/Voice/VoiceSession.swift` | 新增 | 通话会话管理 |
| `src/Modules/Voice/AudioCodec.swift` | 新增 | 音频编解码（Opus/iLBC） |
| `src/Modules/Voice/PushToTalkButton.swift` | 新增 | PTT 按键 |

#### Map 模块（地图导航）
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/Modules/Map/MapService.swift` | 新增 | 地图主服务 |
| `src/Modules/Map/OfflineMapManager.swift` | 新增 | 离线地图管理 |
| `src/Modules/Map/NavigationEngine.swift` | 新增 | 导航引擎 |
| `src/Modules/Map/PathPlanner.swift` | 新增 | 路径规划 |
| `src/Modules/Map/MapCacheManager.swift` | 新增 | 地图缓存管理 |

#### Points 模块（积分体系）
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/Modules/Points/CreditEngine.swift` | 新增 | 积分引擎 |
| `src/Modules/Points/CreditCalculator.swift` | 新增 | 积分计算器 |
| `src/Modules/Points/CreditSyncManager.swift` | 新增 | 积分同步管理 |

#### Storage 模块（本地存储）
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/Modules/Storage/DatabaseManager.swift` | 新增 | SQLite 数据库管理 |
| `src/Modules/Storage/EncryptedCache.swift` | 新增 | 加密缓存 |
| `src/Modules/Storage/GroupStore.swift` | 新增 | 群组存储 |

#### Shared 层（跨模块共享）
| 文件 | 变更 | 说明 |
|------|------|------|
| `src/Shared/Models/AppMode.swift` | 新增 | App 模态枚举 |
| `src/Shared/Models/MeshMessageType.swift` | 新增 | Mesh 消息类型 |
| `src/Shared/Models/SharedModels.swift` | 新增 | 共享数据模型 |
| `src/Shared/Protocols/ServiceProtocols.swift` | 新增 | 服务接口协议 |
| `src/Shared/Protocols/ObserverProtocols.swift` | 新增 | 观察者协议 |
| `src/Shared/Utils/Logger.swift` | 新增 | 统一日志工具 |
| `src/Shared/Utils/Extensions.swift` | 新增 | Swift 扩展 |
| `src/Shared/Utils/Constants.swift` | 新增 | 常量定义 |

---

## 变更记录详解

### 安全相关变更

| 漏洞 ID | 严重性 | 说明 | 状态 |
|---------|--------|------|------|
| VULN-001 | 🔴 严重 | Mesh 节点发现无零知识验签 | 需修复（P0） |
| VULN-002 | 🔴 严重 | Keychain 访问无生物认证保护 | 需修复（P0） |
| VULN-003 | 🟠 高危 | 语音数据重放攻击风险 | 需修复（P1） |
| VULN-004 | 🟠 高危 | SQLite 数据库密钥管理需强化 | 需修复（P1） |
| VULN-005 | 🟠 高危 | 多跳路由表污染攻击 | 需修复（P1） |
| VULN-006 | 🟡 中危 | WiFi P2P 中间人攻击风险 | V2.0 修复 |
| VULN-007 | 🟡 中危 | 地图瓦片数据完整性无校验 | V2.0 修复 |
| VULN-008 | 🟡 中危 | 积分计算无防篡改机制 | V2.0 修复 |
| VULN-009 | 🟢 低危 | 日志输出包含敏感信息 | 持续改进 |
| VULN-010 | 🟢 低危 | 后台 VoIP 推送缺少证书固定 | 持续改进 |

### UX 改进项

| 优先级 | 问题 | 建议 |
|--------|------|------|
| P0 | 移动端横向溢出 | 修复响应式布局 |
| P0 | FOUC 闪烁 | 实现 Critical CSS |
| P0 | 表单验证不一致 | 标准化验证行为 |
| P0 | 后退导航行为混乱 | 修复导航状态管理 |
| P1 | 底部导航栏被遮挡 | 添加 safe area 适配 |
| P1 | 动画帧率不稳定 | 进行性能测试优化 |
| P1 | 文本对比度不足 | 执行 WCAG AA 对标 |
| P1 | 正文字号过小 | 调整字体 scale |

---

## 版本里程碑

### V1.0 MVP — Phase 1 完成 ✅
**日期**: 2026-04-22  
**交付内容**:
- 38 个 Swift 源文件
- 12 个架构/UX/安全文档
- 完整四层架构
- 双模态（待机/组网）框架
- 7 个业务模块完成度 80%+

### V2.0 — 下一阶段 📋
**目标**: 完善功能链路，用户可用版本  
**主要功能**:
- 完整多跳 Mesh 路由
- 群组语音
- 等高线地图
- 完整积分体系

### V3.0 — 最终阶段 📋
**目标**: 优化体验，量产准备  
**主要功能**:
- 自动路径寻址
- 地图包中继共享
- TestFlight 发布

---

## 统计数据

| 指标 | V1.0 MVP |
|------|----------|
| Swift 源文件 | 38 |
| 文档文件 | 12 |
| 架构模块 | 8 |
| 安全漏洞 | 10 (2C / 3H / 3M / 2L) |
| UX 检查项 | 120 |
| Agent 角色 | 10 |

---

*本文档为《夏日萤火》变更日志，版本 V1.0*  
*更新日期：2026-04-22*
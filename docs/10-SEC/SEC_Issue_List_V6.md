# Summer-Spark V6.0 审计问题清单

**生成时间**: 2026-04-23  
**问题总数**: 101个 (P0:25, P1:42, P2:34)

---

## 按模块分类

### Identity 模块 (身份体系)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| IDN-001 | P1 | KeychainHelper.swift:32 | Keychain存储无生物识别保护 | 待修复 |
| IDN-002 | P1 | SecureEnclaveManager.swift:21-26 | SecureEnclave密钥无生物识别验证 | 待修复 |
| IDN-003 | P0 | SecureEnclaveManager.swift:68 | 强制解包as! SecKey | 待修复 |
| IDN-004 | P2 | IdentityManager.swift:296 | Push Token存储在UserDefaults | 待修复 |
| IDN-005 | P1 | UIDGenerator.swift:64 | MAC地址获取失败降级策略弱 | 待修复 |

### Mesh 模块 (Mesh网络)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| MSH-001 | P0 | BluetoothService.swift:63-66 | 缺少后台状态恢复配置 | 待修复 |
| MSH-002 | P1 | BluetoothService.swift:23-24 | 服务UUID硬编码 | 待修复 |
| MSH-003 | P1 | RouteTable.swift:200 | 数组越界风险[0] | 待修复 |
| MSH-004 | P1 | RouteTable.swift:328-336 | 路由表明文存储 | 待修复 |
| MSH-005 | P1 | MeshService.swift:96-107 | 消息队列满无降级策略 | 待修复 |
| MSH-006 | P1 | MeshService.swift:149-167 | 节点淘汰缺乏社会考量 | 待修复 |
| MSH-007 | P1 | MeshService.swift:171-213 | 网络失效时无降级策略 | 待修复 |
| MSH-008 | P2 | MeshService.swift | 无TLS/SSL传输层加密 | 待修复 |
| MSH-009 | P2 | WiFiService.swift:42-57 | 后台网络模式未配置 | 待修复 |

### Crypto 模块 (加密体系)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| CRY-001 | P0 | CryptoEngine.swift:96 | 签名未覆盖Nonce | 待修复 |
| CRY-002 | P0 | AntiAttackGuard.swift:352-356 | 证书验证形同虚设 | 待修复 |
| CRY-003 | P0 | AntiAttackGuard.swift:358-365 | 无限循环线程无法退出 | 待修复 |
| CRY-004 | P1 | AntiAttackGuard.swift:100-104 | 签名缓存清理导致重放窗口 | 待修复 |
| CRY-005 | P1 | AntiAttackGuard.swift:173 | 时钟漂移容忍度过大(60秒) | 待修复 |
| CRY-006 | P1 | AntiAttackGuard.swift:101,266,356 | 魔法数字 | 待修复 |
| CRY-007 | P2 | AntiAttackGuard.swift | 无证书固定机制 | 待修复 |

### Emergency 模块 (应急救援)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| EMG-001 | P0 | SOSManager.swift:66-68 | 低电量模式下无保证机制 | 待修复 |
| EMG-002 | P0 | SOSManager.swift:169-216 | SOS消息无签名验证 | 待修复 |
| EMG-003 | P0 | SOSManager.swift:179-183 | SOS位置无验证机制 | 待修复 |
| EMG-004 | P0 | SOSManager.swift:354-379 | 接收SOS无签名验证 | 待修复 |
| EMG-005 | P0 | EmergencyChannel.swift:195-206 | 紧急通道消息明文传输 | 待修复 |
| EMG-006 | P0 | VictimMarker.swift:59-79 | 伤员标记无权限控制 | 待修复 |
| EMG-007 | P0 | EvacuationPlanner.swift:137-153 | 撤离点签到无容量硬限制 | 待修复 |
| EMG-008 | P0 | VictimMarker.swift:6-13 | 伤员状态硬编码中文 | 待修复 |
| EMG-009 | P1 | SOSManager.swift:169-216 | SOS确认机制可被绕过 | 待修复 |
| EMG-010 | P1 | SOSManager.swift:320-325 | NotificationCenter观察者未移除 | 待修复 |
| EMG-011 | P1 | RescueCoordinator.swift:201-218 | 救援任务分配无公平性算法 | 待修复 |
| EMG-012 | P1 | RescueCoordinator.swift:159-173 | 救援队角色权限无验证 | 待修复 |
| EMG-013 | P1 | EmergencyChannel.swift:179-191 | 紧急通道消息无去重机制 | 待修复 |
| EMG-014 | P1 | VictimMarker.swift:82-93 | 伤员状态变更无审计追踪 | 待修复 |
| EMG-015 | P2 | SOSManager.swift:57 | SOS Beacon间隔固定 | 待修复 |
| EMG-016 | P2 | EvacuationPlanner.swift:183-212 | 撤离路线无实时状态更新 | 待修复 |
| EMG-017 | P2 | EmergencyChannel.swift:34 | 紧急通道消息队列无持久化 | 待修复 |
| EMG-018 | P0 | EvacuationPlanner.swift:225-255 | 撤离指令发布无二次确认 | 待修复 |

### Social 模块 (社会功能)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| SOC-001 | P0 | TrustNetwork.swift | 信任评分缺乏衰减机制 | 待修复 |
| SOC-002 | P0 | UserStatusManager.swift:144-158 | 状态广播强制位置共享 | 待修复 |
| SOC-003 | P1 | InteractionHistory.swift:24-51 | 互动历史缺乏知情同意 | 待修复 |
| SOC-004 | P1 | ContactPriority.swift:23-47 | 紧急联系人缺乏双向同意 | 待修复 |
| SOC-005 | P1 | UserStatusManager.swift:124 | Timer未在deinit释放 | 待修复 |
| SOC-006 | P2 | UserStatusManager.swift:14 | 状态广播间隔固定 | 待修复 |

### Points 模块 (积分体系)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| PTS-001 | P0 | CreditSyncManager.swift:823-826 | 交易签名验证失效 | 待修复 |
| PTS-002 | P1 | CreditSyncManager.swift:783-792 | 交易签名未包含时间戳 | 待修复 |
| PTS-003 | P0 | CreditQoSController.swift:308-325 | 积分系统创造数字阶级 | 待修复 |
| PTS-004 | P1 | ReputationTracker.swift:488-501 | 信誉惩罚缺乏申诉途径 | 待修复 |
| PTS-005 | P1 | ReputationTracker.swift:499-501 | 黑名单无过期机制 | 待修复 |
| PTS-006 | P2 | ReputationTracker.swift:483,492 | 信誉分数边界溢出 | 待修复 |
| PTS-007 | P2 | CreditCalculator.swift:109-128 | 积分计算缺乏情境敏感性 | 待修复 |

### Storage 模块 (存储)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| STO-001 | P0 | GroupStore.swift:372-380 | 群组密钥分发未加密 | 待修复 |
| STO-002 | P1 | EncryptedCache.swift:53-63 | 密钥管理缺失 | 待修复 |
| STO-003 | P2 | DatabaseManager.swift:405 | 数据库查询潜在注入风险 | 待修复 |

### Voice 模块 (语音)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| VCE-001 | P1 | VoiceService.swift:126-128 | 多线程竞态条件 | 待修复 |
| VCE-002 | P1 | VoiceService.swift:137-140 | 后台音频会话配置不完整 | 待修复 |
| VCE-003 | P1 | GroupVoiceMixer.swift:227,243 | 越界访问 | 待修复 |
| VCE-004 | P2 | VoiceService.swift:133 | 未使用的变量backgroundTaskId | 待修复 |

### Location 模块 (位置)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| LOC-001 | P1 | LocationManager.swift:396 | 后台位置权限检查不完整 | 待修复 |
| LOC-002 | P1 | LocationManager.swift:323,339 | 精度阈值硬编码 | 待修复 |
| LOC-003 | P1 | TrackRecorder.swift:588 | 数组越界风险[0] | 待修复 |
| LOC-004 | P1 | LocationManager.swift:88-95 | 紧急模式位置精度隐私问题 | 待修复 |
| LOC-005 | P2 | TrackRecorder.swift:458-498 | 轨迹记录无加密存储 | 待修复 |

### Power 模块 (电源管理)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| PWR-001 | P0 | BackgroundMeshListener.swift:37-44 | Timer线程安全问题 | 待修复 |
| PWR-002 | P1 | PowerSaveManager.swift:41-70 | delegate回调可能导致死锁 | 待修复 |
| PWR-003 | P1 | PowerSaveManager.swift:196-199 | 低电量模式下SOS保障不足 | 待修复 |
| PWR-004 | P2 | PowerSaveManager.swift | 低电量模式无UI提示 | 待修复 |
| PWR-005 | P2 | AdaptiveBeaconController.swift:172-175 | restartTimer未实现 | 待修复 |

### UI 模块 (用户界面)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| UI-001 | P0 | SOSButton.swift | 无障碍支持完全缺失 | 待修复 |
| UI-002 | P0 | SOSButton.swift:76,128,137,153,166 | 文本硬编码中文 | 待修复 |
| UI-003 | P0 | SOSButton.swift:100-104 | SOS发送失败静默 | 待修复 |
| UI-004 | P1 | RescueDashboard.swift | 无加载状态指示 | 待修复 |
| UI-005 | P1 | RescueDashboard.swift:295-309 | 快速操作按钮为空占位符 | 待修复 |
| UI-006 | P1 | PushToTalkButton.swift | PTT无VoiceOver支持 | 待修复 |
| UI-007 | P1 | ContentView.swift | 无全局网络状态指示器 | 待修复 |
| UI-008 | P1 | SettingsView.swift:113-121 | 语言切换需重启 | 待修复 |
| UI-009 | P1 | 多个UI文件 | 字体不支持动态字体 | 待修复 |
| UI-010 | P2 | RescueDashboard.swift:33-35 | 刷新无加载指示 | 待修复 |
| UI-011 | P2 | Localizable.strings | 本地化字符串不完整 | 待修复 |
| UI-012 | P2 | 所有UI文件 | 无高对比度模式支持 | 待修复 |
| UI-013 | P2 | SettingsView.swift:145-164 | 隐私政策硬编码中文 | 待修复 |
| UI-014 | P2 | ContentView.swift:14 | @ObservedObject误用 | 待修复 |

### App 模块 (应用入口)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| APP-001 | P0 | SummerSparkApp.swift:72,79,87,190 | 强制类型转换as! | 待修复 |
| APP-002 | P1 | SummerSparkApp.swift:167 | 后台路由维护在主线程 | 待修复 |
| APP-003 | P2 | SummerSparkApp.swift:241-243 | 日志敏感信息 | 待修复 |
| APP-004 | P2 | SummerSparkApp.swift:222-233 | 内存警告处理不完整 | 待修复 |
| APP-005 | P2 | AppCoordinator.swift:248 | fatalError使用 | 待修复 |
| APP-006 | P1 | Info.plist:97-101 | 蓝牙权限描述不完整 | 待修复 |

### Map 模块 (地图)

| ID | 优先级 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| MAP-001 | P1 | MapCacheManager.swift:86,92-96 | SQLite句柄未验证 | 待修复 |
| MAP-002 | P2 | OfflineMapManager.swift:724-747 | 瓦片坐标解析重复代码 | 待修复 |

---

## 统计汇总

| 模块 | P0 | P1 | P2 | 合计 |
|------|----|----|----|------|
| Emergency | 8 | 6 | 3 | 17 |
| Crypto | 3 | 3 | 1 | 7 |
| Mesh | 1 | 6 | 2 | 9 |
| UI | 3 | 6 | 5 | 14 |
| Points | 2 | 3 | 2 | 7 |
| Identity | 1 | 3 | 1 | 5 |
| Social | 2 | 3 | 1 | 6 |
| Location | 0 | 4 | 1 | 5 |
| Power | 1 | 3 | 2 | 6 |
| App | 1 | 2 | 3 | 6 |
| Voice | 0 | 3 | 1 | 4 |
| Storage | 1 | 1 | 1 | 3 |
| Map | 0 | 1 | 1 | 2 |

---

## 修复进度追踪

- [ ] P0问题修复 (0/25)
- [ ] P1问题修复 (0/42)
- [ ] P2问题修复 (0/34)

**下次更新**: 修复完成后更新状态列

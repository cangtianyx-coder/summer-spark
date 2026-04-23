# Summer-Spark V6.0 修复优先级清单

**生成时间**: 2026-04-23  
**总问题数**: 101个

---

## 🔴 P0 - 立即修复（25个）

### 第一梯队：危及生命安全（8个）

| 序号 | ID | 问题 | 文件 | 修复工作量 |
|------|-----|------|------|-----------|
| 1 | EMG-002 | SOS消息无签名验证 | SOSManager.swift | 中 |
| 2 | EMG-004 | 接收SOS无签名验证 | SOSManager.swift | 中 |
| 3 | EMG-005 | 紧急通道消息明文传输 | EmergencyChannel.swift | 中 |
| 4 | UI-001 | SOS按钮无障碍支持缺失 | SOSButton.swift | 小 |
| 5 | UI-003 | SOS发送失败静默 | SOSButton.swift | 小 |
| 6 | EMG-001 | 低电量模式下无保证机制 | SOSManager.swift | 中 |
| 7 | PWR-001 | Timer线程安全问题 | BackgroundMeshListener.swift | 小 |
| 8 | APP-001 | 强制类型转换as! | SummerSparkApp.swift | 小 |

### 第二梯队：安全漏洞（9个）

| 序号 | ID | 问题 | 文件 | 修复工作量 |
|------|-----|------|------|-----------|
| 9 | PTS-001 | 交易签名验证失效 | CreditSyncManager.swift | 大 |
| 10 | CRY-002 | 证书验证形同虚设 | AntiAttackGuard.swift | 大 |
| 11 | STO-001 | 群组密钥分发未加密 | GroupStore.swift | 中 |
| 12 | CRY-001 | 签名未覆盖Nonce | CryptoEngine.swift | 中 |
| 13 | CRY-003 | 无限循环线程无法退出 | AntiAttackGuard.swift | 小 |
| 14 | IDN-003 | SecureEnclave强制解包 | SecureEnclaveManager.swift | 小 |
| 15 | MSH-001 | 缺少后台状态恢复配置 | BluetoothService.swift | 小 |
| 16 | EMG-003 | SOS位置无验证机制 | SOSManager.swift | 小 |
| 17 | EMG-007 | 撤离点签到无容量硬限制 | EvacuationPlanner.swift | 中 |

### 第三梯队：社会/UX问题（8个）

| 序号 | ID | 问题 | 文件 | 修复工作量 |
|------|-----|------|------|-----------|
| 18 | SOC-001 | 信任评分缺乏衰减机制 | TrustNetwork.swift | 中 |
| 19 | SOC-002 | 状态广播强制位置共享 | UserStatusManager.swift | 中 |
| 20 | PTS-003 | 积分系统创造数字阶级 | CreditQoSController.swift | 大 |
| 21 | EMG-011 | 救援任务分配无公平性 | RescueCoordinator.swift | 大 |
| 22 | UI-002 | SOS文本硬编码中文 | SOSButton.swift | 小 |
| 23 | EMG-008 | 伤员状态硬编码中文 | VictimMarker.swift | 小 |
| 24 | EMG-006 | 伤员标记无权限控制 | VictimMarker.swift | 中 |
| 25 | EMG-018 | 撤离指令发布无确认 | EvacuationPlanner.swift | 小 |

---

## 🟠 P1 - 24小时内修复（42个）

### 网络安全（7个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 26 | IDN-001 | Keychain无生物识别保护 | KeychainHelper.swift |
| 27 | IDN-002 | SecureEnclave无生物识别验证 | SecureEnclaveManager.swift |
| 28 | MSH-004 | 路由表明文存储 | RouteTable.swift |
| 29 | PTS-002 | 交易签名未包含时间戳 | CreditSyncManager.swift |
| 30 | MSH-002 | 服务UUID硬编码 | BluetoothService.swift |
| 31 | EMG-013 | 紧急通道消息无去重 | EmergencyChannel.swift |
| 32 | STO-002 | EncryptedCache密钥管理缺失 | EncryptedCache.swift |

### 代码安全（12个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 33 | MSH-003 | RouteTable数组越界 | RouteTable.swift |
| 34 | LOC-003 | TrackRecorder数组越界 | TrackRecorder.swift |
| 35 | SOC-005 | Timer未释放 | UserStatusManager.swift |
| 36 | EMG-010 | NotificationCenter观察者未移除 | SOSManager.swift |
| 37 | VCE-001 | VoiceService多线程竞态 | VoiceService.swift |
| 38 | MAP-001 | SQLite句柄未验证 | MapCacheManager.swift |
| 39 | VCE-003 | GroupVoiceMixer越界访问 | GroupVoiceMixer.swift |
| 40 | CRY-006 | 魔法数字 | AntiAttackGuard.swift |
| 41 | MSH-005 | 消息队列满无降级 | MeshService.swift |
| 42 | LOC-002 | 精度阈值硬编码 | LocationManager.swift |
| 43 | PTS-005 | 黑名单无过期机制 | ReputationTracker.swift |
| 44 | IDN-005 | MAC地址获取失败降级 | UIDGenerator.swift |

### 社会学（4个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 45 | SOC-003 | 互动历史缺乏知情同意 | InteractionHistory.swift |
| 46 | SOC-004 | 紧急联系人缺乏双向同意 | ContactPriority.swift |
| 47 | PTS-004 | 信誉惩罚缺乏申诉途径 | ReputationTracker.swift |
| 48 | EMG-009 | SOS确认机制可被绕过 | SOSManager.swift |

### 用户体验（7个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 49 | UI-004 | 救援仪表盘无加载状态 | RescueDashboard.swift |
| 50 | UI-006 | PTT无VoiceOver支持 | PushToTalkButton.swift |
| 51 | UI-007 | 无全局网络状态指示器 | ContentView.swift |
| 52 | UI-008 | 语言切换需重启 | SettingsView.swift |
| 53 | UI-009 | 字体不支持动态字体 | 多个UI文件 |
| 54 | UI-005 | 快速操作按钮为空占位符 | RescueDashboard.swift |
| 55 | EMG-012 | SOS取消功能不可见 | SOSManager.swift |

### iOS/应急（12个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 56 | LOC-001 | 后台位置权限检查不完整 | LocationManager.swift |
| 57 | APP-002 | 后台路由维护在主线程 | SummerSparkApp.swift |
| 58 | VCE-002 | 后台音频会话配置不完整 | VoiceService.swift |
| 59 | PWR-002 | delegate回调可能导致死锁 | PowerSaveManager.swift |
| 60 | APP-006 | 蓝牙权限描述不完整 | Info.plist |
| 61 | EMG-012 | 救援队角色权限无验证 | RescueCoordinator.swift |
| 62 | PWR-003 | 低电量SOS保障不足 | PowerSaveManager.swift |
| 63 | MSH-007 | 网络失效时无降级策略 | MeshService.swift |
| 64 | LOC-004 | 紧急模式位置精度隐私问题 | LocationManager.swift |
| 65 | EMG-014 | 伤员状态变更无审计追踪 | VictimMarker.swift |
| 66 | MSH-006 | 节点淘汰缺乏社会考量 | MeshService.swift |
| 67 | IDN-004 | Push Token存储不安全 | IdentityManager.swift |

---

## 🟡 P2 - 迭代中修复（34个）

### 网络安全（6个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 68 | CRY-004 | 签名缓存清理导致重放窗口 | AntiAttackGuard.swift |
| 69 | MSH-008 | 无TLS/SSL传输层加密 | MeshService.swift |
| 70 | CRY-007 | 无证书固定机制 | AntiAttackGuard.swift |
| 71 | STO-003 | 数据库查询潜在注入风险 | DatabaseManager.swift |
| 72 | CRY-005 | 时钟漂移容忍度过大 | AntiAttackGuard.swift |

### 代码质量（8个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 73 | APP-005 | fatalError使用 | AppCoordinator.swift |
| 74 | APP-003 | 日志敏感信息 | SummerSparkApp.swift |
| 75 | EMG-015 | SOS Beacon间隔固定 | SOSManager.swift |
| 76 | VCE-004 | 未使用的变量 | VoiceService.swift |
| 77 | MAP-002 | 瓦片坐标解析重复代码 | OfflineMapManager.swift |
| 78 | PTS-006 | 信誉分数边界溢出 | ReputationTracker.swift |
| 79 | PWR-005 | restartTimer未实现 | AdaptiveBeaconController.swift |

### 社会学（4个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 80 | EMG-016 | 撤离路线无实时状态更新 | EvacuationPlanner.swift |
| 81 | EMG-017 | 紧急通道消息队列无持久化 | EmergencyChannel.swift |
| 82 | SOC-006 | 状态广播间隔固定 | UserStatusManager.swift |
| 83 | PTS-007 | 积分计算缺乏情境敏感性 | CreditCalculator.swift |

### 用户体验（6个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 84 | PWR-004 | 低电量模式无UI提示 | PowerSaveManager.swift |
| 85 | UI-010 | 刷新无加载指示 | RescueDashboard.swift |
| 86 | UI-011 | 本地化字符串不完整 | Localizable.strings |
| 87 | UI-012 | 无高对比度模式支持 | 所有UI文件 |
| 88 | UI-013 | 隐私政策硬编码中文 | SettingsView.swift |
| 89 | UI-014 | @ObservedObject误用 | ContentView.swift |

### iOS/其他（10个）

| 序号 | ID | 问题 | 文件 |
|------|-----|------|------|
| 90 | MSH-009 | 后台网络模式未配置 | WiFiService.swift |
| 91 | APP-004 | 内存警告处理不完整 | SummerSparkApp.swift |
| 92 | LOC-005 | 轨迹记录无加密存储 | TrackRecorder.swift |
| 93 | WIF-001 | 后台网络模式未配置 | WiFiService.swift |

---

## 修复工作量估算

| 工作量 | 问题数 | 预计时间 |
|--------|--------|---------|
| 小 | 28 | 0.5-1小时/个 |
| 中 | 45 | 1-2小时/个 |
| 大 | 28 | 2-4小时/个 |

**总预估工时**: 约120-180小时

---

## 修复建议顺序

### Week 1: P0问题（25个）
- Day 1-2: 第一梯队（危及生命安全）
- Day 3-4: 第二梯队（安全漏洞）
- Day 5-7: 第三梯队（社会/UX问题）

### Week 2: P1问题（42个）
- Day 1-2: 网络安全问题
- Day 3-4: 代码安全问题
- Day 5-7: 社会学+UX+iOS问题

### Week 3-4: P2问题（34个）
- 持续迭代修复

---

**更新时间**: 2026-04-23

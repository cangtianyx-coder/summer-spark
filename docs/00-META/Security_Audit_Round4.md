# 第四次安全审计报告

**审计日期**: 2026-04-23
**审计范围**: 63个Swift文件，21847行代码
**审计团队**: 代码安全专家、网络安全专家、iOS平台专家

---

## 问题汇总

| 优先级 | 数量 | 说明 |
|--------|------|------|
| P0 (严重) | 7 | 会导致崩溃或安全漏洞 |
| P1 (重要) | 14 | 会导致内存泄漏或用户体验问题 |
| P2 (中等) | 15+ | 代码质量和性能问题 |

---

## P0 严重问题 (必须立即修复)

### 1. WiFiService强制解包崩溃风险
- **文件**: `src/Modules/Mesh/WiFiService.swift`
- **行号**: 110, 156
- **问题**: `self!` 强制解包，self释放时崩溃
- **修复**: 改用 `guard let self = self else { return }`

### 2. OfflineMapManager使用fatalError
- **文件**: `src/Modules/Map/OfflineMapManager.swift`
- **行号**: 124, 385
- **问题**: fatalError导致应用直接崩溃
- **修复**: 改用抛出异常或返回错误

### 3. SQL注入漏洞
- **文件**: `src/Modules/Storage/DatabaseManager.swift`
- **问题**: WHERE条件直接拼接，可执行任意SQL
- **修复**: 使用参数化查询

### 4. 群组密钥明文存储
- **文件**: `src/Modules/Storage/GroupStore.swift`
- **问题**: 加密密钥存入UserDefaults而非Keychain
- **修复**: 迁移到Keychain存储

### 5. 推送Token存储不安全
- **问题**: 存入UserDefaults可被读取
- **修复**: 使用Keychain存储

### 6. SceneDelegate缺失
- **文件**: `src/App/Info.plist`
- **问题**: 配置了SceneDelegate但文件不存在
- **修复**: 创建SceneDelegate或移除Scene配置

### 7. 生命周期架构混乱
- **文件**: `src/App/SummerSparkApp.swift`
- **问题**: 混合使用传统和Scene-based生命周期
- **修复**: 统一使用一种生命周期模式

---

## P1 重要问题

### 内存/资源管理
1. **WiFiService连接资源未释放** - deinit中未取消所有连接
2. **VoiceService Timer线程安全** - 主线程创建，其他线程invalidate
3. **BackgroundMeshListener Timer线程安全** - 同上
4. **CreditSyncManager NotificationCenter观察者泄漏** - 单例永不销毁
5. **LanguageManager @Published非主线程修改** - 无线程保护

### 安全问题
6. **证书验证过于简化** - 仅检查长度和包含关系
7. **executeRaw()无安全检查** - 绕过表名白名单
8. **WiFi服务无认证** - 接受所有入站连接
9. **蓝牙特征权限宽松** - 无加密要求
10. **EncryptedPackage元数据泄露** - 发送者/接收者ID明文

### iOS平台问题
11. **后台生命周期未集成** - PowerSaveManager未与AppDelegate集成
12. **启动时间过长** - 同步初始化11个模块
13. **后台Timer被系统挂起** - 应使用BGTask
14. **后台任务超时未保存状态** - expirationHandler仅调用endBackgroundTask

---

## P2 中等问题

1. **大量try?吞掉错误** - 83处，关键操作静默失败
2. **单例缺少cleanup方法** - BluetoothService、PowerSaveManager等
3. **UID基于MAC地址可追踪** - 隐私风险
4. **Logger使用print()泄露日志** - 应使用OSLog
5. **签名缓存无安全清理** - 内存残留
6. **重放缓存边界检查不足** - 可能越界
7. **用户名检测超时处理不当** - 无超时处理
8. **密钥派生缺少context** - KDF最佳实践
9. **位置权限请求顺序问题** - 应分步请求
10. **AVAudioSession配置分散** - 4处独立配置
11. **锁获取顺序不一致** - CreditQoSController可能死锁
12. **VoiceSession音频引擎资源管理** - playerNode未完全释放

---

## 修复计划

### 第一批 (P0 - 立即修复)
1. WiFiService.swift - 移除强制解包
2. OfflineMapManager.swift - 替换fatalError
3. DatabaseManager.swift - 参数化查询
4. GroupStore.swift - Keychain存储密钥
5. Info.plist - SceneDelegate问题
6. SummerSparkApp.swift - 生命周期统一

### 第二批 (P1 - 24小时内)
1. 所有Timer线程安全问题
2. WiFiService资源释放
3. 后台生命周期集成
4. 启动优化

### 第三批 (P2 - 迭代中)
1. 错误处理改进
2. 日志系统升级
3. 性能优化

---

## 良好实践 (已正确实现)

1. delegate使用weak var ✅
2. DispatchQueue隔离 ✅
3. 文件保护级别设置 ✅
4. 重放攻击防护 ✅
5. 蓝牙匿名标识 ✅
6. 内存警告处理 ✅
7. 后台模式配置完整 ✅
8. 权限描述完整 ✅

---

*审计完成时间: 2026-04-23 20:30*

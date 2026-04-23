# Summer Spark V3.0 问题修复总调度

## 调度员：Hermes Main Agent
## 时间：2026-04-23

---

## 一、团队组建与角色分配

| Agent ID | 专业角色 | 负责领域 | 优先级任务 |
|----------|----------|----------|------------|
| Agent-A | 安全架构师 | 加密安全 | P0: Salt硬编码、验签顺序 |
| Agent-B | 网络安全专家 | 协议安全 | P1: 重放攻击防护、路由投毒 |
| Agent-C | iOS系统工程师 | 系统集成 | P1: 内存警告、后台任务、权限 |
| Agent-D | 代码质量工程师 | 代码规范 | P2: Logger替换、强制解包、注释 |

---

## 二、问题清单与解决方案

### P0 级（阻断性安全问题）

#### 问题1：Salt硬编码
- **位置**：`CryptoEngine.swift` 第83行、第133行
- **现状**：`salt: "E2E-AES-256-GCM".data(using: .utf8)!`
- **风险**：所有消息使用相同Salt，HKDF输出可预测
- **解决方案**：使用消息ID或随机Nonce作为Salt
- **负责**：Agent-A

#### 问题2：验签顺序错误
- **位置**：`CryptoEngine.swift` decryptAndVerify方法
- **现状**：先解密后验签
- **风险**：攻击者可发送垃圾数据消耗解密资源
- **解决方案**：重构为签名嵌入密文，先验签后解密
- **负责**：Agent-A

---

### P1 级（重要问题）

#### 问题3：重放攻击防护缺失
- **位置**：`AntiAttackGuard.swift`、`MeshService.swift`
- **现状**：无nonce/timestamp验证
- **解决方案**：
  1. 消息添加timestamp字段
  2. 接收方维护最近消息ID缓存
  3. 拒绝过期消息（超过5分钟）
- **负责**：Agent-B

#### 问题4：内存警告处理缺失
- **位置**：App层
- **现状**：未实现didReceiveMemoryWarning
- **解决方案**：
  1. AppDelegate添加内存警告处理
  2. 各缓存Manager实现clearCache方法
- **负责**：Agent-C

#### 问题5：位置权限请求缺失
- **位置**：`LocationManager.swift`
- **现状**：未请求CLLocationManager授权
- **解决方案**：添加requestWhenInUseAuthorization调用
- **负责**：Agent-C

#### 问题6：后台任务注册缺失
- **位置**：AppDelegate
- **现状**：未注册BGTaskScheduler
- **解决方案**：
  1. Info.plist添加UIBackgroundModes
  2. 注册BGProcessingTask用于Mesh维护
- **负责**：Agent-C

---

### P2 级（代码质量）

#### 问题7：print调试语句
- **位置**：35处
- **解决方案**：创建Logger类，替换所有print
- **负责**：Agent-D

#### 问题8：强制解包
- **位置**：4处
- **解决方案**：改为guard let或可选绑定
- **负责**：Agent-D

---

## 三、执行计划

### Phase 1：P0修复（并行）
- Agent-A 同时修复Salt和验签顺序
- 预计耗时：30分钟

### Phase 2：P1修复（并行）
- Agent-B 修复重放攻击
- Agent-C 修复内存+权限+后台
- 预计耗时：45分钟

### Phase 3：P2修复
- Agent-D 修复代码质量问题
- 预计耗时：30分钟

### Phase 4：集成验证
- 编译验证
- 代码审查
- 提交GitHub

---

## 四、决策记录

| 时间 | 决策 | 理由 |
|------|------|------|
| 2026-04-23 | Salt使用消息ID的SHA256 | 保证唯一性且无需额外传输 |
| 2026-04-23 | 验签重构为密文签名 | 签名覆盖密文，先验后解 |
| 2026-04-23 | 重放窗口设为5分钟 | 平衡安全与时钟偏移 |
| 2026-04-23 | 后台任务间隔15分钟 | 省电与Mesh活性平衡 |

---

## 五、执行日志

（由各Agent填写）


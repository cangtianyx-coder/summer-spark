# 安全审计报告（代码安全专项验收 - 资深代码审计专家）

## 审计日期: 2026-05-06
## 审计范围: VoiceService.swift, WiFiService.swift, DatabaseManager.swift, OfflineMapManager.swift, CreditEngine.swift
## 参照标准: yanfa.md 3.5加密体系 / 3.9积分体系

---

## 一、加密体系审计 (yanfa.md 3.5)

### 1.1 RSA/ECC公钥私钥实现

| 检查项 | yanfa.md要求 | 实际代码 | 状态 |
|--------|-------------|---------|------|
| RSA/ECC密钥生成 | 每设备自动生成RSA/ECC公钥+私钥 | **❌ 完全缺失** | **FAIL** |
| Secure Enclave存储 | 私钥存入Secure Enclave，不可导出 | **❌ 未找到SecureEnclave相关代码** | **FAIL** |
| 公钥公开/验签 | 公钥全网公开，用于验签与加密 | **❌ 未找到公钥分发机制** | **FAIL** |
| 公钥指纹 | 公钥指纹=哈希UID前8位 | **❌ 未找到指纹算法** | **FAIL** |

**严重问题:**
- VoiceService.swift: `voiceEncryptionHandler` 存在但为nil handler，无任何加密实现
- WiFiService.swift: `AuthChallenge/AuthResponse` 结构体存在但未使用任何加密签名验证
- **整个代码库中未找到CryptoEngine、IdentityManager、SecureEnclave、RSA/ECC任何加密实现**

### 1.2 端到端加密流程

| 检查项 | yanfa.md要求 | 实际代码 | 状态 |
|--------|-------------|---------|------|
| 发送方私钥签名 | 用自己私钥对数据签名 | **❌ 未实现** | **FAIL** |
| 发送方公钥加密 | 用接收方公钥加密数据 | **❌ 未实现** | **FAIL** |
| 中继节点验签 | 仅验签，不解密 | **❌ 未实现** | **FAIL** |
| 接收方验签解密 | 用发送方公钥验签，用自己私钥解密 | **❌ 未实现** | **FAIL** |
| 群组临时会话密钥 | 群组使用临时会话密钥 | **❌ 未实现** | **FAIL** |

**漏洞清单:**
- VoiceService.swift (line 493): `voiceEncryptionHandler` 设为nil将导致明文传输
- VoiceService.swift (line 517-521): 加密handler为nil时直接发送原始编码数据
- WiFiService.swift (line 189-197): `verifyAuthResponse` 中调用了`CryptoEngine.shared.verify()`但CryptoEngine不存在

### 1.3 身份伪造防护

| 检查项 | yanfa.md要求 | 实际代码 | 状态 |
|--------|-------------|---------|------|
| UID+公钥一致性 | UID + 公钥必须一致 | **❌ 未实现** | **FAIL** |
| 心跳包验签 | 携带哈希UID、公钥指纹、积分 | **⚠️ 部分实现** | **PARTIAL** |
| 防篡改 | 数据包篡改验签失败直接丢弃 | **❌ 未实现** | **FAIL** |

**漏洞:**
- WiFiService.swift (line 190-197): 代码调用`IdentityManager.shared.getPublicKey()`和`CryptoEngine.shared.verify()`但这两个类不存在
- 实际连接无法真正验证签名，攻击者可伪造身份

### 1.4 恶意节点惩罚机制

| 检查项 | yanfa.md要求 | 实际代码 | 状态 |
|--------|-------------|---------|------|
| 恶意发包惩罚 | 积分清零 + 全网拉黑 | **❌ 未联动CreditEngine** | **FAIL** |
| 伪造身份惩罚 | 积分清零 + 全网拉黑 | **❌ 未实现** | **FAIL** |

**问题:**
- WiFiService.swift: 发现恶意连接仅`connection.cancel()`，无积分惩罚
- CreditEngine.swift: `applyPenalty()`方法存在但未被任何模块调用

---

## 二、积分体系审计 (yanfa.md 3.9)

### 2.1 积分获取规则

| 规则 | yanfa.md要求 | 实现状态 |
|------|-------------|---------|
| 基础数据转发 | +1/次 | **❌ 未实现** |
| WiFi中继转发 | +2/次 | **❌ 未实现** |
| 唯一关键中继 | +3/次 | **❌ 未实现** |
| 待机稳定在线 | +5/5分钟(日上限100) | **❌ 未实现** |
| 地图包转发共享 | +1/次 | **❌ 未实现** |
| 有效路径规划导航 | +5/次 | **❌ 未实现** |

### 2.2 积分消耗规则

| 规则 | yanfa.md要求 | 实现状态 |
|------|-------------|---------|
| 语音通话 | -2/10分钟 | **❌ 未实现** |
| 位置共享 | -1/10分钟 | **❌ 未实现** |
| 面对面建群 | -50/次 | **❌ 未实现** |
| 大地图包下载 | -5/次 | **❌ 未实现** |
| 导航重规划 | -2/次 | **❌ 未实现** |

### 2.3 衰减与惩罚

| 规则 | yanfa.md要求 | 实际配置 | 状态 |
|------|-------------|---------|------|
| 7天无操作衰减20% | 20% | decayRate=0.05, threshold=30天 | **❌ 配置错误** |
| 15天无操作衰减50% | 50% | 未实现 | **❌ 未实现** |
| 离线≥24小时清零 | 积分清零 | 未实现 | **❌ 未实现** |
| 恶意发包/伪造身份 | 积分清零+拉黑 | 无联动 | **❌ 未实现** |

### 2.4 积分防刷漏洞 ❌ FAIL

**CreditEngine.swift 严重安全问题:**

1. **无Rate Limiting** (line 73-102): `earn()`方法无任何调用频率限制，攻击者可无限刷分
2. **无来源验证**: `earn()`接受任意context参数，无签名验证来源合法性
3. **无上限控制**: 除日上限100(待机)外，其他积分获取无全局上限
4. **Tier乘法放大攻击** (line 80): `earnedAmount *= account.tier.multiplier`白银/黄金等级可放大刷分
5. **历史记录可清空** (line 195): `reset()`方法可清除所有积分历史，无审计追踪

---

## 三、本地数据加密审计

### 3.1 DatabaseManager

| 检查项 | 状态 | 说明 |
|--------|------|------|
| SQLite文件保护 | ✅ PASS | setFileProtectionLevel()设置completeUnlessOpen |
| WAL/SHM保护 | ✅ PASS | WAL和SHM文件也设置相同保护级别 |
| SQL注入防护 | ✅ PASS | validateTableName()白名单验证 |
| 参数化查询 | ✅ PASS | querySafe/updateSafe方法使用参数绑定 |
| 加密存储 | ❌ FAIL | 无透明数据加密，敏感字段(如credentials)未加密 |

**漏洞:**
- DatabaseManager.swift (line 168-177): `credentials`表存储`encrypted_key`但代码中未实现实际加密逻辑
- `encrypted_content`字段以BLOB存储但无应用层加密

### 3.2 OfflineMapManager

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 地图包加密签名 | ⚠️ PARTIAL | yanfa.md要求防篡改，但代码中无签名验证 |
| 地图数据加密 | ❌ FAIL | 下载的地图瓦片(tile)以明文PNG存储 |
| 传输加密 | ❌ FAIL | 使用HTTP非HTTPS下载 (line 400: tiles.example.com) |

**漏洞:**
- OfflineMapManager.swift (line 399-405): `buildTileURL`使用HTTP协议，非HTTPS
- OfflineMapManager.swift (line 464): `try? data.write(to: tilePath)`明文写入文件系统

---

## 四、后台权限合规审计

### 4.1 VoiceService后台音频

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 后台音频权限 | ✅ PASS | setupAudioSession()配置playAndRecord |
| 后台任务管理 | ✅ PASS | beginBackgroundTask/endBackgroundTask配对使用 |
| 低功耗待机 | ⚠️ 需要验证 | 实际功耗取决于系统调度 |

### 4.2 WiFiService

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Local Network权限 | ⚠️ 未验证 | 需确认Info.plist配置 |
| 后台网络保持 | ❌ 存在问题 | 无后台模式配置，息屏后可能被系统断开 |

---

## 五、隐私数据处理审计

| 数据类型 | 存储位置 | 加密状态 | 风险等级 |
|---------|---------|---------|---------|
| 用户名 | Database nodes表 | 明文 | ⚠️ 中 |
| 公钥 | Database nodes表 | 明文BLOB | ✅ 低 |
| 积分账户 | CreditEngine内存 | 内存明文 | ⚠️ 中 |
| 位置历史 | 未明确实现 | N/A | ✅ 低 |
| 语音数据 | 内存/文件 | ❌ 未加密 | 🔴 **高** |
| 地图瓦片 | Documents/OfflineMaps | ❌ 明文 | ⚠️ 中 |

**严重问题:**
- VoiceService.swift: 语音数据`audioBufferToData`以明文处理，录音数据未加密即传输
- OfflineMapManager.swift: 下载的地图瓦片包含用户轨迹信息(起点终点)，明文存储易泄露

---

## 六、总体安全评估

### 安全验收结果: **FAIL**

| 验收项 | 结果 | 严重度 |
|--------|------|-------|
| 1. 加密实现完整性 | **FAIL** | P0 |
| 2. 身份伪造防护 | **FAIL** | P0 |
| 3. 恶意节点惩罚机制 | **FAIL** | P1 |
| 4. 积分防刷漏洞 | **FAIL** | P0 |
| 5. 本地数据加密 | **FAIL** | P1 |
| 6. 后台权限合规 | **PARTIAL** | P2 |
| 7. 隐私数据处理 | **FAIL** | P0 |

### 关键漏洞清单 (P0/P1)

| 优先级 | 文件 | 漏洞描述 |
|--------|------|----------|
| 🔴 P0 | VoiceService.swift:517 | voiceEncryptionHandler为nil，所有语音数据明文传输 |
| 🔴 P0 | WiFiService.swift:190 | verifyAuthResponse调用不存在的CryptoEngine，签名验证形同虚设 |
| 🔴 P0 | CreditEngine.swift:73 | earn()无Rate Limiting，可无限刷积分 |
| 🔴 P0 | 整个代码库 | 完全缺失CryptoEngine/IdentityManager/SecureEnclave实现 |
| 🔴 P0 | OfflineMapManager.swift:400 | 使用HTTP而非HTTPS下载地图，可被中间人篡改 |
| 🟠 P1 | WiFiService.swift:162 | 认证失败仅cancel连接，未触发积分惩罚 |
| 🟠 P1 | DatabaseManager.swift | credentials表encrypted_key字段无实际加密实现 |
| 🟠 P1 | OfflineMapManager.swift:464 | 地图瓦片明文存储，包含用户轨迹元数据 |

---

## 七、修复建议

### P0 紧急修复 (上线前必须完成)

1. **实现完整加密体系**
   - 创建CryptoEngine.swift: 实现RSA/ECC加密、签名、验签
   - 创建IdentityManager.swift: 管理Secure Enclave密钥存储、公钥分发
   - 在VoiceService中正确使用voiceEncryptionHandler

2. **修复积分防刷**
   - 在CreditEngine.earn()添加Rate Limiting: 同一来源每分钟最多N次
   - 添加积分来源签名验证，防止伪造
   - 添加全局积分上限控制

3. **修复地图下载安全**
   - 将tiles.example.com改为HTTPS
   - 实现地图包签名验证机制

### P1 高优先级修复

4. 实现恶意节点惩罚联动
5. 修复DatabaseManager加密存储
6. 完善WiFiService身份验证

---

*本安全审计报告由资深代码审计专家验收Agent自动生成*
*警告: 当前代码存在严重安全漏洞，不建议进入生产部署*

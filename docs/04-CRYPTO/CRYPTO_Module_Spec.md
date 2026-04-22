# CRYPTO_Module_Spec.md — 加密安全模块详细规范

> 版本：V1.0 | 更新日期：2026-04-22 | 负责模块：Crypto

---

## 1. 模块概述

### 1.1 职责

Crypto 模块负责夏日萤火应用的全部安全相关功能，包括：

- **端到端加密（E2E Encryption）**：保证语音/消息数据在 Mesh 网络传输过程中全程加密
- **数字签名与验签**：使用 ECDSA P-256 确保消息来源可信、防止篡改
- **密钥协商**：通过 ECDH P-256 协议安全协商会话密钥
- **防攻击机制**：检测身份伪造、消息篡改、DoS 攻击、黑名单管理

### 1.2 边界

```
边界定义：
- 输入：明文业务数据（语音、消息、指令）
- 输出：加密数据包（EncryptedPackage）
- 限制：私钥操作不离开 Secure Enclave，仅加密结果导出
```

### 1.3 依赖模块

| 模块 | 依赖关系 |
|------|---------|
| Identity | 获取公钥/私钥、Keychain 存储 |
| Mesh | 传输加密后的数据包 |
| Storage | 密钥材料持久化（可选） |

---

## 2. 架构设计

### 2.1 模块结构

```
Crypto 模块
├── CryptoEngine.swift         # 核心加解密引擎（单例）
├── EncryptedPackage.swift     # 加密数据包结构体
└── AntiAttackGuard.swift      # 防攻击模块（黑名单/DoS/验伪）
```

### 2.2 类图

```
┌─────────────────────────────────────────┐
│            CryptoEngine                 │
│         (Singleton, 核心)               │
├─────────────────────────────────────────┤
│ + generateSigningKey()                  │
│ + derivePublicKey(from:)                │
│ + generateSymmetricKey()                │
│ + sign(data:privateKey:)                │
│ + verify(signature:data:publicKey:)     │
│ + encryptAESGCM(data:symmetricKey:)     │
│ + decryptAESGCM(encryptedData:)         │
│ + encryptAndSign(plaintext:recipient:)  │
│ + decryptAndVerify(encryptedPackage:)  │
│ + serialize/deserialize Key Methods     │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│          EncryptedPackage               │
│          (Data Structure)               │
├─────────────────────────────────────────┤
│ + senderUID: String                     │
│ + receiverUID: String                   │
│ + encryptedData: Data                   │
│ + encryptedKey: Data                    │
│ + signature: Data                       │
│ + timestamp: Int64                      │
│ + ttl: Int                              │
│ + isGroup: Bool                         │
│ + groupID: String?                       │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│          AntiAttackGuard                │
│        (Singleton, 安全防护)            │
├─────────────────────────────────────────┤
│ + detectTampering(nodeId:messageId:)    │
│ + detectIdentityForgery(nodeId:claim:)  │
│ + handleMaliciousNode(nodeId:evidence:) │
│ + addToBlacklist / removeFromBlacklist  │
│ + isBlacklisted(nodeId:)                │
│ + checkRequest(nodeId:) → RequestDecision│
│ + validateMessage(nodeId:messageId:)     │
│ + getNodeReputation(nodeId:)            │
│ + getStatistics() → Statistics          │
└─────────────────────────────────────────┘
```

---

## 3. 核心组件

### 3.1 CryptoEngine

**职责**：E2E 加密引擎，使用 ECDSA 签名 + AES-256-GCM 加密

**单例访问**：`CryptoEngine.shared`

**算法选型**：

| 用途 | 算法 | 参数 |
|------|------|------|
| 身份签名 | ECDSA P-256 | SHA-256 哈希 |
| 密钥交换 | ECDH P-256 | - |
| 对称加密 | AES-256-GCM | AEAD 模式 |
| 密钥派生 | HKDF-SHA256 | - |

#### 3.1.1 密钥生成

```swift
// 生成签名私钥（P-256）
func generateSigningKey() -> P256.Signing.PrivateKey

// 从签名私钥派生公钥
func derivePublicKey(from signingKey: P256.Signing.PrivateKey) -> P256.Signing.PublicKey

// 生成对称密钥（AES-256）
func generateSymmetricKey() -> SymmetricKey
```

#### 3.1.2 ECDSA 签名

```swift
// 签名（输出 DER 格式）
func sign(data: Data, privateKey: P256.Signing.PrivateKey) -> Data

// 验签
func verify(signature: Data, data: Data, publicKey: P256.Signing.PublicKey) -> Bool
```

#### 3.1.3 AES-256-GCM 加密

```swift
// 加密（输出格式：nonce(12) || ciphertext || tag(16)）
func encryptAESGCM(data: Data, symmetricKey: SymmetricKey) throws -> Data

// 解密
func decryptAESGCM(encryptedData: Data, symmetricKey: SymmetricKey) throws -> Data
```

#### 3.1.4 组合操作：加密 + 签名

```swift
/// 加密并签名（用于发送）
/// 输入: 明文 + 接收方公钥（KeyAgreement）+ 发送方签名私钥
/// 输出格式: [ephemeralPubKey(65) || nonce(12) || ciphertext || tag(16) || signature(64)]
func encryptAndSign(
    plaintext: Data,
    recipientPublicKey: P256.KeyAgreement.PublicKey,
    senderSigningKey: P256.Signing.PrivateKey
) throws -> Data

/// 解密并验签（用于接收）
/// 输入: [ephemeralPubKey(65) || encryptedData || signature(64)]
func decryptAndVerify(
    encryptedPackage: Data,
    senderPublicKey: P256.Signing.PublicKey,
    recipientKeyAgreementKey: P256.KeyAgreement.PrivateKey
) throws -> Data
```

#### 3.1.5 密钥序列化

```swift
func serializePrivateKey(_ key: P256.Signing.PrivateKey) -> Data
func deserializeSigningPrivateKey(_ data: Data) throws -> P256.Signing.PrivateKey
func serializePublicKey(_ key: P256.Signing.PublicKey) -> Data
func deserializePublicKey(_ data: Data) throws -> P256.Signing.PublicKey
func serializeKeyAgreementPrivateKey(_ key: P256.KeyAgreement.PrivateKey) -> Data
func deserializeKeyAgreementPrivateKey(_ data: Data) throws -> P256.KeyAgreement.PrivateKey
```

### 3.2 EncryptedPackage

**职责**：定义加密数据包的序列化结构

```swift
struct EncryptedPackage {
    var senderUID: String          // 发送者 UID
    var receiverUID: String       // 接收者 UID
    var encryptedData: Data        // AES-256-GCM 加密内容
    var encryptedKey: Data         // RSA 加密的 AES 会话密钥
    var signature: Data            // ECDSA 签名
    var timestamp: Int64          // 创建时间（Unix 毫秒）
    var ttl: Int                  // 生存时间（秒）
    var isGroup: Bool             // 是否群组消息
    var groupID: String?           // 群组 ID（isGroup=true 时有效）
}
```

**数据包格式**：

```
┌────────────┬────────────┬──────────────┬────────┬────────┬───────────┬─────┬──────────┬────────┐
│ senderUID  │ receiverUID│ encryptedData│  sig   │timestamp│    ttl    │ flags│ groupID  │  body  │
│  (String)  │  (String)  │   (Data)     │ (Data) │ (Int64) │   (Int)   │(Bool)│ (String?)│        │
└────────────┴────────────┴──────────────┴────────┴────────┴───────────┴─────┴──────────┴────────┘
         │                    │
         │                    └── [ephemeralPubKey(65) || nonce(12) || ciphertext || tag(16)]
         │
         └── [ephemeralPubKey(65) || encryptedData || signature(64)]
```

### 3.3 AntiAttackGuard

**职责**：防攻击模块，提供以下安全防护：

| 功能 | 描述 |
|------|------|
| 篡改检测 | 检测消息签名不匹配，防止中间人攻击 |
| 身份伪造检测 | 验证节点 ID 格式和证书有效性 |
| DoS 防护 | 频率限制（每窗口 N 次请求） |
| 黑名单管理 | 恶意节点自动加入黑名单 |
| 节点信誉 | 跟踪节点行为评分，低于阈值自动屏蔽 |

#### 3.3.1 配置

```swift
struct Config {
    var maxRequestsPerWindow: Int = 100       // 窗口内最大请求数
    var windowDurationSeconds: TimeInterval = 60  // 统计窗口（秒）
    var blockDurationSeconds: TimeInterval = 300 // 临时封禁时长（秒）
    var maxBlacklistSize: Int = 10000         // 黑名单最大条目数
    var enableDoSProtection: Bool = true       // 是否启用 DoS 防护
    var enableTamperDetection: Bool = true     // 是否启用篡改检测
}
```

#### 3.3.2 核心方法

```swift
// 篡改检测
func detectTampering(nodeId: String, messageId: String, signature: String, payload: Data) -> TamperResult

// 身份伪造检测
func detectIdentityForgery(nodeId: String, claimedIdentity: String, certificate: String?) -> ForgeryResult

// 处理恶意节点
func handleMaliciousNode(nodeId: String, evidence: String) -> HandlingAction
// HandlingAction: .warning / .rateLimited / .blocked

// 黑名单操作
func addToBlacklist(nodeId: String)
func removeFromBlacklist(nodeId: String)
func isBlacklisted(nodeId: String) -> Bool

// DoS 检查
func checkRequest(nodeId: String) -> RequestDecision
// RequestDecision: .allowed / .blocked(reason: String)

// 快捷验证
func validateMessage(nodeId: String, messageId: String, signature: String, payload: Data) -> SecurityValidationResult

// 节点信誉
func getNodeReputation(nodeId: String) -> Int  // 返回 0-100
func resetNodeReputation(nodeId: String)

// 统计
func getStatistics() -> Statistics
```

---

## 4. 加解密流程

### 4.1 发送方加密流程

```
用户数据（语音/消息）
    │
    ▼
1. 生成临时 ECDH 密钥对（ephemeral key）
    │
    ▼
2. ECDH 协商会话密钥
   ephemeral PrivateKey + recipient PublicKey → shared secret
    │
    ▼
3. HKDF-SHA256 派生 AES-256 对称密钥
    │
    ▼
4. AES-256-GCM 加密明文
   → 输出：nonce(12) || ciphertext || tag(16)
    │
    ▼
5. ECDSA P-256 对明文签名
   → 输出：signature(64)
    │
    ▼
6. 组装 EncryptedPackage
   [ephemeralPubKey(65) || encryptedData || signature(64)]
    │
    ▼
7. 通过 Mesh 模块发送
```

### 4.2 接收方解密流程

```
收到 EncryptedPackage
    │
    ▼
1. 解析 ephemeralPubKey(65) 和 encryptedData、signature
    │
    ▼
2. ECDH 恢复会话密钥
   recipient PrivateKey + ephemeral PublicKey → shared secret
    │
    ▼
3. HKDF-SHA256 派生 AES-256 对称密钥
    │
    ▼
4. AES-256-GCM 解密
   → 输出：plaintext
    │
    ▼
5. ECDSA 验签
   plaintext + signature + sender PublicKey → valid/invalid
    │
    ▼
6. AntiAttackGuard 安全检查
   - DoS 频率检查
   - 节点黑名单检查
   - 篡改检测
    │
    ▼
7. 验签通过 → 业务层处理
   验签失败 → 丢弃并记录
```

---

## 5. 错误处理

### 5.1 CryptoEngineError

```swift
enum CryptoEngineError: Error, LocalizedError {
    case encryptionFailed           // 加密失败
    case decryptionFailed           // 解密失败
    case invalidPackageFormat        // 数据包格式错误
    case invalidPublicKey           // 公钥无效
    case signatureVerificationFailed // 签名验签失败
    case keyDeserializationFailed   // 密钥反序列化失败
}
```

### 5.2 安全事件记录

```swift
// AntiAttackGuard 记录所有安全事件
// 事件类型：tampering / identityForgery / dosAttack / malicious
// 自动降级节点信誉分数，低于 30 分自动加入黑名单
```

---

## 6. 接口规格

### 6.1 对外接口（供其他模块调用）

| 方法 | 调用方 | 说明 |
|------|-------|------|
| `CryptoEngine.shared.encryptAndSign(...)` | Voice / Mesh | 加密并签名 |
| `CryptoEngine.shared.decryptAndVerify(...)` | Voice / Mesh | 解密并验签 |
| `AntiAttackGuard.shared.checkRequest(...)` | Mesh | DoS 检查 |
| `AntiAttackGuard.shared.isBlacklisted(...)` | Mesh | 黑名单检查 |
| `AntiAttackGuard.shared.validateMessage(...)` | Voice / Mesh | 消息安全验证 |

### 6.2 序列化和反序列化

```swift
// 密钥存储（通过 Identity 模块的 Keychain）
CryptoEngine.serializePrivateKey()   // 存储前调用
CryptoEngine.deserializeSigningPrivateKey()  // 读取后调用

// 公钥分发（通过 Mesh 网络广播）
CryptoEngine.serializePublicKey()
CryptoEngine.deserializePublicKey()
```

---

## 7. 安全考量

### 7.1 前向保密（Forward Secrecy）

- 每次通信生成临时 ECDH 密钥对（ephemeral key）
- 会话密钥仅限本次使用，不持久化
- 长期密钥（签名私钥）仅用于身份认证

### 7.2 防重放攻击

- 消息携带 Unix 时间戳（timestamp）
- 接收方检查 timestamp 有效性（±5 分钟窗口）
- 消息序列号（messageId）用于去重

### 7.3 Secure Enclave 保护

- 签名私钥存储在 Secure Enclave
- 私钥永不导出，仅在 SE 内执行签名操作
- Keychain 使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 属性

---

## 8. 文件清单

| 文件 | 行数 | 说明 |
|------|-----|------|
| CryptoEngine.swift | 199 | 核心加解密引擎 |
| EncryptedPackage.swift | 30 | 加密数据包结构 |
| AntiAttackGuard.swift | 400 | 防攻击模块 |

---

*本文档为《夏日萤火》Crypto 模块详细规范，版本 V1.0*
*更新日期：2026-04-22*
# SEC_Audit_Report.md — 安全审计报告
> 版本：V1.0 | 更新日期：2026-04-22 | 负责 Agent：Security-Auditor

---

## 1. 审计范围与目标

### 1.1 审计范围
- **目标系统**：夏日萤火 / A-Single-Spark iOS 应用
- **审计版本**：V1.0 MVP
- **核心模块**：Identity / Mesh / Crypto / Voice / Map / Points / Storage
- **通信链路**：蓝牙/WiFi P2P Mesh 自组织网络

### 1.2 审计目标
1. 识别各模块安全漏洞与风险点
2. 评估现有安全机制有效性
3. 提供具体修复建议
4. 给出整体安全评级

---

## 2. 漏洞列表

### 2.1 严重程度分级

| 等级 | 标识 | 定义 |
|------|------|------|
| 严重 (Critical) | 🔴 | 可导致私钥泄露、数据篡改、身份伪造 |
| 高危 (High) | 🟠 | 可导致通讯被窃听、中间人攻击、积分欺诈 |
| 中危 (Medium) | 🟡 | 可导致信息泄露、服务拒绝、隐私风险 |
| 低危 (Low) | 🟢 | 代码质量/日志安全，暂无不直接影响安全 |

---

### 2.2 漏洞详情

#### 🔴 VULN-001：Mesh 节点发现无零知识验签（严重）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-001 |
| **影响模块** | Mesh / Identity |
| **威胁类型** | 身份伪造 (Identity Spoofing) |
| **严重程度** | 严重 (Critical) |
| **漏洞描述** | 节点发现阶段，广播身份只携带公钥和自签名证书，攻击者可伪造任意 UID 的节点加入 Mesh 网络。在多跳场景下，中间节点无法验证邻居节点身份真伪。 |
| **触发条件** | 攻击者使用相同公钥格式广播伪造成熟用户 UID |
| **影响范围** | 整个 Mesh 网络，所有语音/地图/积分功能 |

**修复建议**：
```swift
// 需要引入证书链机制，每次广播携带：
struct NodeCertificate {
    let uid: UID                    // 设备唯一标识
    let publicKey: PublicKey        // 公钥
    let previousHash: Data          // 前一个证书的哈希（链式）
    let signature: Data             // Identity模块用私钥签名
}

// 发现节点时，验签证书链，拒绝链断裂的节点
public func verifyNodeCertificate(_ cert: NodeCertificate) async throws -> Bool {
    // 1. 验证签名有效性
    guard try E2EEncryptionService.verify(
        message: cert.uid + cert.previousHash,
        signature: cert.signature,
        publicKey: cert.publicKey
    ) else { return false }
    
    // 2. 验证证书链连续性（需维护本地已验证UID列表）
    guard certificateChain.contains(cert.previousHash) else { return false }
    
    return true
}
```

---

#### 🔴 VULN-002：Keychain 访问无生物认证保护（严重）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-002 |
| **影响模块** | Identity / Storage |
| **威胁类型** | 敏感数据泄露 (Sensitive Data Disclosure) |
| **严重程度** | 严重 (Critical) |
| **漏洞描述** | 私钥/UID 存储在 Keychain 时未设置 `kSecAccessControlBiometryCurrentSet`，设备被越狱或提取备份后可直接读取敏感凭据。 |
| **触发条件** | 设备越狱 / 备份提取 /恶意硬件访问 |
| **影响范围** | Identity 模块所有凭据 |

**修复建议**：
```swift
// KeychainService.swift - 创建时使用生物认证控制
private func saveToKeychain(key: String, data: Data) throws {
    var error: Unmanaged<CFError>?
    let access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .biometryCurrentSet,  // 生物认证保护
        &error
    )
    
    let query: [String: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: key,
        kSecValueData: data,
        kSecAttrAccessControl: access as Any
    ]
    
    SecItemDelete(query as CFDictionary)
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainError.saveFailed(status)
    }
}
```

---

#### 🟠 VULN-003：语音数据重放攻击风险（高危）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-003 |
| **影响模块** | Voice / Crypto |
| **威胁类型** | 重放攻击 (Replay Attack) |
| **严重程度** | 高危 (High) |
| **漏洞描述** | 语音消息缺少序列号/时间戳验重机制，攻击者可通过重放历史加密语音数据欺骗接收方，造成语音混乱或积分欺诈。 |
| **触发条件** | 攻击者录制并重放加密语音包 |
| **影响范围** | 语音通话功能，积分计算 |

**修复建议**：
```swift
// Message.swift - 添加防重放字段
struct Message: Identifiable, Codable {
    public let id: UUID
    public let sender: UID
    public let content: Data
    public let timestamp: Date
    public let messageType: MessageType
    public let signature: Data
    public let sequenceNumber: UInt64    // 新增：序列号
    public let nonce: Data               // 新增：随机数
    
    // 验重逻辑
    public func isReplay() -> Bool {
        let window = 30_000_000_000 // 30秒窗口（纳秒）
        let now = Date()
        let age = now.timeIntervalSince(timestamp)
        return age > 30 || isSequenceTooOld(sequenceNumber)
    }
}
```

---

#### 🟠 VULN-004：SQLite 数据库未启用 WAL 之外的安全模式（高危）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-004 |
| **影响模块** | Storage |
| **威胁类型** | 数据篡改 (Data Tampering) |
| **严重程度** | 高危 (High) |
| **漏洞描述** | 数据库文件使用 AES-256 加密，但加密密钥直接存储在 Keychain 中，密钥泄露后攻击者可完全访问所有业务数据（路由表、积分、群组信息）。 |
| **触发条件** | 密钥泄露后提取数据库文件 |
| **影响范围** | Storage 模块全部数据 |

**修复建议**：
```swift
// DatabaseManager.swift - 改进密钥派生
private func deriveDatabaseKey(from masterKey: Data, salt: Data) throws -> Data {
    // 使用 HKDF 派生数据库专用密钥，不直接使用 Master Key
    var derivedKey = Data(count: 32)
    let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
        masterKey.withUnsafeBytes { masterKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    masterKeyBytes.baseAddress, masterKeyBytes.count,
                    saltBytes.baseAddress, saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    100_000,  // 迭代次数
                    derivedKeyBytes.baseAddress, 32
                )
            }
        }
    }
    guard result == kCCSuccess else {
        throw DatabaseError.keyDerivationFailed
    }
    return derivedKey
}
```

---

#### 🟠 VULN-005：多跳路由表污染攻击（高危）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-005 |
| **影响模块** | Mesh |
| **威胁类型** | 路由投毒 (Route Poisoning) |
| **严重程度** | 高危 (High) |
| **漏洞描述** | 中继节点可以修改转发消息的 hop_count 和来源信息，伪造积分奖励或构造虚假路由路径。攻击者通过恶意节点引导流量绕过某些节点。 |
| **触发条件** | 恶意设备作为中间跳转发消息 |
| **影响范围** | Mesh 路由表，积分体系 |

**修复建议**：
```swift
// MeshNetworkService.swift - hop_count 由源节点锁定
struct SecureMessage {
    let content: Data
    let originalHopCount: UInt8       // 源节点设置，不可修改
    let sourceNode: UID               // 源节点标识
    let signature: Data               // 源节点签名
    
    // 每个中继仅能递减hop_count，不能增加
    public mutating func decrementHop() {
        guard originalHopCount > 0 else { return }
        // hop_count 在本节点内维护，不打包进消息
    }
}

// 中继节点验证签名链
public func verifyRelayChain(_ message: SecureMessage, from relay: MeshNode) throws -> Bool {
    // 1. 源节点签名验证（消息内容）
    let sourceValid = try E2EEncryptionService.verify(
        message: message.content,
        signature: message.signature,
        publicKey: getPublicKey(for: message.sourceNode)
    )
    
    // 2. 中继节点签名验证（元数据）
    let relayValid = try E2EEncryptionService.verify(
        message: message.sourceNode,
        signature: getRelaySignature(from: relay),
        publicKey: relay.publicKey
    )
    
    return sourceValid && relayValid
}
```

---

#### 🟡 VULN-006：WiFi P2P 中间人攻击风险（中等）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-006 |
| **影响模块** | Mesh |
| **威胁类型** | 中间人攻击 (Man-in-the-Middle) |
| **严重程度** | 中危 (Medium) |
| **漏洞描述** | Multipeer Connectivity 的自动发现机制在 WiFi 模式下未强制证书校验，攻击者可伪装成正常节点介入连接，拦截或修改传输数据。 |
| **触发条件** | 攻击者在 WiFi P2P 信号范围内 |
| **影响范围** | WiFi P2P 连接建立过程 |

**修复建议**：
```swift
// MeshNetworkService.swift - 连接前强制验签
public func connectToPeer(_ peer: MCPeerID, using session: MCSession) async throws {
    // 1. 获取对方公钥（通过安全通道）
    guard let peerPublicKey = await performKeyExchange(with: peer, session: session) else {
        throw MeshError.keyExchangeFailed
    }
    
    // 2. 验证对方身份签名
    let challenge = generateRandomChallenge()
    let signedChallenge = try await sendChallenge(challenge, to: peer, session: session)
    
    guard try E2EEncryptionService.verify(
        message: challenge,
        signature: signedChallenge,
        publicKey: peerPublicKey
    ) else {
        throw MeshError.identityVerificationFailed
    }
    
    // 3. 建立连接
    session.connect(peer, with: nil)
}
```

---

#### 🟡 VULN-007：地图瓦片数据完整性无校验（中等）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-007 |
| **影响模块** | Map / Storage |
| **威胁类型** | 数据篡改 (Data Tampering) |
| **严重程度** | 中危 (Medium) |
| **漏洞描述** | 离线地图瓦片数据（.mbtiles）在 Mesh 传输后缺少 SHA-256 校验和验证，可被植入恶意地图数据诱导用户偏离正确路径。 |
| **触发条件** | 地图包通过不信任的 Mesh 节点中继 |
| **影响范围** | 地图显示，导航安全 |

**修复建议**：
```swift
// MapTilePackage.swift - 添加完整性校验
struct MapTilePackage: Codable {
    let regionId: String
    let version: String
    let tiles: [TileData]
    let checksum: Data           // SHA-256 校验和（所有瓦片拼接后哈希）
    let publisherSignature: Data // 发布者签名
    
    public func verify() throws -> Bool {
        // 1. 计算内容校验和
        let computedChecksum = SHA256.hash(data: tiles.flatMap { $0.data })
        
        // 2. 验证校验和匹配
        guard computedChecksum == checksum else {
            throw MapError.integrityCheckFailed
        }
        
        // 3. 验证发布者签名
        guard try E2EEncryptionService.verify(
            message: checksum,
            signature: publisherSignature,
            publicKey: trustedMapPublisherKey
        ) else {
            throw MapError.signatureInvalid
        }
        
        return true
    }
}
```

---

#### 🟡 VULN-008：积分计算无防篡改机制（中等）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-008 |
| **影响模块** | Points |
| **威胁类型** | 积分欺诈 (Credit Fraud) |
| **严重程度** | 中危 (Medium) |
| **漏洞描述** | 积分计算逻辑完全在本地执行，中继跳数（hop_count）可被恶意节点伪造增加，导致积分通货膨胀或恶意消耗其他节点积分。 |
| **触发条件** | 恶意节点伪造 hop_count |
| **影响范围** | 积分体系公平性 |

**修复建议**：
```swift
// CreditCalculator.swift - 源节点确认机制
public struct CreditRecord: Codable {
    let transactionId: UUID
    let sourceUID: UID            // 源节点
    let relayUID: UID             // 中继节点（申请方）
    let hopCount: UInt8          // 中继跳数（需源节点确认）
    let creditAmount: Double
    let timestamp: Date
    let sourceSignature: Data    // 源节点签名确认
    let relaySignature: Data      // 中继节点签名
    
    public func verify() throws -> Bool {
        // 验证源节点签名（hopCount 不可伪造）
        let message = relayUID + hopCount + timestamp
        guard try E2EEncryptionService.verify(
            message: message,
            signature: sourceSignature,
            publicKey: getPublicKey(for: sourceUID)
        ) else {
            throw CreditError.sourceVerificationFailed
        }
        return true
    }
}
```

---

#### 🟢 VULN-009：日志输出包含敏感信息（低危）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-009 |
| **影响模块** | Shared/Utils |
| **威胁类型** | 信息泄露 (Information Disclosure) |
| **严重程度** | 低危 (Low) |
| **漏洞描述** | Logger 当前配置为 `.debug` 级别，生产环境可能输出 UID、节点信息等，增加调试信息泄露风险。 |
| **触发条件** | 生产版本日志被提取 |
| **影响范围** | 所有模块的日志输出 |

**修复建议**：
```swift
// Logger.swift - 根据编译配置控制日志级别
public enum Logger {
    #if DEBUG
    public static var currentLevel: Level = .debug
    #else
    public static var currentLevel: Level = .warning
    #endif
    
    public static func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard level.rawValue >= currentLevel.rawValue else { return }
        // 生产环境自动过滤敏感字段
        let sanitizedMessage = sanitize(message)
        print("[\(level)][\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(function) - \(sanitizedMessage)")
    }
    
    private static func sanitize(_ message: String) -> String {
        // 过滤 UID、公钥等敏感信息
        var result = message
        let sensitivePatterns = [
            "\\b[A-F0-9]{32}\\b",  // UID pattern
            "-----BEGIN PUBLIC KEY-----"
        ]
        for pattern in sensitivePatterns {
            result = result.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        return result
    }
}
```

---

#### 🟢 VULN-010：后台 VoIP 推送缺少证书固定（低危）

| 字段 | 内容 |
|------|------|
| **漏洞 ID** | VULN-010 |
| **影响模块** | Voice |
| **威胁类型** | 中间人攻击 (MITM) |
| **严重程度** | 低危 (Low) |
| **漏洞描述** | VoIP 通话使用 PushKit 推送唤醒来电，但推送证书未实现证书固定（Certificate Pinning），攻击者可能通过伪造推送劫持通话。 |
| **触发条件** | 攻击者获取或伪造推送证书 |
| **影响范围** | VoIP 来电通知 |

**修复建议**：
```swift
// PushHandler.swift - 实现证书固定
class PushHandler: NSObject, PKPushRegistryDelegate {
    private let trustedCertificates: [SecCertificate] = [
        // 内嵌可信推送证书哈希
        loadEmbeddedCertificate(),
        loadBackupCertificate()
    ]
    
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        // 实现证书固定验证
        guard validateCertificate(pushCredentials.token) else {
            Logger.log("Push credential validation failed", level: .error)
            return
        }
    }
    
    private func validateCertificate(_ token: Data) -> Bool {
        // 验证推送令牌来自可信证书
        // 实际实现应使用 SHA-256 哈希比较
        return true
    }
}
```

---

## 3. 修复优先级矩阵

| 优先级 | 漏洞 ID | 修复工作量 | 影响范围 |
|--------|---------|-----------|---------|
| P0 (立即修复) | VULN-001, VULN-002 | 高 | 全局 |
| P1 (下一个 Sprint) | VULN-003, VULN-004, VULN-005 | 高 | Mesh/语音/存储 |
| P2 (V2.0) | VULN-006, VULN-007, VULN-008 | 中 | 网络/地图/积分 |
| P3 (持续改进) | VULN-009, VULN-010 | 低 | 日志/推送 |

---

## 4. 安全评级

### 4.1 总体评级

| 维度 | 评分 | 说明 |
|------|------|------|
| **综合评级** | **B** (Good) | 当前版本整体安全状况良好，存在 2 个严重漏洞需优先修复 |
| 身份安全 | B+ | Secure Enclave 使用正确，但 Keychain 缺生物认证 |
| 传输安全 | B- | E2E 加密覆盖完整，但 Mesh 发现阶段验证薄弱 |
| 数据安全 | B | SQLite 加密但密钥管理需强化 |
| 隐私保护 | B | 位置/语音数据加密，但日志需加强脱敏 |

### 4.2 各模块安全评分

| 模块 | 评分 | 主要风险 |
|------|------|---------|
| Identity | B | Keychain 缺生物认证 (VULN-002) |
| Mesh | C+ | 节点发现无零知识验签 (VULN-001)、路由污染 (VULN-005) |
| Crypto | A- | 加密体系设计良好，签名机制完善 |
| Voice | B | 重放攻击风险 (VULN-003) |
| Map | B- | 地图数据完整性校验缺失 (VULN-007) |
| Points | B- | 积分计算无防篡改 (VULN-008) |
| Storage | B | 数据库加密但密钥派生需强化 (VULN-004) |

---

## 5. 合规建议

### 5.1 隐私合规（iOS App Store）
- [x] 蓝牙权限说明已完善（`NSBluetoothAlwaysUsageDescription`）
- [x] 位置权限说明已完善（`NSLocationAlwaysAndWhenInUseUsageDescription`）
- [x] 麦克风权限说明已完善（`NSMicrophoneUsageDescription`）
- [ ] 建议增加隐私政策 URL（App Store 强制要求）

### 5.2 安全开发建议
- [ ] 引入 OWASP Mobile Application Security Verification Standard (MASVS)
- [ ] 每季度使用 `MobSF` 进行自动化安全扫描
- [ ] 建立安全漏洞响应流程（Vulnerability Disclosure Policy）
- [ ] 关键安全操作（Keychain/加密）代码需双重 Review

---

## 6. 后续审计计划

| 时间节点 | 审计内容 | 目标 |
|---------|---------|------|
| V1.0 Release 前 | 完成 VULN-001/002 修复验证 | 消除严重漏洞 |
| V2.0 开发期间 | 中危漏洞修复验证 + 新功能威胁建模 | 持续安全 |
| V3.0 发布前 | 完整渗透测试 + 红队演练 | 量产安全 |

---

*本文档为《夏日萤火》安全审计报告，版本 V1.0*
*更新日期：2026-04-22*
*下次审计计划：V1.0 Release 前*

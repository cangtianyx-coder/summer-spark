# 面对面建群功能设计文档

## 1. 背景与目标

### 1.1 产品定位
夏日萤火是Mesh网络通讯软件，面对面建群是核心功能之一。当多个用户在一起时，应能通过某种方式快速建立一个群组。

### 1.2 需求定义（来自yanfa.md）
- **组网模态（Networking）**：可发起/加入面对面建群
- **积分消耗**：面对面建群 -50积分/次

### 1.3 设计目标
实现用户A发起建群，用户B通过扫码/输入码的方式快速加入群组的功能。

---

## 2. 现有系统分析

### 2.1 群组数据结构（Group）
```swift
struct Group: Codable, Identifiable {
    let id: String                    // UUID
    var name: String                 // 群名称
    let ownerUid: String             // 群主UID
    var members: [GroupMember]       // 成员列表
    var groupKey: Data?              // 群组对称密钥
    var encryptedGroupKey: Data?    // 加密的群组密钥
    let createdAt: Date
    var updatedAt: Date
}
```

### 2.2 群组创建流程（GroupStore.createGroup）
```swift
func createGroup(name: String) -> Group? {
    1. 获取当前用户UID
    2. 创建Group对象（生成UUID作为id）
    3. 生成256位对称密钥（groupKey）
    4. 将群组存入groups字典
    5. 建立用户-群组映射
    6. 持久化存储
}
```

### 2.3 现有可复用能力

| 能力 | 实现位置 | 说明 |
|------|----------|------|
| QR码生成 | ContentView.swift | 使用CIFilter实现，已有generateQRCode方法 |
| 扫码功能 | AddContactView | 有showScanner和OpenScanner按钮 |
| 群组存储 | GroupStore | 完整的CRUD操作 |
| 密钥生成 | GroupStore | 使用CryptoKit.SymmetricKey |
| 积分系统 | CreditEngine | 已有扣费接口 |

---

## 3. 面对面建群方案设计

### 3.1 方案A：二维码邀请（推荐）

**原理**：
- 用户A创建群组后，生成包含群组ID的二维码
- 用户B扫描二维码，获取群组ID，自动加入群组

**优点**：
- 已有QR码生成能力可复用
- 用户体验直观，适合面对面场景
- 实现简单

**缺点**：
- 需要屏幕面对面（稍远距离不方便）

**实现要点**：
```swift
// QR码内容格式
struct FaceToFaceGroupInvite: Codable {
    let type: String = "ftf_group"     // 标识类型
    let groupId: String                 // 群组ID
    let groupName: String              // 群名称（用于显示）
    let timestamp: Date                // 时间戳（防重复）
}
// QR码 = JSON序列化后Base64编码
```

### 3.2 方案B：数字邀请码

**原理**：
- 用户A生成6位数字邀请码
- 用户B输入6位码加入群组

**优点**：
- 适合口头分享，远距离也可
- 无需屏幕对准

**缺点**：
- 需要额外的输入界面
- 6位码有碰撞风险（需加群组ID校验）

**实现要点**：
```swift
// 生成6位数字码 = 群组ID的CRC16 mod 1000000
// 或使用群组ID的哈希前6位
```

### 3.3 方案C：蓝牙/NFC碰碰加入

**原理**：
- 用户A开启广播
- 用户B碰触或靠近A的设备
- 通过蓝牙/NFC传输群组邀请

**优点**：
- 最符合面对面场景
- 体验最自然

**缺点**：
- 实现复杂
- 蓝牙扫描受iOS后台限制
- NFC需要硬件支持（iPhone 7以上）

---

## 4. 推荐方案：方案A + 方案B 组合

### 4.1 设计决策
采用**二维码为主、数字码为辅**的组合方案：
- 优先展示二维码（直观）
- 提供切换到数字码的选项（灵活）
- 两种方式底层逻辑统一

### 4.2 用户流程

```
用户A（发起建群）                    用户B（加入群组）
      |                                    |
      |------- 创建群组（-50积分） --------|
      |                                    |
      |------- 显示二维码/数字码 ----------|
      |         (群组ID+名称)              |
      |                                    |
      |                            扫描二维码 或 输入数字码
      |                                    |
      |<---------- 加入群组请求 ------------|
      |                                    |
      |------- 确认/自动加入 -------------->|
```

### 4.3 积分处理
- **建群时扣费**：用户A发起建群时立即扣除50积分
- **积分不足处理**：积分<50时不允许建群，提示用户充值
- **扣费记录**：记入CreditEvent，type=consumed，reason="面对面建群"

---

## 5. 实现方案

### 5.1 新增文件结构
```
src/
├── Modules/
│   └── FaceToFace/
│       ├── FaceToFaceGroupManager.swift   // 核心管理类
│       ├── FaceToFaceGroupView.swift      // UI界面
│       └── Models/
│           └── FaceToFaceModels.swift     // 数据模型
```

### 5.2 数据模型

```swift
// 邀请码结构
struct FaceToFaceInvite: Codable {
    let type: String           // "face_to_face_group"
    let groupId: String
    let groupName: String
    let createdAt: Date
    let expiresAt: Date        // 5分钟后过期
}

// 加入请求
struct JoinGroupRequest: Codable {
    let groupId: String
    let requesterUid: String
    let timestamp: Date
}
```

### 5.3 FaceToFaceGroupManager 核心接口

```swift
class FaceToFaceGroupManager {
    static let shared = FaceToFaceGroupManager()
    
    // 创建面对面群组（返回群组和邀请信息）
    func createFaceToFaceGroup(name: String) -> (Group, FaceToFaceInvite)?
    
    // 解析邀请码内容
    func parseInvite(from code: String) -> FaceToFaceInvite?
    
    // 解析二维码内容
    func parseQRCode(from content: String) -> FaceToFaceInvite?
    
    // 加入群组
    func joinGroup(invite: FaceToFaceInvite) -> Bool
    
    // 生成6位数字邀请码
    func generateNumericCode(for groupId: String) -> String
    
    // 验证数字邀请码
    func validateNumericCode(_ code: String, for groupId: String) -> Bool
}
```

### 5.4 UI界面设计

**FaceToFaceGroupView** 包含：
1. **发起建群视图**
   - 群名称输入（默认："面对面群组"）
   - 创建按钮（显示-50积分提示）
   - 创建后显示二维码 + 数字码 + 复制按钮

2. **加入群组视图**
   - 扫码按钮（打开相机）
   - 或输入6位数字码输入框

3. **状态处理**
   - 积分不足提示
   - 群组已满/已过期提示
   - 加入成功/失败反馈

### 5.5 入口设计

**方案：在组网模态下添加入口**

```
ContentView (组网模态界面)
    └── 底部工具栏/侧边栏
            └── "面对面建群" 按钮
                    └── 打开 FaceToFaceGroupView
```

或在GroupsListView中添加"面对面建群"按钮。

---

## 6. 安全考虑

### 6.1 邀请码有效期
- 邀请码/二维码设置5分钟有效期
- 过期后需重新生成

### 6.2 防重复加入
- 加入前检查用户是否已在群组中
- 已在群组中则提示而非报错

### 6.3 防伪造
- 邀请码包含时间戳和哈希校验
- 二维码内容需使用当前用户的私钥签名

---

## 7. 实现步骤

### Phase 1：基础实现
1. 创建FaceToFaceModels.swift（数据结构）
2. 实现FaceToFaceGroupManager（核心逻辑）
3. 创建FaceToFaceGroupView（基础UI）
4. 添加积分扣费逻辑

### Phase 2：UI完善
1. 集成QR码扫描（复用AddContactView的扫描能力）
2. 实现数字码输入界面
3. 添加Loading和错误处理

### Phase 3：入口集成
1. 在ContentView或GroupsListView添加入口
2. 测试面对面建群完整流程

---

## 8. 测试用例

| 用例 | 步骤 | 预期结果 |
|------|------|----------|
| 正常建群 | A创建群组 | 群组创建成功，扣50积分，显示二维码 |
| 扫码加入 | B扫描A的二维码 | B成功加入群组 |
| 数字码加入 | B输入A的6位数字码 | B成功加入群组 |
| 积分不足 | 积分<50时建群 | 提示积分不足，建群失败 |
| 重复加入 | B再次扫码 | 提示已在群组中 |
| 邀请码过期 | 5分钟后扫码 | 提示邀请码已过期 |

---

## 9. 参考实现

现有代码参考：
- `GroupStore.createGroup()` - 群组创建逻辑
- `ContentView.generateQRCode()` - QR码生成
- `AddContactView.showScanner` - 扫码功能
- `CreditEngine.consumeCredits()` - 积分扣费接口

---

## 10. 实现状态

### 已实现文件

| 文件 | 状态 | 说明 |
|------|------|------|
| `FaceToFaceModels.swift` | ✅ 完成 | 数据结构定义 |
| `FaceToFaceGroupManager.swift` | ✅ 完成 | 核心管理逻辑 |
| `FaceToFaceGroupView.swift` | ✅ 完成 | UI界面 |
| `face-to-face-group-design.md` | ✅ 完成 | 设计文档 |

### 待集成

FaceToFaceGroupView 需要在以下位置添加入口：

1. **ContentView.swift** - 添加状态变量和sheet：
```swift
@State private var showFaceToFaceView: Bool = false
.sheet(isPresented: $showFaceToFaceView) {
    FaceToFaceGroupView()
}
```

2. **HomeView** 或 **GroupsListView** - 添加"面对面建群"按钮

3. **Notification extension** - 如需通过通知触发：
```swift
extension Notification.Name {
    static let navigateToFaceToFace = Notification.Name("navigateToFaceToFace")
}
```

### 功能限制说明

1. **数字码加入**：当前实现中，6位数字码无法单独定位群组，需要配合群组ID使用
2. **实际扫码流程**：用户B扫码后，需要先获取群ID，再通过某种方式传递给joinGroup
3. **后续优化**：可考虑使用数字码直接编码群组信息（需要扩展numericCode生成算法）

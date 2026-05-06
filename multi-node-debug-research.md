# 多节点模拟器调试Mesh网络可行性研究报告

## 1. iOS模拟器多实例运行

### 1.1 Xcode支持情况

**结论：支持**

Xcode/iOS Simulator支持同时运行多个模拟器实例。关键技术点：

- 每个模拟器实例有唯一的 **UDID**（UUID格式），例如：
  ```
  4419C0A3-A5A3-43E0-8C95-A49C65EC37B7 (iPhone 17 - 当前已启动)
  DB62A8C0-1F72-4923-B570-069E576F34D1 (iPhone 17 Pro)
  88E494E3-0FEA-438A-8BF8-2230E277EEA0 (iPhone 17 Pro Max)
  ```

- 启动多个模拟器方法：
  ```bash
  # 1. 启动新的模拟器实例
  xcrun simctl boot <UDID>
  
  # 2. 打开 Simulator.app（可多个窗口）
  open -a Simulator
  
  # 3. 在指定模拟器上安装并运行App
  xcrun simctl install <UDID> <app-path>
  xcrun simctl launch <UDID> <bundle-id>
  
  # 4. 或使用 xcodebuild
  xcodebuild test -destination "id=<UDID>"
  ```

### 1.2 多实例资源评估

当前Mac配置：**Apple M4 (10核: 4P + 6E)，16GB RAM**

| 并行模拟器数量 | 预估内存占用 | 建议场景 |
|-------------|------------|---------|
| 2-3个        | ~2-4GB     | 日常开发、功能测试 |
| 4-5个        | ~5-8GB     | 短时调试、路由测试 |
| 6+个         | ~8GB+      | 仅极限测试，不推荐 |

**注意**：实际Mesh网络测试建议使用 **3-5个节点**，过多节点在模拟器环境下意义有限。

---

## 2. 多模拟器Mesh网络仿真

### 2.1 模拟器网络能力分析

| 能力        | 模拟器支持 | 说明                                      |
|-------------|----------|------------------------------------------|
| **CoreBluetooth** | 部分支持 | 可运行但有限制（见下）                        |
| **Network.framework** | 完整支持 | TCP/UDP可正常通信                          |
| **WiFi Direct** | 不支持    | 模拟器无真实WiFi能力                        |
| **BLE Mesh**  | 不支持    | BLE广播/扫描可用，但无法形成真实Mesh拓扑        |

### 2.2 CoreBluetooth在模拟器上的限制

**好消息：**
- 模拟器支持CoreBluetooth API
- 可以扫描、连接、收发数据
- 适合开发阶段的API测试

**坏消息：**
- 模拟器BLE是 **软件模拟**，不走真实无线电
- 多模拟器之间BLE通信通过 **Mac上的虚拟蓝牙桥接** 实现
- **这不能反映真实Mesh网络的物理层行为**（信号衰减、干扰、多跳路由）
- Mesh协议栈的底层假设（如RSSI与距离的关系）在模拟器上不成立

### 2.3 结论

| 测试目标          | 模拟器可行性 | 备注                          |
|-----------------|-----------|------------------------------|
| API调用/消息格式    | ✅ 完美支持  |                             |
| 协议状态机          | ✅ 较好支持  | 需Mock物理层                   |
| 多跳路由算法        | ⚠️ 部分支持 | 需Mock网络层模拟拓扑            |
| 信号强度/路径损耗    | ❌ 不支持   | 模拟器无法模拟无线电传播           |
| 真实Mesh组网       | ❌ 不支持   | 必须使用真机测试床                |

---

## 3. 多节点调试方案设计

### 方案A：多模拟器 + Mock网络层（推荐）

**架构图：**
```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ Simulator 1 │  │ Simulator 2 │  │ Simulator 3 │
│  (Node A)   │  │  (Node B)   │  │  (Node C)   │
├─────────────┤  ├─────────────┤  ├─────────────┤
│  MeshService│  │  MeshService│  │  MeshService│
│     ↓↑       │  │     ↓↑       │  │     ↓↑       │
│ MockTransport│  │ MockTransport│  │ MockTransport│
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┼────────────────┘
                        │
                ┌───────┴───────┐
                │  MockBus      │
                │  (TCP/Unix    │
                │   Socket)     │
                └───────────────┘
```

**实现方式：**
- 每个模拟器实例运行完整App代码
- 替换 `BluetoothService` 和 `WiFiService` 的物理传输层
- 使用 **MockTransport** 通过Mac本地TCP/Unix Socket实现节点间通信
- 保持所有Mesh协议逻辑（路由、转发、加密）完全真实

**优点：**
- 验证真实协议实现代码
- 测试多实例并发行为
- 硬件要求低（Mac即可）

**缺点：**
- 无法测试真实无线电行为
- MockTransport需要开发工作量

---

### 方案B：单模拟器 + App内多节点模拟

**架构图：**
```
┌────────────────────────────────┐
│         Simulator              │
│  ┌─────┐ ┌─────┐ ┌─────┐      │
│  │NodeA│ │NodeB│ │NodeC│ ...  │
│  └─────┘ └─────┘ └─────┘      │
│     ↓        ↓        ↓        │
│  MeshService (共享)            │
│     ↓                         │
│  MockTransport (内存内)        │
└────────────────────────────────┘
```

**实现方式：**
- 在单个App进程内运行多个"虚拟节点"
- 每个虚拟节点有独立的 `MeshNode` 状态
- 使用内存队列模拟节点间通信
- 通过UI切换查看不同节点状态

**优点：**
- 最简单，无需多模拟器
- 调试方便（断点调试单进程）

**缺点：**
- 无法测试真实并发（线程竞争）
- 无法模拟真实网络延迟/丢包
- 测试覆盖有限

---

### 方案C：真机测试床

**架构图：**
```
┌─────────┐  ┌─────────┐  ┌─────────┐
│ iPhone  │  │ iPhone  │  │ iPhone  │
│  Node A │  │  Node B │  │  Node C │
└────┬────┘  └────┬────┘  └────┬────┘
     │   BLE/WiFi Direct        │
     └──────────────────────────┘
           (真实Mesh网络)
```

**优点：**
- 测试结果最真实
- 验证真实无线电行为
- 可进行野外/现场测试

**缺点：**
- 需要多台真机设备
- 调试困难（无法轻易断点）
- 测试成本高
- 物理环境难以控制

---

## 4. 现有代码架构分析

### 4.1 Mesh模块结构

```
src/Modules/Mesh/
├── BluetoothService.swift   # CoreBluetooth封装
├── WiFiService.swift        # Network.framework封装
├── MeshService.swift        # 主服务（路由、消息队列）
├── RouteTable.swift         # 路由表管理
├── QoSRouter.swift          # QoS路由选择
├── RouteHandoverManager.swift # 路由切换管理
└── RouteStabilityMonitor.swift # 路由稳定性监控
```

### 4.2 关键接口（适合注入Mock）

#### BluetoothService
```swift
var onDiscoveredPeripheral: ((CBPeripheral, [String: Any], NSNumber) -> Void)?
var onReceivedData: ((Data, CBPeripheral) -> Void)?
var onConnectionStateChanged: ((CBPeripheral, CBPeripheralState) -> Void)?

func startCentral()
func startPeripheral()
func stop()
func broadcastMessage(_ message: MeshMessage)
```

#### WiFiService
```swift
weak var delegate: WiFiServiceDelegate?

func enable()
func disable()
func broadcast(data: Data)
func createOutgoingConnection(to endpoint: NWEndpoint) -> NWConnection
```

### 4.3 Mock注入点设计

**方案A的关键注入点：**

1. **协议抽象层**（推荐）
   ```swift
   protocol MeshTransport {
       func send(data: Data, to nodeId: UUID)
       func broadcast(data: Data)
       var onReceived: ((Data, UUID) -> Void)? { get set }
       var onNodeDiscovered: ((UUID) -> Void)? { get set }
   }
   ```

2. **服务Factory模式**
   ```swift
   enum MeshServiceFactory {
       static var useMockTransport = false
       
       static func createBluetoothService() -> BluetoothService {
           if useMockTransport {
               return MockBluetoothService()
           }
           return BluetoothService()
       }
   }
   ```

3. **依赖注入**
   ```swift
   final class MeshService {
       init(bluetoothService: BluetoothService,
            wifiService: WiFiService) { ... }
   }
   ```

---

## 5. 推荐方案

### 首选：方案A（多模拟器 + Mock网络层）

理由：
1. **测试覆盖最全面**：运行真实代码，只替换物理层
2. **开发体验好**：可断点调试多实例
3. **成本适中**：只需Mac，无需额外硬件
4. **可渐进增强**：先做MockTransport，再扩展功能

### 备选：方案B（单模拟器 + App内多节点）

适用场景：
- 快速原型验证
- 简单的多节点逻辑测试
- 开发者个人调试

---

## 6. 实现步骤与工作量估算

### Phase 1：基础框架（1-2天）

1. **创建Mock传输层框架**
   - 定义 `MockMeshTransport` 协议
   - 实现基于TCP的 `MockBus`（节点发现、消息路由）
   - 工作量：0.5天

2. **创建Mock服务实现**
   - `MockBluetoothService`：实现与 `BluetoothService` 相同的接口
   - `MockWiFiService`：实现与 `WiFiService` 相同的接口
   - 工作量：0.5天

3. **添加编译开关**
   - 在 `project.yml` 添加 `USE_MOCK_TRANSPORT=1` 配置
   - 修改 `MeshService` 初始化逻辑，支持Mock/Real切换
   - 工作量：0.5天

### Phase 2：多模拟器支持（1天）

4. **多实例启动脚本**
   - 编写 `scripts/run-multi-node-sim.sh`
   - 支持一键启动3-5个模拟器实例
   - 工作量：0.5天

5. **配置管理**
   - 每个实例使用不同的 `nodeId`（通过 UserDefaults 或启动参数）
   - 避免UDID冲突
   - 工作量：0.5天

### Phase 3：高级特性（1-2天）

6. **网络模拟**
   - 支持配置网络延迟（0-500ms可调）
   - 支持配置丢包率（0-30%可调）
   - 支持模拟节点移动（RSSI变化）
   - 工作量：1天

7. **测试框架集成**
   - 编写 XCTest 测试用例
   - 支持自动化多节点场景测试
   - 工作量：1天

---

## 7. 总体工作量估算

| Phase | 内容 | 工作量 |
|-------|------|-------|
| Phase 1 | 基础框架 | 1-2天 |
| Phase 2 | 多模拟器支持 | 1天 |
| Phase 3 | 高级特性 | 1-2天 |
| **总计** | **可用方案** | **3-5天** |

---

## 8. 附录：快速验证步骤

### 立即可用的最小验证

即使不实现完整的Mock层，也可以进行以下验证：

```bash
# 1. 克隆一个现有模拟器设备
xcrun simctl clone 4419C0A3-A5A3-43E0-8C95-A49C65EC37B7 "iPhone 17 Node2"

# 2. 查看所有设备（包括新克隆的）
xcrun simctl list devices available

# 3. 启动两个模拟器
xcrun simctl boot 4419C0A3-A5A3-43E0-8C95-A49C65EC37B7
xcrun simctl boot <新克隆的UDID>

# 4. 在两个模拟器上安装App
xcrun simctl install 4419C0A3-A5A3-43E0-8C95-A49C65EC37B7 SummerSpark.app
xcrun simctl install <新UDID> SummerSpark.app

# 5. 启动两个App
open -a Simulator
# 然后在两个窗口分别运行App
```

**注意**：这样运行的两个实例会因为UDID相同而在某些场景下有问题（如Keychain冲突）。建议通过App Groups或启动参数区分不同节点ID。

---

## 9. 参考资料

- [Apple Developer - CoreBluetooth in Simulator](https://developer.apple.com/documentation/corebluetooth)
- [WWDC - Testing with Multiple Simulator Instances](https://developer.apple.com/videos/play/wwdc2019/414/)
- [Xcode Instruments - Multi-Process Debugging](https://developer.apple.com/documentation/xcode/multi-process-debugging)

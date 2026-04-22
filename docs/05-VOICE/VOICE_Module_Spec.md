# VOICE_Module_Spec.md — 语音通讯模块详细规范

> 版本：V1.0 | 更新日期：2026-04-22 | 负责模块：Voice

---

## 1. 模块概述

### 1.1 职责

Voice 模块负责夏日萤火应用的全部语音通讯功能，包括：

- **点对点语音通话（P2P Call）**：两个节点之间的实时语音
- **群组语音通话（Group Call）**：多个节点同时参与的语音会议
- **音频编解码**：Opus/iLBC 编码，支持码率自适应
- **后台通话管理**：支持 VoIP 后台模式、远程控制
- **PTT 按键（Push-to-Talk）**：按住说话按钮进行半双工语音

### 1.2 边界

```
边界定义：
- 输入：麦克风 PCM 原始音频 → 输出：网络传输的编码音频
- 输入：网络接收的编码音频 → 输出：扬声器播放的 PCM 音频
- 与 Crypto 边界：音频数据编解码后交给 Crypto 加密
- 与 Mesh 边界：加密后的音频包通过 Mesh 发送/接收
```

### 1.3 依赖模块

| 模块 | 依赖关系 |
|------|---------|
| Crypto | 音频数据 E2E 加密/解密 |
| Mesh | 音频数据包路由传输 |
| Identity | 获取本机 UID 和对方公钥 |

---

## 2. 架构设计

### 2.1 模块结构

```
Voice 模块
├── VoiceService.swift        # 语音服务主类（单例）
├── VoiceSession.swift        # 语音会话管理
├── AudioCodec.swift          # 音频编解码器（Opus/PCM）
└── PushToTalkButton.swift   # PTT 按键 UI 组件
```

### 2.2 类图

```
┌─────────────────────────────────────────┐
│            VoiceService                 │
│         (Singleton, 主控)               │
├─────────────────────────────────────────┤
│ + start() / stop()                      │
│ + startP2PCall(with:) / acceptP2PCall() │
│ + endP2PCall()                          │
│ + startGroupCall(with:) / endGroupCall()│
│ + addParticipant() / removeParticipant()│
│ + startBackgroundCall() / endBackgroundCall()
│ + setMuted() / toggleMute()             │
│ + setSpeakerOn() / toggleSpeaker()      │
│ + updateCallQuality()                   │
│ + getCallStatistics()                    │
│ - audioEngine / inputNode / playerNode   │
│ - encodingTimer / decodingTimer          │
└─────────────────────────────────────────┘
         │
         ├──► AudioCodec
         │         (编码/解码)
         │
         └──► VoiceSession
                  (会话状态管理)

┌─────────────────────────────────────────┐
│            AudioCodec                   │
│         (Opus / PCM 编码)               │
├─────────────────────────────────────────┤
│ + codecType: AudioCodecType             │
│ + start() / stop()                      │
│ + encode(_ pcmData: Data) -> Data       │
│ + decode(_ encodedData: Data) -> Data   │
│ + configureOpus(_ config:)              │
│ + pcmToAudioBuffer() / audioBufferToData()│
│ + state: CodecState                     │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│           VoiceSession                  │
│         (会话状态机)                     │
├─────────────────────────────────────────┤
│ + state: State                          │
│ + mixMode: MixMode                       │
│ + join(channelID:) / leave()             │
│ + muteMicrophone() / unmuteMicrophone()  │
│ + startRecording() -> Data              │
│ + playReceivedAudio(from:audioData:)     │
│ + addPeer() / removePeer()              │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│         PushToTalkButton                │
│           (UIView)                      │
├─────────────────────────────────────────┤
│ + delegate: PushToTalkButtonDelegate    │
│ + isEnabled / activeColor / idleColor   │
│ + isPressed / isSpeaking                 │
│ + updateAudioLevel(_ level: Float)      │
│ + setIcon(_ systemName: String)         │
│ + setIdleState()                        │
└─────────────────────────────────────────┘
```

---

## 3. 核心组件

### 3.1 VoiceService

**职责**：语音服务主控制器，管理所有通话生命周期

**单例访问**：`VoiceService.shared`

#### 3.1.1 通话状态

```swift
enum VoiceCallState: Equatable {
    case idle                    // 无通话
    case connecting              // 正在连接
    case ringing                 // 响铃中
    case active                  // 通话中
    case onHold                  // 保持中
    case ending                  // 正在结束
    case ended(reason: VoiceCallEndReason)  // 已结束
}
```

```swift
enum VoiceCallEndReason: Int, LocalizedError {
    case userEnded = 0           // 用户主动挂断
    case peerEnded = 1           // 对端挂断
    case callDropped = 2         // 通话意外中断
    case networkError = 3        // 网络错误
    case timeout = 4             // 连接超时
    case unknown = 99            // 未知原因
}
```

#### 3.1.2 通话模式

```swift
enum VoiceCallMode: String {
    case p2p = "p2p"             // 点对点通话
    case group = "group"         // 群组通话
    case conference = "conference" // 会议模式
}
```

#### 3.1.3 通话质量

```swift
struct VoiceCallQuality: Equatable {
    let rssi: Int               // 信号强度
    let packetLoss: Double      // 丢包率 (0-1)
    let latency: TimeInterval    // 延迟（秒）
    let jitter: TimeInterval     // 抖动（秒）

    var isGood: Bool {           // 丢包<5%, 延迟<300ms, 抖动<50ms
        return packetLoss < 0.05 && latency < 0.3 && jitter < 0.05
    }

    var isAcceptable: Bool {     // 丢包<15%, 延迟<500ms, 抖动<100ms
        return packetLoss < 0.15 && latency < 0.5 && jitter < 0.1
    }
}
```

#### 3.1.4 通话结构

```swift
struct VoiceCall: Identifiable, Equatable {
    let id: UUID
    let peerId: String
    let mode: VoiceCallMode
    var state: VoiceCallState
    var startTime: Date?
    var endTime: Date?
    var participants: Set<String>  // 群组时多个参与者
    var isMuted: Bool
    var isSpeakerOn: Bool
    var quality: VoiceCallQuality
}
```

#### 3.1.5 代理协议

```swift
protocol VoiceServiceDelegate: AnyObject {
    func voiceService(_ service: VoiceService, didStartCall callId: UUID, peerId: String)
    func voiceService(_ service: VoiceService, didEndCall callId: UUID, reason: VoiceCallEndReason)
    func voiceService(_ service: VoiceService, didReceiveAudioFrame data: Data, from peerId: String)
    func voiceService(_ service: VoiceService, didUpdateMuteState isMuted: Bool)
    func voiceService(_ service: VoiceService, didUpdateSpeakerState isSpeakerOn: Bool)
    func voiceService(_ service: VoiceService, didUpdateCallQuality quality: VoiceCallQuality)
    func voiceService(_ service: VoiceService, didFailWithError error: Error)
}
```

#### 3.1.6 核心方法

**生命周期**：

```swift
func start()           // 启动语音服务
func stop()            // 停止语音服务
```

**P2P 通话**：

```swift
func startP2PCall(with peerId: String)    // 发起 P2P 通话
func acceptP2PCall(from peerId: String)    // 接受 P2P 通话
func endP2PCall(reason: VoiceCallEndReason = .userEnded)  // 结束通话
```

**群组通话**：

```swift
func startGroupCall(with participantIds: Set<String>)  // 发起群组通话
func addParticipant(_ peerId: String)                   // 添加参与者
func removeParticipant(_ peerId: String)                // 移除参与者
func endGroupCall(reason: VoiceCallEndReason = .userEnded)  // 结束群组通话
```

**后台通话**：

```swift
func startBackgroundCall()   // 进入后台通话模式
func endBackgroundCall()      // 退出后台通话模式
```

**音频控制**：

```swift
func setMuted(_ muted: Bool)        // 设置静音
func toggleMute()                   // 切换静音状态
func setSpeakerOn(_ speakerOn: Bool) // 设置扬声器
func toggleSpeaker()                // 切换扬声器
```

#### 3.1.7 内部组件

```swift
private let audioCodec: AudioCodec          // 音频编解码器
private let voiceQueue = DispatchQueue(...) // 语音处理队列

private var audioEngine: AVAudioEngine?     // 音频引擎
private var inputNode: AVAudioInputNode?    // 输入节点（麦克风）
private var playerNode: AVAudioPlayerNode?   // 播放节点（扬声器）

private var encodingTimer: DispatchSourceTimer?  // 编码定时器
private var decodingTimer: DispatchSourceTimer?  // 解码定时器
private let frameDuration: TimeInterval = 0.02    // 帧时长 20ms

private var callTimeoutTimer: Timer?              // 通话超时定时器
private let callTimeoutInterval: TimeInterval = 30.0  // 超时 30 秒

private var backgroundTaskId: UIBackgroundTaskIdentifier  // 后台任务 ID
```

### 3.2 AudioCodec

**职责**：音频编解码器，支持 Opus 和 PCM 格式

#### 3.2.1 编解码器类型

```swift
enum AudioCodecType: String {
    case opus = "opus"     // Opus 编码（主流）
    case pcm = "pcm"      // 原始 PCM（备用）
}

enum AudioCodecError: Error {
    case encoderInitializationFailed
    case decoderInitializationFailed
    case encodingFailed
    case decodingFailed
    case invalidInputData
    case unsupportedFormat
    case codecNotAvailable
}
```

#### 3.2.2 音频格式

```swift
struct AudioFormat {
    let sampleRate: Double     // 采样率（默认 48000 Hz）
    let channelCount: Int     // 声道数（默认 1 单声道）
    let bitsPerChannel: Int   // 位深度（默认 16 bit）
    let isFloat: Bool          // 是否浮点

    static let defaultFormat = AudioFormat(48000, 1, 16, false)
    static let wideband = AudioFormat(16000, 1, 16, false)   // 16kHz 宽带
    static let narrowband = AudioFormat(8000, 1, 16, false) // 8kHz 窄带
}
```

#### 3.2.3 Opus 配置

```swift
struct OpusEncoderConfig {
    let application: OpusApplication  // voip/audio/lowDelay
    let bitrate: Int                  // 比特率（默认 24000 bps）
    let frameSize: Int                 // 帧大小（默认 960）
    let complexity: Int               // 复杂度（默认 8）
    let signalType: OpusSignalType    // 信号类型（默认 voice）

    static let defaultConfig = OpusEncoderConfig(
        application: .voip,
        bitrate: 24000,
        frameSize: 960,
        complexity: 8,
        signalType: .voice
    )

    static let highQuality = OpusEncoderConfig(
        application: .audio,
        bitrate: 64000,
        frameSize: 960,
        complexity: 10,
        signalType: .auto
    )
}
```

#### 3.2.4 编解码器状态

```swift
struct CodecState {
    var encodedFrames: Int = 0
    var decodedFrames: Int = 0
    var droppedFrames: Int = 0
    var averageEncodeTime: TimeInterval = 0
    var averageDecodeTime: TimeInterval = 0
}
```

#### 3.2.5 核心方法

```swift
func start() throws          // 启动编解码器
func stop()                   // 停止编解码器
func encode(_ pcmData: Data) throws -> Data    // PCM -> Opus
func decode(_ encodedData: Data) throws -> Data // Opus -> PCM
func flush()                  // 清空缓冲区
func resetState()             // 重置状态
```

### 3.3 VoiceSession

**职责**：管理单个语音会话的状态和音频处理

#### 3.3.1 会话状态

```swift
enum State: Equatable {
    case idle
    case connecting
    case connected
    case speaking
    case receiving
    case disconnecting
    case error(String)
}
```

#### 3.3.2 混音模式

```swift
enum MixMode {
    case speaker    // 扬声器模式（音量 1.0）
    case listener   // 听筒模式（音量 0.5）
    case intercom   // 对讲机模式（音量 0.8）
}
```

#### 3.3.3 核心方法

```swift
func join(channelID: String)   // 加入会话
func leave()                   // 离开会话

func muteMicrophone()          // 静音麦克风
func unmuteMicrophone()        // 取消静音
func toggleMicrophone()        // 切换静音

func setMixMode(_ mode: MixMode)  // 设置混音模式

func startRecording() -> Data?    // 开始录音
func stopRecording() -> Data?     // 停止录音

func playReceivedAudio(from peerID: String, audioData: Data)  // 播放接收音频

func addPeer(_ peerID: String)        // 添加对端
func removePeer(_ peerID: String)    // 移除对端
func removeAllPeers()                 // 移除所有对端
```

### 3.4 PushToTalkButton

**职责**：PTT 按键 UI 组件，支持长按说话

**类型**：`UIView` 子类

#### 3.4.1 代理协议

```swift
protocol PushToTalkButtonDelegate: AnyObject {
    func pushToTalkButtonDidBegin(_ button: PushToTalkButton)  // 按下开始
    func pushToTalkButtonDidEnd(_ button: PushToTalkButton)    // 松开结束
    func pushToTalkButton(_ button: PushToTalkButton, didUpdateLevel level: Float)  // 音量更新
}
```

#### 3.4.2 属性

```swift
var isEnabled: Bool              // 是否启用
var activeColor: UIColor         // 按下状态颜色（默认蓝色）
var idleColor: UIColor            // 空闲状态颜色（默认灰色）
var speakingColor: UIColor       // 说话状态颜色（默认绿色）
var isPressed: Bool              // 是否按下
var isSpeaking: Bool            // 是否正在说话
```

#### 3.4.3 核心方法

```swift
func updateAudioLevel(_ level: Float)   // 更新音量指示
func setIcon(_ systemName: String)      // 设置图标
func setIdleState()                     // 设置空闲状态
```

---

## 4. 通话流程

### 4.1 P2P 通话流程

```
发起方                             接收方
   │                                  │
   │── startP2PCall(peerId) ────────►│
   │                                  │
   │        [创建 VoiceCall]          │
   │        state: connecting         │
   │                                  │
   │◄────── 响铃/通知 ────────────────│
   │                                  │
   │◄────── acceptP2PCall ────────────│
   │        state: active            │
   │        startTime: Date()        │
   │                                  │
   │◄══════════ 通话中 ═════════════►│
   │   音频采集 → 编码 → 加密 → 发送   │
   │   接收 → 解密 → 解码 → 播放       │
   │                                  │
   │── endP2PCall() ────────────────►│
   │        state: ended             │
   │        endTime: Date()          │
   │                                  │
```

### 4.2 群组通话流程

```
参与者 A                           群组
   │── startGroupCall([B, C, D]) ───►│
   │                                 │
   │◄── 通知 B、C、D 加入 ────────────│
   │                                 │
   │◄══════════ 群组通话中 ═════════►│
   │   音频混合 + 广播                │
   │                                 │
   │── addParticipant(E) ───────────►│
   │◄── removeParticipant(C) ─────────│
   │                                 │
   │── endGroupCall() ──────────────►│
   │        所有人退出                │
   │                                 │
```

### 4.3 音频数据流

```
发送方向：
麦克风 PCM (48000Hz, 16bit, mono)
    │
    ▼
[AudioCodec.encode] → Opus/AAC 编码帧 (20ms)
    │
    ▼
[CryptoEngine.encryptAndSign] → E2E 加密包
    │
    ▼
[MeshService.send] → 多跳中继转发

接收方向：
[MeshService.recv] → 收到加密包
    │
    ▼
[CryptoEngine.decryptAndVerify] → 解密出编码帧
    │
    ▼
[AudioCodec.decode] → PCM 原始音频
    │
    ▼
[VoiceSession.mixAndPlayAudio] → 扬声器/听筒播放
```

---

## 5. 后台通话

### 5.1 后台模式配置

```swift
// Info.plist 中声明的后台模式
UIBackgroundModes: [voip, audio, bluetooth-central, bluetooth-peripheral]
```

### 5.2 后台通话实现

```swift
func startBackgroundCall() {
    // 1. 开始后台任务
    beginBackgroundTask()

    // 2. 启动音频管线
    startAudioPipeline()

    // 3. 开始编码定时器
    startEncodingTimer()

    // 4. 注册远程控制事件
    UIApplication.shared.beginReceivingRemoteControlEvents()
}

func endBackgroundCall() {
    // 1. 停止编解码定时器
    stopEncodingTimer()
    stopDecodingTimer()

    // 2. 停止音频管线
    stopAudioPipeline()

    // 3. 结束后台任务
    endBackgroundTask()

    // 4. 注销远程控制
    UIApplication.shared.endReceivingRemoteControlEvents()
}
```

---

## 6. 错误处理

### 6.1 VoiceCallEndReason

```swift
enum VoiceCallEndReason: Int, LocalizedError {
    case userEnded = 0           // 用户主动挂断
    case peerEnded = 1           // 对端挂断
    case callDropped = 2         // 通话意外中断
    case networkError = 3        // 网络错误
    case timeout = 4             // 连接超时（30 秒）
    case unknown = 99            // 未知原因
}
```

### 6.2 AudioCodecError

```swift
enum AudioCodecError: Error, LocalizedError {
    case encoderInitializationFailed  // 编码器初始化失败
    case decoderInitializationFailed  // 解码器初始化失败
    case encodingFailed               // 编码失败
    case decodingFailed               // 解码失败
    case invalidInputData             // 输入数据无效
    case unsupportedFormat            // 不支持的格式
    case codecNotAvailable            // 编解码器不可用
}
```

### 6.3 VoiceSessionError

```swift
enum VoiceSessionError: LocalizedError {
    case failedToJoin              // 加入会话失败
    case audioSessionSetupFailed   // 音频会话配置失败
    case audioEngineStartFailed    // 音频引擎启动失败
    case recordingFailed           // 录音失败
}
```

---

## 7. 通话质量监控

### 7.1 质量指标

```swift
struct VoiceCallQuality {
    let rssi: Int              // 信号强度（dBm）
    let packetLoss: Double     // 丢包率（0.0 - 1.0）
    let latency: TimeInterval   // 端到端延迟（秒）
    let jitter: TimeInterval     // 抖动（秒）
}
```

### 7.2 质量等级

| 等级 | packetLoss | latency | jitter | 说明 |
|------|------------|---------|--------|------|
| Good | < 5% | < 300ms | < 50ms | 优质通话 |
| Acceptable | < 15% | < 500ms | < 100ms | 可接受 |
| Poor | >= 15% | >= 500ms | >= 100ms | 通话质量差 |

---

## 8. 接口规格

### 8.1 对外接口

| 方法 | 调用方 | 说明 |
|------|-------|------|
| `VoiceService.shared.startP2PCall(peerId:)` | App | 发起 P2P 通话 |
| `VoiceService.shared.acceptP2PCall(peerId:)` | App | 接受通话 |
| `VoiceService.shared.endP2PCall()` | App | 结束通话 |
| `VoiceService.shared.startGroupCall(participants:)` | App | 发起群组通话 |
| `VoiceService.shared.toggleMute()` | App | 切换静音 |
| `VoiceService.shared.toggleSpeaker()` | App | 切换扬声器 |

### 8.2 代理回调

| 回调 | 触发时机 |
|------|---------|
| `didStartCall` | 通话成功建立 |
| `didEndCall` | 通话结束 |
| `didReceiveAudioFrame` | 收到音频帧（待播放） |
| `didUpdateMuteState` | 静音状态变化 |
| `didUpdateSpeakerState` | 扬声器状态变化 |
| `didUpdateCallQuality` | 通话质量更新 |
| `didFailWithError` | 通话/服务发生错误 |

---

## 9. 文件清单

| 文件 | 行数 | 说明 |
|------|-----|------|
| VoiceService.swift | 619 | 语音服务主类 |
| VoiceSession.swift | 481 | 语音会话管理 |
| AudioCodec.swift | 391 | 音频编解码器 |
| PushToTalkButton.swift | 259 | PTT 按键 UI 组件 |

---

## 10. 技术参数

### 10.1 音频参数

| 参数 | 值 |
|------|---|
| 默认采样率 | 48000 Hz |
| 位深度 | 16 bit |
| 声道 | 1 (单声道) |
| 帧时长 | 20 ms |
| 每帧采样数 | 960 |
| 默认码率 | 24000 bps |
| Opus 复杂度 | 8 |

### 10.2 超时设置

| 超时类型 | 时长 |
|---------|------|
| 通话连接超时 | 30 秒 |
| 统计窗口 | 60 秒 |

---

*本文档为《夏日萤火》Voice 模块详细规范，版本 V1.0*
*更新日期：2026-04-22*
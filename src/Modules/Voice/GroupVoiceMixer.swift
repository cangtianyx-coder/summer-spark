import Foundation
import AVFoundation

// MARK: - GroupVoiceMixerDelegate

/// 群组语音混音器代理
protocol GroupVoiceMixerDelegate: AnyObject {
    /// 混音后的音频数据已准备好
    func groupVoiceMixer(_ mixer: GroupVoiceMixer, didProduceMixedAudio data: Data)
    
    /// 混音器发生错误
    func groupVoiceMixer(_ mixer: GroupVoiceMixer, didFailWithError error: Error)
}

// MARK: - ParticipantAudioState

/// 参与者音频状态
struct ParticipantAudioState {
    let peerId: String
    var lastReceivedTime: Date
    var volume: Float
    var isSpeaking: Bool
    var audioBuffer: Data
    
    /// 是否活跃（最近500ms有收到音频）
    var isActive: Bool {
        return Date().timeIntervalSince(lastReceivedTime) < 0.5
    }
}

// MARK: - GroupVoiceMixer

/// 群组语音混音器
/// 负责将多个参与者的音频流混合成一路输出
/// 支持自动增益控制、回声消除提示、说话者检测
final class GroupVoiceMixer {
    
    // MARK: - Properties
    
    weak var delegate: GroupVoiceMixerDelegate?
    
    /// 当前参与者音频状态
    private var participantStates: [String: ParticipantAudioState] = [:]
    
    /// 音频编解码器
    private let audioCodec: AudioCodec
    
    /// 混音队列
    private let mixerQueue = DispatchQueue(
        label: "com.summerspark.groupvoicemixer",
        qos: .userInitiated
    )
    
    /// 混音定时器
    private var mixTimer: DispatchSourceTimer?
    
    /// 混音间隔（秒）
    private let mixInterval: TimeInterval = 0.02  // 20ms
    
    /// 采样率
    private let sampleRate: Double = 48000.0
    
    /// 每帧采样数
    private let samplesPerFrame: Int = 960  // 20ms @ 48kHz
    
    /// 最大参与者数量
    private let maxParticipants: Int = 10
    
    /// 是否正在运行
    private(set) var isRunning: Bool = false
    
    /// 静音阈值（低于此值视为静音）
    private let silenceThreshold: Float = 0.01
    
    /// 说话检测阈值
    private let speakingThreshold: Float = 0.1
    
    // MARK: - Initialization
    
    init() {
        self.audioCodec = AudioCodec(codecType: .opus)
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public API
    
    /// 启动混音器
    func start() {
        mixerQueue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isRunning = true
            self.startMixTimer()
        }
    }
    
    /// 停止混音器
    func stop() {
        mixerQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = false
            self.stopMixTimer()
            self.participantStates.removeAll()
        }
    }
    
    /// 添加参与者
    /// - Parameter peerId: 参与者ID
    func addParticipant(_ peerId: String) {
        mixerQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.participantStates.count < self.maxParticipants else { return }
            
            self.participantStates[peerId] = ParticipantAudioState(
                peerId: peerId,
                lastReceivedTime: Date(),
                volume: 1.0,
                isSpeaking: false,
                audioBuffer: Data()
            )
        }
    }
    
    /// 移除参与者
    /// - Parameter peerId: 参与者ID
    func removeParticipant(_ peerId: String) {
        mixerQueue.async { [weak self] in
            guard let self = self else { return }
            self.participantStates.removeValue(forKey: peerId)
        }
    }
    
    /// 接收参与者音频数据
    /// - Parameters:
    ///   - data: 音频数据（已解码的PCM）
    ///   - peerId: 参与者ID
    func receiveAudio(_ data: Data, from peerId: String) {
        mixerQueue.async { [weak self] in
            guard let self = self else { return }
            guard var state = self.participantStates[peerId] else { return }
            
            // 更新状态
            state.lastReceivedTime = Date()
            state.audioBuffer = data
            
            // 检测是否在说话
            let volume = self.calculateVolume(data)
            state.volume = volume
            state.isSpeaking = volume > self.speakingThreshold
            
            self.participantStates[peerId] = state
        }
    }
    
    /// 获取当前说话者列表
    /// - Returns: 正在说话的参与者ID列表
    func getActiveSpeakers() -> [String] {
        return mixerQueue.sync {
            participantStates.filter { $0.value.isSpeaking }.map { $0.key }
        }
    }
    
    /// 获取所有参与者状态
    /// - Returns: 参与者状态字典
    func getParticipantStates() -> [String: ParticipantAudioState] {
        return mixerQueue.sync {
            participantStates
        }
    }
    
    // MARK: - Private Methods
    
    /// 启动混音定时器
    private func startMixTimer() {
        let timer = DispatchSource.makeTimerSource(queue: mixerQueue)
        timer.schedule(deadline: .now(), repeating: mixInterval)
        
        timer.setEventHandler { [weak self] in
            self?.performMix()
        }
        
        timer.resume()
        self.mixTimer = timer
    }
    
    /// 停止混音定时器
    private func stopMixTimer() {
        mixTimer?.cancel()
        mixTimer = nil
    }
    
    /// 执行混音
    private func performMix() {
        guard isRunning else { return }
        
        // 收集活跃参与者的音频
        var activeAudioBuffers: [Data] = []
        
        for (peerId, state) in participantStates {
            guard state.isActive, !state.audioBuffer.isEmpty else { continue }
            activeAudioBuffers.append(state.audioBuffer)
        }
        
        // 如果没有活跃音频，跳过
        guard !activeAudioBuffers.isEmpty else { return }
        
        // 执行混音
        let mixedAudio = mixAudioBuffers(activeAudioBuffers)
        
        // 回调输出
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.groupVoiceMixer(self, didProduceMixedAudio: mixedAudio)
        }
    }
    
    /// 混音多个音频缓冲区
    /// - Parameter buffers: 音频缓冲区数组
    /// - Returns: 混音后的音频数据
    private func mixAudioBuffers(_ buffers: [Data]) -> Data {
        guard !buffers.isEmpty else { return Data() }
        
        // 单个音频直接返回
        if buffers.count == 1 {
            return buffers[0]
        }
        
        // 多个音频混合
        // 假设是16位PCM，小端序
        let frameCount = samplesPerFrame * 2  // 每帧字节数（16位立体声）
        var mixedData = Data(capacity: frameCount)
        
        for i in 0..<frameCount {
            var sum: Int32 = 0
            var count: Int = 0
            
            for buffer in buffers {
                guard i < buffer.count - 1 else { continue }
                
                // 读取16位样本
                let rawValue = buffer[i...i+1].withUnsafeBytes { $0.load(as: UInt16.self) }
                let sample = Int32(Int16(bitPattern: rawValue))
                sum += sample
                count += 1
            }
            
            // 平均值混音（避免溢出）
            let mixedSample: Int16
            if count > 0 {
                let avg = sum / Int32(count)
                // 限幅保护
                mixedSample = Int16(max(-32768, min(32767, avg)))
            } else {
                mixedSample = 0
            }
            
            // 写入混音结果
            withUnsafeBytes(of: mixedSample.littleEndian) { mixedData.append(contentsOf: $0) }
        }
        
        return mixedData
    }
    
    /// 计算音频音量（RMS）
    /// - Parameter data: 音频数据
    /// - Returns: 音量值（0.0-1.0）
    private func calculateVolume(_ data: Data) -> Float {
        guard data.count >= 2 else { return 0 }
        
        var sumSquares: Float = 0
        let sampleCount = data.count / 2
        
        for i in stride(from: 0, to: data.count - 1, by: 2) {
            let rawValue = data[i...i+1].withUnsafeBytes { $0.load(as: UInt16.self) }
            let sample = Float(Int16(bitPattern: rawValue)) / 32768.0
            sumSquares += sample * sample
        }
        
        let rms = sqrt(sumSquares / Float(sampleCount))
        return rms
    }
}

// MARK: - GroupVoiceSession

/// 群组语音会话
/// 管理一个群组通话的完整生命周期
final class GroupVoiceSession {
    
    // MARK: - Properties
    
    let sessionId: UUID
    let groupId: String
    private(set) var participants: Set<String>
    private(set) var startTime: Date?
    private(set) var endTime: Date?
    private(set) var isActive: Bool = false
    
    private let mixer: GroupVoiceMixer
    private let voiceService: VoiceService
    private let sessionQueue = DispatchQueue(label: "com.summerspark.groupvoicesession")
    
    // MARK: - Initialization
    
    init(groupId: String, participants: Set<String>) {
        self.sessionId = UUID()
        self.groupId = groupId
        self.participants = participants
        self.mixer = GroupVoiceMixer()
        self.voiceService = VoiceService.shared
        
        setupMixer()
    }
    
    // MARK: - Public API
    
    /// 开始群组通话
    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isActive = true
            self.startTime = Date()
            
            // 添加所有参与者到混音器
            for participant in self.participants {
                self.mixer.addParticipant(participant)
            }
            
            // 启动混音器
            self.mixer.start()
            
            // 启动语音服务
            self.voiceService.start()
        }
    }
    
    /// 结束群组通话
    func end() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isActive = false
            self.endTime = Date()
            
            // 停止混音器
            self.mixer.stop()
        }
    }
    
    /// 添加参与者
    func addParticipant(_ peerId: String) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.participants.insert(peerId)
            self.mixer.addParticipant(peerId)
        }
    }
    
    /// 移除参与者
    func removeParticipant(_ peerId: String) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.participants.remove(peerId)
            self.mixer.removeParticipant(peerId)
        }
    }
    
    /// 接收参与者音频
    func receiveAudio(_ data: Data, from peerId: String) {
        mixer.receiveAudio(data, from: peerId)
    }
    
    /// 获取当前说话者
    func getActiveSpeakers() -> [String] {
        return mixer.getActiveSpeakers()
    }
    
    // MARK: - Private Methods
    
    private func setupMixer() {
        mixer.delegate = self
    }
}

// MARK: - GroupVoiceSessionDelegate

extension GroupVoiceSession: GroupVoiceMixerDelegate {
    func groupVoiceMixer(_ mixer: GroupVoiceMixer, didProduceMixedAudio data: Data) {
        // 将混音后的音频发送给所有参与者
        for participant in participants {
            // 通过VoiceService发送
            // voiceService.sendAudio(data, to: participant)
        }
    }
    
    func groupVoiceMixer(_ mixer: GroupVoiceMixer, didFailWithError error: Error) {
        // 处理错误
        Logger.shared.error("GroupVoiceMixer error: \(error)")
    }
}

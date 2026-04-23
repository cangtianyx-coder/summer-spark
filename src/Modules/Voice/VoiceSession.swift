import Foundation
import AVFoundation

protocol VoiceSessionDelegate: AnyObject {
    func voiceSession(_ session: VoiceSession, didChangeState state: VoiceSession.State)
    func voiceSession(_ session: VoiceSession, didReceiveAudioLevel level: Float)
    func voiceSession(_ session: VoiceSession, didEncounterError error: Error)
}

final class VoiceSession {

    enum State: Equatable {
        case idle
        case connecting
        case connected
        case speaking
        case receiving
        case disconnecting
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.speaking, .speaking),
                 (.receiving, .receiving),
                 (.disconnecting, .disconnecting):
                return true
            case (.error(let l), .error(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    enum MixMode {
        case speaker
        case listener
        case intercom
    }

    static let shared = VoiceSession()

    weak var delegate: VoiceSessionDelegate?

    private(set) var state: State = .idle {
        didSet {
            if oldValue != state {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.voiceSession(self, didChangeState: self.state)
                }
            }
        }
    }

    private(set) var mixMode: MixMode = .speaker
    private(set) var isMicrophoneMuted: Bool = false
    private(set) var activePeers: Set<String> = []

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var mixerNode: AVAudioMixerNode?
    private var audioLevelTimer: Timer?

    private let sessionQueue = DispatchQueue(label: "com.voice.session", qos: .userInteractive)
    private let audioProcessingQueue = DispatchQueue(label: "com.voice.audioProcessing", qos: .userInteractive)

    private var recordedAudioData: Data = Data()
    private var receivedAudioBuffers: [String: Data] = [:]

    private init() {}
    
    deinit {
        stopAudioLevelMonitoring()
        teardownAudioEngine()
    }

    // MARK: - Session Lifecycle

    func join(channelID: String) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.state == .idle || self.state == .disconnecting else {
                return
            }

            self.state = .connecting

            self.setupAudioSession { success, error in
                if success {
                    self.setupAudioEngine()
                    self.state = .connected
                    self.startAudioLevelMonitoring()
                } else {
                    self.state = .error(error?.localizedDescription ?? "Failed to join")
                    DispatchQueue.main.async {
                        self.delegate?.voiceSession(self, didEncounterError: error ?? VoiceSessionError.failedToJoin)
                    }
                }
            }
        }
    }

    func leave() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.state != .idle && self.state != .disconnecting else {
                return
            }

            self.state = .disconnecting

            self.stopAudioLevelMonitoring()
            self.teardownAudioEngine()
            self.deactivateAudioSession()

            self.activePeers.removeAll()
            self.recordedAudioData.removeAll()
            self.receivedAudioBuffers.removeAll()

            self.state = .idle
        }
    }

    // MARK: - Audio Engine Setup

    private func setupAudioSession(completion: @escaping (Bool, Error?) -> Void) {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            completion(true, nil)
        } catch {
            completion(false, error)
        }
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        inputNode = audioEngine.inputNode
        mixerNode = AVAudioMixerNode()

        guard let mixerNode = mixerNode else { return }

        audioEngine.attach(mixerNode)

        let inputFormat = inputNode?.outputFormat(forBus: 0)

        if let inputFormat = inputFormat {
            audioEngine.connect(inputNode!, to: mixerNode, format: inputFormat)
        }

        let outputFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: outputFormat)

        do {
            try audioEngine.start()
        } catch {
            Logger.shared.error("VoiceSession: Failed to start audio engine - \(error)")
        }
    }

    private func teardownAudioEngine() {
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        mixerNode = nil
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Logger.shared.error("VoiceSession: Failed to deactivate audio session - \(error)")
        }
    }

    // MARK: - Microphone Control

    func muteMicrophone() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isMicrophoneMuted = true
            self.inputNode?.volume = 0
        }
    }

    func unmuteMicrophone() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isMicrophoneMuted = false
            self.inputNode?.volume = 1.0
        }
    }

    func toggleMicrophone() {
        if isMicrophoneMuted {
            unmuteMicrophone()
        } else {
            muteMicrophone()
        }
    }

    // MARK: - Mix Mode

    func setMixMode(_ mode: MixMode) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.mixMode = mode
            self.applyMixModeSettings()
        }
    }

    private func applyMixModeSettings() {
        switch mixMode {
        case .speaker:
            mixerNode?.outputVolume = 1.0
        case .listener:
            mixerNode?.outputVolume = 0.5
        case .intercom:
            mixerNode?.outputVolume = 0.8
        }
    }

    // MARK: - Audio Recording

    func startRecording() {
        guard state == .connected || state == .speaking else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.state != .speaking {
                self.state = .speaking
            }

            self.recordedAudioData.removeAll()
            self.installTapOnInputNode()
        }
    }

    func stopRecording() -> Data? {
        var audioData: Data?

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.removeTapFromInputNode()

            audioData = self.recordedAudioData
            self.recordedAudioData.removeAll()

            if self.state == .speaking {
                self.state = .connected
            }
        }

        return audioData
    }

    private func installTapOnInputNode() {
        guard let inputNode = inputNode else { return }

        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            self?.processInputAudioBuffer(buffer)
        }
    }

    private func removeTapFromInputNode() {
        inputNode?.removeTap(onBus: 0)
    }

    private func processInputAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let frameLength = UInt(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<Int(frameLength) {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let meanSquare = sum / Float(frameLength)
        let rms = sqrt(meanSquare)
        let level = min(1.0, max(0.0, rms * 2.0))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.voiceSession(self, didReceiveAudioLevel: level)
        }

        audioProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            guard let data = self.pcmBufferToData(buffer) else { return }
            self.recordedAudioData.append(data)
        }
    }

    private func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var data = Data()

        for channel in 0..<channelCount {
            let channelDataPtr = channelData[channel]
            let byteCount = frameLength * MemoryLayout<Float>.size

            data.append(UnsafeBufferPointer(start: channelDataPtr, count: frameLength))
        }

        return data
    }

    // MARK: - Audio Playback / Mixing

    func playReceivedAudio(from peerID: String, audioData: Data) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.receivedAudioBuffers[peerID] = audioData

            if self.state == .connected || self.state == .speaking {
                self.state = .receiving
            }

            self.mixAndPlayAudio()
        }
    }

    private func mixAndPlayAudio() {
        guard let mixerNode = mixerNode else { return }

        audioProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            let combinedData = self.combineAudioBuffers()

            guard !combinedData.isEmpty else { return }

            if let pcmBuffer = self.dataToPCMBuffer(combinedData) {
                self.schedulePlayback(buffer: pcmBuffer)
            }
        }
    }

    private func combineAudioBuffers() -> Data {
        var combined = Data()

        for (_, buffer) in receivedAudioBuffers {
            combined.append(buffer)
        }

        return combined
    }

    private func dataToPCMBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = data.count / MemoryLayout<Float>.size / 2

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        data.withUnsafeBytes { rawBufferPointer in
            guard let floatPointer = rawBufferPointer.baseAddress?.assumingMemoryBound(to: Float.self) else { return }

            for i in 0..<frameCount * 2 {
                buffer.floatChannelData?[0][i] = floatPointer[i]
            }
        }

        return buffer
    }

    private func schedulePlayback(buffer: AVAudioPCMBuffer) {
        guard let audioEngine = audioEngine else { return }

        let playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)

        let format = buffer.format
        audioEngine.connect(playerNode, to: mixerNode!, format: format)

        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        playerNode.play()
    }

    // MARK: - Peer Management

    func addPeer(_ peerID: String) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.activePeers.insert(peerID)
        }
    }

    func removePeer(_ peerID: String) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.activePeers.remove(peerID)
            self.receivedAudioBuffers.removeValue(forKey: peerID)
        }
    }

    func removeAllPeers() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.activePeers.removeAll()
            self.receivedAudioBuffers.removeAll()
        }
    }

    // MARK: - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateAudioLevel()
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        DispatchQueue.main.async { [weak self] in
            self?.audioLevelTimer?.invalidate()
            self?.audioLevelTimer = nil
        }
    }

    private func updateAudioLevel() {
        guard let inputNode = inputNode, state == .speaking else { return }

        inputNode.volume = isMicrophoneMuted ? 0 : 1.0
    }

    // MARK: - State Queries

    var isActive: Bool {
        return state == .connected || state == .speaking || state == .receiving
    }

    var isJoined: Bool {
        return state != .idle && state != .disconnecting
    }
}

// MARK: - Errors

enum VoiceSessionError: LocalizedError {
    case failedToJoin
    case audioSessionSetupFailed
    case audioEngineStartFailed
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .failedToJoin:
            return "Failed to join voice session"
        case .audioSessionSetupFailed:
            return "Failed to set up audio session"
        case .audioEngineStartFailed:
            return "Failed to start audio engine"
        case .recordingFailed:
            return "Failed to record audio"
        }
    }
}
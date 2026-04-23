import Foundation
import AVFoundation
import UIKit

// MARK: - VoiceServiceDelegate

protocol VoiceServiceDelegate: AnyObject {
    func voiceService(_ service: VoiceService, didStartCall callId: UUID, peerId: String)
    func voiceService(_ service: VoiceService, didEndCall callId: UUID, reason: VoiceCallEndReason)
    func voiceService(_ service: VoiceService, didReceiveAudioFrame data: Data, from peerId: String)
    func voiceService(_ service: VoiceService, didUpdateMuteState isMuted: Bool)
    func voiceService(_ service: VoiceService, didUpdateSpeakerState isSpeakerOn: Bool)
    func voiceService(_ service: VoiceService, didUpdateCallQuality quality: VoiceCallQuality)
    func voiceService(_ service: VoiceService, didFailWithError error: Error)
}

// MARK: - VoiceCallEndReason

enum VoiceCallEndReason: Int, LocalizedError {
    case userEnded = 0
    case peerEnded = 1
    case callDropped = 2
    case networkError = 3
    case timeout = 4
    case unknown = 99

    var errorDescription: String? {
        switch self {
        case .userEnded: return "Call ended by user"
        case .peerEnded: return "Call ended by peer"
        case .callDropped: return "Call dropped unexpectedly"
        case .networkError: return "Network error occurred"
        case .timeout: return "Call timed out"
        case .unknown: return "Unknown reason"
        }
    }
}

// MARK: - VoiceCallState

enum VoiceCallState: Equatable {
    case idle
    case connecting
    case ringing
    case active
    case onHold
    case ending
    case ended(reason: VoiceCallEndReason)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

// MARK: - VoiceCallMode

enum VoiceCallMode: String, CaseIterable {
    case p2p = "p2p"
    case group = "group"
    case conference = "conference"
}

// MARK: - VoiceCallQuality

struct VoiceCallQuality: Equatable {
    let rssi: Int
    let packetLoss: Double
    let latency: TimeInterval
    let jitter: TimeInterval

    static let unknown = VoiceCallQuality(rssi: -100, packetLoss: 0, latency: 0, jitter: 0)

    var isGood: Bool {
        return packetLoss < 0.05 && latency < 0.3 && jitter < 0.05
    }

    var isAcceptable: Bool {
        return packetLoss < 0.15 && latency < 0.5 && jitter < 0.1
    }
}

// MARK: - VoiceCall

struct VoiceCall: Identifiable, Equatable {
    let id: UUID
    let peerId: String
    let mode: VoiceCallMode
    var state: VoiceCallState
    var startTime: Date?
    var endTime: Date?
    var participants: Set<String>
    var isMuted: Bool
    var isSpeakerOn: Bool
    var quality: VoiceCallQuality

    static func == (lhs: VoiceCall, rhs: VoiceCall) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - VoiceService

final class VoiceService {
    static let shared = VoiceService()


    
    // MARK: - Properties

    weak var delegate: VoiceServiceDelegate?

    private(set) var currentCall: VoiceCall?
    private(set) var activeCalls: [UUID: VoiceCall] = [:]
    private(set) var isRunning: Bool = false
    private(set) var isMuted: Bool = false
    private(set) var isSpeakerOn: Bool = false

    private let audioCodec: AudioCodec
    private let voiceQueue = DispatchQueue(label: "com.voice.service", qos: .userInitiated)

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var playerNode: AVAudioPlayerNode?

    private var encodingTimer: DispatchSourceTimer?
    private var decodingTimer: DispatchSourceTimer?
    private let frameDuration: TimeInterval = 0.02

    private var callTimeoutTimer: Timer?
    private let callTimeoutInterval: TimeInterval = 30.0

    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Initialization

    private init() {
        self.audioCodec = AudioCodec(codecType: .opus)
        setupAudioSession()
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    func configure() {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }
            self.setupAudioSession()
        }
    }

    func start() {
        voiceQueue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isRunning = true

            do {
                try self.audioCodec.start()
                self.startAudioPipeline()
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.voiceService(self, didFailWithError: error)
                }
            }
        }
    }

    func stop() {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = false

            self.stopAudioPipeline()
            self.audioCodec.stop()
            self.endBackgroundTask()

            if let call = self.currentCall {
                var endedCall = call
                endedCall.state = .ended(reason: .userEnded)
                self.activeCalls[call.id] = endedCall
            }
            self.currentCall = nil
        }
    }

    // MARK: - P2P Call

    func startP2PCall(with peerId: String) {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            let callId = UUID()
            var call = VoiceCall(
                id: callId,
                peerId: peerId,
                mode: .p2p,
                state: .connecting,
                participants: [peerId],
                isMuted: false,
                isSpeakerOn: false,
                quality: .unknown
            )

            self.currentCall = call
            self.activeCalls[callId] = call

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didStartCall: callId, peerId: peerId)
            }

            self.startCallTimeoutTimer()
        }
    }

    func acceptP2PCall(from peerId: String) {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            if let call = self.currentCall, call.peerId == peerId {
                var acceptedCall = call
                acceptedCall.state = .active
                acceptedCall.startTime = Date()
                self.currentCall = acceptedCall
                self.activeCalls[call.id] = acceptedCall

                self.stopCallTimeoutTimer()
                self.startEncodingTimer()

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.voiceService(self, didStartCall: call.id, peerId: peerId)
                }
            }
        }
    }

    func endP2PCall(reason: VoiceCallEndReason = .userEnded) {
        voiceQueue.async { [weak self] in
            guard let self = self, let call = self.currentCall else { return }

            self.stopEncodingTimer()
            self.stopDecodingTimer()

            var endedCall = call
            endedCall.state = .ended(reason: reason)
            endedCall.endTime = Date()
            self.activeCalls[call.id] = endedCall
            self.currentCall = nil

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didEndCall: call.id, reason: reason)
            }

            self.endBackgroundTask()
        }
    }

    // MARK: - Group Call

    func startGroupCall(with participantIds: Set<String>) {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            let callId = UUID()
            var call = VoiceCall(
                id: callId,
                peerId: "",
                mode: .group,
                state: .active,
                startTime: Date(),
                participants: participantIds,
                isMuted: false,
                isSpeakerOn: false,
                quality: .unknown
            )

            self.currentCall = call
            self.activeCalls[callId] = call

            self.startEncodingTimer()
            self.startDecodingTimer()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didStartCall: callId, peerId: "")
            }
        }
    }

    func addParticipant(_ peerId: String) {
        voiceQueue.async { [weak self] in
            guard let self = self, var call = self.currentCall, call.mode == .group else { return }

            call.participants.insert(peerId)
            self.currentCall = call
            self.activeCalls[call.id] = call
        }
    }

    func removeParticipant(_ peerId: String) {
        voiceQueue.async { [weak self] in
            guard let self = self, var call = self.currentCall, call.mode == .group else { return }

            call.participants.remove(peerId)
            self.currentCall = call
            self.activeCalls[call.id] = call
        }
    }

    func endGroupCall(reason: VoiceCallEndReason = .userEnded) {
        voiceQueue.async { [weak self] in
            guard let self = self, let call = self.currentCall else { return }

            self.stopEncodingTimer()
            self.stopDecodingTimer()

            var endedCall = call
            endedCall.state = .ended(reason: reason)
            endedCall.endTime = Date()
            self.activeCalls[call.id] = endedCall
            self.currentCall = nil

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didEndCall: call.id, reason: reason)
            }

            self.endBackgroundTask()
        }
    }

    // MARK: - Background Call

    func startBackgroundCall() {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            self.beginBackgroundTask()
            self.startAudioPipeline()
            self.startEncodingTimer()

            DispatchQueue.main.async {
                UIApplication.shared.beginReceivingRemoteControlEvents()
            }
        }
    }

    func endBackgroundCall() {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            self.stopEncodingTimer()
            self.stopDecodingTimer()
            self.stopAudioPipeline()
            self.endBackgroundTask()

            DispatchQueue.main.async {
                UIApplication.shared.endReceivingRemoteControlEvents()
            }
        }
    }

    // MARK: - Audio Controls

    func setMuted(_ muted: Bool) {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            self.isMuted = muted

            if var call = self.currentCall {
                call.isMuted = muted
                self.currentCall = call
                self.activeCalls[call.id] = call
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didUpdateMuteState: muted)
            }
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setSpeakerOn(_ speakerOn: Bool) {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            self.isSpeakerOn = speakerOn

            do {
                let session = AVAudioSession.sharedInstance()
                try session.overrideOutputAudioPort(speakerOn ? .speaker : .none)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.voiceService(self, didFailWithError: error)
                }
            }

            if var call = self.currentCall {
                call.isSpeakerOn = speakerOn
                self.currentCall = call
                self.activeCalls[call.id] = call
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didUpdateSpeakerState: speakerOn)
            }
        }
    }

    func toggleSpeaker() {
        setSpeakerOn(!isSpeakerOn)
    }

    // MARK: - Audio Pipeline

    private func startAudioPipeline() {
        audioEngine = AVAudioEngine()

        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        self.inputNode = inputNode

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.handleInputBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didFailWithError: error)
            }
        }
    }

    private func stopAudioPipeline() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard !isMuted, let call = currentCall, call.state.isActive else { return }

        let pcmData = audioCodec.audioBufferToData(buffer)

        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let encodedData = try self.audioCodec.encode(pcmData)
                let isKeyframe = true

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.voiceService(self, didReceiveAudioFrame: encodedData, from: "local")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.voiceService(self, didFailWithError: error)
                }
            }
        }
    }

    // MARK: - Encoding Timer

    private func startEncodingTimer() {
        encodingTimer = DispatchSource.makeTimerSource(queue: voiceQueue)
        encodingTimer?.schedule(deadline: .now(), repeating: frameDuration)
        encodingTimer?.setEventHandler { [weak self] in
            self?.encodingTick()
        }
        encodingTimer?.resume()
    }

    private func stopEncodingTimer() {
        encodingTimer?.cancel()
        encodingTimer = nil
    }

    private func encodingTick() {
    }

    // MARK: - Decoding Timer

    private func startDecodingTimer() {
        decodingTimer = DispatchSource.makeTimerSource(queue: voiceQueue)
        decodingTimer?.schedule(deadline: .now(), repeating: frameDuration)
        decodingTimer?.setEventHandler { [weak self] in
            self?.decodingTick()
        }
        decodingTimer?.resume()
    }

    private func stopDecodingTimer() {
        decodingTimer?.cancel()
        decodingTimer = nil
    }

    private func decodingTick() {
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // P1-FIX: 添加后台音频支持选项
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .defaultToSpeaker,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .mixWithOthers,
                    .allowAirPlay
                ]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            Logger.shared.info("VoiceService: Audio session configured with background support")
        } catch {
            Logger.shared.error("Failed to setup audio session: \(error)")
        }
    }
    
    // P1-FIX: 配置后台音频会话
    private func setupBackgroundAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // 后台模式使用更保守的配置
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .allowBluetooth,
                    .mixWithOthers
                ]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            Logger.shared.info("VoiceService: Background audio session configured")
        } catch {
            Logger.shared.error("Failed to setup background audio session: \(error)")
        }
    }

    // MARK: - Call Timeout

    private func startCallTimeoutTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.callTimeoutTimer = Timer.scheduledTimer(withTimeInterval: self.callTimeoutInterval, repeats: false) { [weak self] _ in
                self?.handleCallTimeout()
            }
        }
    }

    private func stopCallTimeoutTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.callTimeoutTimer?.invalidate()
            self?.callTimeoutTimer = nil
        }
    }

    private func handleCallTimeout() {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }
            self.endP2PCall(reason: .timeout)
        }
    }

    // MARK: - Background Task

    private func beginBackgroundTask() {
        backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }

    // MARK: - Call Quality

    func updateCallQuality(_ quality: VoiceCallQuality) {
        voiceQueue.async { [weak self] in
            guard let self = self, var call = self.currentCall else { return }

            call.quality = quality
            self.currentCall = call
            self.activeCalls[call.id] = call

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didUpdateCallQuality: quality)
            }
        }
    }

    // MARK: - Statistics

    func getCallStatistics() -> VoiceCallStatistics {
        return VoiceCallStatistics(
            callId: currentCall?.id,
            duration: currentCall?.startTime.map { Date().timeIntervalSince($0) },
            participantCount: currentCall?.participants.count,
            codecState: audioCodec.state
        )
    }
}

// MARK: - VoiceCallStatistics

struct VoiceCallStatistics {
    let callId: UUID?
    let duration: TimeInterval?
    let participantCount: Int?
    let codecState: AudioCodec.CodecState
}



extension VoiceService {

    static func == (lhs: VoiceService, rhs: VoiceService) -> Bool {
        return lhs === rhs
    }
}

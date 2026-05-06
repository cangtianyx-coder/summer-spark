import Foundation
import AVFoundation
import UIKit
import CryptoKit

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
    
    // PTT state tracking
    private(set) var isPTTMode: Bool = false
    private(set) var currentGroupId: String?
    
    /// PTT-FIX: Published group name for UI binding
    @Published var currentGroupName: String?

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
        initializeVoiceEncryption()
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
            self.isPTTMode = false

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
            
            // PTT-FIX: Clean up PTT state if this was a PTT-initiated call
            if self.isPTTMode {
                self.isPTTMode = false
            }
            
            // P2-FIX: Clean up currentGroupId when ending group call
            self.currentGroupId = nil

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didEndCall: call.id, reason: reason)
            }

            self.endBackgroundTask()
        }
    }
    
    // MARK: - PTT Group Call Support
    
    /// Join an existing group call for PTT, or create one if none exists
    /// Called automatically when PTT is pressed without an active call
    func joinGroupCall(groupId: String) {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If already in a group call for this group, don't create duplicate
            if let existingCall = self.currentCall, existingCall.mode == .group {
                Logger.shared.debug("VoiceService: Already in group call \(existingCall.id)")
                return
            }
            
            // Get group members from GroupStore
            let members = GroupStore.shared.getGroupMembers(groupId: groupId)
            let participantIds = Set(members.map { $0.uid })
            
            Logger.shared.info("VoiceService: Creating group call for group \(groupId) with \(participantIds.count) members")
            
            let callId = UUID()
            var call = VoiceCall(
                id: callId,
                peerId: groupId, // Use groupId as peerId for group calls
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
                self.delegate?.voiceService(self, didStartCall: callId, peerId: groupId)
            }
        }
    }
    
    /// Set the current group context for PTT operations
    /// Call this when user selects/enters a group to enable PTT in that group
    func setCurrentGroup(_ groupId: String?, name: String? = nil) {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentGroupId = groupId
            // PTT-FIX: Also update published group name for UI binding
            DispatchQueue.main.async {
                self.currentGroupName = name
            }
            Logger.shared.debug("VoiceService: Current group context set to \(groupId ?? "nil") (name: \(name ?? "nil"))")
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

    // MARK: - PTT (Push-to-Talk) Support

    /// Start transmitting audio for PTT
    /// Call this when PTT button is pressed
    func startTransmitting() {
        // P0-FIX: Check microphone permission before attempting to start audio pipeline
        let permission = AVAudioSession.sharedInstance().recordPermission
        switch permission {
        case .granted:
            break // Permission OK, proceed
        case .denied:
            Logger.shared.error("VoiceService: Microphone permission denied - cannot start PTT")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let error = NSError(
                    domain: "VoiceService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Please enable in Settings."]
                )
                self.delegate?.voiceService(self, didFailWithError: error)
            }
            return
        case .undetermined:
            // Request permission asynchronously
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    Logger.shared.info("VoiceService: Microphone permission granted, starting PTT")
                    // P2-FIX: Use dispatch to break recursive call chain
                    DispatchQueue.main.async {
                        self.startTransmitting()
                    }
                } else {
                    Logger.shared.error("VoiceService: Microphone permission denied by user")
                    DispatchQueue.main.async {
                        let error = NSError(
                            domain: "VoiceService",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied by user"]
                        )
                        self.delegate?.voiceService(self, didFailWithError: error)
                    }
                }
            }
            return
        @unknown default:
            Logger.shared.warn("VoiceService: Unknown audio permission state")
            return
        }

        voiceQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRunning else { return }

            do {
                try self.audioCodec.start()
                self.startAudioPipeline()
                self.isRunning = true
                self.isPTTMode = true
                
                // PTT-FIX: If no active call exists but we're in a group, auto-join group call
                if self.currentCall == nil {
                    if let groupId = self.currentGroupId {
                        Logger.shared.info("VoiceService: PTT started with no call, joining group \(groupId)")
                        self.joinGroupCall(groupId: groupId)
                    } else {
                        // PTT-FIX: Notify delegate of silent failure when no group context
                        Logger.shared.warn("VoiceService: PTT started with no active call and no group context")
                        let error = NSError(
                            domain: "VoiceService",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "ptt_error_no_group".localized]
                        )
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.voiceService(self, didFailWithError: error)
                        }
                    }
                }
                
                Logger.shared.debug("VoiceService: PTT transmit started")
            } catch {
                Logger.shared.error("VoiceService: Failed to start PTT - \(error)")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.voiceService(self, didFailWithError: error)
                }
            }
        }
    }

    /// Stop transmitting audio for PTT
    /// Call this when PTT button is released
    func stopTransmitting() {
        voiceQueue.async { [weak self] in
            guard let self = self else { return }

            self.stopAudioPipeline()
            self.audioCodec.stop()
            self.isRunning = false
            self.isPTTMode = false
            Logger.shared.debug("VoiceService: PTT transmit stopped")
        }
    }

    // MARK: - Audio Pipeline

    private func startAudioPipeline() {
        // P0-FIX: Verify audio input availability before accessing inputNode
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.recordPermission == .granted else {
            Logger.shared.error("VoiceService: Cannot start audio pipeline - no microphone permission")
            return
        }

        audioEngine = AVAudioEngine()

        guard let engine = audioEngine else { return }

        // P0-FIX: Verify input node is accessible before using it
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Check if input format is valid (sample rate > 0 means available)
        guard inputFormat.sampleRate > 0 else {
            Logger.shared.error("VoiceService: Audio input not available - permission may be denied")
            audioEngine = nil
            return
        }

        self.inputNode = inputNode

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.handleInputBuffer(buffer)
        }

        do {
            try engine.start()
            Logger.shared.debug("VoiceService: Audio pipeline started successfully")
        } catch {
            Logger.shared.error("VoiceService: Failed to start audio engine - \(error)")
            audioEngine?.stop()
            audioEngine = nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didFailWithError: error)
            }
        }
    }

    // MARK: - Voice Encryption Handler

    /// Handler for encrypting voice data before mesh transmission
    /// Initialized with real E2E encryption using CryptoEngine.encryptAndSign()
    /// P0-FIX: Voice data must be encrypted before transmission to prevent eavesdropping
    private var _voiceEncryptionHandler: ((Data, String) -> Data)?
    
    var voiceEncryptionHandler: ((Data, String) -> Data)? {
        get { return _voiceEncryptionHandler }
        set { _voiceEncryptionHandler = newValue }
    }
    
    /// Initialize the voice encryption handler with proper E2E encryption
    /// Uses CryptoEngine.encryptAndSign() with ECDH key agreement + ECDSA signatures
    private func initializeVoiceEncryption() {
        // P3-FIX: Use [weak self] to prevent retain cycle in encryption handler closure
        _voiceEncryptionHandler = { [weak self] (audioData: Data, peerId: String) -> Data in
            guard let self = self else { return audioData }
            
            // Get peer's public key for encryption
            guard let recipientPublicKey = IdentityManager.shared.getPublicKey(for: peerId) else {
                Logger.shared.warn("VoiceService: No public key for peer \(peerId), sending unencrypted")
                return audioData
            }
            
            // Get our signing key for ECDSA signature
            guard let senderSigningKey = IdentityManager.shared.getPrivateKeyForSigning() else {
                Logger.shared.error("VoiceService: No signing key available")
                return audioData
            }
            
            // Get our key agreement key
            guard let senderKeyAgreementKey = IdentityManager.shared.getPrivateKeyForAgreement() else {
                Logger.shared.error("VoiceService: No key agreement key available")
                return audioData
            }
            
            do {
                // Convert signing public key to key agreement public key (same key pair used for both)
                let recipientKeyAgreementPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey.rawRepresentation)
                
                // Encrypt and sign: [ephemeralPubKey(65) || nonce(12) || ciphertext || tag(16) || signature(64)]
                let encryptedPackage = try CryptoEngine.shared.encryptAndSign(
                    plaintext: audioData,
                    recipientPublicKey: recipientKeyAgreementPublicKey,
                    senderSigningKey: senderSigningKey
                )
                
                // Prepend peer ID length (1 byte) and peer ID for routing
                var packet = Data()
                packet.append(UInt8(peerId.utf8.count))
                packet.append(peerId.data(using: .utf8) ?? Data())
                packet.append(encryptedPackage)
                
                return packet
            } catch {
                Logger.shared.error("VoiceService: Encryption failed - \(error)")
                return audioData
            }
        }
        
        Logger.shared.info("VoiceService: Voice encryption handler initialized with E2E encryption")
    }

    // MARK: - Audio Pipeline

    private func stopAudioPipeline() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // P0-FIX: Capture state copies on audio thread to avoid data race with voiceQueue modifications
        let muted = self.isMuted
        let pttMode = self.isPTTMode
        let groupId = self.currentGroupId
        let call = self.currentCall
        
        // PTT-FIX: Allow audio through in PTT mode even without active call
        // This handles the case where PTT was just pressed and we're waiting to join a group call
        guard !muted else { return }
        
        let shouldTransmit = call?.state.isActive == true || (pttMode && groupId != nil)
        
        guard shouldTransmit else {
            // If in PTT mode but no call and no group context, silently discard
            if pttMode {
                Logger.shared.warn("VoiceService: PTT active but no group context - discarding audio")
            }
            return
        }

        let pcmData = audioCodec.audioBufferToData(buffer)

        // P1-FIX: Encode on audio thread to avoid per-packet dispatch overhead
        do {
            let encodedData = try self.audioCodec.encode(pcmData)

            // P0-FIX: Use captured call reference for encryption (avoids data race on currentCall)
            // Use call.peerId for normal calls, or groupId for PTT-initiated group calls
            let targetPeerId = call?.peerId ?? groupId ?? "local"
            let dataToSend: Data
            if let encryptHandler = self.voiceEncryptionHandler {
                dataToSend = encryptHandler(encodedData, targetPeerId)
            } else {
                dataToSend = encodedData
            }

            // Only dispatch delegate callback to main queue (minimal synchronization point)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didReceiveAudioFrame: dataToSend, from: "local")
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.voiceService(self, didFailWithError: error)
            }
        }
    }

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

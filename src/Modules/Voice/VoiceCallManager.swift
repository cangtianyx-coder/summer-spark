import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - Voice Group Member

struct VoiceGroupMember: Identifiable {
    let id: String
    let name: String
    var isOnline: Bool = true
}

// MARK: - Voice Call Manager

@available(iOS 13.0, *)
class VoiceCallManager: ObservableObject {
    static let shared = VoiceCallManager()

    // MARK: - Published Properties
    @Published var groupMembers: [VoiceGroupMember] = []
    @Published var incomingCall: IncomingCallInfo?
    @Published var activeCall: ActiveCallInfo?
    @Published var isInCall: Bool = false

    // MARK: - Call State

    enum CallState {
        case idle
        case ringing
        case connected
        case ended
    }

    // MARK: - Init

    private init() {
        loadMockGroupMembers()
        setupNotifications()
    }

    private func loadMockGroupMembers() {
        // 模拟群组成员数据 - 实际应从MeshService获取
        groupMembers = [
            VoiceGroupMember(id: "1", name: "Alice"),
            VoiceGroupMember(id: "2", name: "Bob"),
            VoiceGroupMember(id: "3", name: "Charlie"),
            VoiceGroupMember(id: "4", name: "Diana")
        ]
    }

    private func setupNotifications() {
        // 请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("Notification permission granted: \(granted)")
        }
    }

    // MARK: - Initiate Call

    func initiateCall(to member: VoiceGroupMember) {
        let callInfo = ActiveCallInfo(
            id: UUID().uuidString,
            callerName: member.name,
            isGroupCall: false,
            startTime: Date()
        )

        DispatchQueue.main.async {
            self.activeCall = callInfo
            self.isInCall = true
        }

        // 模拟开始通话
        startCallTimer()
    }

    func initiateGroupCall() {
        let callInfo = ActiveCallInfo(
            id: UUID().uuidString,
            callerName: "Group Call",
            isGroupCall: true,
            startTime: Date()
        )

        DispatchQueue.main.async {
            self.activeCall = callInfo
            self.isInCall = true
        }

        startCallTimer()
    }

    // MARK: - Receive Call

    func receiveCall(from callerName: String, isGroupCall: Bool) {
        let callInfo = IncomingCallInfo(
            id: UUID().uuidString,
            callerName: callerName,
            isGroupCall: isGroupCall,
            receiveTime: Date()
        )

        DispatchQueue.main.async {
            self.incomingCall = callInfo
        }

        // 发送系统通知（如果在后台）
        sendIncomingCallNotification(from: callerName, isGroupCall: isGroupCall)
    }

    private func sendIncomingCallNotification(from callerName: String, isGroupCall: Bool) {
        let content = UNMutableNotificationContent()
        content.title = isGroupCall ? "Group Call" : "Incoming Call"
        content.body = "\(callerName) is calling you..."
        content.sound = .default
        content.categoryIdentifier = "VOICE_CALL"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Accept / Decline Call

    func acceptCall() {
        guard let incoming = incomingCall else { return }

        let activeInfo = ActiveCallInfo(
            id: incoming.id,
            callerName: incoming.callerName,
            isGroupCall: incoming.isGroupCall,
            startTime: Date()
        )

        DispatchQueue.main.async {
            self.activeCall = activeInfo
            self.incomingCall = nil
            self.isInCall = true
        }

        startCallTimer()
    }

    func declineCall() {
        DispatchQueue.main.async {
            self.incomingCall = nil
        }
    }

    // MARK: - End Call

    func endCall() {
        DispatchQueue.main.async {
            self.activeCall = nil
            self.incomingCall = nil
            self.isInCall = false
        }
    }

    // MARK: - Call Timer

    private func startCallTimer() {
        // 实际应用中这里会启动音频会话
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
}

// MARK: - Incoming Call Info

struct IncomingCallInfo: Identifiable {
    let id: String
    let callerName: String
    let isGroupCall: Bool
    let receiveTime: Date
}

// MARK: - Active Call Info

struct ActiveCallInfo: Identifiable {
    let id: String
    let callerName: String
    let isGroupCall: Bool
    let startTime: Date
}

// MARK: - Notification Names

extension Notification.Name {
    static let incomingVoiceCall = Notification.Name("incomingVoiceCall")
    static let voiceCallAccepted = Notification.Name("voiceCallAccepted")
    static let voiceCallEnded = Notification.Name("voiceCallEnded")
}

// MARK: - PTT Error Handler (PTT-FIX)

/// Singleton class to handle PTT errors and show UI feedback
/// Implements VoiceServiceDelegate to catch all PTT error conditions
@available(iOS 13.0, *)
final class PTTErrorHandler: ObservableObject, VoiceServiceDelegate {
    static let shared = PTTErrorHandler()
    
    // Published error state for UI binding
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    
    private init() {}
    
    // MARK: - VoiceServiceDelegate Implementation
    
    func voiceService(_ service: VoiceService, didStartCall callId: UUID, peerId: String) {
        // Call started - no error handling needed
    }
    
    func voiceService(_ service: VoiceService, didEndCall callId: UUID, reason: VoiceCallEndReason) {
        // Call ended - no error handling needed
    }
    
    func voiceService(_ service: VoiceService, didReceiveAudioFrame data: Data, from peerId: String) {
        // Audio received - no error handling needed
    }
    
    func voiceService(_ service: VoiceService, didUpdateMuteState isMuted: Bool) {
        // Mute state changed - no error handling needed
    }
    
    func voiceService(_ service: VoiceService, didUpdateSpeakerState isSpeakerOn: Bool) {
        // Speaker state changed - no error handling needed
    }
    
    func voiceService(_ service: VoiceService, didUpdateCallQuality quality: VoiceCallQuality) {
        // Call quality changed - no error handling needed
    }
    
    func voiceService(_ service: VoiceService, didFailWithError error: Error) {
        // PTT-FIX: Handle all PTT errors and show UI feedback
        // Map error to friendly localized message
        let friendlyMessage = mapToFriendlyErrorMessage(error)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.errorMessage = friendlyMessage
            self.showError = true
            Logger.shared.error("PTTErrorHandler: Received error - \(friendlyMessage)")
        }
    }

    // PTT-FIX: Map error to user-friendly localized message
    private func mapToFriendlyErrorMessage(_ error: Error) -> String {
        // Check if it's a VoiceCallEndReason
        if let reason = error as? VoiceCallEndReason {
            switch reason {
            case .userEnded:
                return "ptt_error_call_ended".localized
            case .peerEnded:
                return "ptt_error_peer_ended".localized
            case .callDropped:
                return "ptt_error_call_dropped".localized
            case .networkError:
                return "ptt_error_network".localized
            case .timeout:
                return "ptt_error_timeout".localized
            case .unknown:
                return "ptt_error_unknown".localized
            }
        }

        // Check if it's an NSError from VoiceService
        if let nsError = error as NSError?, nsError.domain == "VoiceService" {
            switch nsError.code {
            case 1:
                // Microphone permission denied
                return "ptt_error_mic_denied".localized
            case 2:
                // No group selected
                return "ptt_error_no_group".localized
            default:
                return nsError.localizedDescription
            }
        }

        // Default to the error's localized description
        return error.localizedDescription
    }
}

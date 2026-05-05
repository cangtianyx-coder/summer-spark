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

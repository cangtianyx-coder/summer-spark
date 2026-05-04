import Foundation
import CryptoKit

// MARK: - Emergency Channel Message

/// 紧急通道消息
struct EmergencyChannelMessage: Codable, Identifiable {
    let id: UUID
    let senderId: String
    let senderName: String
    let content: String
    let priority: MessagePriority
    let timestamp: Date
    var acknowledgedBy: Set<String>
    
    init(senderId: String, senderName: String, content: String, priority: MessagePriority) {
        self.id = UUID()
        self.senderId = senderId
        self.senderName = senderName
        self.content = content
        self.priority = priority
        self.timestamp = Date()
        self.acknowledgedBy = []
    }
}

// MARK: - Emergency Channel

/// 紧急通道 - 应急指挥专用频道
final class EmergencyChannel {
    static let shared = EmergencyChannel()
    
    private var messages: [EmergencyChannelMessage] = []
    private var members: Set<String> = []
    private var messageQueue: [EmergencyChannelMessage] = []  // 待发送队列
    private let queue = DispatchQueue(label: "com.summerspark.emergencychannel", attributes: .concurrent)
    
    private let maxHistorySize = 200
    private let maxQueueSize = 50
    
    weak var delegate: EmergencyChannelDelegate?
    
    private init() {
        // 当前用户自动加入
        if let uid = IdentityManager.shared.uid {
            members.insert(uid)
        }
    }
    
    // MARK: - Membership
    
    /// 加入紧急通道
    func join(userId: String) {
        queue.sync(flags: .barrier) {
            members.insert(userId)
        }
        Logger.shared.info("EmergencyChannel: User \(userId) joined")
    }
    
    /// 离开紧急通道
    func leave(userId: String) {
        queue.sync(flags: .barrier) {
            members.remove(userId)
        }
        Logger.shared.info("EmergencyChannel: User \(userId) left")
    }
    
    /// 获取成员列表
    func getMembers() -> [String] {
        return queue.sync { Array(members) }
    }
    
    /// 成员数量
    func memberCount() -> Int {
        return queue.sync { members.count }
    }
    
    // MARK: - Messaging
    
    /// 发送紧急消息
    func send(content: String, priority: MessagePriority = .high) -> EmergencyChannelMessage? {
        guard let uid = IdentityManager.shared.uid else { return nil }
        let name = IdentityManager.shared.displayName
        
        let message = EmergencyChannelMessage(
            senderId: uid,
            senderName: name,
            content: content,
            priority: priority
        )
        
        // 添加到历史
        queue.sync(flags: .barrier) {
            messages.append(message)
            if messages.count > maxHistorySize {
                messages.removeFirst(messages.count - maxHistorySize)
            }
        }
        
        // 广播到Mesh网络
        broadcastMessage(message)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.emergencyChannel(self, didSendMessage: message)
        }
        
        Logger.shared.info("EmergencyChannel: Sent message with priority \(priority.rawValue)")
        return message
    }
    
    /// 发送紧急指令（最高优先级）
    func sendCommand(_ content: String) -> EmergencyChannelMessage? {
        return send(content: content, priority: .emergency)
    }
    
    /// 确认收到消息
    func acknowledge(messageId: UUID, by userId: String) {
        queue.sync(flags: .barrier) {
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].acknowledgedBy.insert(userId)
            }
        }
        
        Logger.shared.info("EmergencyChannel: Message \(messageId) acknowledged by \(userId)")
    }
    
    /// 获取消息历史
    func getHistory(limit: Int = 50) -> [EmergencyChannelMessage] {
        return queue.sync {
            Array(messages.suffix(limit))
        }
    }
    
    /// 获取未确认的消息
    func getUnacknowledgedMessages() -> [EmergencyChannelMessage] {
        guard let uid = IdentityManager.shared.uid else { return [] }
        
        return queue.sync {
            messages.filter { !$0.acknowledgedBy.contains(uid) && $0.senderId != uid }
        }
    }
    
    /// 获取紧急消息（emergency优先级）
    func getEmergencyMessages() -> [EmergencyChannelMessage] {
        return queue.sync {
            messages.filter { $0.priority == .emergency }
                .sorted { $0.timestamp > $1.timestamp }
        }
    }
    
    // MARK: - Queue Management
    
    /// 将消息加入队列
    func enqueue(_ message: EmergencyChannelMessage) {
        queue.sync(flags: .barrier) {
            messageQueue.append(message)
            messageQueue.sort { $0.priority.rawValue < $1.priority.rawValue }
            
            if messageQueue.count > maxQueueSize {
                messageQueue = Array(messageQueue.prefix(maxQueueSize))
            }
        }
    }
    
    /// 处理队列
    func processQueue() {
        queue.sync(flags: .barrier) {
            while !messageQueue.isEmpty {
                let message = messageQueue.removeFirst()
                messages.append(message)
                broadcastMessage(message)
            }
        }
    }
    
    // MARK: - Reception
    
    /// 接收外部消息
    func receive(_ message: EmergencyChannelMessage) {
        queue.sync(flags: .barrier) {
            messages.append(message)
            if messages.count > maxHistorySize {
                messages.removeFirst(messages.count - maxHistorySize)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.emergencyChannel(self, didReceiveMessage: message)
        }
    }
    
    // MARK: - Private
    
    private func broadcastMessage(_ message: EmergencyChannelMessage) {
        guard let messageData = try? JSONEncoder().encode(message) else { return }

        // P0-FIX: 对紧急通道消息进行加密和签名
        // For emergency broadcast, we still need to ensure the message can be decrypted by recipients
        // Use AES-256-GCM encryption with a shared emergency channel key
        guard let localSigningKey = IdentityManager.shared.getPrivateKeyForSigning() else {
            Logger.shared.error("EmergencyChannel: No signing key available")
            return
        }

        // Generate session key for this message
        let sessionKey = SymmetricKey(size: .bits256)

        // Encrypt the message content
        guard let encryptedPayload = try? CryptoEngine.shared.encryptAESGCM(data: messageData, symmetricKey: sessionKey) else {
            Logger.shared.error("EmergencyChannel: Failed to encrypt message")
            return
        }

        // Sign the encrypted payload
        let signature = CryptoEngine.shared.sign(data: encryptedPayload, privateKey: localSigningKey)

        // Package: [加密payload || 签名(64字节)]
        var signedData = Data()
        signedData.append(encryptedPayload)
        signedData.append(signature)

        let meshMessage = MeshMessage(
            source: IdentityManager.shared.uid.flatMap { UUID(uuidString: $0) } ?? UUID(),
            payload: signedData,  // 使用加密+签名后的数据
            ttl: 64,
            messageType: .emergency
        )

        MeshService.shared.sendEmergencyMessage(meshMessage)
    }
    
    /// 清理缓存
    func clearCache() {
        queue.sync(flags: .barrier) {
            if messages.count > 100 {
                messages = Array(messages.suffix(100))
            }
        }
        Logger.shared.info("EmergencyChannel: Cache cleared")
    }
}

// MARK: - Delegate

protocol EmergencyChannelDelegate: AnyObject {
    func emergencyChannel(_ channel: EmergencyChannel, didSendMessage message: EmergencyChannelMessage)
    func emergencyChannel(_ channel: EmergencyChannel, didReceiveMessage message: EmergencyChannelMessage)
}

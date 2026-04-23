import Foundation

// MARK: - User Status Manager

/// 用户状态管理器
final class UserStatusManager {
    static let shared = UserStatusManager()
    
    private(set) var currentStatus: UserStatus = .available
    private var peerStatuses: [String: UserStatus] = [:]
    private var statusBroadcastTimer: Timer?
    private let queue = DispatchQueue(label: "com.summerspark.userstatus", attributes: .concurrent)
    
    private let broadcastInterval: TimeInterval = 30.0  // 状态广播间隔
    
    weak var delegate: UserStatusManagerDelegate?
    
    private init() {}
    
    // MARK: - Current User Status
    
    /// 设置当前用户状态
    func setStatus(_ status: UserStatus) {
        let previousStatus = currentStatus
        currentStatus = status
        
        // 立即广播状态变更
        broadcastStatus()
        
        // 如果是紧急状态，触发紧急通知
        if status == .emergency && previousStatus != .emergency {
            triggerEmergencyNotification()
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.userStatusManager(self, didChangeStatus: status, from: previousStatus)
        }
        
        Logger.shared.info("UserStatusManager: Status changed from \(previousStatus.rawValue) to \(status.rawValue)")
    }
    
    /// 进入救援模式
    func enterRescueMode() {
        setStatus(.inRescue)
    }
    
    /// 退出救援模式
    func exitRescueMode() {
        setStatus(.available)
    }
    
    /// 激活紧急求助状态
    func activateEmergency() {
        setStatus(.emergency)
    }
    
    /// 解除紧急状态
    func deactivateEmergency() {
        setStatus(.available)
    }
    
    /// 获取当前状态
    func getCurrentStatus() -> UserStatus {
        return currentStatus
    }
    
    // MARK: - Peer Status
    
    /// 接收其他用户状态
    func receiveStatus(_ broadcast: UserStatusBroadcast) {
        queue.sync(flags: .barrier) {
            peerStatuses[broadcast.userId] = broadcast.status
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.userStatusManager(self, didReceiveStatus: broadcast.status, from: broadcast.userId)
        }
    }
    
    /// 获取用户状态
    func getStatus(for userId: String) -> UserStatus? {
        return queue.sync { peerStatuses[userId] }
    }
    
    /// 获取所有用户状态
    func getAllPeerStatuses() -> [String: UserStatus] {
        return queue.sync { peerStatuses }
    }
    
    /// 获取紧急求助的用户
    func getUsersNeedingHelp() -> [String] {
        return queue.sync {
            peerStatuses.filter { $0.value == .emergency || $0.value == .needHelp }
                .map { $0.key }
        }
    }
    
    /// 获取可用的用户
    func getAvailableUsers() -> [String] {
        return queue.sync {
            peerStatuses.filter { $0.value == .available }
                .map { $0.key }
        }
    }
    
    /// 获取正在救援的用户
    func getRescuingUsers() -> [String] {
        return queue.sync {
            peerStatuses.filter { $0.value == .inRescue }
                .map { $0.key }
        }
    }
    
    // MARK: - Broadcasting
    
    /// 开始定期广播状态
    func startStatusBroadcast() {
        stopStatusBroadcast()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusBroadcastTimer = Timer.scheduledTimer(withTimeInterval: self.broadcastInterval, repeats: true) { [weak self] _ in
                self?.broadcastStatus()
            }
        }
        
        // 立即广播一次
        broadcastStatus()
        
        Logger.shared.info("UserStatusManager: Started status broadcast")
    }
    
    /// 停止状态广播
    func stopStatusBroadcast() {
        DispatchQueue.main.async { [weak self] in
            self?.statusBroadcastTimer?.invalidate()
            self?.statusBroadcastTimer = nil
        }
    }
    
    /// 广播当前状态
    func broadcastStatus() {
        let location = LocationManager.shared.currentLocation
        let broadcast = UserStatusBroadcast(status: currentStatus, location: location)
        
        guard let broadcastData = try? JSONEncoder().encode(broadcast) else { return }
        
        let message = MeshMessage(
            source: IdentityManager.shared.uid.flatMap { UUID(uuidString: $0) } ?? UUID(),
            payload: broadcastData,
            ttl: 64,
            messageType: .broadcast
        )
        
        MeshService.shared.sendMessage(message)
    }
    
    // MARK: - Private
    
    private func triggerEmergencyNotification() {
        // 通知紧急联系人
        let contacts = ContactPriority.shared.getEmergencyContacts()
        for contact in contacts where contact.notifyOnEmergency {
            // 发送紧急通知
            Logger.shared.info("UserStatusManager: Notifying emergency contact \(contact.contactId)")
        }
    }
    
    /// 清理过期状态
    func cleanupStaleStatuses() {
        // TODO: 根据最后接收时间清理过期状态
    }
}

// MARK: - Delegate

protocol UserStatusManagerDelegate: AnyObject {
    func userStatusManager(_ manager: UserStatusManager, didChangeStatus status: UserStatus, from previous: UserStatus)
    func userStatusManager(_ manager: UserStatusManager, didReceiveStatus status: UserStatus, from userId: String)
}

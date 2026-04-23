import Foundation

// MARK: - Victim Status

/// 伤员状态
enum VictimStatus: String, Codable {
    case reported = "reported"      // 刚报告，未确认
    case acknowledged = "acknowledged"  // 已确认，等待救援
    case responding = "responding"    // 救援人员正在前往
    case rescued = "rescued"       // 已成功救出
    case deceased = "deceased"      // 已确认遇难
    case cancelled = "cancelled"     // 误报取消
    
    // P0-FIX: 国际化显示名称
    var displayName: String {
        switch self {
        case .reported: return "victim_status_reported".localized
        case .acknowledged: return "victim_status_acknowledged".localized
        case .responding: return "victim_status_responding".localized
        case .rescued: return "victim_status_rescued".localized
        case .deceased: return "victim_status_deceased".localized
        case .cancelled: return "victim_status_cancelled".localized
        }
    }
}

// MARK: - Victim Marker

/// 伤员标记
struct VictimMarker: Codable, Identifiable {
    let id: UUID
    let location: LocationData
    let severity: Severity
    var status: VictimStatus
    let reportedBy: String
    var assignedResponder: String?
    let reportedAt: Date
    var updatedAt: Date
    var notes: String?
    var injuryDescription: String?
    
    init(location: LocationData, severity: Severity, reportedBy: String, notes: String? = nil) {
        self.id = UUID()
        self.location = location
        self.severity = severity
        self.status = .reported
        self.reportedBy = reportedBy
        self.assignedResponder = nil
        self.reportedAt = Date()
        self.updatedAt = Date()
        self.notes = notes
        self.injuryDescription = nil
    }
}

// MARK: - Victim Marker Manager

/// 伤员标记管理器
final class VictimMarkerManager {
    static let shared = VictimMarkerManager()
    
    private var markers: [UUID: VictimMarker] = [:]
    private let queue = DispatchQueue(label: "com.summerspark.victimmarker", attributes: .concurrent)
    
    weak var delegate: VictimMarkerManagerDelegate?
    
    private init() {}
    
    // MARK: - Public API
    
    /// 标记伤员
    func markVictim(location: LocationData, severity: Severity, notes: String? = nil) -> VictimMarker? {
        guard let uid = IdentityManager.shared.uid else { return nil }
        
        // P0-FIX: 权限验证 - 检查用户信任等级
        let trustScore = TrustNetwork.shared.getTrustScore(for: uid)
        guard trustScore >= Constants.minimumTrustScoreForVictimMarking else {
            Logger.shared.warning("VictimMarker: User \(uid) has insufficient trust score: \(trustScore)")
            return nil
        }
        
        let marker = VictimMarker(location: location, severity: severity, reportedBy: uid, notes: notes)
        
        queue.sync(flags: .barrier) {
            markers[marker.id] = marker
        }
        
        // 广播伤员标记
        broadcastMarker(marker)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.victimMarkerManager(self, didAddMarker: marker)
        }
        
        Logger.shared.info("VictimMarker: Marked victim at \(location.latitude), \(location.longitude), severity: \(severity.rawValue)")
        return marker
    }
    
    /// 更新伤员状态
    func updateStatus(markerId: UUID, status: VictimStatus) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var marker = markers[markerId] else { return false }
            guard let uid = IdentityManager.shared.uid else { return false }
            
            // P0-FIX: 敏感状态变更需要特殊权限
            if status == .deceased || status == .rescued {
                // 只有医疗员或救援队长可以标记已遇难/已救出
                let hasPermission = RescueCoordinator.shared.isMedicalStaff(uid) ||
                                   RescueCoordinator.shared.isTeamLeader(uid)
                guard hasPermission else {
                    Logger.shared.warning("VictimMarker: User \(uid) not authorized to set status \(status.rawValue)")
                    return false
                }
            }
            
            // P0-FIX: 记录状态变更审计日志
            let auditEntry = StatusAuditEntry(
                markerId: markerId,
                oldStatus: marker.status,
                newStatus: status,
                changedBy: uid,
                timestamp: Date()
            )
            recordAuditEntry(auditEntry)
            
            marker.status = status
            marker.updatedAt = Date()
            markers[markerId] = marker
            
            Logger.shared.info("VictimMarker: Updated marker \(markerId) status to \(status.rawValue)")
            return true
        }
    }
    
    // P0-FIX: 审计日志结构
    private struct StatusAuditEntry: Codable {
        let markerId: UUID
        let oldStatus: VictimStatus
        let newStatus: VictimStatus
        let changedBy: String
        let timestamp: Date
    }
    
    private var auditLog: [StatusAuditEntry] = []
    private let auditLock = NSLock()
    
    private func recordAuditEntry(_ entry: StatusAuditEntry) {
        auditLock.lock()
        auditLog.append(entry)
        // 保留最近1000条审计记录
        if auditLog.count > 1000 {
            auditLog.removeFirst(auditLog.count - 1000)
        }
        auditLock.unlock()
    }
    
    /// 指派救援人员
    func assignResponder(markerId: UUID, responderId: String) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var marker = markers[markerId] else { return false }
            
            marker.assignedResponder = responderId
            marker.status = .responding
            marker.updatedAt = Date()
            markers[markerId] = marker
            
            Logger.shared.info("VictimMarker: Assigned responder \(responderId) to marker \(markerId)")
            return true
        }
    }
    
    /// 获取所有伤员标记
    func getAllMarkers() -> [VictimMarker] {
        return queue.sync { Array(markers.values) }
    }
    
    /// 获取附近伤员
    func getNearbyVictims(center: LocationData, radius: Double) -> [VictimMarker] {
        return queue.sync {
            markers.values.filter { marker in
                let distance = center.clLocation.distance(from: marker.location.clLocation)
                return distance <= radius
            }
        }
    }
    
    /// 获取指定状态的伤员
    func getMarkersByStatus(_ status: VictimStatus) -> [VictimMarker] {
        return queue.sync {
            markers.values.filter { $0.status == status }
        }
    }
    
    /// 清除已解决的伤员标记
    func clearResolvedMarkers() {
        queue.sync(flags: .barrier) {
            markers = markers.filter { 
                $0.value.status != .rescued && $0.value.status != .deceased && $0.value.status != .cancelled
            }
        }
        Logger.shared.info("VictimMarker: Cleared resolved markers")
    }
    
    // MARK: - Private
    
    private func broadcastMarker(_ marker: VictimMarker) {
        guard let markerData = try? JSONEncoder().encode(marker) else { return }
        
        let message = MeshMessage(
            source: IdentityManager.shared.uid.flatMap { UUID(uuidString: $0) } ?? UUID(),
            payload: markerData,
            ttl: 64,
            messageType: .emergency
        )
        
        MeshService.shared.sendEmergencyMessage(message)
    }
    
    /// 接收外部伤员标记
    func receiveMarker(_ marker: VictimMarker) {
        queue.sync(flags: .barrier) {
            markers[marker.id] = marker
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.victimMarkerManager(self, didAddMarker: marker)
        }
    }
}

// MARK: - Delegate

protocol VictimMarkerManagerDelegate: AnyObject {
    func victimMarkerManager(_ manager: VictimMarkerManager, didAddMarker marker: VictimMarker)
    func victimMarkerManager(_ manager: VictimMarkerManager, didUpdateMarker marker: VictimMarker)
}

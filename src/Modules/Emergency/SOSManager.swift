import Foundation
import CoreLocation

// MARK: - SOSManagerDelegate

/// Delegate protocol for SOS Manager events
protocol SOSManagerDelegate: AnyObject {
    /// SOS was triggered
    func sosManager(_ manager: SOSManager, didTriggerSOS sos: EmergencySOS)
    
    /// SOS status changed
    func sosManager(_ manager: SOSManager, didUpdateSOSStatus sos: EmergencySOS)
    
    /// Received SOS from another node
    func sosManager(_ manager: SOSManager, didReceiveSOS sos: EmergencySOS)
    
    /// SOS was cancelled
    func sosManager(_ manager: SOSManager, didCancelSOS sos: EmergencySOS)
    
    /// SOS beacon update
    func sosManager(_ manager: SOSManager, didUpdateBeaconLocation location: LocationData)
}

// MARK: - SOSManager

/// SOS Emergency Manager
/// Handles SOS triggering, broadcasting, and receiving
final class SOSManager {
    
    // MARK: - Singleton
    
    static let shared = SOSManager()
    
    // MARK: - Properties
    
    weak var delegate: SOSManagerDelegate?
    
    /// Current active SOS (if any)
    private(set) var activeSOS: EmergencySOS?
    
    /// All received SOS signals
    private(set) var receivedSOS: [String: EmergencySOS] = [:]
    
    /// SOS confirmation state
    private var confirmationProgress: Float = 0.0
    
    /// Long press timer for SOS confirmation
    private var confirmationTimer: Timer?
    
    /// Required hold duration for SOS trigger (seconds)
    let confirmationDuration: TimeInterval = 3.0
    
    /// Beacon broadcast timer
    private var beaconTimer: Timer?
    
    /// Beacon interval (seconds)
    let beaconInterval: TimeInterval = 10.0
    
    /// Whether SOS system is active
    private(set) var isEnabled: Bool = false
    
    /// Operation queue for thread safety
    private let sosQueue = DispatchQueue(label: "com.summerspark.sosmanager", qos: .userInitiated)
    
    /// Device battery level (0-1)
    private var batteryLevel: Float {
        return UIDevice.current.batteryLevel
    }
    
    /// Signal strength (RSSI approximation)
    private var signalStrength: Int {
        // Approximate based on mesh node count
        let nodeCount = MeshService.shared.discoveredNodes.count
        return min(0, -100 + nodeCount * 5)
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNotifications()
    }
    
    deinit {
        stopConfirmationTimer()
        stopBeaconTimer()
    }
    
    // MARK: - Public API
    
    /// Enable the SOS system
    func enable() {
        sosQueue.async { [weak self] in
            guard let self = self else { return }
            self.isEnabled = true
            Logger.shared.info("SOSManager: Enabled")
        }
    }
    
    /// Disable the SOS system
    func disable() {
        sosQueue.async { [weak self] in
            guard let self = self else { return }
            self.isEnabled = false
            self.stopBeaconTimer()
            Logger.shared.info("SOSManager: Disabled")
        }
    }
    
    /// Start SOS confirmation process (call on button press)
    /// - Parameters:
    ///   - type: Emergency type
    ///   - severity: Severity level
    ///   - message: Optional message
    func startConfirmation(type: EmergencyType, severity: Severity, message: String? = nil) {
        sosQueue.async { [weak self] in
            guard let self = self, self.isEnabled else { return }
            
            // Cancel any existing confirmation
            self.stopConfirmationTimer()
            
            // Reset progress
            self.confirmationProgress = 0.0
            
            // Start timer for confirmation
            DispatchQueue.main.async {
                self.confirmationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    
                    self.sosQueue.async {
                        self.confirmationProgress += Float(0.1 / self.confirmationDuration)
                        
                        if self.confirmationProgress >= 1.0 {
                            timer.invalidate()
                            self.triggerSOS(type: type, severity: severity, message: message)
                        }
                    }
                }
            }
            
            Logger.shared.info("SOSManager: Confirmation started for \(type.rawValue)")
        }
    }
    
    /// Cancel SOS confirmation (call on button release before completion)
    func cancelConfirmation() {
        sosQueue.async { [weak self] in
            guard let self = self else { return }
            self.stopConfirmationTimer()
            self.confirmationProgress = 0.0
            Logger.shared.info("SOSManager: Confirmation cancelled")
        }
    }
    
    /// Get current confirmation progress (0-1)
    func getConfirmationProgress() -> Float {
        return sosQueue.sync {
            confirmationProgress
        }
    }
    
    /// Trigger SOS immediately (bypasses confirmation)
    /// - Parameters:
    ///   - type: Emergency type
    ///   - severity: Severity level
    ///   - message: Optional message
    func triggerSOS(type: EmergencyType, severity: Severity, message: String? = nil) {
        sosQueue.async { [weak self] in
            guard let self = self, self.isEnabled else { return }
            
            // Check if already have active SOS
            if self.activeSOS != nil {
                Logger.shared.warning("SOSManager: Already have active SOS")
                return
            }
            
            // P0-FIX: 强制切换到活跃状态，确保低电量模式下SOS可用
            PowerSaveManager.shared.transitionTo(.active)
            
            // P0-FIX: 确保Mesh服务运行
            if !MeshService.shared.isRunning {
                MeshService.shared.start()
            }
            
            // Get current location with validation
            guard let location = LocationManager.shared.currentLocation else {
                Logger.shared.error("SOSManager: No location available for SOS")
                // P0-FIX: 通知代理位置不可用，让UI显示错误
                DispatchQueue.main.async {
                    self.delegate?.sosManager(self, didFailWithError: .locationUnavailable)
                }
                return
            }
            
            // P0-FIX: 验证位置有效性
            let validation = LocationManager.shared.validateLocation(location)
            if !validation.isValid {
                Logger.shared.warning("SOSManager: Location validation failed: \(validation.anomaly ?? "unknown")")
            }
            
            // Get sender info
            let senderId = IdentityManager.shared.uid ?? "unknown"
            let senderName = IdentityManager.shared.username
            
            // Create SOS
            let sos = EmergencySOS(
                senderId: senderId,
                senderName: senderName,
                type: type,
                severity: severity,
                location: location,
                message: message,
                batteryLevel: Double(self.batteryLevel),
                signalStrength: self.signalStrength
            )
            
            self.activeSOS = sos
            
            // Broadcast SOS
            self.broadcastSOS(sos)
            
            // Start beacon
            self.startBeacon()
            
            // Notify delegate
            DispatchQueue.main.async {
                self.delegate?.sosManager(self, didTriggerSOS: sos)
            }
            
            Logger.shared.info("SOSManager: SOS triggered - \(sos.id)")
        }
    }
    
    /// Cancel active SOS
    func cancelActiveSOS() {
        sosQueue.async { [weak self] in
            guard let self = self, var sos = self.activeSOS else { return }
            
            sos.status = .cancelled
            self.activeSOS = nil
            
            // Broadcast cancellation
            self.broadcastSOSCancellation(sos)
            
            // Stop beacon
            self.stopBeaconTimer()
            
            // Notify delegate
            DispatchQueue.main.async {
                self.delegate?.sosManager(self, didCancelSOS: sos)
            }
            
            Logger.shared.info("SOSManager: SOS cancelled - \(sos.id)")
        }
    }
    
    /// Update active SOS status
    /// - Parameter status: New status
    func updateSOSStatus(_ status: SOSStatus) {
        sosQueue.async { [weak self] in
            guard let self = self, var sos = self.activeSOS else { return }
            
            sos.status = status
            self.activeSOS = sos
            
            // Notify delegate
            DispatchQueue.main.async {
                self.delegate?.sosManager(self, didUpdateSOSStatus: sos)
            }
            
            Logger.shared.info("SOSManager: SOS status updated to \(status.rawValue)")
        }
    }
    
    /// Mark SOS as responded
    func markAsResponded() {
        updateSOSStatus(.responded)
    }
    
    /// Mark SOS as resolved
    func markAsResolved() {
        sosQueue.async { [weak self] in
            guard let self = self else { return }
            self.updateSOSStatus(.resolved)
            self.stopBeaconTimer()
            
            // Keep the SOS for history but clear active
            if let sos = self.activeSOS, sos.status == .resolved {
                // Could store to history here
                self.activeSOS = nil
            }
        }
    }
    
    /// Get all active SOS signals (own + received)
    func getAllActiveSOS() -> [EmergencySOS] {
        return sosQueue.sync {
            var allSOS: [EmergencySOS] = []
            
            if let active = activeSOS, active.status == .active {
                allSOS.append(active)
            }
            
            allSOS.append(contentsOf: receivedSOS.values.filter { $0.status == .active && !$0.isExpired })
            
            return allSOS.sorted { $0.severity > $1.severity }
        }
    }
    
    /// Get SOS by ID
    func getSOS(by id: String) -> EmergencySOS? {
        return sosQueue.sync {
            if activeSOS?.id == id {
                return activeSOS
            }
            return receivedSOS[id]
        }
    }
    
    /// Clean up expired SOS signals
    func cleanupExpiredSOS() {
        sosQueue.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            self.receivedSOS = self.receivedSOS.filter { !$0.value.isExpired }
            
            Logger.shared.info("SOSManager: Cleaned up expired SOS signals")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        // Listen for emergency messages from MeshService
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMeshMessage(_:)),
            name: .meshMessageReceived,
            object: nil
        )
    }
    
    @objc private func handleMeshMessage(_ notification: Notification) {
        guard let message = notification.userInfo?["message"] as? MeshMessage else { return }
        
        // Check if it's an emergency message
        if message.messageType == .emergency {
            handleEmergencyMessage(message)
        }
    }
    
    private func handleEmergencyMessage(_ message: MeshMessage) {
        guard let emergencyMessage = try? JSONDecoder().decode(EmergencyMessage.self, from: message.payload) else {
            return
        }
        
        switch emergencyMessage.type {
        case .sos:
            handleReceivedSOS(emergencyMessage)
        case .sosAck:
            handleSOSAcknowledgement(emergencyMessage)
        case .sosCancel:
            handleSOSCancellation(emergencyMessage)
        default:
            break
        }
    }
    
    private func handleReceivedSOS(_ message: EmergencyMessage) {
        // P0-FIX: 验证消息签名
        guard let verifiedData = CryptoEngine.shared.verify(message.payload, from: message.senderId) else {
            Logger.shared.warning("SOSManager: SOS signature verification failed from \(message.senderId)")
            AntiAttackGuard.shared.reportSuspiciousActivity(from: message.senderId, type: .invalidSignature)
            return
        }
        
        guard let sos = try? JSONDecoder().decode(EmergencySOS.self, from: verifiedData) else {
            Logger.shared.warning("SOSManager: Failed to decode SOS after verification")
            return
        }
        
        sosQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Don't process our own SOS
            if sos.senderId == IdentityManager.shared.uid {
                return
            }
            
            // P0-FIX: 验证位置合理性
            let locationValidation = LocationManager.shared.validateLocation(sos.location)
            if !locationValidation.isValid {
                Logger.shared.warning("SOSManager: SOS location suspicious: \(locationValidation.anomaly ?? "unknown")")
                // 仍然处理，但标记可疑
            }
            
            // Store received SOS
            self.receivedSOS[sos.id] = sos
            
            // Send acknowledgement
            self.sendSOSAcknowledgement(for: sos)
            
            // Notify delegate
            DispatchQueue.main.async {
                self.delegate?.sosManager(self, didReceiveSOS: sos)
            }
            
            Logger.shared.info("SOSManager: Received SOS from \(sos.senderId)")
        }
    }
    
    private func handleSOSAcknowledgement(_ message: EmergencyMessage) {
        // Could track who acknowledged our SOS
        Logger.shared.debug("SOSManager: Received SOS acknowledgement")
    }
    
    private func handleSOSCancellation(_ message: EmergencyMessage) {
        guard let sos = try? JSONDecoder().decode(EmergencySOS.self, from: message.payload) else {
            return
        }
        
        sosQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Update received SOS status
            if var receivedSOS = self.receivedSOS[sos.id] {
                receivedSOS.status = .cancelled
                self.receivedSOS[sos.id] = receivedSOS
            }
            
            Logger.shared.info("SOSManager: SOS cancelled by sender - \(sos.id)")
        }
    }
    
    private func broadcastSOS(_ sos: EmergencySOS) {
        guard let sosData = try? JSONEncoder().encode(sos) else {
            Logger.shared.error("SOSManager: Failed to encode SOS")
            return
        }
        
        // P0-FIX: 对SOS消息进行签名
        guard let signedData = CryptoEngine.shared.sign(sosData) else {
            Logger.shared.error("SOSManager: Failed to sign SOS")
            return
        }
        
        let emergencyMessage = EmergencyMessage(
            type: .sos,
            senderId: sos.senderId,
            priority: sos.priority,
            payload: signedData  // 使用签名后的数据
        )
        
        sendEmergencyMessage(emergencyMessage)
    }
    
    private func broadcastSOSCancellation(_ sos: EmergencySOS) {
        guard let sosData = try? JSONEncoder().encode(sos) else {
            return
        }
        
        let emergencyMessage = EmergencyMessage(
            type: .sosCancel,
            senderId: sos.senderId,
            priority: .command,
            payload: sosData
        )
        
        sendEmergencyMessage(emergencyMessage)
    }
    
    private func sendSOSAcknowledgement(for sos: EmergencySOS) {
        let ackData = Data([UInt8(sos.id.hashValue)])
        
        let emergencyMessage = EmergencyMessage(
            type: .sosAck,
            senderId: IdentityManager.shared.uid ?? "unknown",
            priority: .command,
            payload: ackData
        )
        
        sendEmergencyMessage(emergencyMessage)
    }
    
    private func sendEmergencyMessage(_ message: EmergencyMessage) {
        guard let messageData = try? JSONEncoder().encode(message) else {
            Logger.shared.error("SOSManager: Failed to encode emergency message")
            return
        }
        
        let meshMessage = MeshMessage(
            source: MeshService.shared.localNodeId,
            payload: messageData,
            ttl: 64,
            messageType: .emergency
        )
        
        MeshService.shared.sendMessage(meshMessage)
    }
    
    private func startBeacon() {
        stopBeaconTimer()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.beaconTimer = Timer.scheduledTimer(withTimeInterval: self.beaconInterval, repeats: true) { [weak self] _ in
                self?.broadcastBeacon()
            }
        }
    }
    
    private func broadcastBeacon() {
        sosQueue.async { [weak self] in
            guard let self = self, let sos = self.activeSOS, let location = LocationManager.shared.currentLocation else {
                return
            }
            
            // Notify delegate of beacon update
            DispatchQueue.main.async {
                self.delegate?.sosManager(self, didUpdateBeaconLocation: location)
            }
            
            // Broadcast updated location
            var updatedSOS = sos
            // Note: EmergencySOS is struct with let location, so we'd need to create a new one
            // For now, just log the beacon
            Logger.shared.debug("SOSManager: Beacon broadcast - location: \(location.latitude), \(location.longitude)")
        }
    }
    
    private func stopConfirmationTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.confirmationTimer?.invalidate()
            self?.confirmationTimer = nil
        }
    }
    
    private func stopBeaconTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.beaconTimer?.invalidate()
            self?.beaconTimer = nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let meshMessageReceived = Notification.Name("meshMessageReceived")
}

// MARK: - MeshMessageType Extension

extension MeshMessageType {
    static let emergency = MeshMessageType.broadcast
}

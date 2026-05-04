import Foundation
import Combine

// MARK: - Mesh Status Manager

/// Observable object managing mesh network status for UI updates
@available(iOS 13.0, *)
final class MeshStatusManager: ObservableObject {
    static let shared = MeshStatusManager()

    @Published var isConnected: Bool = false
    @Published var connectedNodes: Int = 0
    @Published var signalStrength: Int = 0
    @Published var currentMedium: MeshNode.TransportMedium = .bluetoothLE

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        // Subscribe to MeshService updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMeshUpdate(_:)),
            name: .meshStatusUpdated,
            object: nil
        )
    }

    @objc private func handleMeshUpdate(_ notification: Notification) {
        DispatchQueue.main.async {
            self.updateStatus()
        }
    }

    func updateStatus() {
        // Get status from MeshService
        let nodes = MeshService.shared.getActiveNodes()
        let connectionInfo = MeshService.shared.getConnectionInfo()

        self.connectedNodes = nodes.count
        self.isConnected = connectionInfo.isConnected
        self.signalStrength = connectionInfo.signalStrength
        self.currentMedium = connectionInfo.medium
    }
}

// MARK: - Emergency Manager

/// Observable object managing emergency/SOS state for UI updates
@available(iOS 13.0, *)
final class EmergencyManager: ObservableObject {
    static let shared = EmergencyManager()

    @Published var isSOSActive: Bool = false
    @Published var activeEmergency: EmergencySOS?
    @Published var emergencyStatus: SOSStatus = .inactive

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        // Subscribe to SOS manager updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSOSUpdate(_:)),
            name: .sosStatusChanged,
            object: nil
        )
    }

    @objc private func handleSOSUpdate(_ notification: Notification) {
        DispatchQueue.main.async {
            self.updateStatus()
        }
    }

    func updateStatus() {
        let sosManager = SOSManager.shared
        self.isSOSActive = sosManager.activeSOS != nil
        self.emergencyStatus = sosManager.isEnabled ? .active : .inactive
        self.activeEmergency = sosManager.activeSOS
    }

    func triggerSOS() {
        // Get current location
        let location = LocationManager.shared.currentLocation ?? LocationData(
            latitude: 0,
            longitude: 0,
            altitude: nil
        )

        // Trigger via SOSManager with proper parameters
        SOSManager.shared.triggerSOS(type: .other, severity: .critical, message: "Emergency SOS triggered")
        updateStatus()

        Logger.shared.info("[EmergencyManager] SOS triggered")
    }

    func cancelSOS() {
        SOSManager.shared.cancelActiveSOS()
        updateStatus()
        Logger.shared.info("[EmergencyManager] SOS cancelled")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let meshStatusUpdated = Notification.Name("meshStatusUpdated")
    static let sosStatusChanged = Notification.Name("sosStatusChanged")
}
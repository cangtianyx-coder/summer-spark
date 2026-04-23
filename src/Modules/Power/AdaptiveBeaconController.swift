// MARK: - Adaptive Beacon Controller
// 依赖文件：PowerSaveManager.swift
// 功能：自适应信标控制器

import Foundation
import CoreBluetooth

// MARK: - Adaptive Beacon Controller

public class AdaptiveBeaconController: NSObject {
    private var peripheralManager: CBPeripheralManager?
    private var isBroadcasting = false
    
    private var beaconConfig: BeaconConfiguration
    private var adaptiveInterval: TimeInterval
    private var currentPower: BeaconPower
    
    private var broadcastTimer: Timer?
    private var neighborCount = 0
    private var recentActivity = false
    
    private let controllerLock = NSLock()
    private var statistics: BeaconStatistics = BeaconStatistics(broadcasts: 0, reachability: 0, avgInterval: 0)
    
    public weak var delegate: AdaptiveBeaconDelegate?
    
    // MARK: - Initialization
    
    public init(config: BeaconConfiguration = BeaconConfiguration(
        baseInterval: 5.0,
        minInterval: 1.0,
        maxInterval: 60.0,
        txPower: -6,
        adaptiveEnabled: true
    )) {
        self.beaconConfig = config
        self.adaptiveInterval = config.baseInterval
        self.currentPower = .normal
        super.init()
    }
    
    deinit {
        broadcastTimer?.invalidate()
        broadcastTimer = nil
    }
    
    // MARK: - Broadcasting Control
    
    /// Start beacon broadcasting
    public func startBroadcasting(meshId: String, nodeId: String) {
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [
            CBPeripheralManagerOptionRestoreIdentifierKey: "com.summerspark.mesh.beacon"
        ])
        
        controllerLock.lock()
        isBroadcasting = true
        controllerLock.unlock()
        
        startAdaptiveBroadcast(meshId: meshId, nodeId: nodeId)
    }
    
    /// Stop beacon broadcasting
    public func stopBroadcasting() {
        controllerLock.lock()
        isBroadcasting = false
        controllerLock.unlock()
        
        broadcastTimer?.invalidate()
        broadcastTimer = nil
        
        peripheralManager?.stopAdvertising()
        peripheralManager = nil
    }
    
    // MARK: - Adaptive Broadcasting
    
    private func startAdaptiveBroadcast(meshId: String, nodeId: String) {
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: adaptiveInterval, repeats: true) { [weak self] _ in
            self?.broadcastBeacon(meshId: meshId, nodeId: nodeId)
        }
    }
    
    private func broadcastBeacon(meshId: String, nodeId: String) {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }
        
        controllerLock.lock()
        guard isBroadcasting else {
            controllerLock.unlock()
            return
        }
        controllerLock.unlock()
        
        // Build advertisement data
        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: "SS-\(nodeId.prefix(8))",
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "0x180D")],
            CBAdvertisementDataTxPowerLevelKey: currentPower.txPowerLevel
        ]
        
        manager.startAdvertising(advertisementData)
        
        // Update statistics
        statistics.broadcasts += 1
        
        // Schedule stop after short burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.peripheralManager?.stopAdvertising()
        }
        
        // Adjust interval based on conditions
        adjustBroadcastInterval()
    }
    
    // MARK: - Adaptive Adjustment
    
    /// Update neighbor count for adaptive adjustment
    public func updateNeighborCount(_ count: Int) {
        neighborCount = count
        adjustBroadcastInterval()
    }
    
    /// Mark recent activity
    public func markActivity() {
        recentActivity = true
        adjustBroadcastInterval()
        
        // Reset activity flag after interval
        DispatchQueue.main.asyncAfter(deadline: .now() + adaptiveInterval) { [weak self] in
            self?.recentActivity = false
        }
    }
    
    private func adjustBroadcastInterval() {
        guard beaconConfig.adaptiveEnabled else { return }
        
        var newInterval = beaconConfig.baseInterval
        
        // More neighbors = less frequent beaconing (we're already connected)
        if neighborCount > 5 {
            newInterval *= 1.5
        } else if neighborCount > 2 {
            newInterval *= 1.2
        } else if neighborCount == 0 {
            // No neighbors = more aggressive discovery
            newInterval *= 0.5
        }
        
        // Recent activity = faster beaconing
        if recentActivity {
            newInterval = min(newInterval, beaconConfig.minInterval * 2)
        }
        
        // Clamp to bounds
        newInterval = max(beaconConfig.minInterval, min(beaconConfig.maxInterval, newInterval))
        
        // Update if significantly different
        if abs(newInterval - adaptiveInterval) > 0.5 {
            adaptiveInterval = newInterval
            restartTimer()
            
            delegate?.adaptiveBeaconController(self, didAdjustInterval: newInterval, reason: determineAdjustmentReason())
        }
    }
    
    private func determineAdjustmentReason() -> String {
        if neighborCount == 0 { return "No neighbors" }
        if neighborCount > 5 { return "Many neighbors" }
        if recentActivity { return "Recent activity" }
        return "Normal adjustment"
    }
    
    private func restartTimer() {
        // Would restart the broadcast timer with new interval
        // Implementation depends on having meshId/nodeId stored
    }
    
    // MARK: - Power Control
    
    /// Set beacon power level
    public func setPowerLevel(_ power: BeaconPower) {
        currentPower = power
        delegate?.adaptiveBeaconController(self, didChangePower: power)
    }
    
    /// Adjust power based on battery level
    public func adjustPowerForBattery(_ batteryLevel: Double) {
        if batteryLevel < 0.1 {
            setPowerLevel(.ultraLow)
        } else if batteryLevel < 0.2 {
            setPowerLevel(.low)
        } else if batteryLevel < 0.5 {
            setPowerLevel(.reduced)
        } else {
            setPowerLevel(.normal)
        }
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> BeaconStatistics {
        return statistics
    }
    
    /// Update reachability metric
    public func updateReachability(_ value: Double) {
        statistics.reachability = value
    }
}

// MARK: - CBPeripheralManagerDelegate

extension AdaptiveBeaconController: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            delegate?.adaptiveBeaconController(self, didChangeState: .ready)
            
        case .poweredOff:
            delegate?.adaptiveBeaconController(self, didChangeState: .poweredOff)
            
        default:
            break
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // Handle state restoration
    }
}

// MARK: - Supporting Types

public struct BeaconConfiguration {
    let baseInterval: TimeInterval
    let minInterval: TimeInterval
    let maxInterval: TimeInterval
    let txPower: Int
    let adaptiveEnabled: Bool
}

public enum BeaconPower {
    case normal      // -6 dBm
    case reduced     // -12 dBm
    case low         // -20 dBm
    case ultraLow    // -30 dBm
    
    var txPowerLevel: NSNumber {
        switch self {
        case .normal: return -6
        case .reduced: return -12
        case .low: return -20
        case .ultraLow: return -30
        }
    }
}

public struct BeaconStatistics {
    var broadcasts: Int
    var reachability: Double
    var avgInterval: TimeInterval
}

public enum BeaconState {
    case unknown
    case ready
    case poweredOff
    case broadcasting
}

// MARK: - Adaptive Beacon Delegate

public protocol AdaptiveBeaconDelegate: AnyObject {
    func adaptiveBeaconController(_ controller: AdaptiveBeaconController, didAdjustInterval interval: TimeInterval, reason: String)
    func adaptiveBeaconController(_ controller: AdaptiveBeaconController, didChangePower power: BeaconPower)
    func adaptiveBeaconController(_ controller: AdaptiveBeaconController, didChangeState state: BeaconState)
}

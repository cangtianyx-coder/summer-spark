// MARK: - Background Mesh Listener
// 依赖文件：MeshRelayProtocols.swift, PowerSaveManager.swift
// 功能：BLE 后台 Mesh 监听

import Foundation
import CoreBluetooth

// MARK: - Background Mesh Listener

public class BackgroundMeshListener: NSObject, BackgroundMeshListenerProtocol {
    private var isScanning = false
    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    
    private var config: BackgroundListenerConfig
    private var scanTimer: Timer?
    private var discoveryWindow: [String: Date] = [:]
    
    private let listenerLock = NSLock()
    private var pendingPackets: [BackgroundPacket] = []
    
    public weak var delegate: BackgroundMeshListenerDelegate?
    
    // MARK: - Initialization
    
    public init(config: BackgroundListenerConfig = BackgroundListenerConfig(
        scanInterval: 30.0,
        scanDuration: 5.0,
        discoveryWindow: 300.0,
        adaptivePower: true,
        minimumSignalStrength: -80.0
    )) {
        self.config = config
        super.init()
    }
    
    public var isListening: Bool {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        return isScanning
    }
    
    // MARK: - Listening Control
    
    public func startListening() throws {
        listenerLock.lock()
        guard !isScanning else {
            listenerLock.unlock()
            return
        }
        listenerLock.unlock()
        
        // Initialize central manager
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "com.summerspark.mesh.background",
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        startPeriodicScan()
    }
    
    public func stopListening() {
        listenerLock.lock()
        isScanning = false
        listenerLock.unlock()
        
        scanTimer?.invalidate()
        scanTimer = nil
        
        centralManager?.stopScan()
        centralManager = nil
    }
    
    public func updateConfig(_ newConfig: BackgroundListenerConfig) {
        config = newConfig
        
        // Restart scanning with new config if active
        if isListening {
            stopListening()
            try? startListening()
        }
    }
    
    // MARK: - Scanning
    
    private func startPeriodicScan() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: config.scanInterval, repeats: true) { [weak self] _ in
            self?.performScan()
        }
        
        // Perform immediate first scan
        performScan()
    }
    
    private func performScan() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        
        listenerLock.lock()
        isScanning = true
        listenerLock.unlock()
        
        // Scan for mesh service UUID
        let serviceUUID = CBUUID(string: "0x180D") // Custom mesh service UUID
        let options = [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        
        central.scanForPeripherals(withServices: [serviceUUID], options: options)
        
        // Stop scan after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + config.scanDuration) { [weak self] in
            self?.stopScan()
        }
    }
    
    private func stopScan() {
        centralManager?.stopScan()
        
        listenerLock.lock()
        isScanning = false
        listenerLock.unlock()
    }
    
    // MARK: - Packet Handling
    
    public func handleBackgroundPacket(_ packet: Data, from nodeId: String) {
        let bgPacket = BackgroundPacket(
            data: packet,
            sourceId: nodeId,
            receivedAt: Date(),
            rssi: nil
        )
        
        listenerLock.lock()
        pendingPackets.append(bgPacket)
        listenerLock.unlock()
        
        delegate?.backgroundMeshListener(self, didReceivePacket: bgPacket)
    }
    
    /// Process pending packets
    public func processPendingPackets() -> [BackgroundPacket] {
        listenerLock.lock()
        let packets = pendingPackets
        pendingPackets.removeAll()
        listenerLock.unlock()
        
        return packets
    }
    
    // MARK: - Discovery Management
    
    private func handleDiscoveredPeripheral(_ peripheral: CBPeripheral, rssi: NSNumber) {
        let rssiValue = rssi.doubleValue
        
        // Filter by minimum signal strength
        guard rssiValue >= config.minimumSignalStrength else { return }
        
        let nodeId = peripheral.identifier.uuidString
        
        // Check discovery window
        if let lastDiscovery = discoveryWindow[nodeId] {
            if Date().timeIntervalSince(lastDiscovery) < config.discoveryWindow {
                // Already discovered recently
                return
            }
        }
        
        // Update discovery window
        discoveryWindow[nodeId] = Date()
        discoveredPeripherals[nodeId] = peripheral
        
        // Notify delegate
        delegate?.backgroundMeshListener(self, didDiscoverNode: nodeId, rssi: rssiValue)
        
        // Connect to receive data
        centralManager?.connect(peripheral, options: nil)
    }
    
    /// Get discovered nodes
    public func getDiscoveredNodes() -> [String: Date] {
        return discoveryWindow
    }
    
    /// Clear stale discoveries
    public func clearStaleDiscoveries() {
        let threshold = Date().addingTimeInterval(-config.discoveryWindow)
        discoveryWindow = discoveryWindow.filter { $0.value > threshold }
    }
}

// MARK: - CBCentralManagerDelegate

extension BackgroundMeshListener: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            delegate?.backgroundMeshListener(self, didChangeState: .ready)
            
        case .poweredOff:
            delegate?.backgroundMeshListener(self, didChangeState: .poweredOff)
            
        case .unauthorized:
            delegate?.backgroundMeshListener(self, didChangeState: .unauthorized)
            
        default:
            delegate?.backgroundMeshListener(self, didChangeState: .unknown)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        handleDiscoveredPeripheral(peripheral, rssi: RSSI)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Discover services to read mesh data
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Handle disconnection
        let nodeId = peripheral.identifier.uuidString
        delegate?.backgroundMeshListener(self, nodeDidDisconnect: nodeId)
    }
    
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Handle state restoration after background wake
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                discoveredPeripherals[peripheral.identifier.uuidString] = peripheral
            }
        }
    }
}

// MARK: - Supporting Types

public struct BackgroundPacket {
    let data: Data
    let sourceId: String
    let receivedAt: Date
    let rssi: Double?
}

public enum ListenerState {
    case unknown
    case ready
    case poweredOff
    case unauthorized
}

// MARK: - Background Mesh Listener Delegate

public protocol BackgroundMeshListenerDelegate: AnyObject {
    func backgroundMeshListener(_ listener: BackgroundMeshListener, didReceivePacket packet: BackgroundPacket)
    func backgroundMeshListener(_ listener: BackgroundMeshListener, didDiscoverNode nodeId: String, rssi: Double)
    func backgroundMeshListener(_ listener: BackgroundMeshListener, nodeDidDisconnect nodeId: String)
    func backgroundMeshListener(_ listener: BackgroundMeshListener, didChangeState state: ListenerState)
}

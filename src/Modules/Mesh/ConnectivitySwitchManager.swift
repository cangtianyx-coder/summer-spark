import Foundation
import Network

enum ConnectivityMedium: String, CaseIterable {
    case wifi = "WiFi"
    case ethernet = "Ethernet"
    case cellular = "Cellular"
    case mesh = "Mesh"
    
    var priority: Int {
        switch self {
        case .ethernet: return 0
        case .wifi: return 1
        case .mesh: return 2
        case .cellular: return 3
        }
    }
}

enum SwitchReason {
    case linkFailure
    case qualityDegradation
    case manualSwitch
    case autoOptimize
    case meshNodeChange
}

protocol ConnectivitySwitchManagerDelegate: AnyObject {
    func switchManager(_ manager: ConnectivitySwitchManager, didSwitchTo medium: ConnectivityMedium, reason: SwitchReason)
    func switchManager(_ manager: ConnectivitySwitchManager, didEncounterError error: Error)
    func switchManager(_ manager: ConnectivitySwitchManager, mediumStatusChanged status: [ConnectivityMedium: Bool])
}

final class ConnectivitySwitchManager {
    
    static let shared = ConnectivitySwitchManager()
    
    weak var delegate: ConnectivitySwitchManagerDelegate?
    
    private(set) var currentMedium: ConnectivityMedium = .wifi
    private var mediumStatuses: [ConnectivityMedium: Bool] = [:]
    private var linkMonitors: [ConnectivityMedium: NWConnection?] = [:]
    private let queue = DispatchQueue(label: "com.mesh.switchmanager", qos: .userInitiated)
    private var isMonitoring = false
    
    private let routeTable = RouteTable.shared
    private var wifiService: WiFiService?
    
    // P2-FIX: 网络分区检测
    private var reachableNodes: Set<String> = []
    private var unreachableRegions: Set<String> = []
    private var lastPartitionCheck: Date = Date()
    private let partitionCheckInterval: TimeInterval = 30.0
    private var partitionDetected = false
    
    private init() {
        setupInitialStatuses()
    }
    
    private func setupInitialStatuses() {
        for medium in ConnectivityMedium.allCases {
            mediumStatuses[medium] = false
        }
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        for medium in ConnectivityMedium.allCases {
            startLinkMonitor(for: medium)
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        for (medium, connection) in linkMonitors {
            connection?.cancel()
            linkMonitors[medium] = nil
        }
    }
    
    private func startLinkMonitor(for medium: ConnectivityMedium) {
        let monitor: NWConnection?
        
        switch medium {
        case .wifi:
            monitor = createWiFiMonitor()
        case .ethernet:
            monitor = createEthernetMonitor()
        case .cellular:
            monitor = createCellularMonitor()
        case .mesh:
            monitor = createMeshMonitor()
        }
        
        linkMonitors[medium] = monitor
        
        if let connection = monitor {
            connection.stateUpdateHandler = { [weak self] state in
                self?.handleLinkState(state, for: medium)
            }
            connection.start(queue: queue)
        }
    }
    
    private func createWiFiMonitor() -> NWConnection? {
        let params = NWParameters()
        params.requiredInterfaceType = .wifi
        return NWConnection(to: .hostPort(host: "8.8.8.8", port: 53), using: params)
    }
    
    private func createEthernetMonitor() -> NWConnection? {
        let params = NWParameters()
        params.requiredInterfaceType = .wiredEthernet
        return NWConnection(to: .hostPort(host: "8.8.8.8", port: 53), using: params)
    }
    
    private func createCellularMonitor() -> NWConnection? {
        let params = NWParameters()
        params.requiredInterfaceType = .cellular
        return NWConnection(to: .hostPort(host: "8.8.8.8", port: 53), using: params)
    }
    
    private func createMeshMonitor() -> NWConnection? {
        let params = NWParameters()
        params.requiredInterfaceType = .other
        return NWConnection(to: .hostPort(host: "10.0.0.1", port: 8080), using: params)
    }
    
    private func handleLinkState(_ state: NWConnection.State, for medium: ConnectivityMedium) {
        let isAvailable: Bool
        
        switch state {
        case .ready:
            isAvailable = true
        case .waiting, .preparing:
            isAvailable = mediumStatuses[medium] ?? false
        default:
            isAvailable = false
        }
        
        mediumStatuses[medium] = isAvailable
        delegate?.switchManager(self, mediumStatusChanged: mediumStatuses)
        
        if !isAvailable && medium == currentMedium {
            queue.async { [weak self] in
                self?.performSwitch(reason: .linkFailure)
            }
        }
    }
    
    func switchTo(_ medium: ConnectivityMedium, reason: SwitchReason = .manualSwitch) {
        guard medium != currentMedium else { return }
        
        queue.async { [weak self] in
            self?.performSwitchTo(medium, reason: reason)
        }
    }
    
    private func performSwitch(reason: SwitchReason) {
        let availableMediums = ConnectivityMedium.allCases
            .filter { mediumStatuses[$0] == true }
            .sorted { $0.priority < $1.priority }
        
        guard let bestMedium = availableMediums.first else {
            delegate?.switchManager(self, didEncounterError: ConnectivityError.noMediumAvailable)
            return
        }
        
        performSwitchTo(bestMedium, reason: reason)
    }
    
    private func performSwitchTo(_ medium: ConnectivityMedium, reason: SwitchReason) {
        guard mediumStatuses[medium] == true else {
            delegate?.switchManager(self, didEncounterError: ConnectivityError.mediumUnavailable)
            return
        }
        
        let previousMedium = currentMedium
        currentMedium = medium
        
        updateRouteTable(for: medium)
        reconfigureServices(from: previousMedium, to: medium)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.switchManager(self, didSwitchTo: medium, reason: reason)
        }
    }
    
    private func updateRouteTable(for medium: ConnectivityMedium) {
        routeTable.clearAllRoutes()
        
        let defaultRoute = RouteEntry(
            destination: "0.0.0.0",
            subnetMask: "0.0.0.0",
            gateway: gatewayForMedium(medium),
            interface: interfaceForMedium(medium),
            metric: medium.priority * 10,
            isEnabled: true
        )
        
        routeTable.addRoute(defaultRoute)
    }
    
    private func gatewayForMedium(_ medium: ConnectivityMedium) -> String {
        switch medium {
        case .wifi: return "192.168.1.1"
        case .ethernet: return "192.168.0.1"
        case .cellular: return "10.0.0.1"
        case .mesh: return "10.0.1.1"
        }
    }
    
    private func interfaceForMedium(_ medium: ConnectivityMedium) -> String {
        switch medium {
        case .wifi: return "en0"
        case .ethernet: return "en1"
        case .cellular: return "pdp_ip0"
        case .mesh: return "mesh0"
        }
    }
    
    private func reconfigureServices(from previous: ConnectivityMedium, to current: ConnectivityMedium) {
        if current == .mesh {
            startMeshService()
        } else if previous == .mesh {
            stopMeshService()
        }
    }
    
    private func startMeshService() {
        if wifiService == nil {
            wifiService = WiFiService(host: "0.0.0.0", port: 8080)
        }
        try? wifiService?.startListening()
    }
    
    private func stopMeshService() {
        wifiService?.stopListening()
    }
    
    func forceSwitch(to medium: ConnectivityMedium) {
        switchTo(medium, reason: .manualSwitch)
    }
    
    func getCurrentStatus() -> [ConnectivityMedium: Bool] {
        return mediumStatuses
    }
    
    func getPreferredMedium() -> ConnectivityMedium {
        let available = ConnectivityMedium.allCases
            .filter { mediumStatuses[$0] == true }
            .sorted { $0.priority < $1.priority }
        return available.first ?? currentMedium
    }
    
    // MARK: - P2-FIX: 网络分区检测
    
    /// 检测网络分区
    public func checkNetworkPartition(connectedNodes: [String]) {
        let now = Date()
        guard now.timeIntervalSince(lastPartitionCheck) >= partitionCheckInterval else { return }
        lastPartitionCheck = now
        
        // 更新可达节点集合
        reachableNodes = Set(connectedNodes)
        
        // 检测分区：如果可达节点数突然减少超过50%，可能发生分区
        let previousCount = reachableNodes.count
        let currentCount = connectedNodes.count
        
        if previousCount > 0 && currentCount < previousCount / 2 {
            partitionDetected = true
            Logger.shared.warn("ConnectivitySwitchManager: Network partition detected! Nodes: \(previousCount) -> \(currentCount)")
            
            // 标记不可达区域
            let unreachable = reachableNodes.subtracting(Set(connectedNodes))
            unreachableRegions = unreachable
            
            // 通知代理
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.switchManager(self, didEncounterError: ConnectivityError.noMediumAvailable)
            }
        } else if partitionDetected && currentCount >= previousCount {
            // 分区恢复
            partitionDetected = false
            unreachableRegions.removeAll()
            Logger.shared.info("ConnectivitySwitchManager: Network partition recovered")
        }
    }
    
    /// 检查节点是否在不可达区域
    public func isNodeInUnreachableRegion(_ nodeId: String) -> Bool {
        return unreachableRegions.contains(nodeId)
    }
    
    /// 获取当前分区状态
    public func getPartitionStatus() -> (detected: Bool, unreachableCount: Int) {
        return (partitionDetected, unreachableRegions.count)
    }
}

enum ConnectivityError: Error {
    case noMediumAvailable
    case mediumUnavailable
    case switchInProgress
    case configurationFailed
}
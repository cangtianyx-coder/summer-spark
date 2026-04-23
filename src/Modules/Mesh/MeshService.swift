import Foundation
import CoreBluetooth
import CryptoKit

// MARK: - MeshServiceDelegate

// MARK: - MeshService

final class MeshService {
    static let shared = MeshService()

    weak var delegate: MeshServiceDelegate?

    private(set) var localNodeId: UUID
    private(set) var discoveredNodes: [UUID: MeshNode] = [:]
    private(set) var isRunning: Bool = false

    private let bluetoothService: BluetoothService
    private let meshQueue = DispatchQueue(label: "com.mesh.service", qos: .userInitiated)
    private var nodeExpirationTimer: Timer?
    private let nodeExpirationInterval: TimeInterval = 30.0
    
    // 消息优先级队列
    private var messageQueue: [(message: MeshMessage, medium: MeshNode.TransportMedium?)] = []
    private let maxQueueSize = 100

    // MARK: - Initialization

    private init() {
        self.localNodeId = UUID()
        self.bluetoothService = BluetoothService()
        setupBluetoothCallbacks()
    }
    
    deinit {
        stopNodeExpirationMonitor()
    }

    // MARK: - Public API

    func start() {
        meshQueue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isRunning = true
            self.bluetoothService.startCentral()
            self.bluetoothService.startPeripheral()
            self.startNodeExpirationMonitor()
        }
    }

    func stop() {
        meshQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = false
            self.bluetoothService.stop()
            self.stopNodeExpirationMonitor()
            self.discoveredNodes.removeAll()
        }
    }

    func sendMessage(_ message: MeshMessage, via medium: MeshNode.TransportMedium? = nil) {
        meshQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 将消息加入队列
            self.enqueueMessage(message, medium: medium)
            
            // 处理队列中的消息
            self.processMessageQueue()
        }
    }
    
    /// 发送紧急消息（高优先级路由）
    func sendEmergencyMessage(_ message: MeshMessage, via medium: MeshNode.TransportMedium? = nil) {
        meshQueue.async { [weak self] in
            guard let self = self else { return }
            
            Logger.shared.warn("MeshService: Sending emergency message \(message.id)")
            
            // 紧急消息直接发送，使用最强信号路径
            let routingDecision = self.selectBestRoute(for: message, preferStrongestSignal: true)
            let selectedMedium = medium ?? routingDecision.preferredMedium
            
            switch selectedMedium {
            case .bluetoothLE:
                self.bluetoothService.broadcastMessage(message)
            case .wifi, .ethernet:
                break
            }
            
            Logger.shared.info("MeshService: Emergency message sent via \(selectedMedium.rawValue)")
        }
    }
    
    // MARK: - Message Queue Management
    
    private func enqueueMessage(_ message: MeshMessage, medium: MeshNode.TransportMedium?) {
        // 队列大小限制
        if messageQueue.count >= maxQueueSize {
            // 移除最低优先级的消息
            if let lowestIndex = messageQueue.indices.min(by: { messageQueue[$0].message.priority < messageQueue[$1].message.priority }) {
                messageQueue.remove(at: lowestIndex)
                Logger.shared.warn("MeshService: Queue full, dropped low priority message")
            }
        }
        
        messageQueue.append((message: message, medium: medium))
        Logger.shared.debug("MeshService: Message queued, priority=\(message.priority.displayName), queue size=\(messageQueue.count)")
    }
    
    private func processMessageQueue() {
        // 按优先级排序（高优先级在前）
        messageQueue.sort { $0.message.priority > $1.message.priority }
        
        // 处理队列中的消息
        while !messageQueue.isEmpty {
            let item = messageQueue.removeFirst()
            
            let routingDecision = selectBestRoute(for: item.message)
            let selectedMedium = item.medium ?? routingDecision.preferredMedium
            
            switch selectedMedium {
            case .bluetoothLE:
                bluetoothService.broadcastMessage(item.message)
            case .wifi, .ethernet:
                break
            }
        }
    }

    func discoveredNodes(ofType medium: MeshNode.TransportMedium) -> [MeshNode] {
        return discoveredNodes.values.filter { $0.supportedMedia.contains(medium) }
    }
    
    /// 清理缓存（内存警告时调用）
    func clearCache() {
        meshQueue.async { [weak self] in
            guard let self = self else { return }
            // 清理过期的节点缓存
            let now = Date()
            let threshold = self.nodeExpirationInterval * 2
            self.discoveredNodes = self.discoveredNodes.filter { 
                $0.value.lastSeen.distance(to: now) <= threshold 
            }
            Logger.shared.info("MeshService: Cache cleared, active nodes: \(self.discoveredNodes.count)")
        }
    }
    
    /// 执行路由维护（后台任务）
    func performRouteMaintenance() {
        meshQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 清理过期节点
            self.removeExpiredNodes()
            
            // 2. 优化路由表
            // 保留信号最强的节点
            let connectedNodes = self.discoveredNodes.values.filter { $0.connectionState == .connected }
            if connectedNodes.count > 10 {
                let sortedNodes = connectedNodes.sorted { $0.rssi > $1.rssi }
                let nodesToKeep = Set(sortedNodes.prefix(10).map { $0.id })
                self.discoveredNodes = self.discoveredNodes.filter { nodesToKeep.contains($0.key) }
            }
            
            Logger.shared.info("MeshService: Route maintenance completed, nodes: \(self.discoveredNodes.count)")
        }
    }

    // MARK: - Route Selection

    private func selectBestRoute(for message: MeshMessage, preferStrongestSignal: Bool = false) -> RoutingDecision {
        let candidates = discoveredNodes.values.filter { node in
            node.connectionState == .connected && message.ttl > 0
        }

        guard !candidates.isEmpty else {
            return RoutingDecision(
                preferredMedium: .bluetoothLE,
                estimatedLatency: Double.infinity,
                hopCount: 0,
                reliability: 0.0
            )
        }

        // 紧急消息优先选择最强信号路径
        let bestNode: MeshNode?
        if preferStrongestSignal || message.priority == .emergency {
            // 选择RSSI最强的节点
            bestNode = candidates.max(by: { $0.rssi < $1.rssi })
            Logger.shared.debug("MeshService: Selected strongest signal node for emergency message")
        } else {
            // 正常路由选择
            bestNode = candidates.max(by: { calculateRouteScore(for: $0) < calculateRouteScore(for: $1) })
        }
        
        guard let bestNode = bestNode else {
            return RoutingDecision(
                preferredMedium: .bluetoothLE,
                estimatedLatency: Double.infinity,
                hopCount: 0,
                reliability: 0.0
            )
        }

        let selectedMedium: MeshNode.TransportMedium = bestNode.supportedMedia.contains(.bluetoothLE) ? .bluetoothLE : .wifi

        return RoutingDecision(
            preferredMedium: selectedMedium,
            estimatedLatency: Double(bestNode.rssi) / -70.0,
            hopCount: 1,
            reliability: Double(bestNode.rssi + 100) / 100.0
        )
    }

    private func calculateRouteScore(for node: MeshNode) -> Double {
        let rssiWeight = 0.5
        let recencyWeight = 0.3
        let mediaWeight = 0.2

        let rssiScore = Double(max(0, min(100, node.rssi + 100))) / 100.0
        let ageScore = max(0, 1.0 - node.lastSeen.timeIntervalSinceNow / nodeExpirationInterval)
        let mediaScore = Double(node.supportedMedia.count) / Double(MeshNode.TransportMedium.allCases.count)

        return rssiWeight * rssiScore + recencyWeight * ageScore + mediaWeight * mediaScore
    }

    // MARK: - Node Discovery & Expiration

    private func discoverNode(from peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let nodeId = MeshNode.id(from: peripheral.identifier)
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let address = peripheral.identifier.uuidString

        let node = MeshNode(
            id: nodeId,
            name: name,
            lastSeen: Date(),
            rssi: rssi.intValue,
            connectionState: .disconnected,
            supportedMedia: [.bluetoothLE],
            address: address
        )

        discoveredNodes[nodeId] = node
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.meshService(self, didDiscoverNode: node)
        }
    }

    private func startNodeExpirationMonitor() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.nodeExpirationTimer = Timer.scheduledTimer(withTimeInterval: self.nodeExpirationInterval, repeats: true) { [weak self] _ in
                self?.removeExpiredNodes()
            }
        }
    }

    private func stopNodeExpirationMonitor() {
        nodeExpirationTimer?.invalidate()
        nodeExpirationTimer = nil
    }

    private func removeExpiredNodes() {
        meshQueue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let expiredIds = self.discoveredNodes.filter { $0.value.lastSeen.distance(to: now) > self.nodeExpirationInterval }.map { $0.key }

            for id in expiredIds {
                self.discoveredNodes.removeValue(forKey: id)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.meshService(self, didLoseNode: id)
                }
            }
        }
    }

    // MARK: - BluetoothService Callbacks

    private func setupBluetoothCallbacks() {
        bluetoothService.onDiscoveredPeripheral = { [weak self] peripheral, data, rssi in
            self?.meshQueue.async {
                self?.discoverNode(from: peripheral, advertisementData: data, rssi: rssi)
            }
        }

        bluetoothService.onReceivedData = { [weak self] data, peripheral in
            self?.meshQueue.async {
                self?.handleReceivedData(data, from: peripheral)
            }
        }

        bluetoothService.onConnectionStateChanged = { [weak self] peripheral, state in
            self?.meshQueue.async {
                self?.handleConnectionStateChange(peripheral: peripheral, state: state)
            }
        }
    }

    private func handleReceivedData(_ data: Data, from peripheral: CBPeripheral) {
        guard let message = try? JSONDecoder().decode(MeshMessage.self, from: data) else { return }
        let nodeId = MeshNode.id(from: peripheral.identifier)
        guard var node = discoveredNodes[nodeId] else { return }
        
        // 重放攻击检测
        let replayCheck = AntiAttackGuard.shared.replayAttackCheck(
            nonce: message.nonce,
            timestamp: message.timestamp,
            nodeId: nodeId.uuidString
        )
        
        if replayCheck.isReplay {
            // 检测到重放攻击，拒绝消息
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.meshService(self, didReceiveMessage: message, from: node)
        }
    }

    private func handleConnectionStateChange(peripheral: CBPeripheral, state: CBPeripheralState) {
        let nodeId = MeshNode.id(from: peripheral.identifier)
        guard var node = discoveredNodes[nodeId] else { return }

        switch state {
        case .connected:
            node.connectionState = .connected
        case .connecting:
            node.connectionState = .connecting
        case .disconnected:
            node.connectionState = .disconnected
        @unknown default:
            break
        }

        discoveredNodes[nodeId] = node
    }
    
    // P0-FIX: 获取指定节点的公钥
    /// Get public key for a specific node ID
    func getPublicKey(for nodeId: UUID) -> P256.Signing.PublicKey? {
        // 从已发现节点中获取公钥
        if let node = discoveredNodes[nodeId], let publicKey = node.publicKey {
            return publicKey
        }
        return nil
    }
}

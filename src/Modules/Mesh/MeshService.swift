import Foundation
import CoreBluetooth

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

    // MARK: - Initialization

    private init() {
        self.localNodeId = UUID()
        self.bluetoothService = BluetoothService()
        setupBluetoothCallbacks()
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

            let routingDecision = self.selectBestRoute(for: message)
            let selectedMedium = medium ?? routingDecision.preferredMedium

            switch selectedMedium {
            case .bluetoothLE:
                self.bluetoothService.broadcastMessage(message)
            case .wifi, .ethernet:
                break
            }
        }
    }

    func discoveredNodes(ofType medium: MeshNode.TransportMedium) -> [MeshNode] {
        return discoveredNodes.values.filter { $0.supportedMedia.contains(medium) }
    }

    // MARK: - Route Selection

    private func selectBestRoute(for message: MeshMessage) -> RoutingDecision {
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

        let bestNode = candidates.max { a, b in
            let scoreA = calculateRouteScore(for: a)
            let scoreB = calculateRouteScore(for: b)
            return scoreA < scoreB
        }!

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
}

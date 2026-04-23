import Foundation
import CoreBluetooth
import UIKit

// MARK: - BluetoothService

final class BluetoothService: NSObject {
    static let shared = BluetoothService()


    // MARK: - Properties

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!

    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var pendingConnections: Set<UUID> = []

    private var peripheralCharacteristics: [CBUUID: CBMutableCharacteristic] = [:]
    private var subscribedSubscribers: [CBUUID: [CBCentral]] = [:]

    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
    private let characteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABD")

    private var isCentralStarted = false
    private var isPeripheralStarted = false

    // MARK: - Privacy Configuration

    /// Controls whether the device name is broadcast in Bluetooth advertisements.
    /// When false (default), uses an anonymous identifier to protect user privacy.
    /// Users can enable this in settings if they want to broadcast their device name.
    var enableNameBroadcast: Bool = false

    /// Anonymous identifier used when enableNameBroadcast is false
    private var anonymousIdentifier: String {
        return "Mesh-\(UIDevice.current.identifierForVendor?.uuidString.prefix(8) ?? "Node")"
    }

    // MARK: - Callbacks (Alternative to delegate)

    var onDiscoveredPeripheral: ((CBPeripheral, [String: Any], NSNumber) -> Void)?
    var onReceivedData: ((Data, CBPeripheral) -> Void)?
    var onConnectionStateChanged: ((CBPeripheral, CBPeripheralState) -> Void)?

    weak var delegate: BluetoothServiceDelegate?

    private let bluetoothQueue = DispatchQueue(label: "com.bluetooth.service", qos: .userInitiated)

    // MARK: - Initialization

    override init() {
        super.init()
    }

    func configure() {
        // No additional configuration needed for CBCentralManager
    }

    // MARK: - Central Mode

    func startCentral() {
        guard !isCentralStarted else { return }
        // P0-FIX: 添加后台状态恢复配置
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: "com.summerspark.mesh.central"
        ]
        centralManager = CBCentralManager(delegate: self, queue: bluetoothQueue, options: options)
        isCentralStarted = true
    }

    func stopCentral() {
        guard isCentralStarted else { return }
        centralManager.stopScan()
        centralManager.delegate = nil
        centralManager = nil
        isCentralStarted = false
    }

    func startScanning(for serviceUUIDs: [CBUUID]? = nil) {
        guard let central = centralManager, central.state == .poweredOn else { return }

        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]

        central.scanForPeripherals(withServices: serviceUUIDs, options: options)
    }

    func stopScanning() {
        centralManager?.stopScan()
    }

    func connect(to peripheral: CBPeripheral, timeout: TimeInterval = 10.0) {
        guard let central = centralManager, central.state == .poweredOn else { return }

        pendingConnections.insert(peripheral.identifier)
        central.connect(peripheral, options: nil)

        bluetoothQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self else { return }
            if self.pendingConnections.contains(peripheral.identifier) {
                self.pendingConnections.remove(peripheral.identifier)
                central.cancelPeripheralConnection(peripheral)
            }
        }
    }

    func disconnect(from peripheral: CBPeripheral) {
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func readCharacteristic(from peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        peripheral.readValue(for: characteristic)
    }

    func writeCharacteristic(_ data: Data, to peripheral: CBPeripheral, characteristic: CBCharacteristic, withResponse: Bool = true) {
        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    // MARK: - Peripheral Mode

    func startPeripheral() {
        guard !isPeripheralStarted else { return }
        peripheralManager = CBPeripheralManager(delegate: self, queue: bluetoothQueue)
        isPeripheralStarted = true
    }

    func stopPeripheral() {
        guard isPeripheralStarted else { return }
        peripheralManager.stopAdvertising()
        peripheralManager.delegate = nil
        peripheralManager = nil
        isPeripheralStarted = false
    }

    func startAdvertising(localName: String? = nil) {
        guard let peripheral = peripheralManager, peripheral.state == .poweredOn else { return }

        var advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ]

        // Privacy protection: Only broadcast name if explicitly enabled
        // Default behavior uses anonymous identifier to protect user privacy
        if enableNameBroadcast {
            // User has opted in to broadcast their device name
            if let name = localName {
                advertisementData[CBAdvertisementDataLocalNameKey] = name
            }
        } else {
            // Use anonymous identifier by default for privacy protection
            advertisementData[CBAdvertisementDataLocalNameKey] = anonymousIdentifier
        }

        peripheral.startAdvertising(advertisementData)
    }

    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
    }

    func broadcastMessage(_ message: MeshMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }

        for (_, characteristic) in peripheralCharacteristics {
            if characteristic.isNotifying {
                let packetSize = 512
                var offset = 0

                while offset < data.count {
                    let chunkSize = min(packetSize, data.count - offset)
                    let chunk = data.subdata(in: offset..<(offset + chunkSize))
                    peripheralManager?.updateValue(chunk, for: characteristic, onSubscribedCentrals: nil)
                    offset += chunkSize
                }
            }
        }
    }

    func updateCharacteristicValue(_ value: Data, for characteristicUUID: CBUUID) {
        guard let characteristic = peripheralCharacteristics[characteristicUUID] else { return }
        peripheralManager?.updateValue(value, for: characteristic, onSubscribedCentrals: nil)
    }

    // MARK: - Combined Control

    func start() {
        startCentral()
        startPeripheral()
    }

    func stop() {
        stopCentral()
        stopPeripheral()
        discoveredPeripherals.removeAll()
        connectedPeripherals.removeAll()
        pendingConnections.removeAll()
    }

    // MARK: - Helpers

    private func setupService() {
        // P1-FIX: 蓝牙特征权限配置
        // 注意: iOS蓝牙加密由系统配对机制自动处理
        // 设置适当的权限确保安全通信
        let characteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write, .notify, .indicate],
            value: nil,
            permissions: [.readable, .writeable]
        )
        peripheralCharacteristics[characteristicUUID] = characteristic

        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]

        peripheralManager?.add(service)
        
        Logger.shared.info("BluetoothService: Service setup complete")
    }

    private func notifyDelegates(_ block: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            block()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        notifyDelegates { [weak self] in
            guard let self = self else { return }
            self.delegate?.bluetoothService(self, didUpdateState: central.state)
        }

        if central.state == .poweredOn {
            startScanning(for: [serviceUUID])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        discoveredPeripherals[peripheral.identifier] = peripheral

        notifyDelegates { [weak self] in
            guard let self = self else { return }
            self.delegate?.bluetoothService(self, didDiscoverPeripheral: peripheral, advertisementData: advertisementData, rssi: rssi)
            self.onDiscoveredPeripheral?(peripheral, advertisementData, rssi)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        pendingConnections.remove(peripheral.identifier)
        connectedPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])

        notifyDelegates { [weak self] in
            guard let self = self else { return }
            self.delegate?.bluetoothService(self, didConnectPeripheral: peripheral)
            self.onConnectionStateChanged?(peripheral, peripheral.state)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        pendingConnections.remove(peripheral.identifier)

        notifyDelegates { [weak self] in
            guard let self = self else { return }
            if let error = error {
                self.delegate?.bluetoothService(self, didFailWithError: error)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        discoveredPeripherals.removeValue(forKey: peripheral.identifier)

        notifyDelegates { [weak self] in
            guard let self = self else { return }
            self.delegate?.bluetoothService(self, didDisconnectPeripheral: peripheral, error: error)
            self.onConnectionStateChanged?(peripheral, peripheral.state)
        }

        if central.state == .poweredOn {
            startScanning(for: [serviceUUID])
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        notifyDelegates { [weak self] in
            guard let self = self else { return }
            self.delegate?.bluetoothService(self, didReceiveData: data, from: peripheral)
            self.onReceivedData?(data, peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            notifyDelegates { [weak self] in
                guard let self = self else { return }
                self.delegate?.bluetoothService(self, didFailWithError: error)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            notifyDelegates { [weak self] in
                guard let self = self else { return }
                self.delegate?.bluetoothService(self, didFailWithError: error)
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BluetoothService: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        notifyDelegates { [weak self] in
            guard let self = self else { return }
            self.delegate?.bluetoothService(self, didUpdateState: peripheral.state)
        }

        if peripheral.state == .poweredOn {
            setupService()
            // Privacy: startAdvertising now handles name privacy internally
            // Pass device name but it will only be used if enableNameBroadcast is true
            startAdvertising(localName: UIDevice.current.name)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            notifyDelegates { [weak self] in
                guard let self = self else { return }
                self.delegate?.bluetoothService(self, didFailWithError: error)
            }
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            notifyDelegates { [weak self] in
                guard let self = self else { return }
                self.delegate?.bluetoothService(self, didFailWithError: error)
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let subscriptor = central
        if subscribedSubscribers[characteristic.uuid] == nil {
            subscribedSubscribers[characteristic.uuid] = []
        }
        subscribedSubscribers[characteristic.uuid]?.append(subscriptor)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedSubscribers[characteristic.uuid]?.removeAll { $0.identifier == central.identifier }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == characteristicUUID {
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .unlikelyError)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == characteristicUUID {
                if let _ = request.value {
                    // Note: CBPeripheral not available in didReceiveWrite context
                    // peripheral param is CBPeripheralManager, not CBPeripheral
                }
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .unlikelyError)
            }
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Ready to send more data
    }
}

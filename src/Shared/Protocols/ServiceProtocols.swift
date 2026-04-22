import Foundation
import CoreBluetooth
import CryptoKit
import CoreLocation

// MARK: - Bluetooth Service Protocol

protocol BluetoothServiceProtocol: AnyObject {
    func startCentral()
    func stopCentral()
    func startPeripheral()
    func stopPeripheral()
    func startScanning(for serviceUUIDs: [CBUUID]?)
    func stopScanning()
    func connect(to peripheral: CBPeripheral, timeout: TimeInterval)
    func disconnect(from peripheral: CBPeripheral)
    func broadcastMessage(_ message: MeshMessage)
    func sendData(_ data: Data, to peripheral: CBPeripheral, characteristic: CBCharacteristic, withResponse: Bool)

    var onDiscoveredPeripheral: ((CBPeripheral, [String: Any], NSNumber) -> Void)? { get set }
    var onReceivedData: ((Data, CBPeripheral) -> Void)? { get set }
    var onConnectionStateChanged: ((CBPeripheral, CBPeripheralState) -> Void)? { get set }
    var onBluetoothStateChanged: ((CBManagerState) -> Void)? { get set }
}

// MARK: - Bluetooth Service Delegate

protocol BluetoothServiceDelegate: AnyObject {
    func bluetoothService(_ service: BluetoothService, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)
    func bluetoothService(_ service: BluetoothService, didConnectPeripheral peripheral: CBPeripheral)
    func bluetoothService(_ service: BluetoothService, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    func bluetoothService(_ service: BluetoothService, didReceiveData data: Data, from peripheral: CBPeripheral)
    func bluetoothService(_ service: BluetoothService, didUpdateState state: CBManagerState)
    func bluetoothService(_ service: BluetoothService, didFailWithError error: Error)
}

// MARK: - Mesh Service Protocol

protocol MeshServiceProtocol: AnyObject {
    func start()
    func stop()
    func sendMessage(_ message: MeshMessage, via medium: MeshNode.TransportMedium?)
    func discoveredNodes(ofType medium: MeshNode.TransportMedium) -> [MeshNode]

    var localNodeId: UUID { get }
    var discoveredNodes: [UUID: MeshNode] { get }
    var isRunning: Bool { get }
}

// MARK: - Mesh Service Delegate

protocol MeshServiceDelegate: AnyObject {
    func meshService(_ service: MeshService, didDiscoverNode node: MeshNode)
    func meshService(_ service: MeshService, didLoseNode nodeId: UUID)
    func meshService(_ service: MeshService, didReceiveMessage message: MeshMessage, from node: MeshNode)
    func meshService(_ service: MeshService, didUpdateRoute decision: RoutingDecision)
    func meshService(_ service: MeshService, didFailWithError error: Error)
}

// MARK: - WiFi Service Protocol

protocol WiFiServiceProtocol: AnyObject {
    func startHotspot(name: String) -> Bool
    func stopHotspot()
    func connectToNetwork(ssid: String, password: String) -> Bool
    func disconnectFromNetwork()
    func getCurrentConnections() -> [String]

    var isHotspotActive: Bool { get }
    var isConnectedToNetwork: Bool { get }
}

// MARK: - Identity Service Protocol

protocol IdentityServiceProtocol: AnyObject {
    func initialize()
    func regenerateIdentity()
    func setUsername(_ name: String)
    func getPrivateKey() -> P256.Signing.PrivateKey?
    func getPublicKey() -> P256.Signing.PublicKey?
    func getPublicKeyFingerprint() -> String?
    func exportPublicIdentity() -> [String: Any]
    func resetIdentity()

    var uid: String? { get }
    var username: String? { get }
    var isIdentityComplete: Bool { get }
}

// MARK: - Credit Service Protocol

protocol CreditServiceProtocol: AnyObject {
    func start()
    func stop()
    func getBalance() -> Double
    func getAccount() -> CreditAccount
    func earn(_ amount: Double, reason: String, context: [String: Any]) -> Bool
    func consume(_ amount: Double, reason: String, context: [String: Any]) -> Bool
    func applyDecay() -> Double
    func applyPenalty(_ amount: Double, reason: String) -> Bool
    func syncCredits() async throws

    var eventHistory: [CreditEvent] { get }
}

// MARK: - Storage Service Protocol

protocol StorageServiceProtocol: AnyObject {
    func setup()
    func save<T: Encodable>(_ value: T, forKey key: String)
    func load<T: Decodable>(forKey key: String, as type: T.Type) -> T?
    func remove(forKey key: String)
    func clearAll()

    func saveGroup(_ group: Group) -> Bool
    func getGroup(id: String) -> Group?
    func getAllGroups() -> [Group]
    func deleteGroup(id: String) -> Bool
}

// MARK: - Group Service Protocol

protocol GroupServiceProtocol: AnyObject {
    func createGroup(name: String) -> Group?
    func getGroup(id: String) -> Group?
    func updateGroupName(groupId: String, newName: String) -> Bool
    func deleteGroup(groupId: String) -> Bool
    func getMyGroups() -> [Group]

    func addMember(groupId: String, uid: String, role: GroupMember.GroupRole) -> Bool
    func removeMember(groupId: String, targetUid: String) -> Bool
    func updateMemberRole(groupId: String, targetUid: String, newRole: GroupMember.GroupRole) -> Bool
    func leaveGroup(groupId: String) -> Bool

    func getGroupMembers(groupId: String) -> [GroupMember]
    func isMember(groupId: String, uid: String) -> Bool
}

// MARK: - Voice Service Protocol

protocol VoiceServiceProtocol: AnyObject {
    func configure()
    func startSession()
    func endSession()
    func sendAudioData(_ data: Data)
    func setPushToTalkPressed(_ pressed: Bool)

    var isSessionActive: Bool { get }
    var isPushToTalkEnabled: Bool { get }
}

// MARK: - Map Service Protocol

protocol MapServiceProtocol: AnyObject {
    func configure()
    func startLocationUpdates()
    func stopLocationUpdates()
    func getCurrentLocation() -> LocationData?
    func downloadOfflineRegion(center: LocationData, radiusMeters: Double) async throws

    var currentLocation: LocationData? { get }
    var authorizationStatus: CLAuthorizationStatus { get }
}

// MARK: - Crypto Service Protocol

protocol CryptoServiceProtocol: AnyObject {
    func encrypt(data: Data, with key: SymmetricKey) throws -> EncryptedPackage
    func decrypt(package: EncryptedPackage, with key: SymmetricKey) throws -> Data
    func sign(data: Data, with privateKey: P256.Signing.PrivateKey) throws -> Data
    func verify(signature: Data, for data: Data, with publicKey: P256.Signing.PublicKey) -> Bool
    func generateSymmetricKey() -> SymmetricKey
}

// MARK: - Sync Service Protocol

protocol SyncServiceProtocol: AnyObject {
    func startSync()
    func stopSync()
    func performFullSync() async throws
    func getSyncState() -> SyncState

    var syncState: SyncState { get }
    var lastSyncTimestamp: Date? { get }
}
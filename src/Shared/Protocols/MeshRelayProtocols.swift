import Foundation

// MARK: - Map Relay Service Protocol
/// Protocol for map package relay over mesh network
protocol MapRelayServiceProtocol: AnyObject {
    var delegate: MapRelayDelegate? { get set }

    /// Start relaying map packages to neighbors
    func startRelaying()

    /// Stop relaying
    func stopRelaying()

    /// Broadcast available map packages to the mesh
    func broadcastMapAvailability(_ packages: [MapPackage])

    /// Request a specific map tile from the mesh
    func requestTile(_ tile: TileCoordinate, from sourceId: String)

    /// Serve a tile to requesting nodes
    func serveTile(_ tile: TileCoordinate, data: Data, via relayId: String)

    /// Check if a tile is available locally
    func hasTile(_ tile: TileCoordinate) -> Bool

    /// Get relay statistics
    func getRelayStats() -> MapRelayStats
}

// MARK: - Map Relay Delegate
protocol MapRelayDelegate: AnyObject {
    func mapRelay(_ service: MapRelayService, didReceiveTile tile: TileCoordinate, data: Data, from relayPath: [String])
    func mapRelay(_ service: MapRelayService, didUpdateProgress progress: RelayProgress)
    func mapRelay(_ service: MapRelayService, didCompletePackage packageId: String)
    func mapRelay(_ service: MapRelayService, didFailWithError error: Error)
}

// MARK: - Map Package
struct MapPackage: Codable, Identifiable {
    let id: String
    let name: String
    let regionName: String
    let minZoom: Int
    let maxZoom: Int
    let boundingBox: GeoRegion
    let totalTiles: Int
    let downloadedTiles: Int
    let fileSizeBytes: Int64
    let checksum: String
    let sourceNodeId: String
    let createdAt: Date

    var downloadProgress: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(downloadedTiles) / Double(totalTiles)
    }

    var isComplete: Bool {
        downloadedTiles >= totalTiles
    }
}

// MARK: - Tile Coordinate
struct TileCoordinate: Hashable, Codable {
    let x: Int
    let y: Int
    let zoom: Int

    var key: String { "\(zoom)/\(x)/\(y)" }
}

// MARK: - Tile Integrity
struct TileIntegrity: Codable {
    let coordinate: TileCoordinate
    let checksum: String
    let sizeBytes: Int
    let signature: Data?
    let verifiedAt: Date

    var isValid: Bool { verifiedAt > Date().addingTimeInterval(-3600) }
}

// MARK: - Relay Progress
struct RelayProgress: Codable {
    let packageId: String
    let phase: RelayPhase
    let tilesRelayed: Int
    let totalTiles: Int
    let bytesTransferred: Int64
    let currentRelays: [String]

    enum RelayPhase: String, Codable {
        case announcing
        case requesting
        case relaying
        case verifying
        case completed
    }
}

// MARK: - Map Relay Stats
struct MapRelayStats: Codable {
    let totalTilesServed: Int
    let totalTilesReceived: Int
    let totalBytesServed: Int64
    let totalBytesReceived: Int64
    let activeRelays: Int
    let cacheHitRate: Double
}

// MARK: - Tile Request
struct TileRequest: Codable {
    let requestId: String
    let tile: TileCoordinate
    let requesterId: String
    let timestamp: Date
    let ttl: Int

    var isExpired: Bool {
        ttl <= 0 || Date().timeIntervalSince(timestamp) > TimeInterval(ttl * 60)
    }
}

// MARK: - P2P Share Protocol
/// Protocol for peer-to-peer map package sharing
protocol MapPackageShareProtocol: AnyObject {
    /// Initiate sharing a package with a peer
    func initiateShare(packageId: String, to peerId: String)

    /// Accept incoming share
    func acceptShare(shareId: String)

    /// Reject incoming share
    func rejectShare(shareId: String)

    /// Cancel ongoing share
    func cancelShare(shareId: String)

    /// Get active shares
    func getActiveShares() -> [MapShareSession]
}

// MARK: - Map Share Session
struct MapShareSession: Codable, Identifiable {
    let id: String
    let packageId: String
    let peerId: String
    let direction: ShareDirection
    let state: ShareState
    let progress: Double
    let startedAt: Date

    enum ShareDirection: String, Codable {
        case uploading
        case downloading
    }

    enum ShareState: String, Codable {
        case negotiating
        case transferring
        case verifying
        case completed
        case failed
        case cancelled
    }
}

// MARK: - Background Mesh Listener Protocol
/// Protocol for background BLE mesh listening
protocol BackgroundMeshListenerProtocol: AnyObject {
    var isListening: Bool { get }

    /// Start background listening for mesh beacons
    func startListening() throws

    /// Stop background listening
    func stopListening()

    /// Handle incoming mesh packet while in background
    func handleBackgroundPacket(_ packet: Data, from nodeId: String)

    /// Update listener configuration
    func updateConfig(_ config: BackgroundListenerConfig)
}

// MARK: - Background Listener Config
struct BackgroundListenerConfig: Codable {
    let scanInterval: TimeInterval // seconds
    let scanDuration: TimeInterval // seconds
    let discoveryWindow: TimeInterval // seconds
    let adaptivePower: Bool
    let minimumSignalStrength: Double // dBm
}

// MARK: - Power State
enum PowerState: String, Codable {
    case active
    case lowPower
    case background
    case hibernation
}

// MARK: - Power Save Delegate
protocol PowerSaveDelegate: AnyObject {
    func powerSaveManager(_ manager: PowerSaveManager, didChangeState state: PowerState)
    func powerSaveManager(_ manager: PowerSaveManager, didUpdateBatteryLevel level: Double)
}

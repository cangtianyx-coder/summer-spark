import Foundation

// MARK: - Geo Region
public struct GeoRegion: Codable {
    public let minLat: Double
    public let maxLat: Double
    public let minLon: Double
    public let maxLon: Double
    
    public init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }
}

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

// MARK: - Map Relay Service (placeholder class for protocol)
public class MapRelayService {
    public init() {}
}

// MARK: - Map Relay Delegate
protocol MapRelayDelegate: AnyObject {
    func mapRelay(_ service: MapRelayService, didReceiveTile tile: TileCoordinate, data: Data, from relayPath: [String])
    func mapRelay(_ service: MapRelayService, didUpdateProgress progress: RelayProgress)
    func mapRelay(_ service: MapRelayService, didCompletePackage packageId: String)
    func mapRelay(_ service: MapRelayService, didFailWithError error: Error)
}

// MARK: - Map Package
public struct MapPackage: Codable, Identifiable {
    public let id: String
    public let name: String
    public let regionName: String
    public let minZoom: Int
    public let maxZoom: Int
    public let boundingBox: GeoRegion
    public let totalTiles: Int
    public let downloadedTiles: Int
    public let fileSizeBytes: Int64
    public let checksum: String
    public let sourceNodeId: String
    public let createdAt: Date

    public var downloadProgress: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(downloadedTiles) / Double(totalTiles)
    }

    public var isComplete: Bool {
        downloadedTiles >= totalTiles
    }
    
    public init(id: String, name: String, regionName: String, minZoom: Int, maxZoom: Int, boundingBox: GeoRegion, totalTiles: Int, downloadedTiles: Int, fileSizeBytes: Int64, checksum: String, sourceNodeId: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.regionName = regionName
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.boundingBox = boundingBox
        self.totalTiles = totalTiles
        self.downloadedTiles = downloadedTiles
        self.fileSizeBytes = fileSizeBytes
        self.checksum = checksum
        self.sourceNodeId = sourceNodeId
        self.createdAt = createdAt
    }
}

// MARK: - Tile Integrity
public struct TileIntegrity: Codable {
    public let coordinate: TileCoordinate
    public let checksum: String
    public let sizeBytes: Int
    public let signature: Data?
    public let verifiedAt: Date

    public var isValid: Bool { verifiedAt > Date().addingTimeInterval(-3600) }
    
    public init(coordinate: TileCoordinate, checksum: String, sizeBytes: Int, signature: Data?, verifiedAt: Date) {
        self.coordinate = coordinate
        self.checksum = checksum
        self.sizeBytes = sizeBytes
        self.signature = signature
        self.verifiedAt = verifiedAt
    }
}

// MARK: - Relay Progress
public struct RelayProgress: Codable {
    public let packageId: String
    public let phase: RelayPhase
    public let tilesRelayed: Int
    public let totalTiles: Int
    public let bytesTransferred: Int64
    public let currentRelays: [String]

    public enum RelayPhase: String, Codable {
        case announcing
        case requesting
        case relaying
        case verifying
        case completed
    }
    
    public init(packageId: String, phase: RelayPhase, tilesRelayed: Int, totalTiles: Int, bytesTransferred: Int64, currentRelays: [String]) {
        self.packageId = packageId
        self.phase = phase
        self.tilesRelayed = tilesRelayed
        self.totalTiles = totalTiles
        self.bytesTransferred = bytesTransferred
        self.currentRelays = currentRelays
    }
}

// MARK: - Map Relay Stats
public struct MapRelayStats: Codable {
    public let totalTilesServed: Int
    public let totalTilesReceived: Int
    public let totalBytesServed: Int64
    public let totalBytesReceived: Int64
    public let activeRelays: Int
    public let cacheHitRate: Double
    
    public init(totalTilesServed: Int, totalTilesReceived: Int, totalBytesServed: Int64, totalBytesReceived: Int64, activeRelays: Int, cacheHitRate: Double) {
        self.totalTilesServed = totalTilesServed
        self.totalTilesReceived = totalTilesReceived
        self.totalBytesServed = totalBytesServed
        self.totalBytesReceived = totalBytesReceived
        self.activeRelays = activeRelays
        self.cacheHitRate = cacheHitRate
    }
}

// MARK: - Tile Request
public struct TileRequest: Codable {
    public let requestId: String
    public let tile: TileCoordinate
    public let requesterId: String
    public let timestamp: Date
    public let ttl: Int

    public var isExpired: Bool {
        ttl <= 0 || Date().timeIntervalSince(timestamp) > TimeInterval(ttl * 60)
    }
    
    public init(requestId: String, tile: TileCoordinate, requesterId: String, timestamp: Date, ttl: Int) {
        self.requestId = requestId
        self.tile = tile
        self.requesterId = requesterId
        self.timestamp = timestamp
        self.ttl = ttl
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
public struct MapShareSession: Codable, Identifiable {
    public let id: String
    public let packageId: String
    public let peerId: String
    public let direction: ShareDirection
    public let state: ShareState
    public let progress: Double
    public let startedAt: Date

    public enum ShareDirection: String, Codable {
        case uploading
        case downloading
    }

    public enum ShareState: String, Codable {
        case negotiating
        case transferring
        case verifying
        case completed
        case failed
        case cancelled
    }
    
    public init(id: String, packageId: String, peerId: String, direction: ShareDirection, state: ShareState, progress: Double, startedAt: Date) {
        self.id = id
        self.packageId = packageId
        self.peerId = peerId
        self.direction = direction
        self.state = state
        self.progress = progress
        self.startedAt = startedAt
    }
}

// MARK: - Background Mesh Listener Protocol
/// Protocol for background BLE mesh listening
public protocol BackgroundMeshListenerProtocol: AnyObject {
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
public struct BackgroundListenerConfig: Codable {
    public let scanInterval: TimeInterval // seconds
    public let scanDuration: TimeInterval // seconds
    public let discoveryWindow: TimeInterval // seconds
    public let adaptivePower: Bool
    public let minimumSignalStrength: Double // dBm
    
    public init(scanInterval: TimeInterval, scanDuration: TimeInterval, discoveryWindow: TimeInterval, adaptivePower: Bool, minimumSignalStrength: Double) {
        self.scanInterval = scanInterval
        self.scanDuration = scanDuration
        self.discoveryWindow = discoveryWindow
        self.adaptivePower = adaptivePower
        self.minimumSignalStrength = minimumSignalStrength
    }
}

// MARK: - Power State
public enum PowerState: String, Codable {
    case active
    case lowPower
    case background
    case hibernation
}

// MARK: - Power Save Delegate
public protocol PowerSaveDelegate: AnyObject {
    func powerSaveManager(_ manager: PowerSaveManager, didChangeState state: PowerState)
    func powerSaveManager(_ manager: PowerSaveManager, didUpdateBatteryLevel level: Double)
}

import Foundation
import CoreLocation

// MARK: - Geographic Address
/// Represents a mesh node address based on geographic location
/// Used for Geocast routing (position-based addressing)
public struct GeoAddress: Hashable, Codable {
    public let nodeId: String
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let precision: Double // meters
    public let timestamp: Date

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public func distance(to other: GeoAddress) -> Double {
        let loc1 = CLLocation(latitude: latitude, longitude: longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}

// MARK: - Geocast Region
/// A geographic region for Geocast message delivery
public struct GeoRegion: Hashable, Codable {
    public let center: GeoAddress
    public let radiusMeters: Double

    public func contains(_ address: GeoAddress) -> Bool {
        center.distance(to: address) <= radiusMeters
    }

    public func intersects(_ other: GeoRegion) -> Bool {
        let distance = center.distance(to: other.center)
        return distance <= (radiusMeters + other.radiusMeters)
    }
}

// MARK: - Geocast Message
/// Message structure for geographic broadcast
public struct GeocastMessage: Codable {
    public let id: String
    public let sourceAddress: GeoAddress
    public let destinationRegion: GeoRegion
    public let payload: Data
    public let ttl: Int
    public let hopLimit: Int
    public let timestamp: Date
    public let priority: MessagePriority

    public var isExpired: Bool {
        ttl <= 0 || Date().timeIntervalSince(timestamp) > TimeInterval(ttl * 60)
    }
}

// MARK: - Location Update
/// Periodic location broadcast for mesh networking
public struct LocationUpdate: Codable {
    public let nodeId: String
    public let address: GeoAddress
    public let velocity: Double? // m/s
    public let heading: Double? // degrees
    public let accuracy: Double // meters
    public let timestamp: Date
    public let batteryLevel: Double?
    
    public init(nodeId: String, address: GeoAddress, velocity: Double?, heading: Double?, accuracy: Double, timestamp: Date, batteryLevel: Double?) {
        self.nodeId = nodeId
        self.address = address
        self.velocity = velocity
        self.heading = heading
        self.accuracy = accuracy
        self.timestamp = timestamp
        self.batteryLevel = batteryLevel
    }
}

// MARK: - Waypoint
/// A navigation waypoint with metadata
public struct Waypoint: Codable, Identifiable {
    public let id: String
    public let address: GeoAddress
    public let name: String?
    public let type: WaypointType
    public let metadata: [String: String]

    public enum WaypointType: String, Codable {
        case start
        case waypoint
        case destination
        case shelter
        case danger
        case poi
    }
    
    public init(id: String, address: GeoAddress, name: String?, type: WaypointType, metadata: [String: String]) {
        self.id = id
        self.address = address
        self.name = name
        self.type = type
        self.metadata = metadata
    }
}

// MARK: - Path Route (Geographic)
/// A geographic path between multiple waypoints
public struct GeoPath: Codable {
    public let id: String
    public let waypoints: [Waypoint]
    public let totalDistance: Double // meters
    public let estimatedDuration: TimeInterval
    public let elevationGain: Double? // meters
    public let terrainType: TerrainType
    public let createdAt: Date

    public enum TerrainType: String, Codable {
        case flat
        case hilly
        case mountainous
        case mixed
    }
    
    public init(id: String, waypoints: [Waypoint], totalDistance: Double, estimatedDuration: TimeInterval, elevationGain: Double?, terrainType: TerrainType, createdAt: Date) {
        self.id = id
        self.waypoints = waypoints
        self.totalDistance = totalDistance
        self.estimatedDuration = estimatedDuration
        self.elevationGain = elevationGain
        self.terrainType = terrainType
        self.createdAt = createdAt
    }
}

// MARK: - Navigation Instruction
/// Turn-by-turn navigation instruction
struct NavigationInstruction: Codable, Identifiable {
    let id: String
    let text: String
    let distance: Double // meters to this maneuver
    let maneuverType: ManeuverType
    let bearing: Double? // degrees
    let waypointId: String?

    enum ManeuverType: String, Codable {
        case start
        case continue_
        case turnLeft
        case turnRight
        case uTurn
        case slightLeft
        case slightRight
        case approach
        case arrive
        case offRoute
    }
}



import Foundation
import CoreLocation

// MARK: - Geographic Address
/// Represents a mesh node address based on geographic location
/// Used for Geocast routing (position-based addressing)
struct GeoAddress: Hashable, Codable {
    let nodeId: String
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let precision: Double // meters
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(to other: GeoAddress) -> Double {
        let loc1 = CLLocation(latitude: latitude, longitude: longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}

// MARK: - Geocast Region
/// A geographic region for Geocast message delivery
struct GeoRegion: Hashable, Codable {
    let center: GeoAddress
    let radiusMeters: Double

    func contains(_ address: GeoAddress) -> Bool {
        center.distance(to: address) <= radiusMeters
    }

    func intersects(_ other: GeoRegion) -> Bool {
        let distance = center.distance(to: other.center)
        return distance <= (radiusMeters + other.radiusMeters)
    }
}

// MARK: - Geocast Message
/// Message structure for geographic broadcast
struct GeocastMessage: Codable {
    let id: String
    let sourceAddress: GeoAddress
    let destinationRegion: GeoRegion
    let payload: Data
    let ttl: Int
    let hopLimit: Int
    let timestamp: Date
    let priority: MessagePriority

    var isExpired: Bool {
        ttl <= 0 || Date().timeIntervalSince(timestamp) > TimeInterval(ttl * 60)
    }
}

// MARK: - Location Update
/// Periodic location broadcast for mesh networking
struct LocationUpdate: Codable {
    let nodeId: String
    let address: GeoAddress
    let velocity: Double? // m/s
    let heading: Double? // degrees
    let accuracy: Double // meters
    let timestamp: Date
    let batteryLevel: Double?
}

// MARK: - Waypoint
/// A navigation waypoint with metadata
struct Waypoint: Codable, Identifiable {
    let id: String
    let address: GeoAddress
    let name: String?
    let type: WaypointType
    let metadata: [String: String]

    enum WaypointType: String, Codable {
        case start
        case waypoint
        case destination
        case shelter
        case danger
        case poi
    }
}

// MARK: - Path Route (Geographic)
/// A geographic path between multiple waypoints
struct GeoPath: Codable {
    let id: String
    let waypoints: [Waypoint]
    let totalDistance: Double // meters
    let estimatedDuration: TimeInterval
    let elevationGain: Double? // meters
    let terrainType: TerrainType
    let createdAt: Date

    enum TerrainType: String, Codable {
        case flat
        case hilly
        case mountainous
        case mixed
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

// MARK: - Message Priority
enum MessagePriority: Int, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3
    case emergency = 4

    static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

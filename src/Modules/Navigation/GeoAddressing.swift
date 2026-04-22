// MARK: - Geographic Addressing Engine
// 依赖文件：GeoModels.swift
// 功能：基于地理位置的寻址（Geocast）引擎

import Foundation
import CoreLocation

// MARK: - Geo Address Encoder

public class GeoEncoder {
    /// Encode a geographic address to compact binary format
    public static func encode(_ address: GeoAddress) -> Data? {
        var encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(address)
    }
    
    /// Encode a geocast message
    public static func encodeMessage(_ message: GeocastMessage) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(message)
    }
    
    /// Encode coordinates to geohash string
    public static func geohash(latitude: Double, longitude: Double, precision: Int = 10) -> String {
        let base32 = "0123456789bcdefghjkmnpqrstuvwxyz"
        var latMin = -90.0, latMax = 90.0
        var lonMin = -180.0, lonMax = 180.0
        var hash = ""
        var bit = 0
        var ch = 0
        
        while hash.count < precision {
            if bit % 2 == 0 {
                let mid = (lonMin + lonMax) / 2
                if longitude >= mid {
                    ch |= 1 << (4 - bit % 5)
                    lonMin = mid
                } else {
                    lonMax = mid
                }
            } else {
                let mid = (latMin + latMax) / 2
                if latitude >= mid {
                    ch |= 1 << (4 - bit % 5)
                    latMin = mid
                } else {
                    latMax = mid
                }
            }
            bit += 1
            if bit % 5 == 0 {
                hash.append(base32[base32.index(base32.startIndex, offsetBy: ch)])
                ch = 0
            }
        }
        return hash
    }
}

// MARK: - Geo Address Decoder

public class GeoDecoder {
    /// Decode binary data to geographic address
    public static func decode(_ data: Data) -> GeoAddress? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GeoAddress.self, from: data)
    }
    
    /// Decode geocast message
    public static func decodeMessage(_ data: Data) -> GeocastMessage? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GeastMessage.self, from: data)
    }
    
    /// Decode geohash to coordinates
    public static func decodeGeohash(_ hash: String) -> (latitude: Double, longitude: Double) {
        let base32 = "0123456789bcdefghjkmnpqrstuvwxyz"
        var latMin = -90.0, latMax = 90.0
        var lonMin = -180.0, lonMax = 180.0
        var isLon = true
        
        for c in hash {
            guard let cd = base32.firstIndex(of: c)?.encodedOffset else { continue }
            for i in stride(from: 4, through: 0, by: -1) {
                let mask = 1 << i
                if isLon {
                    if cd & mask != 0 {
                        lonMin = (lonMin + lonMax) / 2
                    } else {
                        lonMax = (lonMin + lonMax) / 2
                    }
                } else {
                    if cd & mask != 0 {
                        latMin = (latMin + latMax) / 2
                    } else {
                        latMax = (latMin + latMax) / 2
                    }
                }
                isLon.toggle()
            }
        }
        return ((latMin + latMax) / 2, (lonMin + lonMax) / 2)
    }
}

// MARK: - Geo Addressing Engine

public class GeoAddressingEngine {
    private var addressCache: [String: GeoAddress] = [:]
    private var nodeLocations: [String: GeoAddress] = [:]
    private let cacheLock = NSLock()
    
    public weak var delegate: GeoAddressingDelegate?
    
    /// Register a node's geographic address
    public func registerNode(_ nodeId: String, address: GeoAddress) {
        cacheLock.lock()
        nodeLocations[nodeId] = address
        addressCache[nodeId] = address
        cacheLock.unlock()
    }
    
    /// Unregister a node
    public func unregisterNode(_ nodeId: String) {
        cacheLock.lock()
        nodeLocations.removeValue(forKey: nodeId)
        cacheLock.unlock()
    }
    
    /// Get all nodes in a geographic region
    public func nodesInRegion(_ region: GeoRegion) -> [String: GeoAddress] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        return nodeLocations.filter { _, address in
            region.contains(address)
        }
    }
    
    /// Find nearest node to a coordinate (proximity-based addressing)
    public func nearestNode(to coordinate: CLLocationCoordinate2D) -> (nodeId: String, address: GeoAddress)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        var nearest: (String, GeoAddress)?
        var minDistance = Double.infinity
        
        for (nodeId, address) in nodeLocations {
            let loc1 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let loc2 = CLLocation(latitude: address.latitude, longitude: address.longitude)
            let distance = loc1.distance(from: loc2)
            
            if distance < minDistance {
                minDistance = distance
                nearest = (nodeId, address)
            }
        }
        
        return nearest
    }
    
    /// Find nearest nodes within radius (proximity search)
    public func nodesNear(coordinate: CLLocationCoordinate2D, radiusMeters: Double) -> [(nodeId: String, address: GeoAddress, distance: Double)] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var results: [(String, GeoAddress, Double)] = []
        
        for (nodeId, address) in nodeLocations {
            let loc = CLLocation(latitude: address.latitude, longitude: address.longitude)
            let distance = center.distance(from: loc)
            
            if distance <= radiusMeters {
                results.append((nodeId, address, distance))
            }
        }
        
        return results.sorted { $0.distance < $1.distance }
    }
    
    /// Anycast: find nearest node providing a service type
    public func anycast(serviceType: String, near coordinate: CLLocationCoordinate2D) -> (nodeId: String, address: GeoAddress)? {
        // In V3.0, this would query a service registry
        // For now, use nearest node as fallback
        return nearestNode(to: coordinate)
    }
    
    /// Build a geocast message for region broadcast
    public func buildGeocastMessage(
        source: GeoAddress,
        targetRegion: GeoRegion,
        payload: Data,
        ttl: Int = 10,
        hopLimit: Int = 5,
        priority: MessagePriority = .normal
    ) -> GeocastMessage {
        GeocastMessage(
            id: UUID().uuidString,
            sourceAddress: source,
            destinationRegion: targetRegion,
            payload: payload,
            ttl: ttl,
            hopLimit: hopLimit,
            timestamp: Date(),
            priority: priority
        )
    }
    
    /// Check if a node is in the destination region
    public func isInRegion(_ address: GeoAddress, region: GeoRegion) -> Bool {
        region.contains(address)
    }
    
    /// Decrement TTL and check if message should propagate
    public func shouldPropagate(_ message: GeocastMessage) -> Bool {
        message.ttl > 0 && message.hopLimit > 0
    }
    
    /// Create decremented message for forwarding
    public func forwardMessage(_ message: GeocastMessage) -> GeocastMessage? {
        guard shouldPropagate(message) else { return nil }
        
        return GeocastMessage(
            id: message.id,
            sourceAddress: message.sourceAddress,
            destinationRegion: message.destinationRegion,
            payload: message.payload,
            ttl: message.ttl - 1,
            hopLimit: message.hopLimit - 1,
            timestamp: message.timestamp,
            priority: message.priority
        )
    }
    
    /// Get cached address for a node
    public func cachedAddress(for nodeId: String) -> GeoAddress? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return addressCache[nodeId]
    }
    
    /// Update address cache
    public func updateCache(_ address: GeoAddress, for nodeId: String) {
        cacheLock.lock()
        addressCache[nodeId] = address
        cacheLock.unlock()
    }
    
    /// Clear stale cache entries (older than threshold seconds)
    public func clearStaleCache(olderThan seconds: TimeInterval) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let threshold = Date().addingTimeInterval(-seconds)
        addressCache = addressCache.filter { _, address in
            address.timestamp > threshold
        }
    }
}

// MARK: - Geo Addressing Delegate

public protocol GeoAddressingDelegate: AnyObject {
    func geoAddressing(_ engine: GeoAddressingEngine, didDiscoverNodes nodes: [String: GeoAddress])
    func geoAddressing(_ engine: GeoAddressingEngine, didReceiveGeocast message: GeocastMessage, from nodeId: String)
    func geoAddressing(_ engine: GeoAddressingEngine, nodeDidDepart nodeId: String)
}

// MARK: - Geocast Router

public class GeocastRouter {
    private let addressingEngine: GeoAddressingEngine
    
    public init(addressingEngine: GeoAddressingEngine) {
        self.addressingEngine = addressingEngine
    }
    
    /// Route a geocast message to appropriate next hops
    public func route(message: GeocastMessage, currentLocation: GeoAddress) -> [String] {
        // Find nodes in the destination region
        let nodesInRegion = addressingEngine.nodesInRegion(message.destinationRegion)
        
        // Also find nodes that could forward towards the region
        let regionCenter = message.destinationRegion.center
        let forwarders = addressingEngine.nodesNear(
            coordinate: CLLocationCoordinate2D(latitude: currentLocation.latitude, longitude: currentLocation.longitude),
            radiusMeters: 1000 // 1km forwarding range
        )
        
        // Combine and deduplicate
        var nextHops = Set(nodesInRegion.keys)
        for (nodeId, _, _) in forwarders {
            nextHops.insert(nodeId)
        }
        
        return Array(nextHops)
    }
    
    /// Calculate forwarding priority based on distance to target region
    public func forwardingPriority(for nodeId: String, targetRegion: GeoRegion) -> Double {
        guard let address = addressingEngine.cachedAddress(for: nodeId) else { return 0 }
        
        let distance = address.distance(to: targetRegion.center)
        let radius = targetRegion.radiusMeters
        
        // Higher priority for nodes closer to or inside the region
        if distance <= radius {
            return 1.0 + (radius - distance) / radius // 1.0 to 2.0 for nodes inside
        } else {
            return max(0, 1.0 - (distance - radius) / 5000) // 0 to 1.0 for nodes outside
        }
    }
}

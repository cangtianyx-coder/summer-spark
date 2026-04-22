// MARK: - Geographic Mesh Navigator
// 依赖文件：GeoAddressing.swift, GeoModels.swift, NavigationEngine.swift
// 功能：结合 Mesh 网络的地理导航引擎

import Foundation
import CoreLocation

// MARK: - Geo Mesh Navigator

public class GeoMeshNavigator {
    private let addressingEngine: GeoAddressingEngine
    private let geocastRouter: GeocastRouter
    
    private var activePaths: [String: GeoPath] = [:]
    private var pathSegments: [String: [PathSegment]] = [:]
    private var messageQueue: [GeocastMessage] = []
    private var locationCache: [String: Date] = [:]
    
    private let queueLock = NSLock()
    private var navigationState: NavigationState = .idle
    
    public weak var delegate: GeoMeshNavigatorDelegate?
    
    public init(addressingEngine: GeoAddressingEngine) {
        self.addressingEngine = addressingEngine
        self.geocastRouter = GeocastRouter(addressingEngine: addressingEngine)
    }
    
    // MARK: - Path-Based Geocast
    
    /// Send a message along a geographic path
    public func sendAlongPath(_ message: GeocastMessage, path: GeoPath) -> Bool {
        guard navigationState == .active else { return false }
        
        // Store the active path
        activePaths[message.id] = path
        
        // Segment the path for geocast
        let segments = segmentPath(path, maxSegmentLength: 500) // 500m segments
        pathSegments[message.id] = segments
        
        // Start geocast from first segment
        if let firstSegment = segments.first {
            return geocastToSegment(message, segment: firstSegment)
        }
        
        return false
    }
    
    /// Segment a path into geocast regions
    private func segmentPath(_ path: GeoPath, maxSegmentLength: Double) -> [PathSegment] {
        var segments: [PathSegment] = []
        var currentDistance = 0.0
        
        guard path.waypoints.count >= 2 else { return segments }
        
        for i in 0..<(path.waypoints.count - 1) {
            let start = path.waypoints[i]
            let end = path.waypoints[i + 1]
            
            let segmentLength = start.address.distance(to: end.address)
            
            if segmentLength <= maxSegmentLength {
                // Single segment
                segments.append(PathSegment(
                    id: UUID().uuidString,
                    startWaypoint: start,
                    endWaypoint: end,
                    region: createSegmentRegion(start: start.address, end: end.address, padding: 100),
                    distance: segmentLength
                ))
            } else {
                // Split into multiple segments
                let numSplits = Int(ceil(segmentLength / maxSegmentLength))
                for j in 0..<numSplits {
                    let ratio = Double(j) / Double(numSplits)
                    let nextRatio = Double(j + 1) / Double(numSplits)
                    
                    let interpStart = interpolateWaypoint(start: start, end: end, ratio: ratio)
                    let interpEnd = interpolateWaypoint(start: start, end: end, ratio: nextRatio)
                    
                    segments.append(PathSegment(
                        id: UUID().uuidString,
                        startWaypoint: interpStart,
                        endWaypoint: interpEnd,
                        region: createSegmentRegion(start: interpStart.address, end: interpEnd.address, padding: 100),
                        distance: segmentLength / Double(numSplits)
                    ))
                }
            }
        }
        
        return segments
    }
    
    /// Create a GeoRegion covering a path segment
    private func createSegmentRegion(start: GeoAddress, end: GeoAddress, padding: Double) -> GeoRegion {
        let midLat = (start.latitude + end.latitude) / 2
        let midLon = (start.longitude + end.longitude) / 2
        
        let distance = start.distance(to: end)
        let radius = distance / 2 + padding
        
        return GeoRegion(
            center: GeoAddress(
                nodeId: "",
                latitude: midLat,
                longitude: midLon,
                altitude: nil,
                precision: padding,
                timestamp: Date()
            ),
            radiusMeters: radius
        )
    }
    
    /// Interpolate between two waypoints
    private func interpolateWaypoint(start: Waypoint, end: Waypoint, ratio: Double) -> Waypoint {
        let lat = start.address.latitude + (end.address.latitude - start.address.latitude) * ratio
        let lon = start.address.longitude + (end.address.longitude - start.address.longitude) * ratio
        
        return Waypoint(
            id: UUID().uuidString,
            address: GeoAddress(
                nodeId: "",
                latitude: lat,
                longitude: lon,
                altitude: nil,
                precision: 10,
                timestamp: Date()
            ),
            name: nil,
            type: .waypoint,
            metadata: [:]
        )
    }
    
    /// Geocast a message to a path segment
    private func geocastToSegment(_ message: GeocastMessage, segment: PathSegment) -> Bool {
        // Find nodes in the segment region
        let nodesInSegment = addressingEngine.nodesInRegion(segment.region)
        
        guard !nodesInSegment.isEmpty else {
            // Queue for later retry
            queueLock.lock()
            messageQueue.append(message)
            queueLock.unlock()
            return false
        }
        
        // Notify delegate of delivery targets
        delegate?.geoMeshNavigator(self, willDeliverTo: Array(nodesInSegment.keys), for: message)
        
        return true
    }
    
    // MARK: - Navigation Control
    
    /// Start navigation mode
    public func startNavigation() {
        navigationState = .active
        processQueuedMessages()
    }
    
    /// Pause navigation
    public func pauseNavigation() {
        navigationState = .paused
    }
    
    /// Stop navigation and clear state
    public func stopNavigation() {
        navigationState = .idle
        activePaths.removeAll()
        pathSegments.removeAll()
        
        queueLock.lock()
        messageQueue.removeAll()
        queueLock.unlock()
    }
    
    /// Process queued messages when nodes become available
    private func processQueuedMessages() {
        queueLock.lock()
        let messages = messageQueue
        messageQueue.removeAll()
        queueLock.unlock()
        
        for message in messages {
            if let path = activePaths[message.id] {
                _ = sendAlongPath(message, path: path)
            }
        }
    }
    
    // MARK: - Location Tracking
    
    /// Update current location for routing decisions
    public func updateLocation(_ location: GeoAddress, for nodeId: String) {
        addressingEngine.updateCache(location, for: nodeId)
        locationCache[nodeId] = Date()
        
        // Check if any active paths need rerouting
        checkPathValidity(nodeId: nodeId)
    }
    
    /// Check if paths need rerouting due to node movement
    private func checkPathValidity(nodeId: String) {
        for (messageId, path) in activePaths {
            // Check if any waypoint nodes have moved significantly
            for waypoint in path.waypoints {
                if let cached = addressingEngine.cachedAddress(for: waypoint.id),
                   waypoint.address.distance(to: cached) > 100 { // 100m threshold
                    delegate?.geoMeshNavigator(self, pathNeedsReroute: messageId, reason: "Node \(nodeId) moved")
                }
            }
        }
    }
    
    // MARK: - Message Handling
    
    /// Receive a geocast message from the mesh
    public func receiveGeocast(_ message: GeocastMessage, from nodeId: String) {
        // Check if we're in the destination region
        guard let myLocation = getCurrentLocation() else { return }
        
        if message.destinationRegion.contains(myLocation) {
            // We're a destination
            delegate?.geoMeshNavigator(self, didReceiveMessage: message, asDestination: true)
        }
        
        // Check if we should forward
        if addressingEngine.shouldPropagate(message) {
            forwardGeocast(message, from: nodeId)
        }
    }
    
    /// Forward a geocast message to next hops
    private func forwardGeocast(_ message: GeocastMessage, from sourceId: String) {
        guard let myLocation = getCurrentLocation(),
              let forwarded = addressingEngine.forwardMessage(message) else { return }
        
        let nextHops = geocastRouter.route(message: forwarded, currentLocation: myLocation)
        
        // Exclude the source to avoid loops
        let filteredHops = nextHops.filter { $0 != sourceId }
        
        if !filteredHops.isEmpty {
            delegate?.geoMeshNavigator(self, willForwardMessage: forwarded, to: filteredHops)
        }
    }
    
    /// Get current location (placeholder - would integrate with LocationManager)
    private func getCurrentLocation() -> GeoAddress? {
        // In production, this would get from LocationManager
        return nil
    }
    
    // MARK: - Statistics
    
    /// Get navigation statistics
    public func getStatistics() -> GeoNavigationStats {
        queueLock.lock()
        let queuedCount = messageQueue.count
        queueLock.unlock()
        
        return GeoNavigationStats(
            activePaths: activePaths.count,
            totalSegments: pathSegments.values.reduce(0) { $0 + $1.count },
            queuedMessages: queuedCount,
            trackedNodes: locationCache.count
        )
    }
}

// MARK: - Path Segment

public struct PathSegment {
    let id: String
    let startWaypoint: Waypoint
    let endWaypoint: Waypoint
    let region: GeoRegion
    let distance: Double
}

// MARK: - Navigation State

public enum NavigationState {
    case idle
    case active
    case paused
    case error(String)
}

// MARK: - Geo Navigation Stats

public struct GeoNavigationStats {
    let activePaths: Int
    let totalSegments: Int
    let queuedMessages: Int
    let trackedNodes: Int
}

// MARK: - Geo Mesh Navigator Delegate

public protocol GeoMeshNavigatorDelegate: AnyObject {
    func geoMeshNavigator(_ navigator: GeoMeshNavigator, willDeliverTo nodeIds: [String], for message: GeocastMessage)
    func geoMeshNavigator(_ navigator: GeoMeshNavigator, didReceiveMessage message: GeocastMessage, asDestination: Bool)
    func geoMeshNavigator(_ navigator: GeoMeshNavigator, willForwardMessage message: GeocastMessage, to nodeIds: [String])
    func geoMeshNavigator(_ navigator: GeoMeshNavigator, pathNeedsReroute messageId: String, reason: String)
}

// MARK: - Geographic Route Planner

public class GeographicRoutePlanner {
    private let addressingEngine: GeoAddressingEngine
    
    public init(addressingEngine: GeoAddressingEngine) {
        self.addressingEngine = addressingEngine
    }
    
    /// Plan a route through mesh nodes
    public func planRoute(from start: GeoAddress, to destination: GeoAddress, via waypoints: [GeoAddress]? = nil) -> GeoPath? {
        var allPoints = [start]
        if let waypoints = waypoints {
            allPoints.append(contentsOf: waypoints)
        }
        allPoints.append(destination)
        
        // Create waypoints
        let pathWaypoints = allPoints.enumerated().map { index, address in
            Waypoint(
                id: UUID().uuidString,
                address: address,
                name: nil,
                type: index == 0 ? .start : (index == allPoints.count - 1 ? .destination : .waypoint),
                metadata: [:]
            )
        }
        
        // Calculate total distance
        var totalDistance = 0.0
        for i in 0..<(allPoints.count - 1) {
            totalDistance += allPoints[i].distance(to: allPoints[i + 1])
        }
        
        // Estimate duration (assuming 5 km/h walking speed)
        let estimatedDuration = totalDistance / 5000 * 3600
        
        return GeoPath(
            id: UUID().uuidString,
            waypoints: pathWaypoints,
            totalDistance: totalDistance,
            estimatedDuration: estimatedDuration,
            elevationGain: nil,
            terrainType: .mixed,
            createdAt: Date()
        )
    }
    
    /// Find intermediate mesh nodes for multi-hop route
    public func findIntermediateNodes(from start: GeoAddress, to destination: GeoAddress, maxHops: Int = 5) -> [String] {
        var intermediateNodes: [String] = []
        
        // Find nodes along the path
        let distance = start.distance(to: destination)
        let hopDistance = distance / Double(maxHops)
        
        for i in 1..<maxHops {
            let ratio = Double(i) / Double(maxHops)
            let interpLat = start.latitude + (destination.latitude - start.latitude) * ratio
            let interpLon = start.longitude + (destination.longitude - start.longitude) * ratio
            
            // Find nearest node to this point
            if let nearest = addressingEngine.nearestNode(to: CLLocationCoordinate2D(latitude: interpLat, longitude: interpLon)) {
                // Only add if within reasonable distance
                let interpLoc = CLLocation(latitude: interpLat, longitude: interpLon)
                let nodeLoc = CLLocation(latitude: nearest.address.latitude, longitude: nearest.address.longitude)
                
                if interpLoc.distance(from: nodeLoc) <= hopDistance * 1.5 {
                    intermediateNodes.append(nearest.nodeId)
                }
            }
        }
        
        return intermediateNodes
    }
}

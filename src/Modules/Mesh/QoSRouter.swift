// MARK: - QoS Aware Router
// 依赖文件：RouteStabilityMonitor.swift, QoSModels.swift
// 功能：根据流量 QoS 要求选择最佳路由

import Foundation

// MARK: - QoS Router

public class QoSRouter {
    private let stabilityMonitor: RouteStabilityMonitor
    private var qosRoutes: [QoSClass: [RouteEntry]] = [:]
    private var bandwidthReservations: [String: BandwidthReservation] = [:]
    private var congestionState: [String: CongestionLevel] = [:]
    
    private let routerLock = NSLock()
    
    public weak var delegate: QoSRouterDelegate?
    
    public init(stabilityMonitor: RouteStabilityMonitor) {
        self.stabilityMonitor = stabilityMonitor
    }
    
    // MARK: - Route Selection
    
    /// Select best route for traffic with given QoS requirements
    public func selectRoute(for descriptor: TrafficDescriptor, candidates: [RouteEntry]) -> RouteEntry? {
        let qosClass = descriptor.qosClass
        
        // Filter routes that meet QoS requirements
        let viableRoutes = candidates.filter { route in
            meetsQoSRequirements(route: route, descriptor: descriptor)
        }
        
        guard !viableRoutes.isEmpty else {
            // No route meets requirements, try best effort
            return selectBestEffortRoute(candidates: candidates, priority: descriptor.priority)
        }
        
        // Sort by quality and select best
        let sorted = viableRoutes.sorted { route1, route2 in
            let score1 = calculateRouteScore(route: route1, qosClass: qosClass)
            let score2 = calculateRouteScore(route: route2, qosClass: qosClass)
            return score1 > score2
        }
        
        return sorted.first
    }
    
    /// Check if a route meets QoS requirements
    private func meetsQoSRequirements(route: RouteEntry, descriptor: TrafficDescriptor) -> Bool {
        // Get link qualities for the route
        let hops = route.path // Assuming RouteEntry has a path property
        var cumulativeLatency: TimeInterval = 0
        var minBandwidth = Double.infinity
        
        for hop in hops {
            if let quality = stabilityMonitor.getLinkQuality(neighborId: hop) {
                cumulativeLatency += quality.latency * 1000 // convert to ms
                minBandwidth = min(minBandwidth, quality.bandwidth)
                
                // Check latency requirement
                if let maxLatency = descriptor.maxLatency, cumulativeLatency > maxLatency {
                    return false
                }
                
                // Check bandwidth requirement
                if let minBw = descriptor.minBandwidth, minBandwidth < minBw {
                    return false
                }
            } else {
                // Unknown link quality - conservative estimate
                cumulativeLatency += 100 // assume 100ms per unknown hop
            }
        }
        
        return true
    }
    
    /// Calculate route score for QoS class
    private func calculateRouteScore(route: RouteEntry, qosClass: QoSClass) -> Double {
        let hops = route.path
        
        // Base stability score
        let stabilityScore = stabilityMonitor.calculateRouteStability(hops: hops)
        
        // QoS priority factor
        let qosFactor = Double(qosClass.rawValue + 1) / Double(QoSClass.allCases.count)
        
        // Congestion factor
        let congestionFactor = getCongestionFactor(route: route)
        
        // Bandwidth availability
        let bandwidthFactor = getBandwidthFactor(route: route)
        
        return stabilityScore * 0.4 + qosFactor * 0.2 + congestionFactor * 0.2 + bandwidthFactor * 0.2
    }
    
    /// Select best effort route when QoS requirements can't be met
    private func selectBestEffortRoute(candidates: [RouteEntry], priority: MessagePriority) -> RouteEntry? {
        let sorted = candidates.sorted { route1, route2 in
            let score1 = stabilityMonitor.calculateRouteStability(hops: route1.path)
            let score2 = stabilityMonitor.calculateRouteStability(hops: route2.path)
            return score1 > score2
        }
        
        return sorted.first
    }
    
    // MARK: - Bandwidth Reservation
    
    /// Reserve bandwidth for a flow
    public func reserveBandwidth(flowId: String, requiredBw: Double, route: RouteEntry) -> Bool {
        routerLock.lock()
        defer { routerLock.unlock() }
        
        // Check available bandwidth on route
        let availableBw = getAvailableBandwidth(route: route)
        
        guard availableBw >= requiredBw else { return false }
        
        // Create reservation
        let reservation = BandwidthReservation(
            flowId: flowId,
            bandwidth: requiredBw,
            route: route,
            createdAt: Date()
        )
        
        bandwidthReservations[flowId] = reservation
        return true
    }
    
    /// Release bandwidth reservation
    public func releaseReservation(flowId: String) {
        routerLock.lock()
        bandwidthReservations.removeValue(forKey: flowId)
        routerLock.unlock()
    }
    
    /// Get available bandwidth on a route
    private func getAvailableBandwidth(route: RouteEntry) -> Double {
        var minAvailable = Double.infinity
        
        for hop in route.path {
            if let quality = stabilityMonitor.getLinkQuality(neighborId: hop) {
                let reserved = getReservedBandwidthOnLink(nodeId: hop)
                let available = quality.bandwidth - reserved
                minAvailable = min(minAvailable, max(0, available))
            }
        }
        
        return minAvailable == Double.infinity ? 0 : minAvailable
    }
    
    /// Get total reserved bandwidth on a link
    private func getReservedBandwidthOnLink(nodeId: String) -> Double {
        var total = 0.0
        for (_, reservation) in bandwidthReservations {
            if reservation.route.path.contains(nodeId) {
                total += reservation.bandwidth
            }
        }
        return total
    }
    
    // MARK: - Congestion Management
    
    /// Update congestion state for a node
    public func updateCongestion(nodeId: String, level: CongestionLevel) {
        routerLock.lock()
        congestionState[nodeId] = level
        routerLock.unlock()
        
        if level == .severe || level == .critical {
            delegate?.qosRouter(self, didDetectCongestion: nodeId, level: level)
        }
    }
    
    /// Get congestion factor for route scoring
    private func getCongestionFactor(route: RouteEntry) -> Double {
        routerLock.lock()
        defer { routerLock.unlock() }
        
        var maxCongestion = CongestionLevel.none
        
        for hop in route.path {
            if let level = congestionState[hop], level.rawValue > maxCongestion.rawValue {
                maxCongestion = level
            }
        }
        
        // Convert to factor (0 = critical, 1 = none)
        return 1.0 - Double(maxCongestion.rawValue) / Double(CongestionLevel.critical.rawValue)
    }
    
    /// Get bandwidth factor for route scoring
    private func getBandwidthFactor(route: RouteEntry) -> Double {
        let available = getAvailableBandwidth(route: route)
        // Normalize to 0-1 range (assume max 1000 kbps)
        return min(1.0, available / 1000.0)
    }
    
    // MARK: - Multi-Path Routing
    
    /// Find multiple paths for load balancing
    public func findMultiPath(to destination: String, maxPaths: Int = 3) -> [RouteEntry] {
        // This would integrate with RouteTable to find candidate routes
        // For now, return empty - would be implemented with actual route table
        return []
    }
    
    /// Select path for load balancing among multiple paths
    public func selectPathForLoadBalancing(paths: [RouteEntry], flowId: String) -> RouteEntry? {
        guard !paths.isEmpty else { return nil }
        
        // Simple round-robin with congestion awareness
        let sorted = paths.sorted { path1, path2 in
            let factor1 = getCongestionFactor(route: path1) * getBandwidthFactor(route: path1)
            let factor2 = getCongestionFactor(route: path2) * getBandwidthFactor(route: path2)
            return factor1 > factor2
        }
        
        return sorted.first
    }
    
    // MARK: - QoS Class Mapping
    
    /// Get recommended QoS class for traffic type
    public func recommendedQoSClass(for trafficType: TrafficType) -> QoSClass {
        switch trafficType {
        case .voice:
            return .interactive
        case .video:
            return .streaming
        case .data:
            return .bestEffort
        case .emergency:
            return .critical
        case .background:
            return .background
        }
    }
}

// MARK: - Supporting Types

public struct RouteEntry {
    let destination: String
    let path: [String]
    let metric: Int
    let interface: String?
}

public struct BandwidthReservation {
    let flowId: String
    let bandwidth: Double
    let route: RouteEntry
    let createdAt: Date
}

public enum CongestionLevel: Int, Comparable {
    case none = 0
    case mild = 1
    case moderate = 2
    case severe = 3
    case critical = 4
    
    public static func < (lhs: CongestionLevel, rhs: CongestionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum TrafficType {
    case voice
    case video
    case data
    case emergency
    case background
}

// MARK: - QoS Router Delegate

public protocol QoSRouterDelegate: AnyObject {
    func qosRouter(_ router: QoSRouter, didDetectCongestion nodeId: String, level: CongestionLevel)
    func qosRouter(_ router: QoSRouter, didReserveBandwidth flowId: String, bandwidth: Double)
    func qosRouter(_ router: QoSRouter, routeDidChange route: RouteEntry, reason: String)
}

// MARK: - Route Handover Manager
// 依赖文件：RouteStabilityMonitor.swift, QoSRouter.swift
// 功能：路由切换与故障转移管理

import Foundation

// MARK: - Route Handover Manager

public class RouteHandoverManager {
    private let stabilityMonitor: RouteStabilityMonitor
    private let qosRouter: QoSRouter
    
    private var primaryRoutes: [String: RouteEntry] = [:]
    private var backupRoutes: [String: RouteEntry] = [:]
    private var pendingHandovers: [String: HandoverContext] = [:]
    private var messageBuffer: [String: [BufferedMessage]] = [:]
    
    private let bufferLock = NSLock()
    private var handoverTimeout: TimeInterval = 0.1 // 100ms target
    private var maxBufferSize = 100
    
    public weak var delegate: RouteHandoverDelegate?
    
    public init(stabilityMonitor: RouteStabilityMonitor, qosRouter: QoSRouter) {
        self.stabilityMonitor = stabilityMonitor
        self.qosRouter = qosRouter
    }
    
    // MARK: - Route Registration
    
    /// Register a primary route with automatic backup computation
    public func registerRoute(_ route: RouteEntry, forDestination destination: String) {
        primaryRoutes[destination] = route
        
        // Pre-compute backup route
        if let backup = computeBackupRoute(for: route) {
            backupRoutes[destination] = backup
            delegate?.routeHandoverManager(self, didComputeBackup: backup, for: destination)
        }
    }
    
    /// Compute a backup route that avoids single points of failure
    private func computeBackupRoute(for primary: RouteEntry) -> RouteEntry? {
        // Find alternative path that doesn't share critical nodes with primary
        // This would integrate with RouteTable/MeshService
        // For now, return nil - actual implementation would query mesh for alternatives
        return nil
    }
    
    /// Update backup route
    public func updateBackupRoute(_ route: RouteEntry, forDestination destination: String) {
        backupRoutes[destination] = route
    }
    
    // MARK: - Failure Detection
    
    /// Handle link failure event
    public func handleLinkFailure(nodeId: String) {
        // Find all routes affected by this failure
        let affectedDestinations = primaryRoutes.filter { _, route in
            route.path.contains(nodeId)
        }.keys
        
        for destination in affectedDestinations {
            initiateHandover(destination: destination, reason: .linkFailure, failedNode: nodeId)
        }
    }
    
    /// Handle quality degradation event
    public func handleQualityDegradation(nodeId: String, newScore: Double) {
        // Check if degradation is severe enough to trigger handover
        guard newScore < 0.4 else { return }
        
        // Find routes where this node is critical
        let affectedDestinations = primaryRoutes.filter { _, route in
            route.path.contains(nodeId)
        }.keys
        
        for destination in affectedDestinations {
            // Check if backup is better
            if let backup = backupRoutes[destination],
               !backup.path.contains(nodeId) {
                initiateHandover(destination: destination, reason: .qualityDegradation, failedNode: nodeId)
            }
        }
    }
    
    // MARK: - Handover Execution
    
    /// Initiate route handover
    private func initiateHandover(destination: String, reason: RouteHandoverEvent.HandoverReason, failedNode: String?) {
        guard let backup = backupRoutes[destination] else {
            // No backup available - notify delegate
            delegate?.routeHandoverManager(self, handoverFailed: destination, reason: "No backup route available")
            return
        }
        
        // Create handover context
        let context = HandoverContext(
            destination: destination,
            oldRoute: primaryRoutes[destination],
            newRoute: backup,
            reason: reason,
            startTime: Date(),
            state: .initiating
        )
        
        pendingHandovers[destination] = context
        
        // Start buffering messages during handover
        startBuffering(destination: destination)
        
        // Execute handover
        executeHandover(context: context, failedNode: failedNode)
    }
    
    /// Execute the actual route switch
    private func executeHandover(context: HandoverContext, failedNode: String?) {
        let destination = context.destination
        
        // Update primary route to backup
        primaryRoutes[destination] = context.newRoute
        
        // Create handover event
        let event = RouteHandoverEvent(
            eventId: UUID().uuidString,
            oldRouteId: context.oldRoute?.destination ?? "",
            newRouteId: context.newRoute.destination,
            reason: context.reason,
            timestamp: Date(),
            affectedFlows: getAffectedFlows(destination: destination)
        )
        
        // Flush buffered messages to new route
        flushBuffer(destination: destination, newRoute: context.newRoute)
        
        // Clear pending handover
        pendingHandovers.removeValue(forKey: destination)
        
        // Notify delegate
        delegate?.routeHandoverManager(self, didCompleteHandover: event)
    }
    
    // MARK: - Message Buffering
    
    /// Start buffering messages for a destination during handover
    private func startBuffering(destination: String) {
        bufferLock.lock()
        if messageBuffer[destination] == nil {
            messageBuffer[destination] = []
        }
        bufferLock.unlock()
    }
    
    /// Buffer a message during handover
    public func bufferMessage(_ message: Data, for destination: String) -> Bool {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        guard var buffer = messageBuffer[destination], buffer.count < maxBufferSize else {
            return false
        }
        
        buffer.append(BufferedMessage(data: message, timestamp: Date()))
        messageBuffer[destination] = buffer
        return true
    }
    
    /// Flush buffered messages to new route
    private func flushBuffer(destination: String, newRoute: RouteEntry) {
        bufferLock.lock()
        let messages = messageBuffer[destination] ?? []
        messageBuffer.removeValue(forKey: destination)
        bufferLock.unlock()
        
        // Send buffered messages on new route
        for msg in messages {
            delegate?.routeHandoverManager(self, shouldSendMessage: msg.data, via: newRoute)
        }
    }
    
    /// Get affected flows for a destination
    private func getAffectedFlows(destination: String) -> [String] {
        // Would query flow table - return placeholder
        return []
    }
    
    // MARK: - Route Maintenance
    
    /// Periodic maintenance - check route health and update backups
    public func performMaintenance() {
        // Check for timed-out handovers
        let now = Date()
        for (destination, context) in pendingHandovers {
            if now.timeIntervalSince(context.startTime) > 5.0 { // 5 second timeout
                // Handover timed out
                pendingHandovers.removeValue(forKey: destination)
                delegate?.routeHandoverManager(self, handoverFailed: destination, reason: "Handover timeout")
            }
        }
        
        // Update backup routes for stability
        for (destination, route) in primaryRoutes {
            let stability = stabilityMonitor.calculateRouteStability(hops: route.path)
            
            // If route is unstable, pre-compute better backup
            if stability < 0.6 {
                if let betterBackup = computeBackupRoute(for: route) {
                    backupRoutes[destination] = betterBackup
                }
            }
        }
    }
    
    /// Get current route for a destination
    public func getCurrentRoute(for destination: String) -> RouteEntry? {
        return primaryRoutes[destination]
    }
    
    /// Get backup route for a destination
    public func getBackupRoute(for destination: String) -> RouteEntry? {
        return backupRoutes[destination]
    }
    
    /// Check if handover is in progress
    public func isHandoverInProgress(for destination: String) -> Bool {
        return pendingHandovers[destination] != nil
    }
    
    // MARK: - Statistics
    
    /// Get handover statistics
    public func getStatistics() -> HandoverStatistics {
        bufferLock.lock()
        let totalBuffered = messageBuffer.values.reduce(0) { $0 + $1.count }
        bufferLock.unlock()
        
        return HandoverStatistics(
            activeRoutes: primaryRoutes.count,
            backupRoutes: backupRoutes.count,
            pendingHandovers: pendingHandovers.count,
            bufferedMessages: totalBuffered
        )
    }
}

// MARK: - Supporting Types

public struct HandoverContext {
    let destination: String
    let oldRoute: RouteEntry?
    let newRoute: RouteEntry
    let reason: RouteHandoverEvent.HandoverReason
    let startTime: Date
    let state: HandoverState
}

public enum HandoverState {
    case initiating
    case buffering
    case switching
    case completed
    case failed
}

public struct BufferedMessage {
    let data: Data
    let timestamp: Date
}

public struct HandoverStatistics {
    let activeRoutes: Int
    let backupRoutes: Int
    let pendingHandovers: Int
    let bufferedMessages: Int
}

// MARK: - Route Handover Delegate

public protocol RouteHandoverDelegate: AnyObject {
    func routeHandoverManager(_ manager: RouteHandoverManager, didComputeBackup route: RouteEntry, for destination: String)
    func routeHandoverManager(_ manager: RouteHandoverManager, didCompleteHandover event: RouteHandoverEvent)
    func routeHandoverManager(_ manager: RouteHandoverManager, handoverFailed destination: String, reason: String)
    func routeHandoverManager(_ manager: RouteHandoverManager, shouldSendMessage message: Data, via route: RouteEntry)
}

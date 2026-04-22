// MARK: - Map Package P2P Sharing
// 依赖文件：MapRelayService.swift, MeshRelayProtocols.swift
// 功能：P2P 地图包分发协议

import Foundation

// MARK: - Map Package P2P

public class MapPackageP2P: MapPackageShareProtocol {
    private var activeSessions: [String: MapShareSession] = [:]
    private var pendingRequests: [String: ShareRequest] = [:]
    private var completedSessions: [String: MapShareSession] = []
    
    private let sessionLock = NSLock()
    private let chunkSize = 8192 // 8KB chunks
    private var maxConcurrentSessions = 3
    
    public weak var delegate: MapPackageP2PDelegate?
    
    // MARK: - Share Initiation
    
    public func initiateShare(packageId: String, to peerId: String) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        // Check if too many active sessions
        let activeCount = activeSessions.values.filter { $0.state == .transferring }.count
        guard activeCount < maxConcurrentSessions else {
            delegate?.mapPackageP2P(self, shareFailed: packageId, reason: "Too many active sessions")
            return
        }
        
        let sessionId = UUID().uuidString
        let session = MapShareSession(
            id: sessionId,
            packageId: packageId,
            peerId: peerId,
            direction: .uploading,
            state: .negotiating,
            progress: 0,
            startedAt: Date()
        )
        
        activeSessions[sessionId] = session
        
        // Send share offer to peer
        let offer = ShareOffer(
            offerId: sessionId,
            packageId: packageId,
            chunkSize: chunkSize,
            timestamp: Date()
        )
        
        delegate?.mapPackageP2P(self, shouldSendOffer: offer, to: peerId)
    }
    
    public func acceptShare(shareId: String) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        guard var session = activeSessions[shareId] else { return }
        
        session = MapShareSession(
            id: session.id,
            packageId: session.packageId,
            peerId: session.peerId,
            direction: session.direction,
            state: .transferring,
            progress: 0,
            startedAt: session.startedAt
        )
        
        activeSessions[shareId] = session
        
        // Notify that we're ready to receive
        delegate?.mapPackageP2P(self, didAcceptShare: shareId)
    }
    
    public func rejectShare(shareId: String) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        guard let session = activeSessions[shareId] else { return }
        
        let failedSession = MapShareSession(
            id: session.id,
            packageId: session.packageId,
            peerId: session.peerId,
            direction: session.direction,
            state: .cancelled,
            progress: session.progress,
            startedAt: session.startedAt
        )
        
        activeSessions.removeValue(forKey: shareId)
        completedSessions.append(failedSession)
        
        delegate?.mapPackageP2P(self, didRejectShare: shareId)
    }
    
    public func cancelShare(shareId: String) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        guard let session = activeSessions[shareId] else { return }
        
        let cancelledSession = MapShareSession(
            id: session.id,
            packageId: session.packageId,
            peerId: session.peerId,
            direction: session.direction,
            state: .cancelled,
            progress: session.progress,
            startedAt: session.startedAt
        )
        
        activeSessions.removeValue(forKey: shareId)
        completedSessions.append(cancelledSession)
        
        delegate?.mapPackageP2P(self, didCancelShare: shareId)
    }
    
    public func getActiveShares() -> [MapShareSession] {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return Array(activeSessions.values)
    }
    
    // MARK: - Chunk Transfer
    
    /// Send a chunk of the map package
    public func sendChunk(sessionId: String, chunkIndex: Int, data: Data) {
        sessionLock.lock()
        guard var session = activeSessions[sessionId] else {
            sessionLock.unlock()
            return
        }
        sessionLock.unlock()
        
        let chunk = PackageChunk(
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            data: data,
            checksum: calculateChecksum(data),
            isLast: false // Will be set by caller
        )
        
        delegate?.mapPackageP2P(self, shouldSendChunk: chunk, to: session.peerId)
    }
    
    /// Receive a chunk
    public func receiveChunk(_ chunk: PackageChunk) -> Bool {
        sessionLock.lock()
        guard var session = activeSessions[chunk.sessionId] else {
            sessionLock.unlock()
            return false
        }
        sessionLock.unlock()
        
        // Verify checksum
        guard verifyChecksum(chunk.data, expected: chunk.checksum) else {
            handleChunkError(sessionId: chunk.sessionId, error: "Checksum mismatch")
            return false
        }
        
        // Update progress
        sessionLock.lock()
        if let s = activeSessions[chunk.sessionId] {
            session = MapShareSession(
                id: s.id,
                packageId: s.packageId,
                peerId: s.peerId,
                direction: s.direction,
                state: .transferring,
                progress: s.progress + 0.01, // Incremental progress
                startedAt: s.startedAt
            )
            activeSessions[chunk.sessionId] = session
        }
        sessionLock.unlock()
        
        // Notify delegate of received chunk
        delegate?.mapPackageP2P(self, didReceiveChunk: chunk, for: chunk.sessionId)
        
        // Check if this is the last chunk
        if chunk.isLast {
            completeSession(sessionId: chunk.sessionId)
        }
        
        return true
    }
    
    // MARK: - Resume Support
    
    /// Request resume from a specific chunk
    public func requestResume(sessionId: String, fromChunk: Int) {
        sessionLock.lock()
        guard let session = activeSessions[sessionId] else {
            sessionLock.unlock()
            return
        }
        sessionLock.unlock()
        
        let resumeRequest = ResumeRequest(
            sessionId: sessionId,
            fromChunk: fromChunk,
            timestamp: Date()
        )
        
        delegate?.mapPackageP2P(self, shouldSendResumeRequest: resumeRequest, to: session.peerId)
    }
    
    /// Handle resume request
    public func handleResumeRequest(_ request: ResumeRequest) {
        // Accept resume and continue from requested chunk
        acceptShare(shareId: request.sessionId)
        delegate?.mapPackageP2P(self, didAcceptResume: request.sessionId, fromChunk: request.fromChunk)
    }
    
    // MARK: - Session Management
    
    private func completeSession(sessionId: String) {
        sessionLock.lock()
        guard let session = activeSessions[sessionId] else {
            sessionLock.unlock()
            return
        }
        
        let completedSession = MapShareSession(
            id: session.id,
            packageId: session.packageId,
            peerId: session.peerId,
            direction: session.direction,
            state: .completed,
            progress: 1.0,
            startedAt: session.startedAt
        )
        
        activeSessions.removeValue(forKey: sessionId)
        completedSessions.append(completedSession)
        sessionLock.unlock()
        
        delegate?.mapPackageP2P(self, didCompleteShare: sessionId)
    }
    
    private func handleChunkError(sessionId: String, error: String) {
        sessionLock.lock()
        guard let session = activeSessions[sessionId] else {
            sessionLock.unlock()
            return
        }
        
        let failedSession = MapShareSession(
            id: session.id,
            packageId: session.packageId,
            peerId: session.peerId,
            direction: session.direction,
            state: .failed,
            progress: session.progress,
            startedAt: session.startedAt
        )
        
        activeSessions.removeValue(forKey: sessionId)
        completedSessions.append(failedSession)
        sessionLock.unlock()
        
        delegate?.mapPackageP2P(self, shareFailed: sessionId, reason: error)
    }
    
    // MARK: - Checksum
    
    private func calculateChecksum(_ data: Data) -> String {
        // Simple hash - in production use SHA256
        var hash: UInt8 = 0
        for byte in data {
            hash = hash &+ byte
        }
        return String(format: "%02x", hash)
    }
    
    private func verifyChecksum(_ data: Data, expected: String) -> Bool {
        return calculateChecksum(data) == expected
    }
}

// MARK: - Supporting Types

public struct ShareOffer: Codable {
    let offerId: String
    let packageId: String
    let chunkSize: Int
    let timestamp: Date
}

public struct ShareRequest: Codable {
    let requestId: String
    let packageId: String
    let requesterId: String
    let timestamp: Date
}

public struct PackageChunk: Codable {
    let sessionId: String
    let chunkIndex: Int
    let data: Data
    let checksum: String
    let isLast: Bool
}

public struct ResumeRequest: Codable {
    let sessionId: String
    let fromChunk: Int
    let timestamp: Date
}

// MARK: - Map Package P2P Delegate

public protocol MapPackageP2PDelegate: AnyObject {
    func mapPackageP2P(_ p2p: MapPackageP2P, shouldSendOffer offer: ShareOffer, to peerId: String)
    func mapPackageP2P(_ p2p: MapPackageP2P, didAcceptShare shareId: String)
    func mapPackageP2P(_ p2p: MapPackageP2P, didRejectShare shareId: String)
    func mapPackageP2P(_ p2p: MapPackageP2P, didCancelShare shareId: String)
    func mapPackageP2P(_ p2p: MapPackageP2P, shouldSendChunk chunk: PackageChunk, to peerId: String)
    func mapPackageP2P(_ p2p: MapPackageP2P, didReceiveChunk chunk: PackageChunk, for sessionId: String)
    func mapPackageP2P(_ p2p: MapPackageP2P, shouldSendResumeRequest request: ResumeRequest, to peerId: String)
    func mapPackageP2P(_ p2p: MapPackageP2P, didAcceptResume sessionId: String, fromChunk: Int)
    func mapPackageP2P(_ p2p: MapPackageP2P, didCompleteShare shareId: String)
    func mapPackageP2P(_ p2p: MapPackageP2P, shareFailed shareId: String, reason: String)
}

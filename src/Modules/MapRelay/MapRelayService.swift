//
//  MapRelayService.swift
//  SummerSpark
//
//  Map Package Mesh Relay Service
//  Manages P2P relay of map packages with multi-hop forwarding
//

import Foundation
import Crypto

// MARK: - MapRelayService

/// Manages map package relay over mesh network with broadcast and multi-hop forwarding
final class MapRelayService: MapRelayServiceProtocol {
    
    // MARK: - Properties
    
    weak var delegate: MapRelayDelegate?
    
    private let nodeId: String
    private let cacheManager: MapRelayCacheManager
    private let integrityVerifier: TileIntegrityVerifier
    private var isRelaying = false
    private var pendingRequests: [String: TileRequest] = [:]
    private var activeRelays: [String: RelaySession] = [:]
    private var announcementTimers: [String: Timer] = [:]
    private var knownPackages: [String: MapPackage] = [:]
    private var tileCache: [String: CachedTile] = [:]
    private var relayStatistics = RelayStatistics()
    
    private let maxHops = 5
    private let announcementInterval: TimeInterval = 30
    private let cacheSizeLimit = 100 * 1024 * 1024 // 100MB
    
    // MARK: - Initialization
    
    init(nodeId: String, cacheManager: MapRelayCacheManager? = nil) {
        self.nodeId = nodeId
        self.cacheManager = cacheManager ?? MapRelayCacheManager(maxSizeBytes: 100 * 1024 * 1024)
        self.integrityVerifier = TileIntegrityVerifier()
    }
    
    // MARK: - Relay Control
    
    func startRelaying() {
        guard !isRelaying else { return }
        isRelaying = true
        relayStatistics.relayStartTime = Date()
        log("MapRelayService started relaying for node: \(nodeId)")
    }
    
    func stopRelaying() {
        isRelaying = false
        announcementTimers.values.forEach { $0.invalidate() }
        announcementTimers.removeAll()
        activeRelays.removeAll()
        relayStatistics.relayStartTime = nil
        log("MapRelayService stopped relaying")
    }
    
    // MARK: - Broadcast Map Availability
    
    func broadcastMapAvailability(_ packages: [MapPackage]) {
        guard isRelaying else {
            log("Cannot broadcast - relaying not started")
            return
        }
        
        for package in packages {
            knownPackages[package.id] = package
            broadcastAnnouncement(package)
            scheduleAnnouncements(for: package)
        }
        
        log("Broadcast availability for \(packages.count) packages")
    }
    
    private func broadcastAnnouncement(_ package: MapPackage) {
        let announcement = MapAnnouncement(
            id: UUID().uuidString,
            packageId: package.id,
            packageName: package.name,
            regionName: package.regionName,
            totalTiles: package.totalTiles,
            fileSizeBytes: package.fileSizeBytes,
            checksum: package.checksum,
            sourceNodeId: nodeId,
            timestamp: Date(),
            ttl: maxHops
        )
        
        relayStatistics.announcementsSent += 1
        log("Broadcast announcement for package: \(package.name)")
        
        delegate?.mapRelay(self, didUpdateProgress: RelayProgress(
            packageId: package.id,
            phase: .announcing,
            tilesRelayed: 0,
            totalTiles: package.totalTiles,
            bytesTransferred: 0,
            currentRelays: [nodeId]
        ))
    }
    
    private func scheduleAnnouncements(for package: MapPackage) {
        let timer = Timer.scheduledTimer(withTimeInterval: announcementInterval, repeats: true) { [weak self] _ in
            self?.broadcastAnnouncement(package)
        }
        announcementTimers[package.id] = timer
    }
    
    // MARK: - Tile Requests
    
    func requestTile(_ tile: TileCoordinate, from sourceId: String) {
        let request = TileRequest(
            requestId: UUID().uuidString,
            tile: tile,
            requesterId: nodeId,
            timestamp: Date(),
            ttl: maxHops
        )
        
        pendingRequests[request.requestId] = request
        relayStatistics.tilesRequested += 1
        
        log("Request tile: \(tile.key) from: \(sourceId)")
        
        forwardTileRequest(request, hopCount: 0, visitedNodes: [nodeId])
    }
    
    func serveTile(_ tile: TileCoordinate, data: Data, via relayId: String) {
        guard let request = findRequest(for: tile) else {
            log("No pending request for tile: \(tile.key)")
            return
        }
        
        do {
            try verifyAndCacheTile(tile, data: data, sourceRelayId: relayId)
            
            delegate?.mapRelay(self, didReceiveTile: tile, data: data, from: [nodeId, relayId])
            
            pendingRequests.removeValue(forKey: request.requestId)
            relayStatistics.tilesServed += 1
            
            log("Served tile: \(tile.key) via relay: \(relayId)")
        } catch {
            log("Failed to serve tile: \(tile.key) - \(error)")
            delegate?.mapRelay(self, didFailWithError: error)
        }
    }
    
    private func findRequest(for tile: TileCoordinate) -> TileRequest? {
        return pendingRequests.values.first { $0.tile == tile }
    }
    
    // MARK: - Multi-Hop Forwarding
    
    func forwardTileRequest(_ request: TileRequest, hopCount: Int, visitedNodes: [String]) {
        guard hopCount < maxHops else {
            log("Max hops reached for request: \(request.requestId)")
            return
        }
        
        guard !request.isExpired else {
            log("Request expired: \(request.requestId)")
            return
        }
        
        let updatedVisited = visitedNodes + [nodeId]
        relayStatistics.requestsForwarded += 1
        
        log("Forward tile request: \(request.tile.key) hop: \(hopCount + 1)")
        
        if let cachedData = getCachedTileData(for: request.tile) {
            serveRequestedTile(request, data: cachedData)
        }
    }
    
    func forwardTileResponse(_ tile: TileCoordinate, data: Data, requestId: String, hopCount: Int, path: [String]) {
        guard hopCount < maxHops else { return }
        
        relayStatistics.responsesForwarded += 1
        relayStatistics.bytesForwarded += Int64(data.count)
        
        log("Forward tile response: \(tile.key) hops: \(path.count)")
    }
    
    // MARK: - Tile Verification and Caching
    
    private func verifyAndCacheTile(_ tile: TileCoordinate, data: Data, sourceRelayId: String) throws {
        let checksum = computeChecksum(for: data)
        
        let integrity = TileIntegrity(
            coordinate: tile,
            checksum: checksum,
            sizeBytes: data.count,
            signature: nil,
            verifiedAt: Date()
        )
        
        guard integrityVerifier.verifyChecksum(data, expected: checksum) else {
            throw RelayError.checksumMismatch(tile: tile.key)
        }
        
        let cachedTile = CachedTile(
            coordinate: tile,
            data: data,
            checksum: checksum,
            integrity: integrity,
            cachedAt: Date(),
            sourceRelayId: sourceRelayId
        )
        
        tileCache[tile.key] = cachedTile
        try cacheManager.store(tile: cachedTile)
        
        log("Verified and cached tile: \(tile.key) checksum: \(checksum.prefix(16))...")
    }
    
    private func computeChecksum(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func getCachedTileData(for tile: TileCoordinate) -> Data? {
        return tileCache[tile.key]?.data ?? cacheManager.getTileData(for: tile)
    }
    
    func hasTile(_ tile: TileCoordinate) -> Bool {
        return tileCache[tile.key] != nil || cacheManager.hasTile(tile)
    }
    
    // MARK: - Relay Statistics
    
    func getRelayStats() -> MapRelayStats {
        let cacheStats = cacheManager.getStats()
        
        return MapRelayStats(
            totalTilesServed: relayStatistics.tilesServed,
            totalTilesReceived: relayStatistics.tilesReceived,
            totalBytesServed: relayStatistics.bytesServed,
            totalBytesReceived: relayStatistics.bytesReceived,
            activeRelays: activeRelays.count,
            cacheHitRate: cacheStats.hitRate
        )
    }
    
    // MARK: - Package Management
    
    func registerPackage(_ package: MapPackage) {
        knownPackages[package.id] = package
        log("Registered package: \(package.name)")
    }
    
    func getKnownPackages() -> [MapPackage] {
        return Array(knownPackages.values)
    }
    
    func removePackage(_ packageId: String) {
        knownPackages.removeValue(forKey: packageId)
        announcementTimers[packageId]?.invalidate()
        announcementTimers.removeValue(forKey: packageId)
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        tileCache.removeAll()
        cacheManager.clearAll()
        log("Cache cleared")
    }
    
    func getCacheSize() -> Int64 {
        return cacheManager.getCurrentSize()
    }
    
    func pruneCache() {
        cacheManager.pruneOldest(count: 10)
        log("Cache pruned")
    }
    
    // MARK: - Relay Session Management
    
    func startRelaySession(_ session: RelaySession) {
        activeRelays[session.id] = session
        log("Started relay session: \(session.id)")
    }
    
    func endRelaySession(_ sessionId: String) {
        activeRelays.removeValue(forKey: sessionId)
        log("Ended relay session: \(sessionId)")
    }
    
    func getActiveSessions() -> [RelaySession] {
        return Array(activeRelays.values)
    }
    
    // MARK: - Logging
    
    private func log(_ message: String) {
        print("[MapRelayService] \(message)")
    }
}

// MARK: - Supporting Types

struct MapAnnouncement: Codable {
    let id: String
    let packageId: String
    let packageName: String
    let regionName: String
    let totalTiles: Int
    let fileSizeBytes: Int64
    let checksum: String
    let sourceNodeId: String
    let timestamp: Date
    let ttl: Int
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > TimeInterval(ttl * 60)
    }
}

struct RelaySession: Codable, Identifiable {
    let id: String
    let packageId: String
    let peerId: String
    let state: RelaySessionState
    let tilesTransferred: Int
    let totalTiles: Int
    let bytesTransferred: Int64
    let startedAt: Date
    
    enum RelaySessionState: String, Codable {
        case negotiating
        case transferring
        case verifying
        case completed
        case failed
    }
    
    var progress: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(tilesTransferred) / Double(totalTiles)
    }
}

struct CachedTile: Codable {
    let coordinate: TileCoordinate
    let data: Data
    let checksum: String
    let integrity: TileIntegrity
    let cachedAt: Date
    let sourceRelayId: String
}

struct RelayStatistics {
    var tilesServed = 0
    var tilesReceived = 0
    var tilesRequested = 0
    var announcementsSent = 0
    var requestsForwarded = 0
    var responsesForwarded = 0
    var bytesServed: Int64 = 0
    var bytesReceived: Int64 = 0
    var bytesForwarded: Int64 = 0
    var relayStartTime: Date?
}

enum RelayError: LocalizedError {
    case checksumMismatch(tile: String)
    case tileNotFound(tile: String)
    case maxHopsExceeded
    case requestExpired
    case cacheFull
    case verificationFailed
    
    var errorDescription: String? {
        switch self {
        case .checksumMismatch(let tile):
            return "Checksum mismatch for tile: \(tile)"
        case .tileNotFound(let tile):
            return "Tile not found: \(tile)"
        case .maxHopsExceeded:
            return "Maximum hop count exceeded"
        case .requestExpired:
            return "Tile request has expired"
        case .cacheFull:
            return "Cache is full"
        case .verificationFailed:
            return "Tile verification failed"
        }
    }
}

// MARK: - MapRelayCacheManager

final class MapRelayCacheManager {
    
    private let maxSizeBytes: Int64
    private var currentSize: Int64 = 0
    private var tileIndex: [String: TileCacheEntry] = [:]
    private var accessOrder: [String] = []
    private let queue = DispatchQueue(label: "com.summerspark.maprelay.cache")
    
    init(maxSizeBytes: Int64) {
        self.maxSizeBytes = maxSizeBytes
    }
    
    func store(tile: CachedTile) throws {
        try queue.sync {
            let size = Int64(tile.data.count)
            
            if currentSize + size > maxSizeBytes {
                try evictIfNeeded(spaceNeeded: size)
            }
            
            let entry = TileCacheEntry(
                tile: tile,
                sizeBytes: size,
                lastAccessed: Date()
            )
            
            tileIndex[tile.coordinate.key] = entry
            accessOrder.append(tile.coordinate.key)
            currentSize += size
        }
    }
    
    func getTileData(for tile: TileCoordinate) -> Data? {
        return queue.sync {
            guard let entry = tileIndex[tile.key] else { return nil }
            entry.lastAccessed = Date()
            moveToEndOfAccessOrder(tile.key)
            return entry.tile.data
        }
    }
    
    func hasTile(_ tile: TileCoordinate) -> Bool {
        return queue.sync {
            tileIndex[tile.key] != nil
        }
    }
    
    func removeTile(_ tile: TileCoordinate) {
        queue.sync {
            guard let entry = tileIndex.removeValue(forKey: tile.key) else { return }
            currentSize -= entry.sizeBytes
            accessOrder.removeAll { $0 == tile.key }
        }
    }
    
    func clearAll() {
        queue.sync {
            tileIndex.removeAll()
            accessOrder.removeAll()
            currentSize = 0
        }
    }
    
    func pruneOldest(count: Int) {
        queue.sync {
            for _ in 0..<count where !accessOrder.isEmpty {
                let oldestKey = accessOrder.removeFirst()
                guard let entry = tileIndex.removeValue(forKey: oldestKey) else { continue }
                currentSize -= entry.sizeBytes
            }
        }
    }
    
    func getCurrentSize() -> Int64 {
        return queue.sync { currentSize }
    }
    
    func getStats() -> CacheStats {
        return queue.sync {
            CacheStats(
                totalTiles: tileIndex.count,
                totalBytes: currentSize,
                maxBytes: maxSizeBytes,
                hitRate: 0.0
            )
        }
    }
    
    private func evictIfNeeded(spaceNeeded: Int64) throws {
        var spaceFreed: Int64 = 0
        let targetSpace = spaceNeeded
        
        while spaceFreed < targetSpace && !accessOrder.isEmpty {
            let key = accessOrder.removeFirst()
            guard let entry = tileIndex.removeValue(forKey: key) else { continue }
            spaceFreed += entry.sizeBytes
        }
        
        if currentSize + spaceNeeded > maxSizeBytes && accessOrder.isEmpty {
            throw RelayError.cacheFull
        }
    }
    
    private func moveToEndOfAccessOrder(_ key: String) {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }
    }
}

struct TileCacheEntry {
    var tile: CachedTile
    var sizeBytes: Int64
    var lastAccessed: Date
}

struct CacheStats {
    let totalTiles: Int
    let totalBytes: Int64
    let maxBytes: Int64
    let hitRate: Double
    
    var utilization: Double {
        guard maxBytes > 0 else { return 0 }
        return Double(totalBytes) / Double(maxBytes)
    }
}

// MARK: - GeoRegion

struct GeoRegion: Codable {
    let northLat: Double
    let southLat: Double
    let eastLon: Double
    let westLon: Double
    
    func contains(lat: Double, lon: Double) -> Bool {
        return lat >= southLat && lat <= northLat &&
               lon >= westLon && lon <= eastLon
    }
}

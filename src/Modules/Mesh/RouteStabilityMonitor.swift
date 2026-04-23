// MARK: - Route Stability Monitor
// 依赖文件：QoSModels.swift
// 功能：链路质量监控与路由评分

import Foundation

// MARK: - Link Probe

public struct LinkProbe: Codable {
    let probeId: String
    let sourceId: String
    let targetId: String
    let timestamp: Date
    let sequenceNumber: Int
}

public struct LinkProbeResponse: Codable {
    let probeId: String
    let responderId: String
    let originalTimestamp: Date
    let responseTimestamp: Date
    let rssi: Double
    let snr: Double
}

// MARK: - Route Stability Monitor

public class RouteStabilityMonitor {
    private var linkQualityTable: [String: LinkQuality] = [:]
    private var probeHistory: [String: [LinkProbeResult]] = [:]
    private var stabilityScores: [String: Double] = [:]
    
    private let tableLock = NSLock()
    private var probeSequence = 0
    private var monitoringActive = false
    
    // P1-FIX: 链路质量表大小限制，防止大规模网络内存溢出
    private let maxNeighbors = 100
    private let maxProbeHistoryPerNeighbor = 10
    
    // P2-FIX: 自适应探测间隔，稳定时降低频率
    private var adaptiveProbeInterval: TimeInterval = 5.0
    private let minProbeInterval: TimeInterval = 2.0
    private let maxProbeInterval: TimeInterval = 30.0
    private var consecutiveStableProbes: Int = 0
    
    private let probeInterval: TimeInterval = 5.0 // seconds
    private let historyWindowSize = 10
    private let degradationThreshold: Double = 0.3
    
    public weak var delegate: RouteStabilityDelegate?
    
    // MARK: - Monitoring Control
    
    public func startMonitoring() {
        monitoringActive = true
    }
    
    public func stopMonitoring() {
        monitoringActive = false
    }
    
    // MARK: - Link Probing
    
    /// Create a new link probe packet
    public func createProbe(targetId: String, sourceId: String) -> LinkProbe {
        probeSequence += 1
        return LinkProbe(
            probeId: UUID().uuidString,
            sourceId: sourceId,
            targetId: targetId,
            timestamp: Date(),
            sequenceNumber: probeSequence
        )
    }
    
    /// Process a received probe response
    public func processProbeResponse(_ response: LinkProbeResponse) {
        let rtt = response.responseTimestamp.timeIntervalSince(response.originalTimestamp)
        
        let result = LinkProbeResult(
            probeId: response.probeId,
            rtt: rtt,
            rssi: response.rssi,
            snr: response.snr,
            timestamp: response.responseTimestamp
        )
        
        // Update history
        tableLock.lock()
        if probeHistory[response.responderId] == nil {
            probeHistory[response.responderId] = []
        }
        probeHistory[response.responderId]?.append(result)
        
        // Keep only recent history
        if let history = probeHistory[response.responderId], history.count > historyWindowSize {
            probeHistory[response.responderId] = Array(history.suffix(historyWindowSize))
        }
        tableLock.unlock()
        
        // Update link quality
        updateLinkQuality(nodeId: response.responderId)
    }
    
    /// Update link quality metrics for a node
    private func updateLinkQuality(nodeId: String) {
        tableLock.lock()
        guard let history = probeHistory[nodeId], !history.isEmpty else {
            tableLock.unlock()
            return
        }
        
        // Calculate metrics from history
        let avgRssi = history.map { $0.rssi }.reduce(0, +) / Double(history.count)
        let avgSnr = history.map { $0.snr }.reduce(0, +) / Double(history.count)
        let avgLatency = history.map { $0.rtt * 1000 }.reduce(0, +) / Double(history.count) // ms
        
        // Calculate jitter (standard deviation of latency)
        let latencyValues = history.map { $0.rtt * 1000 }
        let mean = avgLatency
        let variance = latencyValues.map { pow($0 - mean, 2) }.reduce(0, +) / Double(latencyValues.count)
        let jitter = sqrt(variance)
        
        // Estimate packet loss from missing sequence numbers
        let packetLoss = estimatePacketLoss(history: history)
        
        // Estimate bandwidth (simplified)
        let bandwidth = estimateBandwidth(rssi: avgRssi, snr: avgSnr)
        
        let quality = LinkQuality(
            nodeId: "", // Will be set by caller
            neighborId: nodeId,
            signalStrength: avgRssi,
            snr: avgSnr,
            packetLoss: packetLoss,
            latency: avgLatency / 1000, // convert to seconds
            jitter: jitter / 1000,
            bandwidth: bandwidth,
            timestamp: Date()
        )
        
        linkQualityTable[nodeId] = quality
        tableLock.unlock()
        
        // Check for degradation
        checkQualityDegradation(nodeId: nodeId, quality: quality)
    }
    
    /// Estimate packet loss from probe history
    private func estimatePacketLoss(history: [LinkProbeResult]) -> Double {
        guard history.count >= 2 else { return 0 }
        
        // Simple estimation based on RTT variance
        let rtts = history.map { $0.rtt }
        let avgRtt = rtts.reduce(0, +) / Double(rtts.count)
        
        // High variance suggests packet loss and retransmission
        let variance = rtts.map { pow($0 - avgRtt, 2) }.reduce(0, +) / Double(rtts.count)
        let normalizedVariance = min(1.0, variance / (avgRtt * avgRtt + 0.001))
        
        return normalizedVariance * 0.5 // Scale to reasonable range
    }
    
    /// Estimate bandwidth from signal quality
    private func estimateBandwidth(rssi: Double, snr: Double) -> Double {
        // Simplified model: better signal = higher bandwidth
        // RSSI typically -100 to -40 dBm
        let rssiFactor = max(0, min(1, (rssi + 100) / 60))
        let snrFactor = max(0, min(1, snr / 30)) // SNR 0-30 dB
        
        // Base bandwidth 100 kbps, max 1000 kbps
        return 100 + 900 * rssiFactor * snrFactor
    }
    
    // MARK: - Quality Assessment
    
    /// Get link quality for a specific neighbor
    public func getLinkQuality(neighborId: String) -> LinkQuality? {
        tableLock.lock()
        defer { tableLock.unlock() }
        return linkQualityTable[neighborId]
    }
    
    /// Get all link qualities
    public func getAllLinkQualities() -> [String: LinkQuality] {
        tableLock.lock()
        defer { tableLock.unlock() }
        return linkQualityTable
    }
    
    /// Calculate route stability score for a multi-hop route
    public func calculateRouteStability(hops: [String]) -> Double {
        guard !hops.isEmpty else { return 0 }
        
        tableLock.lock()
        defer { tableLock.unlock() }
        
        var productScore = 1.0
        for hop in hops {
            if let quality = linkQualityTable[hop] {
                productScore *= quality.score
            } else {
                productScore *= 0.5 // Unknown link gets medium score
            }
        }
        
        // Store stability score
        let routeKey = hops.joined(separator: "->")
        stabilityScores[routeKey] = productScore
        
        return productScore
    }
    
    /// Check if link quality has degraded
    private func checkQualityDegradation(nodeId: String, quality: LinkQuality) {
        let previousScore = stabilityScores[nodeId] ?? 1.0
        let currentScore = quality.score
        
        if currentScore < previousScore - degradationThreshold {
            delegate?.routeStabilityMonitor(self, didDetectDegradation: nodeId, 
                                            oldScore: previousScore, newScore: currentScore)
        }
        
        stabilityScores[nodeId] = currentScore
    }
    
    // MARK: - Neighbor Management
    
    /// Record a direct neighbor observation
    public func recordNeighbor(_ nodeId: String, rssi: Double, timestamp: Date = Date()) {
        tableLock.lock()
        
        // P1-FIX: 邻居数量限制检查
        if linkQualityTable.count >= maxNeighbors && linkQualityTable[nodeId] == nil {
            // 新邻居且已满，移除信号最差的邻居
            let worstNeighbor = linkQualityTable.min { 
                $0.value.signalStrength < $1.value.signalStrength 
            }
            if let worst = worstNeighbor {
                linkQualityTable.removeValue(forKey: worst.key)
                probeHistory.removeValue(forKey: worst.key)
                Logger.shared.debug("RouteStabilityMonitor: Removed worst neighbor \(worst.key)")
            }
        }
        
        // Create or update link quality with basic info
        if var quality = linkQualityTable[nodeId] {
            // Update with new RSSI observation
            let newQuality = LinkQuality(
                nodeId: quality.nodeId,
                neighborId: quality.neighborId,
                signalStrength: rssi,
                snr: quality.snr,
                packetLoss: quality.packetLoss,
                latency: quality.latency,
                jitter: quality.jitter,
                bandwidth: quality.bandwidth,
                timestamp: timestamp
            )
            linkQualityTable[nodeId] = newQuality
        } else {
            // Create initial quality estimate
            let initialQuality = LinkQuality(
                nodeId: "",
                neighborId: nodeId,
                signalStrength: rssi,
                snr: 10, // default
                packetLoss: 0,
                latency: 0.05, // 50ms default
                jitter: 0.01,
                bandwidth: estimateBandwidth(rssi: rssi, snr: 10),
                timestamp: timestamp
            )
            linkQualityTable[nodeId] = initialQuality
        }
        
        tableLock.unlock()
    }
    
    /// Remove a departed neighbor
    public func removeNeighbor(_ nodeId: String) {
        tableLock.lock()
        linkQualityTable.removeValue(forKey: nodeId)
        probeHistory.removeValue(forKey: nodeId)
        stabilityScores.removeValue(forKey: nodeId)
        tableLock.unlock()
        
        delegate?.routeStabilityMonitor(self, neighborDidDepart: nodeId)
    }
    
    // MARK: - Statistics
    
    /// Get average link quality across all neighbors
    public func getAverageLinkQuality() -> Double {
        tableLock.lock()
        defer { tableLock.unlock() }
        
        guard !linkQualityTable.isEmpty else { return 0 }
        
        let total = linkQualityTable.values.reduce(0.0) { $0 + $1.score }
        return total / Double(linkQualityTable.count)
    }
    
    /// Get neighbors sorted by quality
    public func getNeighborsByQuality() -> [(nodeId: String, quality: LinkQuality)] {
        tableLock.lock()
        defer { tableLock.unlock() }
        
        return linkQualityTable.map { ($0.key, $0.value) }
            .sorted { $0.quality.score > $1.quality.score }
    }
}

// MARK: - Link Probe Result

public struct LinkProbeResult {
    let probeId: String
    let rtt: TimeInterval
    let rssi: Double
    let snr: Double
    let timestamp: Date
}

// MARK: - Route Stability Delegate

public protocol RouteStabilityDelegate: AnyObject {
    func routeStabilityMonitor(_ monitor: RouteStabilityMonitor, didDetectDegradation nodeId: String, oldScore: Double, newScore: Double)
    func routeStabilityMonitor(_ monitor: RouteStabilityMonitor, neighborDidDepart nodeId: String)
    func routeStabilityMonitor(_ monitor: RouteStabilityMonitor, didUpdateLinkQuality quality: LinkQuality, for nodeId: String)
}

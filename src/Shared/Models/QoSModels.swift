import Foundation

// MARK: - Link Quality Metrics
/// Represents the quality of a mesh link between two nodes
struct LinkQuality: Codable, Comparable {
    let nodeId: String
    let neighborId: String
    let signalStrength: Double // dBm
    let snr: Double // Signal-to-Noise Ratio in dB
    let packetLoss: Double // 0.0 to 1.0
    let latency: TimeInterval // milliseconds
    let jitter: TimeInterval // milliseconds
    let bandwidth: Double // kbps
    let timestamp: Date

    /// Overall quality score 0.0 (worst) to 1.0 (best)
    var score: Double {
        let signalScore = max(0, min(1, (signalStrength + 100) / 60)) // -100 to -40 dBm
        let lossScore = 1.0 - packetLoss
        let latencyScore = max(0, min(1, 1.0 - (latency / 1000.0))) // 0 to 1000ms
        let jitterScore = max(0, min(1, 1.0 - (jitter / 200.0))) // 0 to 200ms

        return signalScore * 0.3 + lossScore * 0.3 + latencyScore * 0.2 + jitterScore * 0.2
    }

    var qualityLevel: QualityLevel {
        switch score {
        case 0.8...1.0: return .excellent
        case 0.6..<0.8: return .good
        case 0.4..<0.6: return .fair
        case 0.2..<0.4: return .poor
        default: return .critical
        }
    }

    enum QualityLevel: String, Codable {
        case excellent
        case good
        case fair
        case poor
        case critical

        var canCarryTraffic: Bool {
            self != .critical
        }
    }

    static func < (lhs: LinkQuality, rhs: LinkQuality) -> Bool {
        lhs.score < rhs.score
    }
}

// MARK: - QoS Class
/// Quality of Service class for traffic prioritization
enum QoSClass: Int, Codable, CaseIterable {
    case background = 0    // Lowest priority, delay tolerant
    case bestEffort = 1    // Default
    case interactive = 2   // Voice/video
    case streaming = 3     // Media streaming
    case critical = 4     // Emergency/control

    var queuePriority: Int { rawValue }

    var description: String {
        switch self {
        case .background: return "Background"
        case .bestEffort: return "Best Effort"
        case .interactive: return "Interactive"
        case .streaming: return "Streaming"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Traffic Descriptor
/// Describes the QoS requirements of a traffic flow
struct TrafficDescriptor: Codable {
    let flowId: String
    let qosClass: QoSClass
    let priority: MessagePriority
    let maxLatency: TimeInterval? // milliseconds
    let maxJitter: TimeInterval? // milliseconds
    let minBandwidth: Double? // kbps
    let packetSize: Int? // bytes
    let isBursty: Bool

    func meetsRequirements(linkQuality: LinkQuality) -> Bool {
        if let maxLat = maxLatency, linkQuality.latency > maxLat / 1000.0 {
            return false
        }
        if let maxJit = maxJitter, linkQuality.jitter > maxJit / 1000.0 {
            return false
        }
        if let minBw = minBandwidth, linkQuality.bandwidth < minBw {
            return false
        }
        return linkQuality.qualityLevel.canCarryTraffic
    }
}

// MARK: - Route Metrics
/// Metrics for evaluating route quality
struct RouteMetrics: Codable {
    let routeId: String
    let hopCount: Int
    let endToEndLatency: TimeInterval // milliseconds
    let endToEndJitter: TimeInterval // milliseconds
    let endToEndPacketLoss: Double
    let totalBandwidth: Double // kbps
    let stabilityScore: Double // 0.0 to 1.0
    let timestamp: Date

    var isStable: Bool {
        stabilityScore >= 0.6 && hopCount <= 5
    }

    var qualityScore: Double {
        let latencyScore = max(0, min(1, 1.0 - (endToEndLatency / 5000.0)))
        let lossScore = 1.0 - endToEndPacketLoss
        return stabilityScore * 0.5 + latencyScore * 0.3 + lossScore * 0.2
    }
}

// MARK: - Route Handover Event
/// Event when a route failover occurs
struct RouteHandoverEvent: Codable {
    let eventId: String
    let oldRouteId: String
    let newRouteId: String
    let reason: HandoverReason
    let timestamp: Date
    let affectedFlows: [String]

    enum HandoverReason: String, Codable {
        case linkFailure
        case qualityDegradation
        case nodeDeparture
        case manual
        case loadBalancing
        case timeout
    }
}

// MARK: - Scheduled Task Priority
/// Priority for scheduled mesh tasks
struct ScheduledTask: Codable, Identifiable {
    let id: String
    let taskType: TaskType
    let priority: MessagePriority
    let creditCost: Int
    let createdAt: Date
    let scheduledFor: Date?
    let expiresAt: Date?
    let constraints: TaskConstraints?

    enum TaskType: String, Codable {
        case mapTileRequest
        case mapTileResponse
        case locationBroadcast
        case routeUpdate
        case creditSync
        case voicePacket
        case dataRelay
    }

    struct TaskConstraints: Codable {
        let maxLatency: TimeInterval?
        let requiredMinBandwidth: Double?
        let requiresStableRoute: Bool
    }

    var isExpired: Bool {
        if let exp = expiresAt { return Date() > exp }
        return false
    }
}

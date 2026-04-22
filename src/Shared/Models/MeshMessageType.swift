import Foundation

/// Types of messages that can be sent over the mesh network
enum MeshMessageType: String, Codable, CaseIterable {
    // Discovery messages
    case nodeAnnouncement = "node.announce"
    case nodeDiscovery = "node.discovery"
    case nodeDeparture = "node.departure"

    // Routing messages
    case routeRequest = "route.request"
    case routeResponse = "route.response"
    case routeUpdate = "route.update"

    // Data messages
    case broadcast = "data.broadcast"
    case directMessage = "data.direct"
    case groupMessage = "data.group"

    // Voice messages
    case voiceData = "voice.data"
    case voiceSessionStart = "voice.session.start"
    case voiceSessionEnd = "voice.session.end"

    // Credit messages
    case creditTransfer = "credit.transfer"
    case creditSync = "credit.sync"
    case creditBalanceQuery = "credit.query"

    // Location messages
    case locationUpdate = "location.update"
    case locationRequest = "location.request"
    case locationBroadcast = "location.broadcast"

    // System messages
    case ping = "system.ping"
    case pong = "system.pong"
    case ack = "system.ack"
    case error = "system.error"

    // Group messages
    case groupCreate = "group.create"
    case groupJoin = "group.join"
    case groupLeave = "group.leave"
    case groupMemberUpdate = "group.member.update"
    case groupKeyDistribution = "group.key.distribute"

    // MARK: - Message Category

    var category: MessageCategory {
        switch self {
        case .nodeAnnouncement, .nodeDiscovery, .nodeDeparture:
            return .discovery
        case .routeRequest, .routeResponse, .routeUpdate:
            return .routing
        case .broadcast, .directMessage, .groupMessage:
            return .data
        case .voiceData, .voiceSessionStart, .voiceSessionEnd:
            return .voice
        case .creditTransfer, .creditSync, .creditBalanceQuery:
            return .credit
        case .locationUpdate, .locationRequest, .locationBroadcast:
            return .location
        case .ping, .pong, .ack, .error:
            return .system
        case .groupCreate, .groupJoin, .groupLeave, .groupMemberUpdate, .groupKeyDistribution:
            return .group
        }
    }

    enum MessageCategory: String, CaseIterable {
        case discovery
        case routing
        case data
        case voice
        case credit
        case location
        case system
        case group
    }

    // MARK: - Priority

    var priority: MessagePriority {
        switch self {
        case .error, .pong:
            return .critical
        case .nodeAnnouncement, .nodeDeparture, .voiceSessionStart, .voiceSessionEnd, .groupCreate, .groupLeave:
            return .high
        case .directMessage, .groupMessage, .voiceData, .locationBroadcast:
            return .normal
        case .broadcast, .locationUpdate, .locationRequest, .creditSync, .creditBalanceQuery, .routeRequest, .routeResponse:
            return .low
        case .ping, .ack, .nodeDiscovery, .routeUpdate, .groupMemberUpdate, .groupKeyDistribution, .creditTransfer, .groupJoin:
            return .background
        }
    }

    enum MessagePriority: Int, Comparable {
        case background = 0
        case low = 1
        case normal = 2
        case high = 3
        case critical = 4

        static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Reliability

    var requiresAck: Bool {
        switch self {
        case .error, .groupCreate, .groupJoin, .groupLeave, .creditTransfer, .directMessage:
            return true
        default:
            return false
        }
    }

    var isReliable: Bool {
        return priority.rawValue >= MessagePriority.normal.rawValue
    }

    // MARK: - Payload Type

    var expectedPayloadType: PayloadType {
        switch self {
        case .voiceData:
            return .audio
        case .locationUpdate, .locationRequest, .locationBroadcast:
            return .location
        case .creditTransfer, .creditSync, .creditBalanceQuery:
            return .credit
        default:
            return .generic
        }
    }

    enum PayloadType: String {
        case generic
        case audio
        case location
        case credit
        case group
    }
}
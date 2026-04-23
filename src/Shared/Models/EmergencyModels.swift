import Foundation
import CoreLocation

// MARK: - Emergency Type

/// Types of emergency situations
enum EmergencyType: String, Codable, CaseIterable {
    case injury = "injury"
    case lost = "lost"
    case trapped = "trapped"
    case medical = "medical"
    case fire = "fire"
    case flood = "flood"
    case earthquake = "earthquake"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .injury: return "Injury"
        case .lost: return "Lost"
        case .trapped: return "Trapped"
        case .medical: return "Medical Emergency"
        case .fire: return "Fire"
        case .flood: return "Flood"
        case .earthquake: return "Earthquake"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .injury: return "cross.case"
        case .lost: return "location.slash"
        case .trapped: return "person.crop.circle.badge.exclamationmark"
        case .medical: return "heart.text.square"
        case .fire: return "flame"
        case .flood: return "drop"
        case .earthquake: return "waveform.path"
        case .other: return "exclamationmark.triangle"
        }
    }
    
    var defaultPriority: MessagePriority {
        switch self {
        case .medical, .fire, .earthquake:
            return .emergency
        case .trapped, .flood:
            return .rescue
        case .injury, .lost:
            return .rescue
        case .other:
            return .rescue
        }
    }
}

// MARK: - Severity Level

/// Severity level of an emergency
enum Severity: Int, Codable, Comparable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    
    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
}

// MARK: - Message Priority (Extended for Emergency)

/// Message priority levels for emergency communications
enum MessagePriority: Int, Codable, Comparable {
    case background = 0
    case normal = 1
    case command = 2
    case rescue = 3
    case emergency = 4
    
    static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var displayName: String {
        switch self {
        case .background: return "Background"
        case .normal: return "Normal"
        case .command: return "Command"
        case .rescue: return "Rescue"
        case .emergency: return "Emergency"
        }
    }
}

// MARK: - SOS Status

/// Status of an SOS signal
enum SOSStatus: String, Codable {
    case inactive = "inactive"
    case active = "active"
    case responded = "responded"
    case resolved = "resolved"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .inactive: return "Inactive"
        case .active: return "Active"
        case .responded: return "Responded"
        case .resolved: return "Resolved"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Emergency SOS

/// Emergency SOS signal structure
struct EmergencySOS: Codable, Identifiable {
    let id: String
    let senderId: String
    let senderName: String?
    let type: EmergencyType
    let severity: Severity
    let location: LocationData
    let timestamp: Date
    var status: SOSStatus
    let message: String?
    let batteryLevel: Double?
    let signalStrength: Int?
    let ttl: Int
    
    init(
        id: String = UUID().uuidString,
        senderId: String,
        senderName: String? = nil,
        type: EmergencyType,
        severity: Severity,
        location: LocationData,
        message: String? = nil,
        batteryLevel: Double? = nil,
        signalStrength: Int? = nil,
        ttl: Int = 60
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.type = type
        self.severity = severity
        self.location = location
        self.timestamp = Date()
        self.status = .active
        self.message = message
        self.batteryLevel = batteryLevel
        self.signalStrength = signalStrength
        self.ttl = ttl
    }
    
    var isExpired: Bool {
        let expirationTime = TimeInterval(ttl * 60)
        return Date().timeIntervalSince(timestamp) > expirationTime
    }
    
    var priority: MessagePriority {
        switch severity {
        case .critical:
            return .emergency
        case .high:
            return .rescue
        case .medium:
            return .rescue
        case .low:
            return .command
        }
    }
}

// MARK: - Rescue Task

/// A rescue task assigned to a team or individual
struct RescueTask: Codable, Identifiable {
    let id: String
    let sosId: String
    var assignedTeamId: String?
    var assignedMemberIds: [String]
    let targetLocation: LocationData
    let createdAt: Date
    var updatedAt: Date
    var status: RescueTaskStatus
    var priority: MessagePriority
    var estimatedArrivalTime: Date?
    var actualArrivalTime: Date?
    var notes: String?
    
    enum RescueTaskStatus: String, Codable {
        case pending = "pending"
        case assigned = "assigned"
        case enRoute = "en_route"
        case onScene = "on_scene"
        case inProgress = "in_progress"
        case completed = "completed"
        case cancelled = "cancelled"
        
        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .assigned: return "Assigned"
            case .enRoute: return "En Route"
            case .onScene: return "On Scene"
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }
    }
    
    init(
        id: String = UUID().uuidString,
        sosId: String,
        targetLocation: LocationData,
        priority: MessagePriority = .rescue
    ) {
        self.id = id
        self.sosId = sosId
        self.assignedTeamId = nil
        self.assignedMemberIds = []
        self.targetLocation = targetLocation
        self.createdAt = Date()
        self.updatedAt = Date()
        self.status = .pending
        self.priority = priority
        self.estimatedArrivalTime = nil
        self.actualArrivalTime = nil
        self.notes = nil
    }
}

// MARK: - Rescue Team

/// A rescue team with members and capabilities
struct RescueTeam: Codable, Identifiable {
    let id: String
    var name: String
    var leaderId: String
    var memberIds: [String]
    var capabilities: Set<RescueCapability>
    var currentLocation: LocationData?
    var status: TeamStatus
    var currentTaskId: String?
    let createdAt: Date
    var updatedAt: Date
    
    enum RescueCapability: String, Codable, CaseIterable {
        case medical = "medical"
        case search = "search"
        case rescue = "rescue"
        case fire = "fire"
        case water = "water"
        case technical = "technical"
        
        var displayName: String {
            switch self {
            case .medical: return "Medical"
            case .search: return "Search"
            case .rescue: return "Rescue"
            case .fire: return "Fire Fighting"
            case .water: return "Water Rescue"
            case .technical: return "Technical Rescue"
            }
        }
    }
    
    enum TeamStatus: String, Codable {
        case available = "available"
        case busy = "busy"
        case offline = "offline"
        case responding = "responding"
        
        var displayName: String {
            switch self {
            case .available: return "Available"
            case .busy: return "Busy"
            case .offline: return "Offline"
            case .responding: return "Responding"
            }
        }
    }
    
    init(
        id: String = UUID().uuidString,
        name: String,
        leaderId: String,
        memberIds: [String] = [],
        capabilities: Set<RescueCapability> = []
    ) {
        self.id = id
        self.name = name
        self.leaderId = leaderId
        self.memberIds = memberIds
        self.capabilities = capabilities
        self.currentLocation = nil
        self.status = .available
        self.currentTaskId = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var isAvailable: Bool {
        status == .available && currentTaskId == nil
    }
}

// MARK: - Victim Marker

/// A marker indicating a victim's location and status
struct VictimMarker: Codable, Identifiable {
    let id: String
    let sosId: String?
    var location: LocationData
    var severity: Severity
    var condition: String?
    var assignedRescuerId: String?
    var status: VictimStatus
    let createdAt: Date
    var updatedAt: Date
    var notes: String?
    var tags: Set<String>
    
    enum VictimStatus: String, Codable {
        case pending = "pending"
        case acknowledged = "acknowledged"
        case helpEnRoute = "help_en_route"
        case beingAssisted = "being_assisted"
        case rescued = "rescued"
        case deceased = "deceased"
        case missing = "missing"
        
        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .acknowledged: return "Acknowledged"
            case .helpEnRoute: return "Help En Route"
            case .beingAssisted: return "Being Assisted"
            case .rescued: return "Rescued"
            case .deceased: return "Deceased"
            case .missing: return "Missing"
            }
        }
        
        var color: String {
            switch self {
            case .pending: return "red"
            case .acknowledged: return "orange"
            case .helpEnRoute: return "yellow"
            case .beingAssisted: return "blue"
            case .rescued: return "green"
            case .deceased: return "gray"
            case .missing: return "purple"
            }
        }
    }
    
    init(
        id: String = UUID().uuidString,
        sosId: String? = nil,
        location: LocationData,
        severity: Severity,
        condition: String? = nil
    ) {
        self.id = id
        self.sosId = sosId
        self.location = location
        self.severity = severity
        self.condition = condition
        self.assignedRescuerId = nil
        self.status = .pending
        self.createdAt = Date()
        self.updatedAt = Date()
        self.notes = nil
        self.tags = []
    }
    
    var needsAssistance: Bool {
        switch status {
        case .pending, .acknowledged, .helpEnRoute:
            return true
        case .beingAssisted, .rescued, .deceased, .missing:
            return false
        }
    }
}

// MARK: - Emergency Message

/// Message for emergency communication over mesh network
struct EmergencyMessage: Codable {
    let id: String
    let type: EmergencyMessageType
    let senderId: String
    let timestamp: Date
    let priority: MessagePriority
    let payload: Data
    
    enum EmergencyMessageType: String, Codable {
        case sos = "emergency.sos"
        case sosAck = "emergency.sos.ack"
        case sosCancel = "emergency.sos.cancel"
        case taskAssign = "emergency.task.assign"
        case taskUpdate = "emergency.task.update"
        case victimMark = "emergency.victim.mark"
        case victimUpdate = "emergency.victim.update"
        case rescueBeacon = "emergency.beacon"
    }
    
    init(type: EmergencyMessageType, senderId: String, priority: MessagePriority, payload: Data) {
        self.id = UUID().uuidString
        self.type = type
        self.senderId = senderId
        self.timestamp = Date()
        self.priority = priority
        self.payload = payload
    }
}

// MARK: - Emergency Statistics

/// Statistics for emergency monitoring
struct EmergencyStatistics: Codable {
    var activeSOSCount: Int
    var pendingTasksCount: Int
    var victimsPendingCount: Int
    var victimsRescuedCount: Int
    var availableTeamsCount: Int
    var respondingTeamsCount: Int
    let updatedAt: Date
    
    init() {
        self.activeSOSCount = 0
        self.pendingTasksCount = 0
        self.victimsPendingCount = 0
        self.victimsRescuedCount = 0
        self.availableTeamsCount = 0
        self.respondingTeamsCount = 0
        self.updatedAt = Date()
    }
}

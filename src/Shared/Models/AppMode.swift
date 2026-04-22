import Foundation

/// Represents the current operational mode of the application
enum AppMode: String, Codable {
    /// Normal user mode with full features
    case normal

    /// Offline mesh mode for disaster scenarios
    case meshOnly

    /// Emergency mode with limited features
    case emergency

    /// Developer/testing mode
    case development

    /// Maintenance mode
    case maintenance

    // MARK: - Mode Properties

    var displayName: String {
        switch self {
        case .normal:
            return "Normal Mode"
        case .meshOnly:
            return "Mesh Only"
        case .emergency:
            return "Emergency"
        case .development:
            return "Development"
        case .maintenance:
            return "Maintenance"
        }
    }

    var isOfflineCapable: Bool {
        switch self {
        case .normal, .meshOnly, .emergency:
            return true
        case .development, .maintenance:
            return false
        }
    }

    var allowsVoiceCommunication: Bool {
        switch self {
        case .normal, .meshOnly, .development:
            return true
        case .emergency, .maintenance:
            return false
        }
    }

    var allowsCreditOperations: Bool {
        switch self {
        case .normal, .meshOnly:
            return true
        case .emergency, .development, .maintenance:
            return false
        }
    }

    var allowsMapAccess: Bool {
        switch self {
        case .normal, .development:
            return true
        case .meshOnly, .emergency, .maintenance:
            return false
        }
    }

    // MARK: - Mode Transitions

    var availableTransitions: [AppMode] {
        switch self {
        case .normal:
            return [.meshOnly, .emergency, .development]
        case .meshOnly:
            return [.normal, .emergency]
        case .emergency:
            return [.normal, .meshOnly]
        case .development:
            return [.normal, .maintenance]
        case .maintenance:
            return [.development, .normal]
        }
    }

    func canTransition(to newMode: AppMode) -> Bool {
        return availableTransitions.contains(newMode)
    }
}

/// Represents the connectivity status of the device
enum ConnectivityStatus: String, Codable {
    case online
    case offline
    case switching
    case unknown

    var isConnected: Bool {
        return self == .online
    }
}

/// Represents the sync state for data synchronization
enum SyncState: String, Codable {
    case idle
    case syncing
    case completed
    case failed
    case pending

    var isInProgress: Bool {
        return self == .syncing || self == .pending
    }
}
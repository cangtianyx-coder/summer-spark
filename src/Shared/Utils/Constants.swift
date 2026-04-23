import Foundation

// MARK: - App Constants

enum AppConstants {
    // App Info
    static let appName = "SummerSpark"
    static let appBundleId = "com.summerspark.app"
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    // Network
    enum Network {
        static let meshBroadcastInterval: TimeInterval = 5.0
        static let nodeExpirationInterval: TimeInterval = 30.0
        static let connectionTimeout: TimeInterval = 10.0
        static let maxRetryAttempts = 3
        static let packetSize = 512
        static let maxTTL = 64
        static let discoveryBroadcastRadius: Double = 100.0 // meters
    }

    // Bluetooth
    enum Bluetooth {
        static let serviceUUID = "12345678-1234-1234-1234-123456789ABC"
        static let characteristicUUID = "12345678-1234-1234-1234-123456789ABD"
        static let scanInterval: TimeInterval = 2.0
        static let minRSSI = -100
        static let maxPeripherals = 20
    }

    // WiFi
    enum WiFi {
        static let hotspotPrefix = "SummerSpark-"
        static let connectionRetryInterval: TimeInterval = 5.0
        static let maxConnectionAttempts = 3
    }

    // Credit System
    enum Credit {
        static let maxBalance: Double = 100000.0
        static let minTransactionAmount: Double = 0.01
        static let decayRate: Double = 0.05
        static let decayIntervalDays: Int = 30
        static let maxPenaltyRatio: Double = 0.5

        // Tier thresholds
        static let bronzeThreshold: Double = 0
        static let silverThreshold: Double = 1000
        static let goldThreshold: Double = 5000
        static let platinumThreshold: Double = 10000
    }

    // Storage
    enum Storage {
        static let keychainService = "com.summerspark.keychain"
        static let userDefaultsSuite = "group.com.summerspark.shared"
        static let databaseName = "summerspark.db"
        static let cacheExpirationDays = 7
        static let maxCacheSizeMB = 100
    }

    // Voice
    enum Voice {
        static let sampleRate: Double = 16000
        static let bitRate = 128000
        static let maxRecordingDuration: TimeInterval = 300.0
        static let pushToTalkHoldTime: TimeInterval = 0.3
        static let voicePacketInterval: TimeInterval = 0.05
    }

    // Map
    enum Map {
        static let defaultZoom: Double = 15.0
        static let maxZoom: Double = 20.0
        static let minZoom: Double = 3.0
        static let offlineRegionBufferMeters: Double = 1000
        static let pathRecalculationDistance: Double = 50.0
    }

    // Security
    enum Security {
        static let keySize = 256
        static let signatureAlgorithm = "P256"
        static let tokenRefreshInterval: TimeInterval = 3600
        static let sessionTimeout: TimeInterval = 86400
        static let maxFailedAttempts = 5
    }

    // Timing
    enum Timing {
        static let animationDuration: TimeInterval = 0.3
        static let toastDisplayDuration: TimeInterval = 2.0
        static let debounceInterval: TimeInterval = 0.5
        static let throttleInterval: TimeInterval = 1.0
    }

    // UI
    enum UI {
        static let cornerRadius: CGFloat = 12.0
        static let borderWidth: CGFloat = 1.0
        static let iconSize: CGFloat = 24.0
        static let avatarSize: CGFloat = 40.0
        static let buttonHeight: CGFloat = 48.0
        static let maxListItemTitleLength = 100
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // App Lifecycle
    static let appDidEnterForeground = Notification.Name("com.summerspark.app.didEnterForeground")
    static let appDidEnterBackground = Notification.Name("com.summerspark.app.didEnterBackground")
    static let appWillTerminate = Notification.Name("com.summerspark.app.willTerminate")

    // Mode Changes
    static let appModeDidChange = Notification.Name("com.summerspark.app.modeDidChange")
    static let connectivityStatusDidChange = Notification.Name("com.summerspark.connectivity.statusDidChange")

    // Mesh Network
    static let meshNodeDiscovered = Notification.Name("com.summerspark.mesh.nodeDiscovered")
    static let meshNodeLost = Notification.Name("com.summerspark.mesh.nodeLost")
    static let meshMessageReceived = Notification.Name("com.summerspark.mesh.messageReceived")
    static let meshRouteUpdated = Notification.Name("com.summerspark.mesh.routeUpdated")

    // Credit
    static let creditBalanceDidChange = Notification.Name("com.summerspark.credit.balanceDidChange")
    static let creditSyncCompleted = Notification.Name("com.summerspark.credit.syncCompleted")
    static let creditTierDidChange = Notification.Name("com.summerspark.credit.tierDidChange")

    // Group
    static let groupCreated = Notification.Name("com.summerspark.group.created")
    static let groupMemberAdded = Notification.Name("com.summerspark.group.memberAdded")
    static let groupMemberRemoved = Notification.Name("com.summerspark.group.memberRemoved")
    static let groupUpdated = Notification.Name("com.summerspark.group.updated")

    // Identity
    static let identityDidChange = Notification.Name("com.summerspark.identity.didChange")
    static let publicKeyRotated = Notification.Name("com.summerspark.identity.publicKeyRotated")

    // Voice
    static let voiceSessionStarted = Notification.Name("com.summerspark.voice.sessionStarted")
    static let voiceSessionEnded = Notification.Name("com.summerspark.voice.sessionEnded")
    static let voicePushToTalkPressed = Notification.Name("com.summerspark.voice.pushToTalkPressed")

    // Location
    static let locationUpdated = Notification.Name("com.summerspark.location.updated")
    static let locationPermissionChanged = Notification.Name("com.summerspark.location.permissionChanged")

    // Sync
    static let syncStateDidChange = Notification.Name("com.summerspark.sync.stateDidChange")
    static let syncCompleted = Notification.Name("com.summerspark.sync.completed")
    static let syncFailed = Notification.Name("com.summerspark.sync.failed")

    // Error
    static let errorOccurred = Notification.Name("com.summerspark.error.occurred")
}

// MARK: - UserDefaults Keys

enum UserDefaultsKeys {
    static let identityUID = "identity.uid"
    static let identityUsername = "identity.username"
    static let identityPrivateKey = "identity.privateKey"
    static let appMode = "app.mode"
    static let lastSyncTimestamp = "sync.lastTimestamp"
    static let creditBalance = "credit.balance"
    static let groupsData = "groups.store"
    static let userGroupsMap = "groups.userGroups"
    static let onboardingCompleted = "onboarding.completed"
    static let pushNotificationsEnabled = "push.notifications.enabled"
    static let locationPermissionGranted = "location.permission.granted"
    static let meshEnabled = "mesh.enabled"
    static let voiceEnabled = "voice.enabled"
}

// MARK: - Keychain Keys

enum KeychainKeys {
    static let service = "com.summerspark.keychain"
    static let encryptionKey = "encryption.key"
    static let privateKey = "identity.privateKey"
    static let uid = "identity.uid"
    static let username = "identity.username"
    static let sessionToken = "session.token"
    static let databaseKey = "database.key"
}

// MARK: - Background Task Identifiers

enum BackgroundTaskIdentifiers {
    static let refresh = "com.summerspark.refresh"
    static let sync = "com.summerspark.sync"
    static let mapDownload = "com.summerspark.map.download"
    static let creditSync = "com.summerspark.credit.sync"
}

// MARK: - URL Schemes

enum URLSchemes {
    static let scheme = "summerspark"
    static let groupPrefix = "summerspark://group/"
    static let profilePrefix = "summerspark://profile/"
    static let settingsPrefix = "summerspark://settings/"
}

// MARK: - Error Domain

enum ErrorDomain {
    static let mesh = "com.summerspark.error.mesh"
    static let credit = "com.summerspark.error.credit"
    static let identity = "com.summerspark.error.identity"
    static let storage = "com.summerspark.error.storage"
    static let network = "com.summerspark.error.network"
    static let crypto = "com.summerspark.error.crypto"
    static let voice = "com.summerspark.error.voice"
    static let location = "com.summerspark.error.location"
}
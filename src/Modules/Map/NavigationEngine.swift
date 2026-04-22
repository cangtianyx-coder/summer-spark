import Foundation
import AVFoundation
import CoreLocation

// MARK: - Navigation Event
struct NavigationEvent {
    let timestamp: Date
    let type: EventType
    let message: String
    let coordinate: Coordinate?

    enum EventType {
        case approach
        case turn
        case destination
        case detour
        case speedAlert
    }
}

// MARK: - Voice Announcement
protocol VoiceAnnouncementDelegate: AnyObject {
    func shouldAnnounce(_ message: String)
}

// MARK: - Text Notification
protocol TextNotificationDelegate: AnyObject {
    func shouldNotify(_ message: String, priority: NotificationPriority)
}

enum NotificationPriority: Int {
    case low = 0
    case medium = 1
    case high = 2
    case urgent = 3
}

// MARK: - Navigation State
enum NavigationState {
    case idle
    case active
    case paused
    case completed
    case error(String)
}

// MARK: - Offline Navigation Engine
class NavigationEngine: NSObject {
    // MARK: - Properties
    private var currentRoute: RouteResult?
    private var currentPathIndex: Int = 0
    private var currentState: NavigationState = .idle
    private var locationUpdateInterval: TimeInterval = 1.0
    private var lastAnnouncedIndex: Int = 0
    private var audioPlayer: AVAudioPlayer?
    private var speechSynthesizer: AVSpeechSynthesizer?

    weak var voiceDelegate: VoiceAnnouncementDelegate?
    weak var textDelegate: TextNotificationDelegate?

    private var eventLog: [NavigationEvent] = []
    private var reroutingThreshold: Double = 20.0 // meters

    // Configuration
    var announceDistanceBefore: Double = 100.0 // meters
    var voiceEnabled: Bool = true
    var textEnabled: Bool = true

    // MARK: - Initialization
    override init() {
        super.init()
        setupAudioSession()
        setupSpeechSynthesizer()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func setupSpeechSynthesizer() {
        speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer?.delegate = self
    }

    // MARK: - Route Management
    func loadRoute(_ route: RouteResult) {
        currentRoute = route
        currentPathIndex = 0
        currentState = .idle
        lastAnnouncedIndex = 0
        eventLog.removeAll()
        logEvent(.destination, message: "Route loaded: \(route.path.count) waypoints")
    }

    func startNavigation() {
        guard currentRoute != nil else {
            currentState = .error("No route loaded")
            return
        }
        currentState = .active
        logEvent(.approach, message: "Navigation started")
        announce("Navigation started. Follow the highlighted route.")
    }

    func pauseNavigation() {
        currentState = .paused
        logEvent(.approach, message: "Navigation paused")
        announce("Navigation paused.")
    }

    func resumeNavigation() {
        currentState = .active
        logEvent(.approach, message: "Navigation resumed")
        announce("Navigation resumed.")
    }

    func stopNavigation() {
        currentState = .idle
        currentPathIndex = 0
        logEvent(.destination, message: "Navigation stopped")
        announce("Navigation stopped.")
    }

    // MARK: - Location Update (Simulated for Offline)
    func updateLocation(_ coordinate: Coordinate) {
        guard case .active = currentState else { return }
        guard let route = currentRoute else { return }

        // Check if approaching next waypoint
        if currentPathIndex < route.path.count {
            let nextWaypoint = route.path[currentPathIndex]
            let distance = calculateDistance(from: coordinate, to: nextWaypoint)

            // Check for rerouting
            checkForRerouting(current: coordinate, route: route)

            // Announce based on distance
            if distance < announceDistanceBefore && currentPathIndex > lastAnnouncedIndex {
                announceUpcomingManeuver(at: currentPathIndex, distance: distance)
                lastAnnouncedIndex = currentPathIndex
            }

            // Check if reached waypoint
            if distance < 5.0 {
                reachedWaypoint(at: currentPathIndex)
            }
        }

        // Check if reached destination
        if currentPathIndex >= route.path.count - 1 {
            let destination = route.path.last!
            let distance = calculateDistance(from: coordinate, to: destination)
            if distance < 10.0 {
                completeNavigation()
            }
        }
    }

    // MARK: - Maneuver Announcement
    private func announceUpcomingManeuver(at index: Int, distance: Double) {
        guard let route = currentRoute else { return }

        if index < route.maneuverInstructions.count {
            let maneuver = route.maneuverInstructions[index]
            let message = "\(Int(distance)) meters ahead. \(maneuver.instruction)"
            announce(message)
            notify(message, priority: .high)
        } else {
            // General turn announcement
            let message = "\(Int(distance)) meters to next waypoint"
            announce(message)
            notify(message, priority: .medium)
        }
    }

    private func reachedWaypoint(at index: Int) {
        currentPathIndex = index + 1
        if currentPathIndex < currentRoute!.path.count {
            let nextCoord = currentRoute!.path[currentPathIndex]
            announce("Passed waypoint. Continue to next destination.")
            notify("Next waypoint reached. Recalculating route...", priority: .low)
        }
    }

    // MARK: - Voice Announcement
    private func announce(_ message: String) {
        guard voiceEnabled else { return }

        // Use speech synthesizer for TTS
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        speechSynthesizer?.speak(utterance)
        voiceDelegate?.shouldAnnounce(message)
    }

    private func notify(_ message: String, priority: NotificationPriority) {
        guard textEnabled else { return }
        textDelegate?.shouldNotify(message, priority: priority)
    }

    // MARK: - Rerouting
    private func checkForRerouting(current: Coordinate, route: RouteResult) {
        // Find closest point on route
        var minDistance: Double = .infinity
        var closestIndex = 0

        for (i, coord) in route.path.enumerated() {
            let distance = calculateDistance(from: current, to: coord)
            if distance < minDistance {
                minDistance = distance
                closestIndex = i
            }
        }

        // If too far from route, trigger rerouting
        if minDistance > reroutingThreshold {
            logEvent(.detour, message: "Off route detected! Distance: \(Int(minDistance))m")
            announce("You have departed from the route. Recalculating...")
            notify("Off-route alert! Recalculating path...", priority: .urgent)
        }
    }

    // MARK: - Navigation Completion
    private func completeNavigation() {
        currentState = .completed
        logEvent(.destination, message: "Destination reached")
        announce("You have arrived at your destination.")
        notify("Navigation completed successfully!", priority: .high)
    }

    // MARK: - Event Logging
    private func logEvent(_ type: NavigationEvent.EventType, message: String, coordinate: Coordinate? = nil) {
        let event = NavigationEvent(timestamp: Date(), type: type, message: message, coordinate: coordinate)
        eventLog.append(event)
    }

    // MARK: - Offline Map Data
    func getCachedMapData(for region: Coordinate, radius: Double) -> [String: Any]? {
        // Simulated offline map data retrieval
        // In a real implementation, this would access local map tile cache
        return [
            "region": region,
            "radius": radius,
            "tiles": [] as [String],
            "pois": [] as [String]
        ]
    }

    // MARK: - Utilities
    private func calculateDistance(from: Coordinate, to: Coordinate) -> Double {
        let R = 6371000.0 // Earth's radius in meters
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(from.latitude * .pi / 180) * cos(to.latitude * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // MARK: - Status
    func getNavigationState() -> NavigationState {
        return currentState
    }

    func getEventLog() -> [NavigationEvent] {
        return eventLog
    }

    func getCurrentProgress() -> (currentIndex: Int, totalPoints: Int, distanceTraveled: Double, distanceRemaining: Double) {
        guard let route = currentRoute else {
            return (0, 0, 0, 0)
        }

        let distanceTraveled = currentPathIndex > 0 ?
            route.path.prefix(currentPathIndex + 1).enumerated().reduce(0.0) { sum, pair in
                if pair.offset > 0 {
                    let prev = route.path[pair.offset - 1]
                    let curr = pair.element
                    return sum + calculateDistance(from: prev, to: curr)
                }
                return sum
            } : 0.0

        let distanceRemaining = route.distance - distanceTraveled

        return (currentPathIndex, route.path.count, distanceTraveled, distanceRemaining)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension NavigationEngine: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Speech finished
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Speech cancelled
    }
}
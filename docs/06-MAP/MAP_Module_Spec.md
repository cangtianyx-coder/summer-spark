# MAP Module Specification

## 1. Module Overview

The MAP module provides offline-capable map navigation services for the Summer Spark mesh networking application. It handles coordinate system conversion, offline map management, path planning with A* algorithm, and turn-by-turn navigation.

**Directory**: `src/Modules/Map/`

### Components

| Component | File | Description |
|-----------|------|-------------|
| MapService | MapService.swift | Core map operations, coordinate systems, offline map info |
| NavigationEngine | NavigationEngine.swift | Turn-by-turn navigation, voice announcements |
| PathPlanner | PathPlanner.swift | A* pathfinding algorithm with obstacle avoidance |
| OfflineMapManager | OfflineMapManager.swift | Offline map download and management |
| MapCacheManager | MapCacheManager.swift | Tile caching for offline use |

---

## 2. Coordinate Systems

### Supported Systems

| System | Identifier | Description |
|--------|------------|-------------|
| WGS84 | `wgs84` | World Geodetic System 1984 (default, international standard) |
| GCJ-02 | `gcj02` | Chinese encrypted coordinate system |
| BD-09 | `bd09` | Baidu-specific coordinate system |

### Conversion Functions

```
CoordinateConverter.wgs84ToGcj02(coord) -> Coordinate2D
CoordinateConverter.wgs84ToBd09(coord) -> Coordinate2D
CoordinateConverter.gcj02ToWgs84(coord) -> Coordinate2D
CoordinateConverter.bd09ToWgs84(coord) -> Coordinate2D
```

### Map Types

| Type | Identifier |
|------|------------|
| Standard | `standard` |
| Satellite | `satellite` |
| Terrain | `terrain` |
| Hybrid | `hybrid` |

---

## 3. Data Structures

### OfflineMapInfo

```swift
struct OfflineMapInfo: Codable, Equatable {
    let mapId: String
    let name: String
    let version: String
    let tileCount: Int
    let downloadedTileCount: Int
    let fileSize: Int64
    let downloadedSize: Int64
    let bounds: MapBounds
    let minZoom: Int
    let maxZoom: Int
    let mapType: MapType
    let coordinateSystem: CoordinateSystem
    let lastUpdated: Date
    
    var downloadProgress: Double  // downloadedTileCount / tileCount
    var isComplete: Bool          // downloadedTileCount >= tileCount
}
```

### MapBounds

```swift
struct MapBounds: Codable, Equatable {
    let northEast: Coordinate2D
    let southWest: Coordinate2D
    var center: Coordinate2D  // (northEast + southWest) / 2
}
```

### Coordinate2D

```swift
struct Coordinate2D: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    
    func converted(to coordinateSystem: CoordinateSystem) -> Coordinate2D
}
```

---

## 4. MapService API

### Protocol: MapServiceDelegate

```swift
protocol MapServiceDelegate: AnyObject {
    func mapService(_ service: MapService, didLoadOfflineMap mapId: String)
    func mapService(_ service: MapService, didFailToLoadMap mapId: String, error: Error)
    func mapService(_ service: MapService, didUpdateCoordinateSystem coordinateSystem: CoordinateSystem)
    func mapService(_ service: MapService, didUpdateOfflineProgress progress: OfflineMapProgress)
    func mapServiceDidUpdateAvailableMaps(_ service: MapService)
}
```

### Class: MapService (Singleton)

```swift
final class MapService {
    static let shared = MapService()
    
    weak var delegate: MapServiceDelegate?
    var currentCoordinateSystem: CoordinateSystem = .wgs84
    
    // Methods
    func loadOfflineMap(mapId: String) async throws -> OfflineMapInfo
    func getAvailableOfflineMaps() -> [OfflineMapInfo]
    func deleteOfflineMap(mapId: String) -> Bool
    func convertCoordinate(_ coordinate: Coordinate2D, to system: CoordinateSystem) -> Coordinate2D
}
```

---

## 5. NavigationEngine API

### Navigation State

```swift
enum NavigationState {
    case idle
    case active
    case paused
    case completed
    case error(String)
}
```

### NavigationEvent

```swift
struct NavigationEvent {
    let timestamp: Date
    let type: EventType
    let message: String
    let coordinate: Coordinate?
    
    enum EventType {
        case approach   // Approaching waypoint
        case turn       // Turn instruction
        case destination // Arrived at destination
        case detour     // Rerouting required
        case speedAlert // Speed warning
    }
}
```

### Delegate Protocols

```swift
protocol VoiceAnnouncementDelegate: AnyObject {
    func shouldAnnounce(_ message: String)
}

protocol TextNotificationDelegate: AnyObject {
    func shouldNotify(_ message: String, priority: NotificationPriority)
}

enum NotificationPriority: Int {
    case low = 0
    case medium = 1
    case high = 2
    case urgent = 3
}
```

### Class: NavigationEngine

```swift
class NavigationEngine: NSObject {
    weak var voiceDelegate: VoiceAnnouncementDelegate?
    weak var textDelegate: TextNotificationDelegate?
    
    var announceDistanceBefore: Double = 100.0  // meters
    var voiceEnabled: Bool = true
    var textEnabled: Bool = true
    
    // Methods
    func startNavigation(route: RouteResult)
    func pauseNavigation()
    func resumeNavigation()
    func stopNavigation()
    func updateLocation(_ coordinate: Coordinate)
}
```

---

## 6. PathPlanner API

### PathNode (A* Algorithm)

```swift
struct PathNode: Equatable, Hashable {
    let coordinate: Coordinate
    let x: Int
    let y: Int
    var gCost: Double = .infinity  // Cost from start
    var hCost: Double = 0          // Heuristic cost to end
    var fCost: Double { gCost + hCost }
    var parent: PathNode?
}
```

### Coordinate (Grid-based)

```swift
struct Coordinate: Hashable {
    let latitude: Double
    let longitude: Double
}
```

### Obstacle

```swift
struct Obstacle {
    let coordinate: Coordinate
    let radius: Double  // in meters
}
```

### RouteResult

```swift
struct RouteResult {
    let path: [Coordinate]
    let distance: Double         // meters
    let estimatedTime: TimeInterval  // seconds
    let maneuverInstructions: [ManeuverInstruction]
}

struct ManeuverInstruction {
    let instruction: String
    let coordinate: Coordinate
    let distance: Double
}
```

### Class: PathPlanner

```swift
class PathPlanner {
    init(origin: Coordinate, widthMeters: Double, heightMeters: Double)
    
    // Grid resolution: 10 meters per cell
    func addObstacle(_ obstacle: Obstacle)
    func clearObstacles()
    func findPath(from start: Coordinate, to end: Coordinate) -> RouteResult?
}
```

**Grid Resolution**: 10 meters per cell  
**Algorithm**: A* with 8-directional movement

---

## 7. Configuration Defaults

| Parameter | Default Value |
|-----------|---------------|
| Grid Resolution | 10 meters/cell |
| Navigation Announcement Distance | 100 meters |
| Rerouting Threshold | 20 meters |
| Location Update Interval | 1.0 second |
| Voice Enabled | true |
| Text Enabled | true |

---

## 8. Dependencies

- **Framework**: Foundation, UIKit, AVFoundation, CoreLocation
- **Internal Dependencies**: None (standalone module)
- **External Dependencies**: None

---

## 9. Error Handling

MapService errors are delivered via delegate:

```swift
func mapService(_ service: MapService, didFailToLoadMap mapId: String, error: Error)
```

NavigationEngine errors are captured in NavigationState:

```swift
case error(String)
```

---

## 10. Thread Safety

- NavigationEngine: Main thread for UI updates, background queue for location processing
- PathPlanner: Thread-safe for concurrent reads, exclusive write for obstacle management
- MapService: async/await with actor-like isolation
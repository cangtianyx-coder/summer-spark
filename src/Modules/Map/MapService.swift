import Foundation
import UIKit

// MARK: - MapServiceDelegate

protocol MapServiceDelegate: AnyObject {
    func mapService(_ service: MapService, didLoadOfflineMap mapId: String)
    func mapService(_ service: MapService, didFailToLoadMap mapId: String, error: Error)
    func mapService(_ service: MapService, didUpdateCoordinateSystem coordinateSystem: CoordinateSystem)
    func mapService(_ service: MapService, didUpdateOfflineProgress progress: OfflineMapProgress)
    func mapServiceDidUpdateAvailableMaps(_ service: MapService)
}

// MARK: - CoordinateSystem

enum CoordinateSystem: String, CaseIterable, Codable {
    case wgs84 = "WGS84"
    case gcj02 = "GCJ-02"
    case bd09 = "BD-09"
    
    var displayName: String {
        switch self {
        case .wgs84: return "World Geodetic System 1984"
        case .gcj02: return "GCJ-02 (China)"
        case .bd09: return "BD-09 (Baidu)"
        }
    }
}

// MARK: - MapType

enum MapType: String, CaseIterable, Codable {
    case standard = "standard"
    case satellite = "satellite"
    case terrain = "terrain"
    case hybrid = "hybrid"
}

// MARK: - OfflineMapInfo

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
    
    var downloadProgress: Double {
        guard tileCount > 0 else { return 0 }
        return Double(downloadedTileCount) / Double(tileCount)
    }
    
    var isComplete: Bool {
        return downloadedTileCount >= tileCount
    }
}

// MARK: - MapBounds

struct MapBounds: Codable, Equatable {
    let northEast: Coordinate2D
    let southWest: Coordinate2D
    
    var center: Coordinate2D {
        return Coordinate2D(
            latitude: (northEast.latitude + southWest.latitude) / 2,
            longitude: (northEast.longitude + southWest.longitude) / 2
        )
    }
}

// MARK: - Coordinate2D

struct Coordinate2D: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    
    func converted(to coordinateSystem: CoordinateSystem) -> Coordinate2D {
        switch coordinateSystem {
        case .wgs84:
            return self
        case .gcj02:
            return CoordinateConverter.wgs84ToGcj02(self)
        case .bd09:
            return CoordinateConverter.wgs84ToBd09(self)
        }
    }
}

// MARK: - CoordinateConverter

enum CoordinateConverter {
    
    static func wgs84ToGcj02(_ coord: Coordinate2D) -> Coordinate2D {
        let a = 6378245.0
        let ee = 0.00669342162296594323
        
        let dlat = transformLat(coord.longitude - 105.0, coord.latitude - 35.0)
        let dlon = transformLon(coord.longitude - 105.0, coord.latitude - 35.0)
        
        let radlat = coord.latitude / 180.0 * .pi
        var magic = sin(radlat)
        magic = 1 - ee * magic * magic
        let sqrtmagic = sqrt(magic)
        
        let dlatTrans = dlat * 180.0 / ((a * (1 - ee)) / (magic * sqrtmagic) * .pi)
        let dlonTrans = dlon * 180.0 / (a / sqrtmagic * cos(radlat) * .pi)
        
        return Coordinate2D(
            latitude: coord.latitude + dlatTrans,
            longitude: coord.longitude + dlonTrans
        )
    }
    
    static func wgs84ToBd09(_ coord: Coordinate2D) -> Coordinate2D {
        let gcj02 = wgs84ToGcj02(coord)
        return bd09Encrypt(gcj02.latitude, gcj02.longitude)
    }
    
    static func gcj02ToWgs84(_ coord: Coordinate2D) -> Coordinate2D {
        let dlat = transformLat(coord.longitude - 105.0, coord.latitude - 35.0)
        let dlon = transformLon(coord.longitude - 105.0, coord.latitude - 35.0)
        
        let radlat = coord.latitude / 180.0 * .pi
        var magic = sin(radlat)
        magic = 1 - 0.00669342162296594323 * magic * magic
        let sqrtmagic = sqrt(magic)
        
        let dlatTrans = dlat * 180.0 / ((6378245.0 * (1 - 0.00669342162296594323)) / (magic * sqrtmagic) * .pi)
        let dlonTrans = dlon * 180.0 / (6378245.0 / sqrtmagic * cos(radlat) * .pi)
        
        return Coordinate2D(
            latitude: coord.latitude - dlatTrans,
            longitude: coord.longitude - dlonTrans
        )
    }
    
    static func bd09ToWgs84(_ coord: Coordinate2D) -> Coordinate2D {
        let gcj02 = bd09Decrypt(coord.latitude, coord.longitude)
        return gcj02ToWgs84(gcj02)
    }
    
    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }
    
    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
    
    private static func bd09Encrypt(_ lat: Double, _ lon: Double) -> Coordinate2D {
        let x = lon - 0.0065
        let y = lat - 0.006
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * .pi)
        let theta = atan2(y, x) - 0.000003 * cos(x * .pi)
        return Coordinate2D(
            latitude: z * sin(theta),
            longitude: z * cos(theta)
        )
    }
    
    private static func bd09Decrypt(_ lat: Double, _ lon: Double) -> Coordinate2D {
        let x = lon
        let y = lat
        let z = sqrt(x * x + y * y) + 0.00002 * sin(y * .pi)
        let theta = atan2(y, x) + 0.000003 * cos(x * .pi)
        return Coordinate2D(
            latitude: z * sin(theta) + 0.006,
            longitude: z * cos(theta) + 0.0065
        )
    }
}

// MARK: - OfflineMapProgress

struct OfflineMapProgress: Equatable {
    let mapId: String
    let totalTiles: Int
    let downloadedTiles: Int
    let totalBytes: Int64
    let downloadedBytes: Int64
    let currentTileCoord: TileCoordinate?
    let isResumable: Bool
    
    var progress: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(downloadedTiles) / Double(totalTiles)
    }
    
    var bytesProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }
    
    var isComplete: Bool {
        return downloadedTiles >= totalTiles
    }
    
    static let zero = OfflineMapProgress(
        mapId: "",
        totalTiles: 0,
        downloadedTiles: 0,
        totalBytes: 0,
        downloadedBytes: 0,
        currentTileCoord: nil,
        isResumable: false
    )
}

// MARK: - TileCoordinate

struct TileCoordinate: Equatable, Hashable, Codable {
    let x: Int
    let y: Int
    let zoom: Int
    
    var key: String {
        return "\(zoom)-\(x)-\(y)"
    }
}

// MARK: - MapService

final class MapService {
    static let shared = MapService()

    
    // MARK: - Properties
    
    weak var delegate: MapServiceDelegate?
    
    private(set) var currentCoordinateSystem: CoordinateSystem = .wgs84
    private(set) var currentMapType: MapType = .standard
    private(set) var availableOfflineMaps: [OfflineMapInfo] = []
    private(set) var isOfflineModeEnabled: Bool = false
    private(set) var currentOfflineMap: OfflineMapInfo?
    
    private let offlineManager: OfflineMapManager
    private let mapQueue = DispatchQueue(label: "com.map.service", qos: .userInitiated)
    private let userDefaults = UserDefaults.standard
    
    private let coordinateSystemKey = "MapService.CoordinateSystem"
    private let offlineMapsKey = "MapService.OfflineMaps"
    
    // MARK: - Initialization
    
    private init() {
        self.offlineManager = OfflineMapManager()
        self.offlineManager.delegate = self
        loadSavedCoordinateSystem()
        loadAvailableOfflineMaps()
    }
    
    deinit {
        saveState()
    }
    
    // MARK: - Coordinate System
    
    func setCoordinateSystem(_ coordinateSystem: CoordinateSystem) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            
            let previousSystem = self.currentCoordinateSystem
            self.currentCoordinateSystem = coordinateSystem
            self.userDefaults.set(coordinateSystem.rawValue, forKey: self.coordinateSystemKey)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.mapService(self, didUpdateCoordinateSystem: coordinateSystem)
            }
        }
    }
    
    func convertCoordinate(_ coordinate: Coordinate2D, to targetSystem: CoordinateSystem) -> Coordinate2D {
        return coordinate.converted(to: targetSystem)
    }
    
    // MARK: - Map Type
    
    func setMapType(_ mapType: MapType) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentMapType = mapType
        }
    }
    
    // MARK: - Offline Mode
    
    func enableOfflineMode() {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            self.isOfflineModeEnabled = true
        }
    }
    
    func disableOfflineMode() {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            self.isOfflineModeEnabled = false
        }
    }
    
    // MARK: - Offline Maps
    
    func loadAvailableOfflineMaps() {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let data = self.userDefaults.data(forKey: self.offlineMapsKey),
               let maps = try? JSONDecoder().decode([OfflineMapInfo].self, from: data) {
                self.availableOfflineMaps = maps
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.mapServiceDidUpdateAvailableMaps(self)
            }
        }
    }
    
    func getOfflineMap(by mapId: String) -> OfflineMapInfo? {
        return availableOfflineMaps.first { $0.mapId == mapId }
    }
    
    func startDownloadingMap(_ mapInfo: OfflineMapInfo) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            self.offlineManager.startDownload(mapInfo)
        }
    }
    
    func pauseDownloadingMap(_ mapId: String) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            self.offlineManager.pauseDownload(mapId: mapId)
        }
    }
    
    func resumeDownloadingMap(_ mapId: String) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            self.offlineManager.resumeDownload(mapId: mapId)
        }
    }
    
    func cancelDownloadingMap(_ mapId: String) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            self.offlineManager.cancelDownload(mapId: mapId)
        }
    }
    
    func deleteOfflineMap(_ mapId: String) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            self.offlineManager.deleteMap(mapId: mapId)
            self.availableOfflineMaps.removeAll { $0.mapId == mapId }
            self.saveOfflineMapsList()
            
            if self.currentOfflineMap?.mapId == mapId {
                self.currentOfflineMap = nil
            }
        }
    }
    
    func setCurrentOfflineMap(_ mapId: String) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let map = self.availableOfflineMaps.first(where: { $0.mapId == mapId && $0.isComplete }) {
                self.currentOfflineMap = map
            }
        }
    }
    
    func getOfflineProgress(for mapId: String) -> OfflineMapProgress {
        return offlineManager.getProgress(for: mapId)
    }
    
    // MARK: - State Persistence
    
    private func loadSavedCoordinateSystem() {
        if let rawValue = userDefaults.string(forKey: coordinateSystemKey),
           let system = CoordinateSystem(rawValue: rawValue) {
            currentCoordinateSystem = system
        }
    }
    
    private func saveState() {
        saveOfflineMapsList()
    }
    
    private func saveOfflineMapsList() {
        if let data = try? JSONEncoder().encode(availableOfflineMaps) {
            userDefaults.set(data, forKey: offlineMapsKey)
        }
    }
    
    // MARK: - Configuration
    
    static func configure() {
        // Configure map tile servers, cache settings, and default coordinate system
        let cacheManager = MapCacheManager.shared
        _ = cacheManager.operationQueue
        
        // Set default coordinate system based on locale if needed
        let locale = Locale.current
        if let regionCode = locale.regionCode {
            switch regionCode {
            case "CN", "TW", "HK", "MO":
                shared.setCoordinateSystem(.gcj02)
            default:
                shared.setCoordinateSystem(.wgs84)
            }
        }
    }
    
    /// 清理缓存（内存警告时调用）
    func clearCache() {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            // 清理未完成的离线地图下载任务
            self.offlineManager.clearCache()
            Logger.shared.info("MapService: Cache cleared")
        }
    }
}

// MARK: - OfflineMapManagerDelegate

extension MapService: OfflineMapManagerDelegate {
    
    func offlineMapManager(_ manager: OfflineMapManager, didUpdateProgress progress: OfflineMapProgress) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.mapService(self, didUpdateOfflineProgress: progress)
        }
    }
    
    func offlineMapManager(_ manager: OfflineMapManager, didCompleteMap mapInfo: OfflineMapInfo) {
        mapQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let index = self.availableOfflineMaps.firstIndex(where: { $0.mapId == mapInfo.mapId }) {
                self.availableOfflineMaps[index] = mapInfo
            } else {
                self.availableOfflineMaps.append(mapInfo)
            }
            
            self.saveOfflineMapsList()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.mapService(self, didLoadOfflineMap: mapInfo.mapId)
                self.delegate?.mapServiceDidUpdateAvailableMaps(self)
            }
        }
    }
    
    func offlineMapManager(_ manager: OfflineMapManager, didFailMap mapId: String, error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.mapService(self, didFailToLoadMap: mapId, error: error)
        }
    }
}

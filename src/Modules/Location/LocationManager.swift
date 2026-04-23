import Foundation
import CoreLocation

// MARK: - LocationManagerDelegate

/// 位置管理器代理协议
protocol LocationManagerDelegate: AnyObject {
    /// 位置更新
    func locationManager(_ manager: LocationManager, didUpdateLocation location: LocationData)
    
    /// 位置授权状态变化
    func locationManager(_ manager: LocationManager, didChangeAuthorization status: CLAuthorizationStatus)
    
    /// 位置错误
    func locationManager(_ manager: LocationManager, didFailWithError error: Error)
    
    /// 进入地理围栏区域
    func locationManager(_ manager: LocationManager, didEnterRegion region: CLRegion)
    
    /// 离开地理围栏区域
    func locationManager(_ manager: LocationManager, didExitRegion region: CLRegion)
}

// MARK: - LocationData Extension

/// 位置数据扩展 - 添加Equatable和CLLocation转换
extension LocationData: Equatable {
    
    /// 转换为CLLocation
    var clLocation: CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude ?? 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 0,
            course: heading ?? 0,
            speed: speed ?? 0,
            timestamp: timestamp
        )
    }
    
    /// 2D坐标
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// 是否有效
    var isValid: Bool {
        return CLLocationCoordinate2DIsValid(coordinate)
    }
    
    /// 从CLLocation创建
    static func from(_ location: CLLocation) -> LocationData {
        return LocationData(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            accuracy: location.horizontalAccuracy,
            speed: location.speed,
            heading: location.course
        )
    }
    
    static func == (lhs: LocationData, rhs: LocationData) -> Bool {
        return lhs.latitude == rhs.latitude &&
               lhs.longitude == rhs.longitude &&
               lhs.timestamp == rhs.timestamp
    }
}

// MARK: - LocationSharingConfig

/// 位置共享配置
struct LocationSharingConfig {
    /// 组网模态位置更新间隔（秒）
    var networkingInterval: TimeInterval = 1.0
    
    /// 待机模态位置更新间隔（秒）
    var standbyInterval: TimeInterval = 300.0
    
    /// 最小更新距离（米）
    var minimumDistance: Double = 0.0
    
    /// 是否启用后台位置更新
    var enableBackgroundUpdates: Bool = true
    
    /// 期望的定位精度
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    
    /// 是否启用轨迹记录
    var enableTrackRecording: Bool = true
    
    /// 轨迹点最小间隔距离（米）
    var trackMinimumDistance: Double = 5.0
}

// MARK: - LocationManager

/// 位置管理器
/// 负责GPS定位、位置共享、轨迹记录
final class LocationManager: NSObject {
    
    // MARK: - Singleton
    
    static let shared = LocationManager()
    
    // MARK: - Properties
    
    weak var delegate: LocationManagerDelegate?
    
    /// 当前位置
    private(set) var currentLocation: LocationData?
    
    /// 当前运行模态
    private var currentMode: MeshOperationMode = .standby
    
    /// 配置
    var config: LocationSharingConfig = LocationSharingConfig()
    
    /// 是否正在运行
    private(set) var isRunning: Bool = false
    
    /// 轨迹记录
    private var trackPoints: [LocationData] = []
    
    /// 当前轨迹ID
    private(set) var currentTrackId: String?
    
    /// 最后一次共享位置的时间
    private var lastSharedTime: Date?
    
    /// CoreLocation管理器
    private let clLocationManager: CLLocationManager
    
    /// 位置更新队列
    private let locationQueue = DispatchQueue(label: "com.summerspark.locationmanager")
    
    /// 位置共享定时器
    private var sharingTimer: Timer?
    
    // MARK: - Initialization
    
    private override init() {
        self.clLocationManager = CLLocationManager()
        super.init()
        
        setupLocationManager()
    }
    
    deinit {
        stopSharingTimer()
        clLocationManager.stopUpdatingLocation()
        clLocationManager.stopUpdatingHeading()
    }
    
    // MARK: - Public API
    
    /// 启动位置服务
    func start() {
        locationQueue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isRunning = true
            
            // 请求授权
            self.requestAuthorization()
            
            // 开始更新位置
            DispatchQueue.main.async {
                // 先请求WhenInUse权限
                self.clLocationManager.requestWhenInUseAuthorization()
                // 然后请求Always权限（如果需要后台位置）
                self.clLocationManager.requestAlwaysAuthorization()
                self.clLocationManager.startUpdatingLocation()
                self.clLocationManager.startUpdatingHeading()
            }
        }
    }
    
    /// 停止位置服务
    func stop() {
        locationQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = false
            
            DispatchQueue.main.async {
                self.clLocationManager.stopUpdatingLocation()
                self.clLocationManager.stopUpdatingHeading()
            }
            
            self.stopSharingTimer()
        }
    }
    
    /// 切换运行模态
    /// - Parameter mode: 新的运行模态
    func setMode(_ mode: MeshOperationMode) {
        locationQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentMode = mode
            self.updateLocationSettings()
            self.restartSharingTimer()
        }
    }
    
    /// 开始轨迹记录
    /// - Parameter trackId: 轨迹ID（可选）
    func startTrackRecording(trackId: String? = nil) {
        locationQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.currentTrackId = trackId ?? UUID().uuidString
            self.trackPoints.removeAll()
            
            if let location = self.currentLocation {
                self.trackPoints.append(location)
            }
        }
    }
    
    /// 停止轨迹记录
    /// - Returns: 轨迹数据
    func stopTrackRecording() -> [LocationData] {
        return locationQueue.sync {
            let points = trackPoints
            currentTrackId = nil
            trackPoints.removeAll()
            return points
        }
    }
    
    /// 导出轨迹为GPX格式
    /// - Returns: GPX XML字符串
    func exportTrackAsGPX() -> String {
        return locationQueue.sync {
            exportTrackToGPX(trackPoints)
        }
    }
    
    /// 导出指定轨迹为GPX格式
    /// - Parameter points: 轨迹点
    /// - Returns: GPX XML字符串
    func exportTrackAsGPX(_ points: [LocationData]) -> String {
        return exportTrackToGPX(points)
    }
    
    /// 获取当前轨迹
    /// - Returns: 轨迹点数组
    func getCurrentTrack() -> [LocationData] {
        return locationQueue.sync {
            trackPoints
        }
    }
    
    /// 计算到目标点的距离
    /// - Parameter target: 目标位置
    /// - Returns: 距离（米）
    func distanceTo(_ target: LocationData) -> Double? {
        guard let current = currentLocation else { return nil }
        
        let currentCL = current.clLocation
        let targetCL = target.clLocation
        
        return currentCL.distance(from: targetCL)
    }
    
    /// 计算到目标点的方位角
    /// - Parameter target: 目标位置
    /// - Returns: 方位角（度，0-360）
    func bearingTo(_ target: LocationData) -> Double? {
        guard let current = currentLocation else { return nil }
        
        let lat1 = current.latitude * .pi / 180.0
        let lon1 = current.longitude * .pi / 180.0
        let lat2 = target.latitude * .pi / 180.0
        let lon2 = target.longitude * .pi / 180.0
        
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        
        var bearing = atan2(y, x) * 180.0 / .pi
        bearing = (bearing + 360.0).truncatingRemainder(dividingBy: 360.0)
        
        return bearing
    }
    
    /// 清理缓存（内存警告时调用）
    func clearCache() {
        locationQueue.async { [weak self] in
            guard let self = self else { return }
            // 清理轨迹点缓存（保留最近100个点）
            if self.trackPoints.count > 100 {
                self.trackPoints = Array(self.trackPoints.suffix(100))
            }
            Logger.shared.info("LocationManager: Cache cleared")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupLocationManager() {
        clLocationManager.delegate = self
        clLocationManager.desiredAccuracy = config.desiredAccuracy
        clLocationManager.distanceFilter = config.minimumDistance
        clLocationManager.activityType = .fitness
        clLocationManager.pausesLocationUpdatesAutomatically = false
        clLocationManager.allowsBackgroundLocationUpdates = config.enableBackgroundUpdates
        clLocationManager.showsBackgroundLocationIndicator = true
    }
    
    private func requestAuthorization() {
        let status = clLocationManager.authorizationStatus
        
        if status == .notDetermined {
            clLocationManager.requestAlwaysAuthorization()
        }
    }
    
    private func updateLocationSettings() {
        let interval = currentMode.locationUpdateInterval
        let accuracy: CLLocationAccuracy
        
        switch currentMode {
        case .standby:
            accuracy = kCLLocationAccuracyHundredMeters
        case .networking:
            accuracy = kCLLocationAccuracyBest
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clLocationManager.desiredAccuracy = accuracy
        }
        
        Logger.shared.info("LocationManager: mode changed to \(currentMode.rawValue), interval=\(interval)s")
    }
    
    private func restartSharingTimer() {
        stopSharingTimer()
        startSharingTimer()
    }
    
    private func startSharingTimer() {
        let interval = currentMode.locationUpdateInterval
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.shareLocation()
            }
            
            self.sharingTimer = timer
        }
    }
    
    private func stopSharingTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.sharingTimer?.invalidate()
            self?.sharingTimer = nil
        }
    }
    
    private func shareLocation() {
        guard let location = currentLocation else { return }
        
        // 通过Mesh服务广播位置
        // MeshService.shared.broadcastLocation(location)
        
        lastSharedTime = Date()
        
        Logger.shared.debug("LocationManager: shared location at \(location.timestamp)")
    }
    
    private func addTrackPoint(_ location: LocationData) {
        guard config.enableTrackRecording, currentTrackId != nil else { return }
        
        // 检查距离间隔
        if let lastPoint = trackPoints.last {
            let distance = lastPoint.clLocation.distance(from: location.clLocation)
            guard distance >= config.trackMinimumDistance else { return }
        }
        
        trackPoints.append(location)
    }
    
    private func exportTrackToGPX(_ points: [LocationData]) -> String {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="SummerSpark" xmlns="http://www.topografix.com/GPX/1/1">
        <trk>
        <trkseg>
        
        """
        
        let dateFormatter = ISO8601DateFormatter()
        
        for point in points {
            let time = dateFormatter.string(from: point.timestamp)
            gpx += """
                <trkpt lat="\(point.latitude)" lon="\(point.longitude)">
                    <ele>\(point.altitude)</ele>
                    <time>\(time)</time>
                </trkpt>
            
            """
        }
        
        gpx += """
        </trkseg>
        </trk>
        </gpx>
        """
        
        return gpx
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        let locationData = LocationData.from(location)
        
        locationQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.currentLocation = locationData
            self.addTrackPoint(locationData)
            
            DispatchQueue.main.async {
                self.delegate?.locationManager(self, didUpdateLocation: locationData)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.shared.error("LocationManager error: \(error)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.locationManager(self, didFailWithError: error)
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        Logger.shared.info("LocationManager authorization changed: \(status.rawValue)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.locationManager(self, didChangeAuthorization: status)
        }
        
        // 如果授权通过，开始更新位置
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Logger.shared.info("Entered region: \(region.identifier)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.locationManager(self, didEnterRegion: region)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Logger.shared.info("Exited region: \(region.identifier)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.locationManager(self, didExitRegion: region)
        }
    }
}

// MARK: - LocationSharingMessage

/// 位置共享消息
struct LocationSharingMessage: Codable {
    let uid: String
    let username: String?
    let location: LocationData
    let timestamp: Date
    let mode: MeshOperationMode
    
    init(location: LocationData) {
        self.uid = IdentityManager.shared.uid ?? ""
        self.username = IdentityManager.shared.username
        self.location = location
        self.timestamp = Date()
        // 默认使用组网模式
        self.mode = .networking
    }
}

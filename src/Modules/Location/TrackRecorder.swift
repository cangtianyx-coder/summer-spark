import Foundation
import CoreLocation

// MARK: - TrackPoint

/// 轨迹点
struct TrackPoint: Codable, Equatable {
    let id: UUID
    let location: LocationData
    let timestamp: Date
    let sequence: Int
    
    /// 附加信息
    var metadata: [String: String] = [:]
    
    /// 是否是标记点（如水源、营地等）
    var isMarker: Bool = false
    
    /// 标记类型
    var markerType: TrackMarkerType?
    
    /// 标记名称
    var markerName: String?
    
    init(location: LocationData, sequence: Int, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.location = location
        self.timestamp = location.timestamp
        self.sequence = sequence
        self.metadata = metadata
    }
    
    static func == (lhs: TrackPoint, rhs: TrackPoint) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - TrackMarkerType

/// 轨迹标记类型
enum TrackMarkerType: String, Codable, CaseIterable {
    case waterSource    // 水源
    case campsite       // 营地
    case danger         // 危险点
    case meetingPoint   // 集合点
    case waypoint       // 途经点
    case custom         // 自定义
    
    var displayName: String {
        switch self {
        case .waterSource: return "水源"
        case .campsite: return "营地"
        case .danger: return "危险点"
        case .meetingPoint: return "集合点"
        case .waypoint: return "途经点"
        case .custom: return "自定义"
        }
    }
    
    var icon: String {
        switch self {
        case .waterSource: return "💧"
        case .campsite: return "⛺"
        case .danger: return "⚠️"
        case .meetingPoint: return "📍"
        case .waypoint: return "🚩"
        case .custom: return "📌"
        }
    }
}

// MARK: - TrackStatistics

/// 轨迹统计信息
struct TrackStatistics: Codable {
    /// 总距离（米）
    let totalDistance: Double
    
    /// 总时间（秒）
    let totalTime: TimeInterval
    
    /// 平均速度（米/秒）
    let averageSpeed: Double
    
    /// 最大速度（米/秒）
    let maxSpeed: Double
    
    /// 平均海拔（米）
    let averageAltitude: Double
    
    /// 最大海拔（米）
    let maxAltitude: Double
    
    /// 最小海拔（米）
    let minAltitude: Double
    
    /// 总爬升（米）
    let totalAscent: Double
    
    /// 总下降（米）
    let totalDescent: Double
    
    /// 点数
    let pointCount: Int
    
    /// 格式化距离
    var formattedDistance: String {
        if totalDistance >= 1000 {
            return String(format: "%.2f km", totalDistance / 1000)
        } else {
            return String(format: "%.0f m", totalDistance)
        }
    }
    
    /// 格式化时间
    var formattedTime: String {
        let hours = Int(totalTime) / 3600
        let minutes = (Int(totalTime) % 3600) / 60
        let seconds = Int(totalTime) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// 格式化平均速度
    var formattedAverageSpeed: String {
        let kmh = averageSpeed * 3.6
        return String(format: "%.1f km/h", kmh)
    }
}

// MARK: - Track

/// 轨迹
struct Track: Codable, Identifiable {
    let id: String
    let name: String
    let startTime: Date
    var endTime: Date?
    var points: [TrackPoint]
    var statistics: TrackStatistics?
    var metadata: [String: String] = [:]
    
    init(name: String? = nil) {
        self.id = UUID().uuidString
        self.name = name ?? "轨迹_\(Date().formatted(date: .abbreviated, time: .shortened))"
        self.startTime = Date()
        self.points = []
    }
}

// MARK: - TrackRecorderDelegate

/// 轨迹记录器代理
protocol TrackRecorderDelegate: AnyObject {
    /// 轨迹点已添加
    func trackRecorder(_ recorder: TrackRecorder, didAddPoint point: TrackPoint)
    
    /// 轨迹已保存
    func trackRecorder(_ recorder: TrackRecorder, didSaveTrack track: Track)
    
    /// 轨迹统计已更新
    func trackRecorder(_ recorder: TrackRecorder, didUpdateStatistics statistics: TrackStatistics)
}

// MARK: - TrackRecorder

/// 轨迹记录器
/// 负责记录、存储、导出GPS轨迹
final class TrackRecorder {
    
    // MARK: - Singleton
    
    static let shared = TrackRecorder()
    
    // MARK: - Properties
    
    weak var delegate: TrackRecorderDelegate?
    
    /// 当前轨迹
    private(set) var currentTrack: Track?
    
    /// 是否正在记录
    private(set) var isRecording: Bool = false
    
    /// 配置
    var config: TrackRecorderConfig = TrackRecorderConfig()
    
    /// 所有保存的轨迹
    private var savedTracks: [Track] = []
    
    /// 记录队列
    private let recorderQueue = DispatchQueue(label: "com.summerspark.trackrecorder")
    
    /// 位置管理器引用
    private var locationManager: LocationManager?
    
    /// 最后添加的点
    private var lastAddedPoint: TrackPoint?
    
    // MARK: - Initialization
    
    private init() {
        loadSavedTracks()
    }
    
    // MARK: - Public API
    
    /// 配置
    func configure(locationManager: LocationManager) {
        self.locationManager = locationManager
    }
    
    /// 开始记录轨迹
    /// - Parameter name: 轨迹名称（可选）
    func startRecording(name: String? = nil) {
        recorderQueue.async { [weak self] in
            guard let self = self, !self.isRecording else { return }
            
            self.currentTrack = Track(name: name)
            self.isRecording = true
            self.lastAddedPoint = nil
            
            Logger.shared.info("TrackRecorder: started recording track \(self.currentTrack?.id ?? "")")
        }
    }
    
    /// 停止记录轨迹
    /// - Returns: 完成的轨迹
    @discardableResult
    func stopRecording() -> Track? {
        return recorderQueue.sync {
            guard isRecording, var track = currentTrack else { return nil }
            
            isRecording = false
            track.endTime = Date()
            track.statistics = calculateStatistics(for: track)
            
            // 保存轨迹
            saveTrack(track)
            savedTracks.append(track)
            
            currentTrack = nil
            lastAddedPoint = nil
            
            Logger.shared.info("TrackRecorder: stopped recording, \(track.points.count) points, \(track.statistics?.formattedDistance ?? "0")")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.trackRecorder(self, didSaveTrack: track)
            }
            
            return track
        }
    }
    
    /// 添加位置点
    /// - Parameter location: 位置数据
    func addLocation(_ location: LocationData) {
        recorderQueue.async { [weak self] in
            guard let self = self, self.isRecording, var track = self.currentTrack else { return }
            
            // 检查是否应该添加此点
            guard self.shouldAddPoint(location) else { return }
            
            // 创建轨迹点
            let point = TrackPoint(
                location: location,
                sequence: track.points.count
            )
            
            // 添加到轨迹
            track.points.append(point)
            self.currentTrack = track
            self.lastAddedPoint = point
            
            // 通知代理
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.trackRecorder(self, didAddPoint: point)
            }
            
            // 定期更新统计
            if track.points.count % 10 == 0 {
                let stats = self.calculateStatistics(for: track)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.trackRecorder(self, didUpdateStatistics: stats)
                }
            }
        }
    }
    
    /// 添加标记点
    /// - Parameters:
    ///   - location: 位置
    ///   - type: 标记类型
    ///   - name: 标记名称
    func addMarker(_ location: LocationData, type: TrackMarkerType, name: String? = nil) {
        recorderQueue.async { [weak self] in
            guard let self = self, self.isRecording, var track = self.currentTrack else { return }
            
            var point = TrackPoint(
                location: location,
                sequence: track.points.count
            )
            point.isMarker = true
            point.markerType = type
            point.markerName = name ?? type.displayName
            
            track.points.append(point)
            self.currentTrack = track
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.trackRecorder(self, didAddPoint: point)
            }
        }
    }
    
    /// 获取所有保存的轨迹
    /// - Returns: 轨迹数组
    func getAllTracks() -> [Track] {
        return recorderQueue.sync {
            savedTracks
        }
    }
    
    /// 删除轨迹
    /// - Parameter trackId: 轨迹ID
    func deleteTrack(_ trackId: String) {
        recorderQueue.async { [weak self] in
            guard let self = self else { return }
            self.savedTracks.removeAll { $0.id == trackId }
            self.saveTracksMetadata()
        }
    }
    
    /// 导出轨迹为GPX
    /// - Parameter track: 轨迹
    /// - Returns: GPX字符串
    func exportToGPX(_ track: Track) -> String {
        return exportTrackToGPX(track)
    }
    
    /// 导出当前轨迹为GPX
    /// - Returns: GPX字符串
    func exportCurrentTrackToGPX() -> String? {
        return recorderQueue.sync {
            guard let track = currentTrack else { return nil }
            return exportTrackToGPX(track)
        }
    }
    
    /// 导入GPX轨迹
    /// - Parameter gpxContent: GPX内容
    /// - Returns: 导入的轨迹
    func importFromGPX(_ gpxContent: String) -> Track? {
        return parseGPX(gpxContent)
    }
    
    /// 获取当前轨迹统计
    /// - Returns: 统计信息
    func getCurrentStatistics() -> TrackStatistics? {
        return recorderQueue.sync {
            guard let track = currentTrack else { return nil }
            return calculateStatistics(for: track)
        }
    }
    
    // MARK: - Private Methods
    
    private func shouldAddPoint(_ location: LocationData) -> Bool {
        // 检查精度
        guard location.accuracy <= config.minimumAccuracy else { return false }
        
        // 检查距离间隔
        if let lastPoint = lastAddedPoint {
            let distance = lastPoint.location.clLocation.distance(from: location.clLocation)
            guard distance >= config.minimumDistance else { return false }
        }
        
        // 检查时间间隔
        if let lastPoint = lastAddedPoint {
            let timeInterval = location.timestamp.timeIntervalSince(lastPoint.location.timestamp)
            guard timeInterval >= config.minimumTimeInterval else { return false }
        }
        
        return true
    }
    
    private func calculateStatistics(for track: Track) -> TrackStatistics {
        let points = track.points
        
        guard !points.isEmpty else {
            return TrackStatistics(
                totalDistance: 0,
                totalTime: 0,
                averageSpeed: 0,
                maxSpeed: 0,
                averageAltitude: 0,
                maxAltitude: 0,
                minAltitude: 0,
                totalAscent: 0,
                totalDescent: 0,
                pointCount: 0
            )
        }
        
        var totalDistance: Double = 0
        var maxSpeed: Double = 0
        var totalAscent: Double = 0
        var totalDescent: Double = 0
        
        let altitudes = points.compactMap { $0.location.altitude }
        let speeds = points.compactMap { $0.location.speed }.map { abs($0) }
        
        for i in 1..<points.count {
            let prev = points[i - 1].location
            let curr = points[i].location
            
            // 距离
            totalDistance += prev.clLocation.distance(from: curr.clLocation)
            
            // 爬升/下降
            if let prevAlt = prev.altitude, let currAlt = curr.altitude {
                let altitudeDiff = currAlt - prevAlt
                if altitudeDiff > 0 {
                    totalAscent += altitudeDiff
                } else {
                    totalDescent += abs(altitudeDiff)
                }
            }
        }
        
        let totalTime = track.endTime?.timeIntervalSince(track.startTime) ??
                       Date().timeIntervalSince(track.startTime)
        
        let avgAltitude = altitudes.isEmpty ? 0 : altitudes.reduce(0, +) / Double(altitudes.count)
        
        return TrackStatistics(
            totalDistance: totalDistance,
            totalTime: totalTime,
            averageSpeed: totalDistance / max(totalTime, 1),
            maxSpeed: speeds.max() ?? 0,
            averageAltitude: avgAltitude,
            maxAltitude: altitudes.max() ?? 0,
            minAltitude: altitudes.min() ?? 0,
            totalAscent: totalAscent,
            totalDescent: totalDescent,
            pointCount: points.count
        )
    }
    
    private func exportTrackToGPX(_ track: Track) -> String {
        let dateFormatter = ISO8601DateFormatter()
        
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="SummerSpark" xmlns="http://www.topografix.com/GPX/1/1">
        <metadata>
        <name>\(track.name)</name>
        <time>\(dateFormatter.string(from: track.startTime))</time>
        </metadata>
        <trk>
        <name>\(track.name)</name>
        <trkseg>
        
        """
        
        for point in track.points {
            let time = dateFormatter.string(from: point.timestamp)
            
            if point.isMarker {
                // 标记点作为wpt
                gpx += """
                <wpt lat="\(point.location.latitude)" lon="\(point.location.longitude)">
                    <ele>\(point.location.altitude)</ele>
                    <time>\(time)</time>
                    <name>\(point.markerName ?? "")</name>
                    <sym>\(point.markerType?.rawValue ?? "")</sym>
                </wpt>
                
                """
            }
            
            // 轨迹点
            gpx += """
                <trkpt lat="\(point.location.latitude)" lon="\(point.location.longitude)">
                    <ele>\(point.location.altitude)</ele>
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
    
    private func parseGPX(_ content: String) -> Track? {
        // 简单的GPX解析（实际项目中应使用XMLParser）
        // 这里提供基础框架
        var track = Track()
        
        // TODO: 实现完整的GPX解析
        
        return track
    }
    
    private func saveTrack(_ track: Track) {
        // 保存到本地存储
        guard let data = try? JSONEncoder().encode(track) else { return }
        
        let filename = "track_\(track.id).json"
        let url = FileManager.default.documentsDirectory.appendingPathComponent("tracks/\(filename)")
        
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        
        saveTracksMetadata()
    }
    
    private func loadSavedTracks() {
        let tracksDir = FileManager.default.documentsDirectory.appendingPathComponent("tracks")
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: tracksDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let track = try? JSONDecoder().decode(Track.self, from: data) else {
                continue
            }
            savedTracks.append(track)
        }
        
        // 按时间排序
        savedTracks.sort { $0.startTime > $1.startTime }
    }
    
    private func saveTracksMetadata() {
        // 保存轨迹列表元数据
        let metadata = savedTracks.map { track -> [String: Any] in
            return [
                "id": track.id,
                "name": track.name,
                "startTime": track.startTime,
                "endTime": track.endTime as Any,
                "pointCount": track.points.count
            ]
        }
        
        UserDefaults.standard.set(metadata, forKey: "tracks.metadata")
    }
}

// MARK: - TrackRecorderConfig

/// 轨迹记录器配置
struct TrackRecorderConfig {
    /// 最小距离间隔（米）
    var minimumDistance: Double = 5.0
    
    /// 最小时间间隔（秒）
    var minimumTimeInterval: TimeInterval = 1.0
    
    /// 最小精度要求（米）
    var minimumAccuracy: Double = 50.0
    
    /// 自动保存间隔（秒）
    var autoSaveInterval: TimeInterval = 60.0
}

// MARK: - FileManager Extension

extension FileManager {
    var documentsDirectory: URL {
        return urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

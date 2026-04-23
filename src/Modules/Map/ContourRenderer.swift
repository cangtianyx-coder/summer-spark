import Foundation
import CoreLocation

// MARK: - CLLocationCoordinate2D Codable Extension

/// CLLocationCoordinate2D的Codable扩展
extension CLLocationCoordinate2D: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}

/// CLLocationCoordinate2D的Equatable扩展
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - ContourLine

/// 等高线
struct ContourLine: Codable {
    /// 高程值（米）
    let elevation: Double
    
    /// 线上的点（经纬度）
    let points: [CLLocationCoordinate2D]
    
    /// 线类型
    let lineType: ContourLineType
    
    /// 是否闭合
    let isClosed: Bool
}

// MARK: - ContourLineType

/// 等高线类型
enum ContourLineType: String, Codable {
    /// 首曲线（基本等高线）
    case index
    
    /// 计曲线（加粗等高线，每5条或10条加粗）
    case intermediate
    
    /// 助曲线（半距等高线）
    case supplementary
}

// MARK: - ElevationData

/// 高程数据点
struct ElevationData: Codable {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double  // 米
    let resolution: Double // 数据分辨率
}

// MARK: - TerrainAnalysis

/// 地形分析结果
struct TerrainAnalysis: Codable {
    /// 坡度（度）
    let slope: Double
    
    /// 坡向（度，0-360）
    let aspect: Double
    
    /// 地形类型
    let terrainType: TerrainType
    
    /// 粗糙度
    let roughness: Double
    
    /// 是否陡峭（坡度>30度）
    var isSteep: Bool {
        return slope > 30.0
    }
    
    /// 是否危险（坡度>45度）
    var isDangerous: Bool {
        return slope > 45.0
    }
}

// MARK: - TerrainType

/// 地形类型
enum TerrainType: String, Codable {
    case flat        // 平地 (<5°)
    case gentle      // 缓坡 (5-15°)
    case moderate    // 中等坡 (15-30°)
    case steep       // 陡坡 (30-45°)
    case verySteep   // 极陡坡 (>45°)
    case cliff       // 悬崖
    
    var displayName: String {
        switch self {
        case .flat: return "平地"
        case .gentle: return "缓坡"
        case .moderate: return "中等坡"
        case .steep: return "陡坡"
        case .verySteep: return "极陡坡"
        case .cliff: return "悬崖"
        }
    }
    
    var difficulty: Int {
        switch self {
        case .flat: return 1
        case .gentle: return 2
        case .moderate: return 3
        case .steep: return 4
        case .verySteep: return 5
        case .cliff: return 6
        }
    }
}

// MARK: - ContourRenderer

/// 等高线渲染器
/// 负责从DEM数据生成等高线、计算坡度坡向、地形分析
final class ContourRenderer {
    
    // MARK: - Properties
    
    /// DEM数据网格
    private var elevationGrid: ElevationGrid?
    
    /// 等高距（米）
    var contourInterval: Double = 10.0
    
    /// 计曲线间隔（每隔多少条首曲线一条计曲线）
    var indexInterval: Int = 5
    
    /// 渲染队列
    private let renderQueue = DispatchQueue(label: "com.summerspark.contourrenderer")
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public API
    
    /// 加载DEM数据
    /// - Parameter data: DEM数据
    func loadDEM(_ data: ElevationGrid) {
        elevationGrid = data
    }
    
    /// 生成等高线
    /// - Parameters:
    ///   - bounds: 范围
    ///   - interval: 等高距（可选，默认使用contourInterval）
    /// - Returns: 等高线数组
    func generateContours(
        in bounds: BoundingBox,
        interval: Double? = nil
    ) -> [ContourLine] {
        guard let grid = elevationGrid else { return [] }
        
        let contourInterval = interval ?? self.contourInterval
        
        // 确定高程范围
        let minElevation = floor(grid.minElevation / contourInterval) * contourInterval
        let maxElevation = ceil(grid.maxElevation / contourInterval) * contourInterval
        
        var contours: [ContourLine] = []
        var contourIndex = 0
        
        // 对每个高程值生成等高线
        var elevation = minElevation
        while elevation <= maxElevation {
            let lines = marchingSquares(grid: grid, elevation: elevation, bounds: bounds)
            
            for line in lines {
                // 确定线类型
                let lineType: ContourLineType
                if contourIndex % indexInterval == 0 {
                    lineType = .intermediate
                } else {
                    lineType = .index
                }
                
                let contour = ContourLine(
                    elevation: elevation,
                    points: line,
                    lineType: lineType,
                    isClosed: line.first == line.last
                )
                contours.append(contour)
            }
            
            elevation += contourInterval
            contourIndex += 1
        }
        
        return contours
    }
    
    /// 获取指定位置的高程
    /// - Parameter coordinate: 坐标
    /// - Returns: 高程值（米）
    func getElevation(at coordinate: CLLocationCoordinate2D) -> Double? {
        guard let grid = elevationGrid else { return nil }
        return interpolateElevation(grid: grid, at: coordinate)
    }
    
    /// 计算指定位置的地形分析
    /// - Parameter coordinate: 坐标
    /// - Returns: 地形分析结果
    func analyzeTerrain(at coordinate: CLLocationCoordinate2D) -> TerrainAnalysis? {
        guard let grid = elevationGrid else { return nil }
        
        // 计算坡度和坡向
        let (slope, aspect) = calculateSlopeAndAspect(grid: grid, at: coordinate)
        
        // 确定地形类型
        let terrainType: TerrainType
        switch abs(slope) {
        case 0..<5:
            terrainType = .flat
        case 5..<15:
            terrainType = .gentle
        case 15..<30:
            terrainType = .moderate
        case 30..<45:
            terrainType = .steep
        case 45..<80:
            terrainType = .verySteep
        default:
            terrainType = .cliff
        }
        
        // 计算粗糙度（简化计算）
        let roughness = calculateRoughness(grid: grid, at: coordinate)
        
        return TerrainAnalysis(
            slope: abs(slope),
            aspect: aspect,
            terrainType: terrainType,
            roughness: roughness
        )
    }
    
    /// 沿路径计算高程剖面
    /// - Parameter path: 路径点
    /// - Returns: 高程剖面数据
    func elevationProfile(along path: [CLLocationCoordinate2D]) -> [ElevationPoint] {
        guard let grid = elevationGrid else { return [] }
        
        var profile: [ElevationPoint] = []
        var cumulativeDistance: Double = 0
        
        for i in 0..<path.count {
            let coordinate = path[i]
            guard let elevation = interpolateElevation(grid: grid, at: coordinate) else { continue }
            
            var distanceFromStart: Double = 0
            if i > 0 {
                let prev = path[i - 1]
                let segmentDistance = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                    .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                cumulativeDistance += segmentDistance
                distanceFromStart = cumulativeDistance
            }
            
            profile.append(ElevationPoint(
                distance: distanceFromStart,
                elevation: elevation,
                coordinate: coordinate
            ))
        }
        
        return profile
    }
    
    /// 查找最佳路线（避开陡坡）
    /// - Parameters:
    ///   - start: 起点
    ///   - end: 终点
    ///   - maxSlope: 最大允许坡度（度）
    /// - Returns: 路线点
    func findBestRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        maxSlope: Double = 30.0
    ) -> [CLLocationCoordinate2D] {
        guard let grid = elevationGrid else { return [start, end] }
        
        // A*寻路，考虑坡度代价
        return findPathWithSlopeConstraint(
            grid: grid,
            start: start,
            end: end,
            maxSlope: maxSlope
        )
    }
    
    // MARK: - Private Methods
    
    /// Marching Squares算法生成等高线
    private func marchingSquares(
        grid: ElevationGrid,
        elevation: Double,
        bounds: BoundingBox
    ) -> [[CLLocationCoordinate2D]] {
        // 简化实现：返回空数组
        // 完整实现需要遍历网格，对每个单元格应用Marching Squares
        return []
    }
    
    /// 双线性插值获取高程
    private func interpolateElevation(
        grid: ElevationGrid,
        at coordinate: CLLocationCoordinate2D
    ) -> Double? {
        // 将坐标转换为网格索引
        let x = (coordinate.longitude - grid.bounds.minLon) / grid.cellSize
        let y = (coordinate.latitude - grid.bounds.minLat) / grid.cellSize
        
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = x0 + 1
        let y1 = y0 + 1
        
        // 边界检查
        guard x0 >= 0, y0 >= 0, x1 < grid.width, y1 < grid.height else { return nil }
        
        // 双线性插值
        let dx = x - Double(x0)
        let dy = y - Double(y0)
        
        let e00 = grid[x0, y0]
        let e10 = grid[x1, y0]
        let e01 = grid[x0, y1]
        let e11 = grid[x1, y1]
        
        let e = e00 * (1 - dx) * (1 - dy) +
                e10 * dx * (1 - dy) +
                e01 * (1 - dx) * dy +
                e11 * dx * dy
        
        return e
    }
    
    /// 计算坡度和坡向
    private func calculateSlopeAndAspect(
        grid: ElevationGrid,
        at coordinate: CLLocationCoordinate2D
    ) -> (slope: Double, aspect: Double) {
        // 使用有限差分法计算梯度
        let cellSize = grid.cellSize * 111000.0 // 转换为米（粗略）
        
        // 获取周围高程
        guard let z = interpolateElevation(grid: grid, at: coordinate) else {
            return (0, 0)
        }
        
        let dx = cellSize
        let dy = cellSize
        
        let coordXPlus = CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude + dx / 111000.0
        )
        let coordXMinus = CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude - dx / 111000.0
        )
        let coordYPlus = CLLocationCoordinate2D(
            latitude: coordinate.latitude + dy / 111000.0,
            longitude: coordinate.longitude
        )
        let coordYMinus = CLLocationCoordinate2D(
            latitude: coordinate.latitude - dy / 111000.0,
            longitude: coordinate.longitude
        )
        
        guard let zXPlus = interpolateElevation(grid: grid, at: coordXPlus),
              let zXMinus = interpolateElevation(grid: grid, at: coordXMinus),
              let zYPlus = interpolateElevation(grid: grid, at: coordYPlus),
              let zYMinus = interpolateElevation(grid: grid, at: coordYMinus) else {
            return (0, 0)
        }
        
        // 偏导数
        let dzdx = (zXPlus - zXMinus) / (2 * dx)
        let dzdy = (zYPlus - zYMinus) / (2 * dy)
        
        // 坡度（弧度）
        let slopeRadians = atan(sqrt(dzdx * dzdx + dzdy * dzdy))
        let slopeDegrees = slopeRadians * 180.0 / .pi
        
        // 坡向（弧度）
        let aspectRadians = atan2(dzdy, -dzdx)
        var aspectDegrees = aspectRadians * 180.0 / .pi
        if aspectDegrees < 0 {
            aspectDegrees += 360.0
        }
        
        return (slopeDegrees, aspectDegrees)
    }
    
    /// 计算粗糙度
    private func calculateRoughness(
        grid: ElevationGrid,
        at coordinate: CLLocationCoordinate2D
    ) -> Double {
        // 简化实现：计算局部高程标准差
        var elevations: [Double] = []
        let sampleRadius = 3 // 采样半径（网格单元数）
        
        for i in -sampleRadius...sampleRadius {
            for j in -sampleRadius...sampleRadius {
                let sampleCoord = CLLocationCoordinate2D(
                    latitude: coordinate.latitude + Double(j) * grid.cellSize,
                    longitude: coordinate.longitude + Double(i) * grid.cellSize
                )
                if let e = interpolateElevation(grid: grid, at: sampleCoord) {
                    elevations.append(e)
                }
            }
        }
        
        guard elevations.count > 1 else { return 0 }
        
        let mean = elevations.reduce(0, +) / Double(elevations.count)
        let variance = elevations.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(elevations.count)
        
        return sqrt(variance)
    }
    
    /// 带坡度约束的寻路
    private func findPathWithSlopeConstraint(
        grid: ElevationGrid,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        maxSlope: Double
    ) -> [CLLocationCoordinate2D] {
        // 简化实现：返回直线路径
        // 完整实现需要A*算法，代价函数考虑坡度
        return [start, end]
    }
}

// MARK: - Supporting Types

/// 高程网格
struct ElevationGrid {
    let width: Int
    let height: Int
    let cellSize: Double  // 度
    let bounds: BoundingBox
    private let data: [Double]
    
    var minElevation: Double {
        return data.min() ?? 0
    }
    
    var maxElevation: Double {
        return data.max() ?? 0
    }
    
    subscript(x: Int, y: Int) -> Double {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return data[y * width + x]
    }
    
    init(width: Int, height: Int, cellSize: Double, bounds: BoundingBox, data: [Double]) {
        self.width = width
        self.height = height
        self.cellSize = cellSize
        self.bounds = bounds
        self.data = data
    }
}

/// 边界框
struct BoundingBox: Codable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    
    var center: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
    }
    
    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }
    
    init(center: CLLocationCoordinate2D, spanLat: Double, spanLon: Double) {
        self.minLat = center.latitude - spanLat / 2
        self.maxLat = center.latitude + spanLat / 2
        self.minLon = center.longitude - spanLon / 2
        self.maxLon = center.longitude + spanLon / 2
    }
}

/// 高程点
struct ElevationPoint: Codable {
    let distance: Double      // 距起点的距离（米）
    let elevation: Double     // 高程（米）
    let coordinate: CLLocationCoordinate2D
}

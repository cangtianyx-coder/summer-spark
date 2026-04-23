import Foundation
import CoreLocation

// MARK: - CoordinateTransformer

/// 坐标系转换器
/// 支持WGS84、GCJ02、BD09之间的相互转换
/// 
/// 坐标系说明：
/// - WGS84: GPS原始坐标，国际通用标准
/// - GCJ02: 国测局坐标（火星坐标），中国强制偏移，高德、腾讯使用
/// - BD09: 百度坐标，在GCJ02基础上再次偏移
///
/// 转换规则：
/// - WGS84 ←→ GCJ02: 双向可转
/// - GCJ02 ←→ BD09: 双向可转
/// - WGS84 ←→ BD09: 通过GCJ02中转
final class CoordinateTransformer {
    
    // MARK: - Singleton
    
    static let shared = CoordinateTransformer()
    
    // MARK: - Constants
    
    /// π值
    private let pi: Double = 3.14159265358979324
    
    /// 长半轴
    private let a: Double = 6378245.0
    
    /// 扁率
    private let ee: Double = 0.00669342162296594323
    
    /// 中国境内边界（粗略）
    private let chinaBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) = (
        minLat: 0.8293,
        maxLat: 55.8271,
        minLon: 72.004,
        maxLon: 137.8347
    )
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// WGS84 转 GCJ02
    /// - Parameter wgs84: WGS84坐标
    /// - Returns: GCJ02坐标
    func wgs84ToGcj02(_ wgs84: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        // 如果不在中国境内，不偏移
        guard isInChina(wgs84) else {
            return wgs84
        }
        
        let dLat = transformLat(wgs84.longitude - 105.0, y: wgs84.latitude - 35.0)
        let dLon = transformLon(wgs84.longitude - 105.0, y: wgs84.latitude - 35.0)
        
        let radLat = wgs84.latitude / 180.0 * pi
        let magic = sin(radLat)
        let sqrtMagic = sqrt(1 - ee * magic * magic)
        
        let mgLat = wgs84.latitude + (dLat * 180.0) / ((a * (1 - ee)) / (sqrtMagic * sqrtMagic) * pi)
        let mgLon = wgs84.longitude + (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * pi)
        
        return CLLocationCoordinate2D(latitude: mgLat, longitude: mgLon)
    }
    
    /// GCJ02 转 WGS84
    /// - Parameter gcj02: GCJ02坐标
    /// - Returns: WGS84坐标
    func gcj02ToWgs84(_ gcj02: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        // 如果不在中国境内，不偏移
        guard isInChina(gcj02) else {
            return gcj02
        }
        
        let mgLat = wgs84ToGcj02(gcj02).latitude
        let mgLon = wgs84ToGcj02(gcj02).longitude
        
        let wgsLat = gcj02.latitude * 2 - mgLat
        let wgsLon = gcj02.longitude * 2 - mgLon
        
        return CLLocationCoordinate2D(latitude: wgsLat, longitude: wgsLon)
    }
    
    /// GCJ02 转 BD09
    /// - Parameter gcj02: GCJ02坐标
    /// - Returns: BD09坐标
    func gcj02ToBd09(_ gcj02: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let z = sqrt(gcj02.longitude * gcj02.longitude + gcj02.latitude * gcj02.latitude) + 0.00002 * sin(gcj02.latitude * pi)
        let theta = atan2(gcj02.latitude, gcj02.longitude) + 0.000003 * cos(gcj02.longitude * pi)
        
        let bdLon = z * cos(theta) + 0.0065
        let bdLat = z * sin(theta) + 0.006
        
        return CLLocationCoordinate2D(latitude: bdLat, longitude: bdLon)
    }
    
    /// BD09 转 GCJ02
    /// - Parameter bd09: BD09坐标
    /// - Returns: GCJ02坐标
    func bd09ToGcj02(_ bd09: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = bd09.longitude - 0.0065
        let y = bd09.latitude - 0.006
        
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * pi)
        let theta = atan2(y, x) - 0.000003 * cos(x * pi)
        
        let gcjLon = z * cos(theta)
        let gcjLat = z * sin(theta)
        
        return CLLocationCoordinate2D(latitude: gcjLat, longitude: gcjLon)
    }
    
    /// WGS84 转 BD09
    /// - Parameter wgs84: WGS84坐标
    /// - Returns: BD09坐标
    func wgs84ToBd09(_ wgs84: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let gcj02 = wgs84ToGcj02(wgs84)
        return gcj02ToBd09(gcj02)
    }
    
    /// BD09 转 WGS84
    /// - Parameter bd09: BD09坐标
    /// - Returns: WGS84坐标
    func bd09ToWgs84(_ bd09: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let gcj02 = bd09ToGcj02(bd09)
        return gcj02ToWgs84(gcj02)
    }
    
    /// 通用坐标转换
    /// - Parameters:
    ///   - coordinate: 原始坐标
    ///   - from: 原始坐标系
    ///   - to: 目标坐标系
    /// - Returns: 转换后的坐标
    func transform(
        _ coordinate: CLLocationCoordinate2D,
        from: CoordinateSystem,
        to: CoordinateSystem
    ) -> CLLocationCoordinate2D {
        // 相同坐标系直接返回
        guard from != to else { return coordinate }
        
        // 先转到WGS84
        let wgs84: CLLocationCoordinate2D
        switch from {
        case .wgs84:
            wgs84 = coordinate
        case .gcj02:
            wgs84 = gcj02ToWgs84(coordinate)
        case .bd09:
            wgs84 = bd09ToWgs84(coordinate)
        }
        
        // 再从WGS84转到目标
        switch to {
        case .wgs84:
            return wgs84
        case .gcj02:
            return wgs84ToGcj02(wgs84)
        case .bd09:
            return wgs84ToBd09(wgs84)
        }
    }
    
    /// 批量坐标转换
    /// - Parameters:
    ///   - coordinates: 坐标数组
    ///   - from: 原始坐标系
    ///   - to: 目标坐标系
    /// - Returns: 转换后的坐标数组
    func transform(
        _ coordinates: [CLLocationCoordinate2D],
        from: CoordinateSystem,
        to: CoordinateSystem
    ) -> [CLLocationCoordinate2D] {
        return coordinates.map { transform($0, from: from, to: to) }
    }
    
    /// 判断坐标是否在中国境内
    /// - Parameter coordinate: 坐标
    /// - Returns: 是否在中国境内
    func isInChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        // 粗略判断
        guard coordinate.latitude > chinaBounds.minLat,
              coordinate.latitude < chinaBounds.maxLat,
              coordinate.longitude > chinaBounds.minLon,
              coordinate.longitude < chinaBounds.maxLon else {
            return false
        }
        
        return true
    }
    
    /// 计算两点之间的距离（使用WGS84坐标）
    /// - Parameters:
    ///   - from: 起点坐标
    ///   - to: 终点坐标
    ///   - coordinateSystem: 坐标系类型
    /// - Returns: 距离（米）
    func distance(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        coordinateSystem: CoordinateSystem = .wgs84
    ) -> Double {
        // 转换为WGS84计算
        let wgsFrom = coordinateSystem == .wgs84 ? from : transform(from, from: coordinateSystem, to: .wgs84)
        let wgsTo = coordinateSystem == .wgs84 ? to : transform(to, from: coordinateSystem, to: .wgs84)
        
        let locFrom = CLLocation(latitude: wgsFrom.latitude, longitude: wgsFrom.longitude)
        let locTo = CLLocation(latitude: wgsTo.latitude, longitude: wgsTo.longitude)
        
        return locFrom.distance(from: locTo)
    }
    
    // MARK: - Private Methods
    
    /// 纬度偏移量计算
    private func transformLat(_ x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * pi) + 320 * sin(y * pi / 30.0)) * 2.0 / 3.0
        return ret
    }
    
    /// 经度偏移量计算
    private func transformLon(_ x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0
        return ret
    }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    
    /// 转换坐标系
    /// - Parameters:
    ///   - from: 原始坐标系
    ///   - to: 目标坐标系
    /// - Returns: 转换后的坐标
    func transform(from: CoordinateSystem, to: CoordinateSystem) -> CLLocationCoordinate2D {
        return CoordinateTransformer.shared.transform(self, from: from, to: to)
    }
    
    /// WGS84转GCJ02
    var toGcj02: CLLocationCoordinate2D {
        return CoordinateTransformer.shared.wgs84ToGcj02(self)
    }
    
    /// GCJ02转WGS84
    var toWgs84: CLLocationCoordinate2D {
        return CoordinateTransformer.shared.gcj02ToWgs84(self)
    }
    
    /// WGS84转BD09
    var toBd09: CLLocationCoordinate2D {
        return CoordinateTransformer.shared.wgs84ToBd09(self)
    }
    
    /// 计算到另一点的距离
    /// - Parameter other: 另一点
    /// - Returns: 距离（米）
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: latitude, longitude: longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
    
    /// 是否在中国境内
    var isInChina: Bool {
        return CoordinateTransformer.shared.isInChina(self)
    }
}

// MARK: - LocationData Extension

extension LocationData {
    
    /// 转换坐标系
    /// - Parameters:
    ///   - from: 原始坐标系
    ///   - to: 目标坐标系
    /// - Returns: 转换后的位置数据
    func transform(from: CoordinateSystem, to: CoordinateSystem) -> LocationData {
        let newCoord = coordinate.transform(from: from, to: to)
        
        return LocationData(
            latitude: newCoord.latitude,
            longitude: newCoord.longitude,
            altitude: altitude,
            accuracy: accuracy,
            speed: speed,
            heading: heading
        )
    }
}

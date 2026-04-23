import Foundation

// MARK: - Evacuation Point

/// 撤离集合点
struct EvacuationPoint: Codable, Identifiable {
    let id: UUID
    let location: LocationData
    let name: String
    var capacity: Int
    var currentCount: Int
    var status: EvacuationPointStatus
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    
    enum EvacuationPointStatus: String, Codable {
        case active = "开放"
        case full = "已满"
        case closed = "已关闭"
    }
    
    var isFull: Bool {
        return currentCount >= capacity
    }
    
    var availableCapacity: Int {
        return max(0, capacity - currentCount)
    }
}

// MARK: - Evacuation Route

/// 撤离路线
struct EvacuationRoute: Codable, Identifiable {
    let id: UUID
    let startPoint: LocationData
    let endPoint: EvacuationPoint
    let path: [LocationData]
    let distance: Double
    let estimatedTime: TimeInterval
    var status: RouteStatus
    let createdAt: Date
    
    enum RouteStatus: String, Codable {
        case active = "可用"
        case congested = "拥堵"
        case blocked = "受阻"
        case closed = "已关闭"
    }
}

// MARK: - Evacuation Instruction

/// 撤离指令
struct EvacuationInstruction: Codable {
    let id: UUID
    let targetArea: LocationData
    let targetPoint: EvacuationPoint
    let route: EvacuationRoute
    let urgency: EvacuationUrgency
    let message: String
    let issuedBy: String
    let issuedAt: Date
    
    enum EvacuationUrgency: String, Codable {
        case immediate = "立即撤离"
        case urgent = "紧急撤离"
        case planned = "计划撤离"
        case voluntary = "自愿撤离"
    }
}

// MARK: - Evacuation Planner

/// 撤离规划系统
final class EvacuationPlanner {
    static let shared = EvacuationPlanner()
    
    private var evacuationPoints: [UUID: EvacuationPoint] = [:]
    private var routes: [UUID: EvacuationRoute] = [:]
    private var activeInstructions: [UUID: EvacuationInstruction] = [:]
    private var checkedInUsers: [UUID: Set<String>] = [:]  // pointId -> user ids
    
    private let queue = DispatchQueue(label: "com.summerspark.evacuationplanner", attributes: .concurrent)
    
    weak var delegate: EvacuationPlannerDelegate?
    
    private init() {}
    
    // MARK: - Evacuation Points
    
    /// 创建撤离集合点
    func createEvacuationPoint(location: LocationData, name: String, capacity: Int = 100) -> EvacuationPoint? {
        guard let uid = IdentityManager.shared.uid else { return nil }
        
        let point = EvacuationPoint(
            id: UUID(),
            location: location,
            name: name,
            capacity: capacity,
            currentCount: 0,
            status: .active,
            createdBy: uid,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        queue.sync(flags: .barrier) {
            evacuationPoints[point.id] = point
            checkedInUsers[point.id] = []
        }
        
        Logger.shared.info("EvacuationPlanner: Created evacuation point \(name) at \(location.latitude), \(location.longitude)")
        return point
    }
    
    /// 获取所有撤离点
    func getAllEvacuationPoints() -> [EvacuationPoint] {
        return queue.sync { Array(evacuationPoints.values) }
    }
    
    /// 获取最近的撤离点
    func getNearestEvacuationPoint(from location: LocationData) -> EvacuationPoint? {
        return queue.sync {
            evacuationPoints.values
                .filter { $0.status == .active && !$0.isFull }
                .min { 
                    let d1 = location.clLocation.distance(from: $0.location.clLocation)
                    let d2 = location.clLocation.distance(from: $1.location.clLocation)
                    return d1 < d2
                }
        }
    }
    
    /// 用户到达撤离点签到
    func checkIn(evacuationPointId: UUID, userId: String) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var point = evacuationPoints[evacuationPointId] else { return false }
            
            point.currentCount += 1
            point.updatedAt = Date()
            if point.isFull {
                point.status = .full
            }
            evacuationPoints[evacuationPointId] = point
            
            checkedInUsers[evacuationPointId]?.insert(userId)
            
            Logger.shared.info("EvacuationPlanner: User \(userId) checked in at \(point.name)")
            return true
        }
    }
    
    /// 用户离开撤离点签退
    func checkOut(evacuationPointId: UUID, userId: String) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var point = evacuationPoints[evacuationPointId] else { return false }
            
            point.currentCount = max(0, point.currentCount - 1)
            point.updatedAt = Date()
            if point.status == .full && !point.isFull {
                point.status = .active
            }
            evacuationPoints[evacuationPointId] = point
            
            checkedInUsers[evacuationPointId]?.remove(userId)
            
            Logger.shared.info("EvacuationPlanner: User \(userId) checked out from \(point.name)")
            return true
        }
    }
    
    /// 获取撤离点人员名单
    func getCheckedInUsers(at pointId: UUID) -> [String] {
        return queue.sync {
            Array(checkedInUsers[pointId] ?? [])
        }
    }
    
    // MARK: - Routes
    
    /// 创建撤离路线
    func createRoute(from start: LocationData, to point: EvacuationPoint, path: [LocationData]) -> EvacuationRoute? {
        // 计算总距离
        var totalDistance = 0.0
        var allPoints = [start] + path + [point.location]
        for i in 0..<allPoints.count-1 {
            totalDistance += allPoints[i].clLocation.distance(from: allPoints[i+1].clLocation)
        }
        
        // 估算时间（假设步行速度 1.4 m/s）
        let estimatedTime = totalDistance / 1.4
        
        let route = EvacuationRoute(
            id: UUID(),
            startPoint: start,
            endPoint: point,
            path: path,
            distance: totalDistance,
            estimatedTime: estimatedTime,
            status: .active,
            createdAt: Date()
        )
        
        queue.sync(flags: .barrier) {
            routes[route.id] = route
        }
        
        Logger.shared.info("EvacuationPlanner: Created route to \(point.name), distance: \(Int(totalDistance))m")
        return route
    }
    
    /// 获取到指定撤离点的最佳路线
    func getBestRoute(to pointId: UUID, from location: LocationData) -> EvacuationRoute? {
        return queue.sync {
            routes.values
                .filter { $0.endPoint.id == pointId && $0.status == .active }
                .min { $0.distance < $1.distance }
        }
    }
    
    // MARK: - Evacuation Instructions
    
    /// 发布撤离指令
    func issueEvacuationInstruction(
        targetArea: LocationData,
        targetPoint: EvacuationPoint,
        route: EvacuationRoute,
        urgency: EvacuationInstruction.EvacuationUrgency,
        message: String
    ) -> EvacuationInstruction? {
        guard let uid = IdentityManager.shared.uid else { return nil }
        
        let instruction = EvacuationInstruction(
            id: UUID(),
            targetArea: targetArea,
            targetPoint: targetPoint,
            route: route,
            urgency: urgency,
            message: message,
            issuedBy: uid,
            issuedAt: Date()
        )
        
        queue.sync(flags: .barrier) {
            activeInstructions[instruction.id] = instruction
        }
        
        // 广播撤离指令
        broadcastInstruction(instruction)
        
        Logger.shared.info("EvacuationPlanner: Issued evacuation instruction: \(message)")
        return instruction
    }
    
    /// 获取活动撤离指令
    func getActiveInstructions() -> [EvacuationInstruction] {
        return queue.sync { Array(activeInstructions.values) }
    }
    
    // MARK: - Statistics
    
    /// 获取撤离统计
    func getStatistics() -> EvacuationStatistics {
        return queue.sync {
            EvacuationStatistics(
                totalPoints: evacuationPoints.count,
                activePoints: evacuationPoints.values.filter { $0.status == .active }.count,
                totalCapacity: evacuationPoints.values.reduce(0) { $0 + $1.capacity },
                currentOccupancy: evacuationPoints.values.reduce(0) { $0 + $1.currentCount },
                totalRoutes: routes.count,
                activeRoutes: routes.values.filter { $0.status == .active }.count,
                activeInstructions: activeInstructions.count
            )
        }
    }
    
    // MARK: - Private
    
    private func broadcastInstruction(_ instruction: EvacuationInstruction) {
        guard let instructionData = try? JSONEncoder().encode(instruction) else { return }
        
        let message = MeshMessage(
            source: IdentityManager.shared.uid.flatMap { UUID(uuidString: $0) } ?? UUID(),
            payload: instructionData,
            ttl: 64,
            messageType: .emergency
        )
        
        MeshService.shared.sendEmergencyMessage(message)
    }
}

// MARK: - Statistics

struct EvacuationStatistics: Codable {
    let totalPoints: Int
    let activePoints: Int
    let totalCapacity: Int
    let currentOccupancy: Int
    let totalRoutes: Int
    let activeRoutes: Int
    let activeInstructions: Int
}

// MARK: - Delegate

protocol EvacuationPlannerDelegate: AnyObject {
    func evacuationPlanner(_ planner: EvacuationPlanner, didCreatePoint point: EvacuationPoint)
    func evacuationPlanner(_ planner: EvacuationPlanner, didIssueInstruction instruction: EvacuationInstruction)
    func evacuationPlanner(_ planner: EvacuationPlanner, userDidCheckIn userId: String, at point: EvacuationPoint)
}

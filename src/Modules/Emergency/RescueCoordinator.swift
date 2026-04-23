import Foundation

// MARK: - Search Area

/// 搜索区域
struct SearchArea: Codable, Identifiable {
    let id: UUID
    let center: LocationData
    let radius: Double  // 米
    let name: String
    var status: SearchStatus
    var assignedTeam: String?
    let createdAt: Date
    
    enum SearchStatus: String, Codable {
        case pending = "待搜索"
        case inProgress = "搜索中"
        case completed = "已完成"
        case partiallyCompleted = "部分完成"
    }
}

// MARK: - Rescue Task

/// 救援任务类型
enum TaskType: String, Codable {
    case search = "搜索"
    case rescue = "救援"
    case evacuate = "撤离"
    case supply = "物资运送"
    case medical = "医疗救助"
    case reconnaissance = "侦察"
}

/// 救援任务状态
enum TaskStatus: String, Codable {
    case pending = "待分配"
    case assigned = "已分配"
    case inProgress = "进行中"
    case completed = "已完成"
    case failed = "失败"
    case cancelled = "已取消"
}

/// 救援任务
struct RescueTask: Codable, Identifiable {
    let id: UUID
    let type: TaskType
    let location: LocationData
    var status: TaskStatus
    var assignedTeam: String?
    var assignedMembers: Set<String>
    let priority: Int  // 1=最高
    let description: String?
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var result: String?
    
    init(type: TaskType, location: LocationData, priority: Int = 3, description: String? = nil) {
        self.id = UUID()
        self.type = type
        self.location = location
        self.status = .pending
        self.assignedTeam = nil
        self.assignedMembers = []
        self.priority = priority
        self.description = description
        self.createdAt = Date()
        self.startedAt = nil
        self.completedAt = nil
        self.result = nil
    }
}

// MARK: - Rescue Team

/// 救援队成员角色
enum TeamRole: String, Codable {
    case leader = "队长"
    case medic = "医疗员"
    case searcher = "搜索员"
    case communicator = "通讯员"
    case support = "支援人员"
}

/// 救援队成员
struct TeamMember: Codable {
    let userId: String
    let role: TeamRole
    let joinedAt: Date
    var currentLocation: LocationData?
}

/// 救援队
struct RescueTeam: Codable, Identifiable {
    let id: UUID
    let name: String
    let leaderId: String
    var members: [TeamMember]
    var assignedArea: SearchArea?
    var currentTasks: [UUID]
    var status: TeamStatus
    let createdAt: Date
    var updatedAt: Date
    
    enum TeamStatus: String, Codable {
        case available = "可用"
        case busy = "任务中"
        case resting = "休整"
        case offline = "离线"
    }
    
    init(name: String, leaderId: String) {
        self.id = UUID()
        self.name = name
        self.leaderId = leaderId
        self.members = [TeamMember(userId: leaderId, role: .leader, joinedAt: Date())]
        self.assignedArea = nil
        self.currentTasks = []
        self.status = .available
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Rescue Coordinator

/// 救援协调系统
final class RescueCoordinator {
    static let shared = RescueCoordinator()
    
    private var teams: [UUID: RescueTeam] = [:]
    private var tasks: [UUID: RescueTask] = [:]
    private var searchAreas: [UUID: SearchArea] = [:]
    private let queue = DispatchQueue(label: "com.summerspark.rescuecoordinator", attributes: .concurrent)
    
    weak var delegate: RescueCoordinatorDelegate?
    
    private init() {}
    
    // MARK: - Team Management
    
    /// 创建救援队
    func createTeam(name: String) -> RescueTeam? {
        guard let uid = IdentityManager.shared.uid else { return nil }
        
        let team = RescueTeam(name: name, leaderId: uid)
        
        queue.sync(flags: .barrier) {
            teams[team.id] = team
        }
        
        Logger.shared.info("RescueCoordinator: Created team \(name) with leader \(uid)")
        return team
    }
    
    /// 加入救援队
    func joinTeam(teamId: UUID, role: TeamRole = .searcher) -> Bool {
        guard let uid = IdentityManager.shared.uid else { return false }
        
        return queue.sync(flags: .barrier) {
            guard var team = teams[teamId] else { return false }
            
            let member = TeamMember(userId: uid, role: role, joinedAt: Date())
            team.members.append(member)
            team.updatedAt = Date()
            teams[teamId] = team
            
            Logger.shared.info("RescueCoordinator: User \(uid) joined team \(teamId)")
            return true
        }
    }
    
    /// 获取所有救援队
    func getAllTeams() -> [RescueTeam] {
        return queue.sync { Array(teams.values) }
    }
    
    /// 获取可用的救援队
    func getAvailableTeams() -> [RescueTeam] {
        return queue.sync {
            teams.values.filter { $0.status == .available }
        }
    }
    
    // MARK: - Task Management
    
    /// 创建救援任务
    func createTask(type: TaskType, location: LocationData, priority: Int = 3, description: String? = nil) -> RescueTask? {
        let task = RescueTask(type: type, location: location, priority: priority, description: description)
        
        queue.sync(flags: .barrier) {
            tasks[task.id] = task
        }
        
        Logger.shared.info("RescueCoordinator: Created task \(task.id) of type \(type.rawValue)")
        return task
    }
    
    /// 分配任务给救援队
    func assignTask(taskId: UUID, toTeam teamId: UUID) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var task = tasks[taskId], var team = teams[teamId] else { return false }
            
            task.status = .assigned
            task.assignedTeam = teamId.uuidString
            tasks[taskId] = task
            
            team.currentTasks.append(taskId)
            team.status = .busy
            team.updatedAt = Date()
            teams[teamId] = team
            
            Logger.shared.info("RescueCoordinator: Assigned task \(taskId) to team \(teamId)")
            return true
        }
    }
    
    /// 开始任务
    func startTask(taskId: UUID) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var task = tasks[taskId] else { return false }
            
            task.status = .inProgress
            task.startedAt = Date()
            tasks[taskId] = task
            
            Logger.shared.info("RescueCoordinator: Started task \(taskId)")
            return true
        }
    }
    
    /// 完成任务
    func completeTask(taskId: UUID, result: String? = nil) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var task = tasks[taskId], let teamIdStr = task.assignedTeam,
                  var team = teams[UUID(uuidString: teamIdStr)] else { return false }
            
            task.status = .completed
            task.completedAt = Date()
            task.result = result
            tasks[taskId] = task
            
            team.currentTasks.removeAll { $0 == taskId }
            if team.currentTasks.isEmpty {
                team.status = .available
            }
            team.updatedAt = Date()
            teams[team.id] = team
            
            Logger.shared.info("RescueCoordinator: Completed task \(taskId)")
            return true
        }
    }
    
    /// 获取所有任务
    func getAllTasks() -> [RescueTask] {
        return queue.sync { Array(tasks.values) }
    }
    
    /// 获取紧急任务
    func getUrgentTasks() -> [RescueTask] {
        return queue.sync {
            tasks.values.filter { $0.priority <= 2 && $0.status != .completed && $0.status != .cancelled }
                .sorted { $0.priority < $1.priority }
        }
    }
    
    // MARK: - Search Area
    
    /// 创建搜索区域
    func createSearchArea(center: LocationData, radius: Double, name: String) -> SearchArea? {
        let area = SearchArea(id: UUID(), center: center, radius: radius, name: name, status: .pending, assignedTeam: nil, createdAt: Date())
        
        queue.sync(flags: .barrier) {
            searchAreas[area.id] = area
        }
        
        Logger.shared.info("RescueCoordinator: Created search area \(name)")
        return area
    }
    
    /// 分配搜索区域
    func assignSearchArea(areaId: UUID, toTeam teamId: UUID) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var area = searchAreas[areaId], var team = teams[teamId] else { return false }
            
            area.status = .inProgress
            area.assignedTeam = teamId.uuidString
            searchAreas[areaId] = area
            
            team.assignedArea = area
            team.updatedAt = Date()
            teams[teamId] = team
            
            Logger.shared.info("RescueCoordinator: Assigned search area \(areaId) to team \(teamId)")
            return true
        }
    }
    
    /// 获取所有搜索区域
    func getAllSearchAreas() -> [SearchArea] {
        return queue.sync { Array(searchAreas.values) }
    }
    
    // MARK: - Statistics
    
    /// 获取救援统计
    func getStatistics() -> RescueStatistics {
        return queue.sync {
            let allTasks = Array(tasks.values)
            return RescueStatistics(
                totalTeams: teams.count,
                availableTeams: teams.values.filter { $0.status == .available }.count,
                totalTasks: allTasks.count,
                pendingTasks: allTasks.filter { $0.status == .pending }.count,
                inProgressTasks: allTasks.filter { $0.status == .inProgress }.count,
                completedTasks: allTasks.filter { $0.status == .completed }.count,
                searchAreas: searchAreas.count
            )
        }
    }
}

// MARK: - Statistics

struct RescueStatistics: Codable {
    let totalTeams: Int
    let availableTeams: Int
    let totalTasks: Int
    let pendingTasks: Int
    let inProgressTasks: Int
    let completedTasks: Int
    let searchAreas: Int
}

// MARK: - Delegate

protocol RescueCoordinatorDelegate: AnyObject {
    func rescueCoordinator(_ coordinator: RescueCoordinator, didCreateTeam team: RescueTeam)
    func rescueCoordinator(_ coordinator: RescueCoordinator, didAssignTask task: RescueTask, toTeam team: RescueTeam)
    func rescueCoordinator(_ coordinator: RescueCoordinator, didCompleteTask task: RescueTask)
}

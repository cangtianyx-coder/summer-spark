import Foundation

// MARK: - MeshOperationMode
/// 双模态运行系统 - 对齐PRD定义
/// 待机模态(Standby): 仅做中继转发、路由、验签，低功耗
/// 组网模态(Networking): 主动建群、语音、位置、导航
enum MeshOperationMode: String, Codable, CaseIterable {
    /// 待机模态 - 仅做数据包验签、中继、路由转发
    /// 低功耗：定位5分钟/次，关闭不必要的传感器
    /// 持续累计转发积分
    case standby
    
    /// 组网模态 - 可发起/加入面对面建群
    /// 可语音通话、位置共享、路径规划
    /// 定位1秒/次，地图实时渲染
    case networking
    
    // MARK: - Mode Properties
    
    /// 模态显示名称
    var displayName: String {
        switch self {
        case .standby:
            return "待机模态"
        case .networking:
            return "组网模态"
        }
    }
    
    /// 是否允许语音通话
    var allowsVoiceCommunication: Bool {
        switch self {
        case .standby:
            return false  // 待机模态不允许主动语音
        case .networking:
            return true   // 组网模态可以语音
        }
    }
    
    /// 是否允许位置共享
    var allowsLocationSharing: Bool {
        switch self {
        case .standby:
            return false  // 待机模态不主动共享位置
        case .networking:
            return true   // 组网模态可以位置共享
        }
    }
    
    /// 是否允许建群
    var allowsGroupCreation: Bool {
        switch self {
        case .standby:
            return false
        case .networking:
            return true
        }
    }
    
    /// 是否允许导航
    var allowsNavigation: Bool {
        switch self {
        case .standby:
            return false
        case .networking:
            return true
        }
    }
    
    /// 是否允许地图下载
    var allowsMapDownload: Bool {
        switch self {
        case .standby:
            return false
        case .networking:
            return true
        }
    }
    
    /// 是否可以做中继转发
    var canRelay: Bool {
        return true  // 两种模态都可以做中继
    }
    
    /// 位置更新间隔（秒）
    var locationUpdateInterval: TimeInterval {
        switch self {
        case .standby:
            return 300.0  // 5分钟/次
        case .networking:
            return 1.0    // 1秒/次
        }
    }
    
    /// 心跳广播间隔（秒）
    var heartbeatInterval: TimeInterval {
        switch self {
        case .standby:
            return 3.0   // 低频心跳
        case .networking:
            return 1.0   // 高频心跳
        }
    }
    
    /// 功耗级别
    var powerLevel: PowerLevel {
        switch self {
        case .standby:
            return .low
        case .networking:
            return .high
        }
    }
    
    // MARK: - Mode Transitions
    
    /// 可切换到的模态
    var availableTransitions: [MeshOperationMode] {
        return MeshOperationMode.allCases  // 两种模态可以互相切换
    }
    
    /// 是否可以切换到指定模态
    func canTransition(to newMode: MeshOperationMode) -> Bool {
        return availableTransitions.contains(newMode)
    }
}

// MARK: - PowerLevel

/// 功耗级别
enum PowerLevel: String, Codable {
    case low      // 低功耗
    case medium   // 中等功耗
    case high     // 高功耗
}

// MARK: - ModeTransitionReason

/// 模态切换原因
enum ModeTransitionReason: String, Codable {
    case userManual        // 用户手动切换
    case autoIdle         // 无操作自动退回待机（15分钟）
    case lowBattery       // 低电量强制待机（≤10%）
    case networkRequired  // 需要组网功能
    case emergency        // 紧急情况
}

// MARK: - ModeTransitionRule

/// 模态切换规则
struct ModeTransitionRule: Codable {
    /// 无操作自动退回待机的超时时间（秒）
    static let idleTimeout: TimeInterval = 900.0  // 15分钟
    
    /// 强制进入待机的电量阈值
    static let lowBatteryThreshold: Double = 0.1  // 10%
    
    /// 检查是否应该强制进入待机模态
    static func shouldForceStandby(batteryLevel: Double, isCharging: Bool) -> Bool {
        // 充电时不强制待机
        if isCharging { return false }
        // 电量≤10%强制待机
        return batteryLevel <= lowBatteryThreshold
    }
    
    /// 检查是否应该自动退回待机（无操作超时）
    static func shouldAutoStandby(lastActivityTime: Date) -> Bool {
        let elapsed = Date().timeIntervalSince(lastActivityTime)
        return elapsed >= idleTimeout
    }
}

// MARK: - AppMode (兼容旧代码)

/// 应用运行模式 - 兼容层
/// 注意：推荐使用 MeshOperationMode
enum AppMode: String, Codable {
    /// 正常模式（等同于组网模态）
    case normal
    
    /// 纯Mesh模式（等同于待机模态）
    case meshOnly
    
    /// 紧急模式
    case emergency
    
    /// 开发测试模式
    case development
    
    /// 维护模式
    case maintenance
    
    // MARK: - 转换到 MeshOperationMode
    
    /// 转换为Mesh运行模态
    var toMeshMode: MeshOperationMode {
        switch self {
        case .normal, .development:
            return .networking
        case .meshOnly, .emergency, .maintenance:
            return .standby
        }
    }
    
    // MARK: - Mode Properties (兼容旧接口)
    
    var displayName: String {
        switch self {
        case .normal:
            return "Normal Mode"
        case .meshOnly:
            return "Mesh Only"
        case .emergency:
            return "Emergency"
        case .development:
            return "Development"
        case .maintenance:
            return "Maintenance"
        }
    }
    
    var isOfflineCapable: Bool {
        switch self {
        case .normal, .meshOnly, .emergency:
            return true
        case .development, .maintenance:
            return false
        }
    }
    
    var allowsVoiceCommunication: Bool {
        switch self {
        case .normal, .meshOnly, .development:
            return true
        case .emergency, .maintenance:
            return false
        }
    }
    
    var allowsCreditOperations: Bool {
        switch self {
        case .normal, .meshOnly:
            return true
        case .emergency, .development, .maintenance:
            return false
        }
    }
    
    var allowsMapAccess: Bool {
        switch self {
        case .normal, .development:
            return true
        case .meshOnly, .emergency, .maintenance:
            return false
        }
    }
    
    // MARK: - Mode Transitions
    
    var availableTransitions: [AppMode] {
        switch self {
        case .normal:
            return [.meshOnly, .emergency, .development]
        case .meshOnly:
            return [.normal, .emergency]
        case .emergency:
            return [.normal, .meshOnly]
        case .development:
            return [.normal, .maintenance]
        case .maintenance:
            return [.development, .normal]
        }
    }
    
    func canTransition(to newMode: AppMode) -> Bool {
        return availableTransitions.contains(newMode)
    }
}

// MARK: - ConnectivityStatus

/// 设备连接状态
enum ConnectivityStatus: String, Codable {
    case online     // 在线
    case offline    // 离线
    case switching  // 切换中
    case unknown    // 未知
    
    var isConnected: Bool {
        return self == .online
    }
}

// MARK: - SyncState

/// 数据同步状态
enum SyncState: String, Codable {
    case idle       // 空闲
    case syncing    // 同步中
    case completed  // 已完成
    case failed     // 失败
    case pending    // 待处理
    
    var isInProgress: Bool {
        return self == .syncing || self == .pending
    }
}

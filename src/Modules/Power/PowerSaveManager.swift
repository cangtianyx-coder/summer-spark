// MARK: - Power Save Manager
// 依赖文件：MeshRelayProtocols.swift
// 功能：功耗状态机管理

import Foundation
import UIKit

// MARK: - Power Save Manager

public class PowerSaveManager {
    // MARK: - Singleton
    
    public static let shared = PowerSaveManager()
    private init() {}
    
    // MARK: - Properties
    
    private var currentState: PowerState = .active
    private var previousState: PowerState = .active
    private var batteryLevel: Double = 1.0
    private var lowPowerModeEnabled = false
    
    private var stateHistory: [StateTransition] = []
    private var adaptiveSettings: AdaptivePowerSettings = .normal
    
    private let stateLock = NSLock()
    private var lastStateChange: Date = Date()
    
    public weak var delegate: PowerSaveDelegate?
    
    // MARK: - State Management
    
    /// Get current power state
    public var state: PowerState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentState
    }
    
    /// Transition to a new power state
    public func transitionTo(_ newState: PowerState) {
        stateLock.lock()
        
        let oldState = currentState
        guard newState != oldState else {
            stateLock.unlock()
            return
        }
        
        // Record transition
        let transition = StateTransition(
            from: oldState,
            to: newState,
            timestamp: Date(),
            reason: determineTransitionReason(from: oldState, to: newState)
        )
        stateHistory.append(transition)
        
        previousState = oldState
        currentState = newState
        lastStateChange = Date()
        
        stateLock.unlock()
        
        // Update adaptive settings based on new state
        updateAdaptiveSettings()
        
        // Notify delegate
        delegate?.powerSaveManager(self, didChangeState: newState)
    }
    
    /// Handle app lifecycle event
    public func handleAppLifecycle(_ event: AppLifecycleEvent) {
        switch event {
        case .willEnterForeground:
            transitionTo(.active)
            
        case .didEnterBackground:
            if lowPowerModeEnabled || batteryLevel < 0.2 {
                transitionTo(.lowPower)
            } else {
                transitionTo(.background)
            }
            
        case .willTerminate:
            transitionTo(.hibernation)
        }
    }
    
    /// Update battery level
    public func updateBatteryLevel(_ level: Double) {
        batteryLevel = level
        delegate?.powerSaveManager(self, didUpdateBatteryLevel: level)
        
        // Auto-adjust state based on battery
        if level < 0.1 && currentState == .background {
            transitionTo(.hibernation)
        } else if level < 0.2 && currentState == .active {
            // Suggest low power mode
            lowPowerModeEnabled = true
            updateAdaptiveSettings()
        }
    }
    
    /// Enable/disable low power mode
    public func setLowPowerMode(_ enabled: Bool) {
        lowPowerModeEnabled = enabled
        
        if enabled && currentState == .active {
            adaptiveSettings = .lowPower
        } else if !enabled && currentState == .active {
            adaptiveSettings = .normal
        }
    }
    
    // MARK: - Adaptive Settings
    
    private func updateAdaptiveSettings() {
        switch currentState {
        case .active:
            adaptiveSettings = lowPowerModeEnabled ? .lowPower : .normal
            
        case .lowPower:
            adaptiveSettings = .lowPower
            
        case .background:
            adaptiveSettings = .background
            
        case .hibernation:
            adaptiveSettings = .hibernation
        }
    }
    
    private func determineTransitionReason(from: PowerState, to: PowerState) -> String {
        if to == .background { return "App moved to background" }
        if to == .active { return "App became active" }
        if to == .lowPower { return "Low power mode enabled" }
        if to == .hibernation { return "Critical battery or termination" }
        return "Unknown"
    }
    
    // MARK: - Resource Limits
    
    /// Get current resource limits based on power state
    public func getResourceLimits() -> ResourceLimits {
        switch currentState {
        case .active:
            return ResourceLimits(
                maxMeshConnections: 10,
                scanInterval: 1.0,
                beaconInterval: 5.0,
                maxConcurrentTransfers: 5,
                backgroundRefreshEnabled: true
            )
            
        case .lowPower:
            return ResourceLimits(
                maxMeshConnections: 5,
                scanInterval: 5.0,
                beaconInterval: 30.0,
                maxConcurrentTransfers: 2,
                backgroundRefreshEnabled: true
            )
            
        case .background:
            return ResourceLimits(
                maxMeshConnections: 3,
                scanInterval: 30.0,
                beaconInterval: 60.0,
                maxConcurrentTransfers: 1,
                backgroundRefreshEnabled: true
            )
            
        case .hibernation:
            return ResourceLimits(
                maxMeshConnections: 1,
                scanInterval: 300.0,
                beaconInterval: 300.0,
                maxConcurrentTransfers: 0,
                backgroundRefreshEnabled: false
            )
        }
    }
    
    /// Check if an operation is allowed in current state
    public func isOperationAllowed(_ operation: PowerOperation) -> Bool {
        switch currentState {
        case .active:
            return true
            
        case .lowPower:
            // P1-FIX: 低电量模式下允许紧急操作
            return operation != .fullMeshScan && operation != .bulkTransfer
            
        case .background:
            // P1-FIX: 后台模式下允许紧急消息和最小信标
            return operation == .minimalBeacon || operation == .emergencyMessage
            
        case .hibernation:
            // P1-FIX: 即使在休眠模式下也必须允许紧急消息（SOS）
            // 这是关键的安全保障
            return operation == .emergencyMessage
        }
    }
    
    // P1-FIX: 低电量SOS保障 - 检查是否可以发送SOS
    /// Check if SOS can be sent in current power state
    /// Returns true even in hibernation mode (critical safety guarantee)
    public func canSendSOS() -> Bool {
        // SOS在任何状态下都必须可用，这是生命安全保障
        return true
    }
    
    // P1-FIX: 获取SOS可用电量阈值
    /// Get minimum battery level required for SOS
    /// Even at 1% battery, SOS must be available
    public var sosMinimumBatteryLevel: Double {
        return 0.01  // 1% - SOS在极低电量下仍可用
    }
    
    // P1-FIX: 检查当前电量是否足够发送SOS
    public func hasSufficientBatteryForSOS() -> Bool {
        return batteryLevel >= sosMinimumBatteryLevel
    }
    
    // P1-FIX: 进入紧急模式（优先保障SOS功能）
    /// Enter emergency mode - prioritizes SOS functionality
    public func enterEmergencyMode() {
        // 即使在休眠模式也恢复最低限度的网络功能
        if currentState == .hibernation {
            transitionTo(.background)
        }
        
        // 确保紧急消息功能可用
        Logger.shared.info("PowerSaveManager: Entered emergency mode for SOS")
    }

    // MARK: - Statistics
    
    /// Get power statistics
    public func getStatistics() -> PowerStatistics {
        stateLock.lock()
        let timeInCurrentState = Date().timeIntervalSince(lastStateChange)
        let historyCount = stateHistory.count
        stateLock.unlock()
        
        return PowerStatistics(
            currentState: currentState,
            batteryLevel: batteryLevel,
            lowPowerMode: lowPowerModeEnabled,
            timeInCurrentState: timeInCurrentState,
            totalTransitions: historyCount
        )
    }
    
    /// Get state transition history
    public func getStateHistory(limit: Int = 10) -> [StateTransition] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Array(stateHistory.suffix(limit))
    }
}

// MARK: - Supporting Types

public enum AppLifecycleEvent {
    case willEnterForeground
    case didEnterBackground
    case willTerminate
}

public enum PowerOperation {
    case fullMeshScan
    case minimalBeacon
    case bulkTransfer
    case emergencyMessage
    case locationUpdate
}

public struct StateTransition {
    let from: PowerState
    let to: PowerState
    let timestamp: Date
    let reason: String
}

public struct ResourceLimits {
    let maxMeshConnections: Int
    let scanInterval: TimeInterval
    let beaconInterval: TimeInterval
    let maxConcurrentTransfers: Int
    let backgroundRefreshEnabled: Bool
}

public enum AdaptivePowerSettings {
    case normal
    case lowPower
    case background
    case hibernation
}

public struct PowerStatistics {
    let currentState: PowerState
    let batteryLevel: Double
    let lowPowerMode: Bool
    let timeInCurrentState: TimeInterval
    let totalTransitions: Int
}

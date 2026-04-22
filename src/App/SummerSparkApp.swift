import UIKit
import SwiftUI
import BackgroundTasks

@main
enum SummerSparkApp {
    static func main() {
        // 模块初始化
        initializeModules()
        
        // 后台配置
        configureBackgroundModes()
        
        // 启动应用
        guard #available(iOS 13.0, *) else {
            // iOS 13 以下使用传统方式
            UIApplicationMain(
                CommandLine.argc,
                CommandLine.unsafeArgv,
                NSStringFromClass(UIApplication.self),
                NSStringFromClass(AppDelegate.self)
            )
            return
        }
        
        // iOS 13+ Scene-based lifecycle
        // 注册 AppDelegate 的 shared 实例
        _ = AppDelegate.shared
    }
    
    // MARK: - 模块初始化
    private static func initializeModules() {
        // 身份模块
        IdentityManager.shared.initialize()
        
        // 存储模块
        DatabaseManager.shared.setup()
        GroupStore.shared.load()
        
        // 积分模块
        CreditEngine.shared.start()
        CreditSyncManager.shared.startSync()
        
        // 地图模块
        MapService.configure()
        OfflineMapManager.shared.prepareOfflineData()
        
        // 语音模块
        VoiceService.shared.configure()
        
        // Mesh 网络模块
        MeshService.shared.start()
        BluetoothService.shared.configure()
        WiFiService.shared.configure()
        
        // 安全模块
        AntiAttackGuard.shared.enable()
        
        print("[SummerSpark] All modules initialized")
    }
    
    // MARK: - 后台模式配置
    private static func configureBackgroundModes() {
        // 后台刷新
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        
        // 后台任务调度器配置
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.summerspark.refresh",
            using: nil
        ) { task in
            handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.summerspark.sync",
            using: nil
        ) { task in
            handleBackgroundSync(task: task as! BGProcessingTask)
        }
        
        print("[SummerSpark] Background modes configured")
    }
    
    // MARK: - 后台任务处理
    private static func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        
        let operation = CreditSyncManager.shared.createSyncOperation()
        
        task.expirationHandler = {
            operation.cancel()
        }
        
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        CreditSyncManager.shared.operationQueue.addOperation(operation)
    }
    
    private static func handleBackgroundSync(task: BGProcessingTask) {
        scheduleBackgroundSync()
        
        let operation = OfflineMapManager.shared.createMapSyncOperation()
        
        task.expirationHandler = {
            operation.cancel()
        }
        
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        MapCacheManager.shared.operationQueue.addOperation(operation)
    }
    
    private static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.summerspark.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15分钟后
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[SummerSpark] Could not schedule app refresh: \(error)")
        }
    }
    
    private static func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: "com.summerspark.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1小时后
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[SummerSpark] Could not schedule background sync: \(error)")
        }
    }
}

// MARK: - AppDelegate（传统生命周期支持）
@available(iOS 13.0, *)
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
    
    var window: UIWindow?
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return true
    }
    
    // MARK: - UISceneSession Lifecycle
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
    
    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // 清理废弃的场景
    }
    
    // MARK: - 远程通知注册
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[SummerSpark] Device Token: \(token)")
        // 将 token 发送到服务器
        IdentityManager.shared.updatePushToken(token)
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[SummerSpark] Failed to register for remote notifications: \(error)")
    }
    
    // MARK: - 后台获取
    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        CreditSyncManager.shared.performSync { result in
            switch result {
            case .success(()):
                completionHandler(.newData)
            case .failure:
                completionHandler(.failed)
            }
        }
    }
    
    // MARK: - 链接处理
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        // 处理 Universal Links 和 Handoff
        return true
    }
}

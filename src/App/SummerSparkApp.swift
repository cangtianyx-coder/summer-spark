import UIKit
import SwiftUI
import BackgroundTasks

// MARK: - SummerSpark App Entry Point

@main
struct SummerSparkApp {
    // App entry point - delegate to proper initialization
    static func main() {
        // Initialize all modules before UI setup
        initializeModules()

        // Configure background modes
        configureBackgroundModes()

        // Set minimum background fetch interval
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

        Logger.shared.info("[SummerSpark] Starting application")

        // Use AppDelegate as the main entry point for scene-based app
        // This bridges the @main struct with the traditional AppDelegate lifecycle
        _ = UIApplicationMain(
            CommandLine.argc,
            CommandLine.unsafeArgv,
            NSStringFromClass(UIApplication.self),
            NSStringFromClass(AppDelegate.self)
        )
    }

    // MARK: - Module Initialization

    private static func initializeModules() {
        // Identity module
        IdentityManager.shared.initialize()

        // Storage module
        DatabaseManager.shared.setup()
        GroupStore.shared.load()

        // Credit/Points module
        CreditEngine.shared.start()
        CreditSyncManager.shared.startSync()

        // Map module
        MapService.configure()
        OfflineMapManager.shared.prepareOfflineData()

        // Voice module
        VoiceService.shared.configure()

        // Mesh network module
        MeshService.shared.start()
        BluetoothService.shared.configure()
        WiFiService.shared.configure()

        // Security module
        AntiAttackGuard.shared.enable()

        // Auto-update module
        AutoUpdater.shared.startAutoCheck()

        Logger.shared.info("[SummerSpark] All modules initialized")
    }

    // MARK: - Background Mode Configuration

    private static func configureBackgroundModes() {
        // Register background task handlers
        registerBackgroundTasks()

        Logger.shared.info("[SummerSpark] Background modes configured")
    }

    // MARK: - Background Task Registration

    private static func registerBackgroundTasks() {
        // App refresh task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.summerspark.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundRefresh(task: refreshTask)
        }

        // Processing task for sync
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.summerspark.sync",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundSync(task: processingTask)
        }

        // Mesh routing maintenance task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.summerspark.mesh-routing",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleMeshRoutingTask(task: processingTask)
        }
    }

    // MARK: - Background Task Handlers

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

    private static func handleMeshRoutingTask(task: BGProcessingTask) {
        scheduleMeshRoutingTask()

        let operation = BlockOperation {
            MeshService.shared.performRouteMaintenance()
        }

        task.expirationHandler = {
            operation.cancel()
        }

        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        OperationQueue.main.addOperation(operation)
    }

    // MARK: - Schedule Background Tasks

    private static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.summerspark.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.shared.error("[SummerSpark] Could not schedule app refresh: \(error)")
        }
    }

    private static func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: "com.summerspark.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.shared.error("[SummerSpark] Could not schedule background sync: \(error)")
        }
    }

    private static func scheduleMeshRoutingTask() {
        let request = BGProcessingTaskRequest(identifier: "com.summerspark.mesh-routing")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.shared.error("[SummerSpark] Could not schedule mesh routing task: \(error)")
        }
    }
}

// MARK: - AppDelegate

/// Main application delegate handling lifecycle events
class AppDelegate: UIResponder, UIApplicationDelegate {

    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        Logger.shared.info("[AppDelegate] Application did finish launching")
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
        // Clean up discarded scenes
    }

    // MARK: - Memory Warning

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Logger.shared.warn("[AppDelegate] Received memory warning, clearing caches...")

        // Clear caches from all modules
        LocationManager.shared.clearCache()
        MeshService.shared.clearCache()
        MapService.shared.clearCache()
        MapCacheManager.shared.clearCache()
        OfflineMapManager.shared.clearCache()

        Logger.shared.info("[AppDelegate] Memory warning handled")
    }

    // MARK: - Remote Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        // Mask token for privacy - only log first and last 4 characters
        let maskedToken = String(token.prefix(4)) + "****" + String(token.suffix(4))
        Logger.shared.info("[SummerSpark] Device Token: \(maskedToken)")
        IdentityManager.shared.updatePushToken(token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.shared.error("[SummerSpark] Failed to register for remote notifications: \(error)")
    }

    // MARK: - Background Fetch

    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        CreditSyncManager.shared.performSync { result in
            switch result {
            case .success:
                completionHandler(.newData)
            case .failure:
                completionHandler(.failed)
            }
        }
    }

    // MARK: - URL Handling

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        // Handle Universal Links and Handoff
        return true
    }

    // MARK: - Background Lifecycle

    func applicationDidEnterBackground(_ application: UIApplication) {
        PowerSaveManager.shared.handleAppLifecycle(.didEnterBackground)
        Logger.shared.info("[AppDelegate] Application did enter background")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        PowerSaveManager.shared.handleAppLifecycle(.willEnterForeground)
        Logger.shared.info("[AppDelegate] Application will enter foreground")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        PowerSaveManager.shared.handleAppLifecycle(.willTerminate)
        Logger.shared.info("[AppDelegate] Application will terminate")
    }
}
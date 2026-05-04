import UIKit
import SwiftUI

// MARK: - Scene Delegate

/// Scene delegate handles window scene lifecycle and SwiftUI/App integration
@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            Logger.shared.error("[SceneDelegate] Invalid scene type")
            return
        }

        // Create the window
        let window = UIWindow(windowScene: windowScene)

        // Always show main app (skip onboarding for now)
        showMainApp(window: window)

        self.window = window
        window.makeKeyAndVisible()

        Logger.shared.info("[SceneDelegate] Window connected to scene")
    }

    // MARK: - Navigation

    private func showMainApp(window: UIWindow) {
        // Use SwiftUI ContentView as root with UIHostingController
        let contentView = ContentView()
        let hostingController = UIHostingController(rootView: contentView)
        window.rootViewController = hostingController
    }

    // MARK: - Scene Lifecycle

    func sceneDidDisconnect(_ scene: UIScene) {
        Logger.shared.info("[SceneDelegate] Scene disconnected")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Logger.shared.info("[SceneDelegate] Scene became active")
        PowerSaveManager.shared.handleAppLifecycle(.willEnterForeground)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Logger.shared.info("[SceneDelegate] Scene will resign active")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Logger.shared.info("[SceneDelegate] Scene will enter foreground")
        PowerSaveManager.shared.handleAppLifecycle(.willEnterForeground)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Logger.shared.info("[SceneDelegate] Scene did enter background")
        PowerSaveManager.shared.handleAppLifecycle(.didEnterBackground)
    }
}
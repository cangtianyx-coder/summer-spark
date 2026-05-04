import UIKit

// MARK: - 导航协调协议
protocol Coordinator: AnyObject {
    var childCoordinators: [Coordinator] { get set }
    var navigationController: UINavigationController { get set }
    func start()
}

extension Coordinator {
    func addChild(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
    }

    func removeChild(_ coordinator: Coordinator) {
        childCoordinators.removeAll { $0 === coordinator }
    }
}

// MARK: - 应用根协调器
@MainActor
final class AppCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController

    private let window: UIWindow
    private var mainTabBarController: UITabBarController?

    init(window: UIWindow) {
        self.window = window
        self.navigationController = UINavigationController()
    }

    func start() {
        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        // 根据启动条件路由
        if isFirstLaunch() {
            showOnboarding()
        } else {
            showMainApp()
        }
    }

    // MARK: - 路由规则

    private func isFirstLaunch() -> Bool {
        return !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }

    private func setLaunched() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }

    func showOnboarding() {
        setLaunched()
        let onboardingCoordinator = OnboardingCoordinator(navigationController: navigationController)
        onboardingCoordinator.parentCoordinator = self
        addChild(onboardingCoordinator)
        onboardingCoordinator.start()
    }

    func showMainApp() {
        let tabBarController = MainTabBarController()
        mainTabBarController = tabBarController

        // 首页协调器
        let homeNav = UINavigationController()
        let homeCoordinator = HomeCoordinator(navigationController: homeNav)
        addChild(homeCoordinator)
        homeCoordinator.start()
        homeNav.tabBarItem = UITabBarItem(title: "首页", image: UIImage(systemName: "house"), tag: 0)

        // 发现协调器
        let discoverNav = UINavigationController()
        let discoverCoordinator = DiscoverCoordinator(navigationController: discoverNav)
        addChild(discoverCoordinator)
        discoverCoordinator.start()
        discoverNav.tabBarItem = UITabBarItem(title: "发现", image: UIImage(systemName: "magnifyingglass"), tag: 1)

        // 个人中心协调器
        let profileNav = UINavigationController()
        let profileCoordinator = ProfileCoordinator(navigationController: profileNav)
        addChild(profileCoordinator)
        profileCoordinator.start()
        profileNav.tabBarItem = UITabBarItem(title: "我的", image: UIImage(systemName: "person"), tag: 2)

        tabBarController.viewControllers = [homeNav, discoverNav, profileNav]
        navigationController.setViewControllers([tabBarController], animated: false)
    }

    func switchToTab(_ index: Int) {
        mainTabBarController?.selectedIndex = index
    }

    func logout() {
        // 清除用户数据
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        // 返回登录页
        let loginCoordinator = LoginCoordinator(navigationController: navigationController)
        loginCoordinator.parentCoordinator = self
        addChild(loginCoordinator)
        loginCoordinator.start()
    }
}

// MARK: - 首页协调器
@MainActor
final class HomeCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let homeVC = HomeViewController()
        homeVC.coordinator = self
        navigationController.setViewControllers([homeVC], animated: true)
    }

    func showDetail(id: String) {
        let detailVC = DetailViewController(id: id)
        navigationController.pushViewController(detailVC, animated: true)
    }
}

// MARK: - 发现协调器
@MainActor
final class DiscoverCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let discoverVC = DiscoverViewController()
        discoverVC.coordinator = self
        navigationController.setViewControllers([discoverVC], animated: true)
    }

    func showSearch() {
        let searchVC = SearchViewController()
        navigationController.pushViewController(searchVC, animated: true)
    }
}

// MARK: - 个人中心协调器
@MainActor
final class ProfileCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let profileVC = ProfileViewController()
        profileVC.coordinator = self
        navigationController.setViewControllers([profileVC], animated: true)
    }

    func showSettings() {
        let settingsVC = SettingsViewController()
        navigationController.pushViewController(settingsVC, animated: true)
    }
}

// MARK: - 登录协调器
@MainActor
final class LoginCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController
    weak var parentCoordinator: AppCoordinator?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let loginVC = LoginViewController()
        loginVC.coordinator = self
        navigationController.setViewControllers([loginVC], animated: true)
    }

    func loginSuccess() {
        parentCoordinator?.showMainApp()
        if let parent = parentCoordinator {
            parent.removeChild(self)
        }
    }
}

// MARK: - 引导页协调器
@MainActor
final class OnboardingCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController
    weak var parentCoordinator: AppCoordinator?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let onboardingVC = OnboardingViewController()
        onboardingVC.coordinator = self
        navigationController.setViewControllers([onboardingVC], animated: true)
    }

    func onboardingComplete() {
        parentCoordinator?.showMainApp()
        if let parent = parentCoordinator {
            parent.removeChild(self)
        }
    }
}

// MARK: - Placeholder View Controllers (TODO: Replace with actual implementation)
/// HomeViewController - Main home screen view controller
/// TODO: Implement home screen with mesh status, quick actions, and connected users
@MainActor
class HomeViewController: UIViewController {
    weak var coordinator: HomeCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // TODO: Implement HomeViewController UI
    }
}

/// DiscoverViewController - Discovery and search view controller
/// TODO: Implement discovery screen with map and search functionality
@MainActor
class DiscoverViewController: UIViewController {
    weak var coordinator: DiscoverCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // TODO: Implement DiscoverViewController UI
    }
}

/// ProfileViewController - User profile view controller
/// TODO: Implement profile screen with user info and settings access
@MainActor
class ProfileViewController: UIViewController {
    weak var coordinator: ProfileCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // TODO: Implement ProfileViewController UI
    }
}

/// LoginViewController - Authentication view controller
/// TODO: Implement login/registration UI with identity verification
@MainActor
class LoginViewController: UIViewController {
    weak var coordinator: LoginCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // TODO: Implement LoginViewController UI
    }
}

/// OnboardingViewController - First-launch onboarding view controller
/// TODO: Implement onboarding flow with permission requests
@MainActor
class OnboardingViewController: UIViewController {
    weak var coordinator: OnboardingCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // TODO: Implement OnboardingViewController UI
    }
}

/// DetailViewController - Generic detail view controller
/// TODO: Implement detail view for displaying item details
@MainActor
class DetailViewController: UIViewController {
    private let itemId: String

    init(id: String) {
        self.itemId = id
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // TODO: Implement DetailViewController UI with itemId
    }
}

/// SearchViewController - Search functionality view controller
/// TODO: Implement search UI for discovering mesh nodes and content
class SearchViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // TODO: Implement SearchViewController UI
    }
}

/// SettingsViewController - App settings view controller
/// TODO: Implement settings screen with preferences and account options
class SettingsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // TODO: Implement SettingsViewController UI
    }
}

/// MainTabBarController - Main tab bar controller
/// TODO: Implement tab bar with proper view controllers and styling
class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.backgroundColor = .systemBackground
        // TODO: Implement MainTabBarController tabs and styling
    }
}
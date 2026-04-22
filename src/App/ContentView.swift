import SwiftUI

// MARK: - ContentView（主界面视图）

/// ContentView 负责主界面的 TabBar、模态切换和状态栏配置
/// 搭配 AppCoordinator 使用，协调各模块的视图展示

// MARK: - SwiftUI Implementation

/// SwiftUI 主视图 - 使用 TabView 实现底部导航
@available(iOS 13.0, *)
struct ContentView: View {
    @State private var selectedIndex: Int = 0
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house")
                }
                .tag(0)
            
            DiscoverView()
                .tabItem {
                    Label("发现", systemImage: "magnifyingglass")
                }
                .tag(1)
            
            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person")
                }
                .tag(2)
        }
        .accentColor(.blue)
    }
}

// MARK: - Tab Views

/// 首页视图
@available(iOS 13.0, *)
struct HomeView: View {
    var body: some View {
        NavigationView {
            Text("首页")
                .font(.largeTitle)
                .navigationTitle("首页")
        }
    }
}

/// 发现视图
@available(iOS 13.0, *)
struct DiscoverView: View {
    var body: some View {
        NavigationView {
            Text("发现")
                .font(.largeTitle)
                .navigationTitle("发现")
        }
    }
}

/// 个人中心视图
@available(iOS 13.0, *)
struct ProfileView: View {
    var body: some View {
        NavigationView {
            Text("我的")
                .font(.largeTitle)
                .navigationTitle("我的")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let modalPresentationRequested = Notification.Name("modalPresentationRequested")
    static let modalDismissRequested = Notification.Name("modalDismissRequested")
    static let statusBarStyleChangeRequested = Notification.Name("statusBarStyleChangeRequested")
    static let tabBarItemSelected = Notification.Name("tabBarItemSelected")
}

// MARK: - StatusBarConfigurable

protocol StatusBarConfigurable: AnyObject {
    var preferredStatusBarStyle: UIStatusBarStyle { get }
    var prefersStatusBarHidden: Bool { get }
}

// MARK: - StatusBarStyleInfo

struct StatusBarStyleInfo {
    let style: UIStatusBarStyle
    let hidden: Bool
    
    static let `default` = StatusBarStyleInfo(style: .default, hidden: false)
    static let light = StatusBarStyleInfo(style: .lightContent, hidden: false)
    static let dark = StatusBarStyleInfo(style: .darkContent, hidden: false)
    static let hidden = StatusBarStyleInfo(style: .default, hidden: true)
}

// MARK: - Preview

#if DEBUG
@available(iOS 13.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif

import SwiftUI
import UIKit

// MARK: - ContentView

/// Main content view with TabBar navigation
/// Coordinates all major sections of the app
@available(iOS 13.0, *)
struct ContentView: View {
    @State private var selectedIndex: Int = 0
    @State private var showPTTOverlay: Bool = false
    @State private var showBatteryWarning: Bool = false
    @State private var showSplash: Bool = true

    var body: some View {
        ZStack {
            // 启动画面
            if showSplash {
                SplashScreen()
                    .transition(.opacity)
            }

            // Main TabView
            TabView(selection: $selectedIndex) {
                HomeView()
                    .tabItem {
                        Label("tab_home".localized, systemImage: "house")
                    }
                    .tag(0)

                DiscoverView()
                    .tabItem {
                        Label("tab_discover".localized, systemImage: "magnifyingglass")
                    }
                    .tag(1)

                ProfileView()
                    .tabItem {
                        Label("tab_profile".localized, systemImage: "person")
                    }
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Label("tab_settings".localized, systemImage: "gear")
                    }
                    .tag(3)
            }
            .tabViewStyle(.automatic)
            .accentColor(.blue)
            .opacity(showSplash ? 0 : 1)

            // P1-FIX: 低电量警告横幅
            if showBatteryWarning {
                VStack {
                    BatteryWarningBanner {
                        showBatteryWarning = false
                    }
                    Spacer()
                }
                .transition(.move(edge: .top))
                .animation(.easeInOut, value: showBatteryWarning)
            }

            // Floating PTT Button Overlay
            PTTButtonOverlay(isVisible: MeshStatusManager.shared.isConnected)
                .allowsHitTesting(true)

            // SOS Emergency Button (top right corner)
            SOSButtonOverlay()
                .allowsHitTesting(true)
        }
        .onAppear {
            checkBatteryLevel()
            // Splash screen auto-hides after loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation {
                    showSplash = false
                }
            }
        }
    }

    private func checkBatteryLevel() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel > 0 && batteryLevel < 0.2 {
            showBatteryWarning = true
        }
    }
}

// MARK: - Battery Warning Banner

struct BatteryWarningBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "battery.25")
                .foregroundColor(.white)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Low Battery Warning")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("Mesh functionality may be limited. Charge your device soon.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding()
        .background(Color.orange)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
        .padding(.top, 50)
    }
}

// MARK: - HomeView

@available(iOS 13.0, *)
struct HomeView: View {
    @State private var showSOSConfirmation: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Mesh Network Status Card
                    MeshStatusCard(status: MeshStatusManager.shared)

                    // Location Info Card
                    LocationCard(manager: LocationManager.shared)

                    // Quick Actions
                    ContentViewQuickActionsSection()

                    // Connected Users Section
                    ConnectedUsersSection()
                }
                .padding()
            }
            .navigationTitle("tab_home".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSOSConfirmation = true }) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .alert("Emergency SOS", isPresented: $showSOSConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Activate SOS", role: .destructive) {
                    // P0-FIX: Ensure message is not nil for emergency SOS
                    let sosMessage = "Emergency SOS triggered from HomeView"
                    SOSManager.shared.triggerSOS(type: .other, severity: .high, message: sosMessage)
                }
            } message: {
                Text("sos_confirmation_message".localized)
            }
        }
    }
}

// MARK: - Mesh Status Card

@available(iOS 13.0, *)
struct MeshStatusCard: View {
    @ObservedObject var status: MeshStatusManager
    @State private var isReconnecting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.blue)
                Text("Mesh Network Status")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(status.isConnected ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
            }

            if status.isConnected {
                Text("Connected to \(status.connectedNodes) nodes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Signal: \(status.signalStrength)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // P1-FIX: 添加重连状态和手动重连按钮
                HStack(spacing: 8) {
                    if isReconnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    }
                    Text(isReconnecting ? "Reconnecting..." : "Searching for mesh network...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Button(action: reconnect) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reconnect")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .disabled(isReconnecting)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private func reconnect() {
        isReconnecting = true
        MeshService.shared.start()

        // Simulate reconnection check after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isReconnecting = false
        }
    }
}

// MARK: - Location Card

@available(iOS 13.0, *)
struct LocationCard: View {
    var manager: LocationManager
    @State private var isAcquiring: Bool = false
    @State private var showMap: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.green)
                Text("Location")
                    .font(.headline)
                Spacer()
                if manager.hasLocationPermission() {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let location = manager.currentLocation {
                Text("Lat: \(String(format: "%.6f", location.latitude))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Lng: \(String(format: "%.6f", location.longitude))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // P0-FIX: 添加loading动画而不是静态文本
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                    Text("Acquiring location...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .onTapGesture {
            showMap = true
        }
        .onAppear {
            checkLocationAcquisition()
        }
        .fullScreenCover(isPresented: $showMap) {
            MapView()
        }
    }

    private func checkLocationAcquisition() {
        if manager.currentLocation == nil {
            isAcquiring = true
        }
    }
}

// MARK: - ContentView Quick Actions Section

@available(iOS 13.0, *)
struct ContentViewQuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                // Mesh - 移到原来Map的位置
                ContentViewQuickActionButton(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Mesh",
                    color: .green
                ) {
                    NotificationCenter.default.post(name: .navigateToMesh, object: nil)
                }

                ContentViewQuickActionButton(
                    icon: "person.2.fill",
                    title: "Groups",
                    color: .purple
                ) {
                    NotificationCenter.default.post(name: .navigateToGroups, object: nil)
                }

                // Voice - 占领原来Mesh的位置
                ContentViewQuickActionButton(
                    icon: "waveform",
                    title: "Voice",
                    color: .orange
                ) {
                    NotificationCenter.default.post(name: .navigateToVoice, object: nil)
                }

                // 占位保持2x2布局
                Color.clear
                    .frame(height: 80)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - ContentView Quick Action Button

@available(iOS 13.0, *)
struct ContentViewQuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

// MARK: - Connected Users Section

@available(iOS 13.0, *)
struct ConnectedUsersSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected Users")
                    .font(.headline)
                Spacer()
                Text("\(MeshStatusManager.shared.connectedNodes)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<min(MeshStatusManager.shared.connectedNodes, 5), id: \.self) { index in
                        UserAvatar(index: index)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - User Avatar

@available(iOS 13.0, *)
struct UserAvatar: View {
    let index: Int

    var body: some View {
        VStack {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 70, height: 70)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                )
                .overlay(Circle().stroke(Color.blue, lineWidth: 2))
            Text("User \(index + 1)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - DiscoverView

@available(iOS 13.0, *)
struct DiscoverView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Map View Container
                MapContainerView()
                    .frame(height: 300)
                    .cornerRadius(12)
                    .padding()

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    Text("Search location or users...")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

                // Discover Options
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        DiscoverCard(
                            icon: "map.fill",
                            title: "Offline Maps",
                            subtitle: "Download for offline use"
                        )
                        DiscoverCard(
                            icon: "wifi",
                            title: "WiFi Direct",
                            subtitle: "Connect to nearby devices"
                        )
                        DiscoverCard(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "Mesh Nodes",
                            subtitle: "View network topology"
                        )
                        DiscoverCard(
                            icon: "person.badge.plus",
                            title: "Add Contact",
                            subtitle: "Scan or share ID"
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle("tab_discover".localized)
        }
    }
}

// MARK: - Map Container View

@available(iOS 13.0, *)
struct MapContainerView: View {
    var body: some View {
        ZStack {
            // Map placeholder - actual implementation would use MapKit
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay(
                    VStack {
                        Image(systemName: "map.fill")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Map View")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                )

            // Overlay controls
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        LocationManager.shared.start()
                    }) {
                        Image(systemName: "location.fill")
                            .padding(10)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Discover Card

@available(iOS 13.0, *)
struct DiscoverCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - ProfileView

@available(iOS 13.0, *)
struct ProfileView: View {

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Header
                    VStack(spacing: 12) {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)
                            )

                        Text(IdentityManager.shared.username ?? "User")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("ID: \(IdentityManager.shared.uid?.prefix(8) ?? "Unknown")...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    // Stats Section
                    HStack(spacing: 20) {
                        StatItem(title: "Credits", value: "\(Int(CreditEngine.shared.getBalance()))")
                        StatItem(title: "Nodes", value: "\(MeshStatusManager.shared.connectedNodes)")
                        StatItem(title: "Groups", value: "0")
                    }
                    .padding()

                    // Menu Items
                    VStack(spacing: 0) {
                        ProfileMenuItem(icon: "creditcard", title: "Credits History")
                        ProfileMenuItem(icon: "person.2", title: "My Groups")
                        ProfileMenuItem(icon: "clock", title: "Activity History")
                        ProfileMenuItem(icon: "gear", title: "Account Settings")
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("tab_profile".localized)
        }
    }
}

// MARK: - Stat Item

@available(iOS 13.0, *)
struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Profile Menu Item

@available(iOS 13.0, *)
struct ProfileMenuItem: View {
    let icon: String
    let title: String

    var body: some View {
        Button(action: {}) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 30)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
        }
        Divider()
    }
}

// MARK: - PTT Button Overlay

@available(iOS 13.0, *)
struct PTTButtonOverlay: View {
    let isVisible: Bool
    @State private var isPressed: Bool = false

    var body: some View {
        if isVisible {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        handlePTTPress()
                    }) {
                        ZStack {
                            Circle()
                                .fill(isPressed ? Color.red : Color.orange)
                                .frame(width: 70, height: 70)
                                .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 3)

                            Image(systemName: "waveform")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .animation(.spring(response: 0.2), value: isPressed)
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
                }
            }
            .transition(.move(edge: .trailing))
        }
    }

    private func handlePTTPress() {
        isPressed = true
        VoiceService.shared.startTransmitting()
        // Reset after 500ms simulated push duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isPressed = false
            VoiceService.shared.stopTransmitting()
        }
    }
}

// MARK: - SOS Button Overlay

@available(iOS 13.0, *)
struct SOSButtonOverlay: View {
    @State private var showSOSAlert: Bool = false
    @State private var isSOSActive: Bool = false
    @State private var showCancelConfirmation: Bool = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    if isSOSActive {
                        showCancelConfirmation = true
                    } else {
                        showSOSAlert = true
                    }
                }) {
                    ZStack {
                        // P0-FIX: SOS激活时显示脉冲动画效果，增大比例
                        if isSOSActive {
                            Circle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: 85, height: 85)
                                .modifier(PulseAnimation())

                            Circle()
                                .fill(Color.red.opacity(0.5))
                                .frame(width: 70, height: 70)
                                .modifier(PulseAnimation(delay: 0.2))
                        }

                        Circle()
                            .fill(isSOSActive ? Color.red : Color.red.opacity(0.9))
                            .frame(width: 60, height: 60)
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)

                        VStack(spacing: 3) {
                            Text("SOS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            if isSOSActive {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(.trailing, 20)
                .padding(.top, 60)
            }
            Spacer()
        }
        .alert("Emergency SOS", isPresented: $showSOSAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Activate SOS", role: .destructive) {
                let sosMessage = "Emergency SOS triggered from SOSButtonOverlay"
                SOSManager.shared.triggerSOS(type: .other, severity: .high, message: sosMessage)
                isSOSActive = true
            }
        } message: {
            Text("sos_confirmation_message".localized)
        }
        .alert("Cancel SOS", isPresented: $showCancelConfirmation) {
            Button("Keep SOS Active", role: .cancel) {}
            Button("Cancel SOS", role: .destructive) {
                SOSManager.shared.cancelActiveSOS()
                isSOSActive = false
            }
        } message: {
            Text("sos_cancel_confirmation_message".localized)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sosStatusChanged)) { notification in
            if let isActive = notification.userInfo?["isActive"] as? Bool {
                isSOSActive = isActive
            }
        }
        .onAppear {
            isSOSActive = SOSManager.shared.activeSOS != nil
        }
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    var delay: Double = 0
    @State private var isPulsing: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0 : 0.7)
            .animation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToMap = Notification.Name("navigateToMap")
    static let navigateToGroups = Notification.Name("navigateToGroups")
    static let navigateToMesh = Notification.Name("navigateToMesh")
    static let navigateToVoice = Notification.Name("navigateToVoice")
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
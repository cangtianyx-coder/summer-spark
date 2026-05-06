import SwiftUI
import UIKit
import CoreImage

// MARK: - ContentView

/// Main content view with TabBar navigation
/// Coordinates all major sections of the app
@available(iOS 13.0, *)
struct ContentView: View {
    @State private var selectedIndex: Int = 0
    @State private var showPTTOverlay: Bool = false
    @State private var showBatteryWarning: Bool = false
    @State private var showSplash: Bool = true
    @State private var showOnboarding: Bool = false
    // PTT-FIX: Error handling state
    @State private var showPTTError: Bool = false
    @State private var pttErrorMessage: String = ""

    // Quick Action navigation state
    @State private var showMeshView: Bool = false
    @State private var showGroupsView: Bool = false
    @State private var showVoiceView: Bool = false
    @State private var showOfflineMapsView: Bool = false
    @State private var showWiFiDirectView: Bool = false
    @State private var showAddContactView: Bool = false
    @State private var showFaceToFaceGroup: Bool = false

    var body: some View {
        ZStack {
            // Onboarding screen (shown first time only)
            if showOnboarding {
                OnboardingView {
                    showOnboarding = false
                }
                .transition(.opacity)
            }

            // Splash screen
            if showSplash && !showOnboarding {
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

            // P2-FIX: PTT Button always visible
            PTTButtonOverlay()
                .allowsHitTesting(true)

            // SOS Emergency Button (top right corner)
            SOSButtonOverlay()
                .allowsHitTesting(true)
        }
        .callOverlay()
        .onAppear {
            checkBatteryLevel()
            // PTT-FIX: Set up VoiceService delegate for error handling
            VoiceService.shared.delegate = PTTErrorHandler.shared
            // Splash screen auto-hides after loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation {
                    showSplash = false
                }
            }
        }
        // Quick Action navigation handlers
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMesh)) { _ in
            showMeshView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToGroups)) { _ in
            showGroupsView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToVoice)) { _ in
            showVoiceView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToOfflineMaps)) { _ in
            showOfflineMapsView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToWiFiDirect)) { _ in
            showWiFiDirectView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAddContact)) { _ in
            showAddContactView = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToFaceToFace)) { _ in
            showFaceToFaceGroup = true
        }
        .sheet(isPresented: $showMeshView) {
            MeshStatusDetailView()
        }
        .sheet(isPresented: $showGroupsView) {
            GroupsListView()
        }
        .sheet(isPresented: $showVoiceView) {
            VoiceChannelView()
        }
        .sheet(isPresented: $showOfflineMapsView) {
            OfflineMapsView()
        }
        .sheet(isPresented: $showWiFiDirectView) {
            WiFiDirectView()
        }
        .sheet(isPresented: $showAddContactView) {
            AddContactView()
        }
        .sheet(isPresented: $showFaceToFaceGroup) {
            FaceToFaceGroupView()
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
                Text("low_battery_warning".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("low_battery_message".localized)
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
        .background(Color.fireflyOrange)
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
    @State private var showCreditsHistory: Bool = false
    @State private var showMapFullScreen: Bool = false
    @State private var currentMode: MeshOperationMode = .standby

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // P1-FIX: 地图预览缩略图 (Map Preview Thumbnail)
                    MapPreviewThumbnail()
                        .onTapGesture {
                            showMapFullScreen = true
                        }

                    // P1-FIX: 一键模态切换按钮 (One-Click Mode Toggle)
                    ModeToggleCard(currentMode: $currentMode)

                    // Credits Quick Access Card with Tier Badge
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill")
                            .font(.title2)
                            .foregroundColor(.fireflyOrange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("credits".localized)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                Text("\(Int(CreditEngine.shared.getBalance()))")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                // P2-FIX: 积分等级徽章 (Credit Tier Badge)
                                CreditTierBadge(tier: CreditEngine.shared.currentAccount.tier)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: { showCreditsHistory = true }) {
                            HStack(spacing: 4) {
                                Text("view_details".localized)
                                    .font(.caption)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundColor(.fireflyOrange)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)

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
            .alert("emergency_sos".localized, isPresented: $showSOSConfirmation) {
                Button("cancel".localized, role: .cancel) {}
                Button("activate_sos".localized, role: .destructive) {
                    // P0-FIX: Ensure message is not nil for emergency SOS
                    let sosMessage = "Emergency SOS triggered from HomeView"
                    SOSManager.shared.triggerSOS(type: .other, severity: .high, message: sosMessage)
                }
            } message: {
                Text("sos_confirmation_message".localized)
            }
            .sheet(isPresented: $showCreditsHistory) {
                CreditsHistoryView()
            }
            .fullScreenCover(isPresented: $showMapFullScreen) {
                MapView()
            }
        }
    }
}

// MARK: - Map Preview Thumbnail (P1-FIX)

struct MapPreviewThumbnail: View {
    var body: some View {
        ZStack {
            // Map placeholder background
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray5))
                .frame(height: 180)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("map_preview".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
            
            // Navigation entry button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        NotificationCenter.default.post(name: .navigateToMap, object: nil)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption)
                            Text("navigate".localized)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.fireflyOrange)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .padding(12)
                }
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Mode Toggle Card (P1-FIX)

struct ModeToggleCard: View {
    @Binding var currentMode: MeshOperationMode
    @State private var showModeDetail: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: currentMode == .networking ? "antenna.radiowaves.left.and.right" : "moon.fill")
                    .foregroundColor(currentMode == .networking ? .fireflyGreen : .blue)
                Text(currentMode == .networking ? "networking_mode".localized : "standby_mode".localized)
                    .font(.headline)
                Spacer()
                // One-click toggle button
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        currentMode = currentMode == .networking ? .standby : .networking
                    }
                    // Apply mode change
                    ModeTransitionManager.shared.transitionTo(currentMode)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                        Text("switch".localized)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.fireflyOrange)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
            }
            
            Text(currentMode == .networking ? "networking_mode_desc".localized : "standby_mode_desc".localized)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .onAppear {
            currentMode = ModeTransitionManager.shared.currentMode
        }
    }
}

// MARK: - Credit Tier Badge (P2-FIX)

struct CreditTierBadge: View {
    let tier: CreditTier
    
    var badgeColor: Color {
        switch tier {
        case .gold: return .yellow
        case .silver: return .gray
        case .bronze: return Color(red: 0.8, green: 0.5, blue: 0.2)
        case .platinum: return Color(red: 0.9, green: 0.9, blue: 0.95)
        }
    }
    
    var badgeIcon: String {
        switch tier {
        case .gold: return "star.fill"
        case .silver: return "star.leadinghalf.filled"
        case .bronze: return "star"
        case .platinum: return "crown.fill"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: badgeIcon)
                .font(.caption2)
            Text(String(describing: tier))
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.2))
        .foregroundColor(badgeColor)
        .cornerRadius(8)
    }
}

// MARK: - Mode Transition Manager

class ModeTransitionManager: ObservableObject {
    static let shared = ModeTransitionManager()
    
    @Published var currentMode: MeshOperationMode = .standby
    
    func transitionTo(_ mode: MeshOperationMode) {
        currentMode = mode
        // Post notification for other views to update
        NotificationCenter.default.post(name: .modeDidChange, object: mode)
    }
}

extension Notification.Name {
    static let modeDidChange = Notification.Name("modeDidChange")
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
                    .foregroundColor(.fireflyYellow)
                Text("mesh_network_status".localized)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(status.isConnected ? Color.fireflyGreen : Color.fireflyOrange)
                    .frame(width: 12, height: 12)
            }

            // Current mode display
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.fireflyOrange)
                Text("standby_mode".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("tap_to_switch".localized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if status.isConnected {
                Text(String(format: "connected_to_nodes".localized, status.connectedNodes))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(String(format: "signal_strength_label".localized, status.signalStrength))
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
                    Text(isReconnecting ? "reconnecting".localized : "searching_for_mesh".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Button(action: reconnect) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("reconnect".localized)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .disabled(isReconnecting)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
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
                    .foregroundColor(.fireflyGreen)
                Text("location".localized)
                    .font(.headline)
                Spacer()
                if manager.hasLocationPermission() {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.fireflyGreen)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let location = manager.currentLocation {
                Text(String(format: "lat_format".localized, location.latitude))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "lng_format".localized, location.longitude))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // P0-FIX: 添加loading动画而不是静态文本
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                    Text("acquiring_location".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
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

/// ContentView quick actions configuration
struct ContentViewQuickActionsConfiguration {
    static let defaultActions: [QuickActionConfig] = [
        QuickActionConfig(
            id: "mesh",
            title: "mesh".localized,
            icon: "antenna.radiowaves.left.and.right",
            color: .fireflyGreen,
            notificationName: .navigateToMesh
        ),
        QuickActionConfig(
            id: "groups",
            title: "groups".localized,
            icon: "person.2.fill",
            color: .purple,
            notificationName: .navigateToGroups
        ),
        QuickActionConfig(
            id: "voice_call",
            title: "voice_call".localized,
            icon: "waveform",
            color: .orange,
            notificationName: .navigateToVoice
        )
    ]
}

@available(iOS 13.0, *)
struct ContentViewQuickActionsSection: View {
    private let actions = ContentViewQuickActionsConfiguration.defaultActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("quick_actions".localized)
                .font(.headline)

            ForEach(actions) { action in
                ContentViewQuickActionButton(
                    icon: action.icon,
                    title: action.title,
                    color: action.color
                ) {
                    NotificationCenter.default.post(name: action.notificationName, object: nil)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - Group Members Section

@available(iOS 13.0, *)
struct ConnectedUsersSection: View {
    @State private var callingMemberId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("group_members".localized)
                    .font(.headline)
                Spacer()
                Text("\(VoiceCallManager.shared.groupMembers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(VoiceCallManager.shared.groupMembers) { member in
                GroupMemberRow(
                    member: member,
                    isCalling: callingMemberId == member.id,
                    onVoiceCall: {
                        callingMemberId = member.id
                        VoiceCallManager.shared.initiateCall(to: member)
                    }
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Group Member Row

struct GroupMemberRow: View {
    let member: VoiceGroupMember
    var isCalling: Bool = false
    var onVoiceCall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.body)
                        .foregroundColor(.blue)
                )

            // Name
            Text(member.name)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            // Voice Call Button
            Button(action: onVoiceCall) {
                Image(systemName: isCalling ? "phone.fill" : "phone")
                    .font(.system(size: 18))
                    .foregroundColor(isCalling ? .red : .fireflyGreen)
                    .frame(width: 44, height: 44)
                    .background(isCalling ? Color.red.opacity(0.1) : Color.fireflyGreen.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 8)
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
                .overlay(Circle().stroke(Color.fireflyOrange, lineWidth: 2))
            Text(String(format: "user_placeholder".localized, index + 1))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - DiscoverView

@available(iOS 13.0, *)
struct DiscoverView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Map View Container - P2-FIX: reduced height for small screens
                MapContainerView()
                    .frame(height: 200)
                    .cornerRadius(12)
                    .padding(.horizontal)

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    Text("search_location_or_users".localized)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

                // Discover Options - P2-FIX: adaptive spacing for small screens
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        DiscoverCard(
                            icon: "map.fill",
                            title: "Offline Maps",
                            subtitle: "Download for offline use"
                        ) {
                            NotificationCenter.default.post(name: .navigateToOfflineMaps, object: nil)
                        }
                        DiscoverCard(
                            icon: "wifi",
                            title: "WiFi Direct",
                            subtitle: "Connect to nearby devices"
                        ) {
                            NotificationCenter.default.post(name: .navigateToWiFiDirect, object: nil)
                        }
                        DiscoverCard(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "Mesh Nodes",
                            subtitle: "View network topology"
                        ) {
                            NotificationCenter.default.post(name: .navigateToMesh, object: nil)
                        }
                        DiscoverCard(
                            icon: "person.badge.plus",
                            title: "Add Contact",
                            subtitle: "Scan or share ID"
                        ) {
                            NotificationCenter.default.post(name: .navigateToAddContact, object: nil)
                        }
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
            // P2-FIX: Replace gray placeholder with firefly brand gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.fireflyOrange.opacity(0.3), Color.fireflyYellow.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    VStack {
                        Image(systemName: "map.fill")
                            .font(.largeTitle)
                            .foregroundColor(.fireflyOrange)
                        Text("map_view".localized)
                            .font(.headline)
                            .foregroundColor(.fireflyOrange)
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.fireflyOrange)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
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
}

// MARK: - ProfileView

@available(iOS 13.0, *)
struct ProfileView: View {
    @ObservedObject private var identityManager = IdentityManager.shared

    @State private var showCreditsHistory = false
    @State private var showMyGroups = false
    @State private var showActivityHistory = false
    @State private var showAccountSettings = false
    @State private var showQRCode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Header
                    VStack(spacing: 12) {
                        Circle()
                            .fill(Color.fireflyOrange.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.fireflyOrange)
                            )

                        Text(identityManager.username ?? "User")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("ID: \(IdentityManager.shared.uid?.prefix(8) ?? "Unknown")...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    // QR Code Section
                    VStack(spacing: 12) {
                        Text("my_qr_code".localized)
                            .font(.headline)
                        
                        if let uid = IdentityManager.shared.uid {
                            if let qrImage = generateQRCode(from: uid) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .padding(8)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        showQRCode = true
                                    }
                            } else {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, height: 120)
                            }
                        } else {
                            Image(systemName: "qrcode")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                                .frame(width: 120, height: 120)
                        }
                        
                        Text("tap_to_enlarge".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Stats Section
                    HStack(spacing: 20) {
                        StatItem(title: "Credits", value: "\(Int(CreditEngine.shared.getBalance()))")
                        StatItem(title: "Nodes", value: "\(MeshStatusManager.shared.connectedNodes)")
                        StatItem(title: "Groups", value: "\(GroupStore.shared.getAllGroups().count)")
                    }
                    .padding()

                    // Menu Items
                    VStack(spacing: 0) {
                        ProfileMenuItem(icon: "creditcard", title: "Credits History") {
                            showCreditsHistory = true
                        }
                        ProfileMenuItem(icon: "person.2", title: "My Groups") {
                            showMyGroups = true
                        }
                        ProfileMenuItem(icon: "clock", title: "Activity History") {
                            showActivityHistory = true
                        }
                        ProfileMenuItem(icon: "gear", title: "Account Settings") {
                            showAccountSettings = true
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("tab_profile".localized)
            .sheet(isPresented: $showCreditsHistory) {
                CreditsHistoryView()
            }
            .sheet(isPresented: $showMyGroups) {
                GroupsListView()
            }
            .sheet(isPresented: $showActivityHistory) {
                ActivityHistoryView()
            }
            .sheet(isPresented: $showAccountSettings) {
                AccountSettingsView()
            }
            .sheet(isPresented: $showQRCode) {
                QRCodeFullscreenView(uid: IdentityManager.shared.uid ?? "")
            }
        }
    }

    // MARK: - QR Code Generator
    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = 10.0 / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - QR Code Fullscreen View

@available(iOS 13.0, *)
struct QRCodeFullscreenView: View {
    let uid: String
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 30) {
            Text("scan_to_add_me".localized)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 40)
            
            if let qrImage = generateQRCode(from: uid) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(radius: 10)
            }
            
            Text("ID: \(uid.prefix(12))...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("close".localized)
                    .fontWeight(.semibold)
                    .foregroundColor(.fireflyOrange)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = 20.0 / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.fireflyOrange)
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

// MARK: - PTT Button Overlay (P2-FIX: Always Visible + Text Label)
// FIX: PTT button now uses DragGesture for proper press/release detection like SOS button

@available(iOS 13.0, *)
struct PTTButtonOverlay: View {
    // P2-FIX: Always visible regardless of connection status
    let isVisible: Bool = true
    @State private var isPressed: Bool = false
    @State private var isConnected: Bool = false
    @State private var currentGroupName: String?
    @State private var showPTTError: Bool = false
    @State private var pttErrorMessage: String = ""

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    // FIX: Use DragGesture instead of Button for proper press/release detection
                    // PTT-FIX: Visual state semantics - distinct colors per state:
                    // - Not connected to Mesh: Light gray (disabled indicator)
                    // - Standby/No group selected: Blue (available but not active)
                    // - Connected + group: FireflyOrange (ready to use)
                    // - Pressed/Transmitting: Red (active transmission)
                    ZStack {
                        Circle()
                            .fill(pttButtonColor)
                            .frame(width: 70, height: 70)
                            .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 3)

                        Image(systemName: "waveform")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .animation(.spring(response: 0.2), value: isPressed)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isPressed {
                                    isPressed = true
                                    handlePTTPress()
                                }
                            }
                            .onEnded { _ in
                                isPressed = false
                                handlePTTRelease()
                            }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("ptt_button_label".localized)
                    .accessibilityHint("ptt_button_hint".localized)
                    .accessibilityValue(isPressed ? "ptt_pressing".localized : "ptt_not_pressed".localized)

                    // P2-FIX: Show current group name or status instead of fixed "PTT"
                    // PTT-FIX: Improved text readability - 14pt font, 100% opacity
                    Text(currentGroupName ?? "ptt_no_group".localized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 70)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 120)
            }
        }
        .transition(.move(edge: .trailing))
        .onAppear {
            isConnected = MeshStatusManager.shared.isConnected
            currentGroupName = VoiceService.shared.currentGroupName
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshStatusChanged)) { _ in
            isConnected = MeshStatusManager.shared.isConnected
        }
        // PTT-FIX: Observe currentGroupName changes
        .onReceive(VoiceService.shared.$currentGroupName) { name in
            currentGroupName = name
        }
        // PTT-FIX: Show error alerts
        .alert("ptt_error_title".localized, isPresented: $showPTTError) {
            Button("ok".localized, role: .cancel) {}
            Button("select_group".localized) {
                NotificationCenter.default.post(name: .navigateToGroups, object: nil)
            }
        } message: {
            Text(pttErrorMessage)
        }
    }

    // FIX: Separate press and release handlers for proper PTT behavior
    private func handlePTTPress() {
        VoiceService.shared.startTransmitting()
    }

    private func handlePTTRelease() {
        VoiceService.shared.stopTransmitting()
    }

    // PTT-FIX: Compute button color based on semantic state
    // - Not connected to Mesh: Light gray (disabled indicator)
    // - Connected but no group: Blue (available but not active)
    // - Connected + group: FireflyOrange (ready to use)
    // - Pressed/Transmitting: Red (active transmission)
    private var pttButtonColor: Color {
        if isPressed {
            return .red
        } else if !isConnected {
            // Not connected to Mesh - show disabled state with light gray
            return Color.gray.opacity(0.5)
        } else if currentGroupName == nil {
            // Connected but no group selected - blue (standby)
            return .blue
        } else {
            // Connected with group - ready state
            return .fireflyOrange
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
                        // P0-FIX: 主按钮在最底层，脉冲动画在上层
                        Circle()
                            .fill(isSOSActive ? Color.red : Color.red.opacity(0.9))
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)

                        VStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                            Text("sos".localized)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            if isSOSActive {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }

                        // P0-FIX: SOS激活时显示脉冲动画效果，确保在最上层
                        if isSOSActive {
                            Circle()
                                .fill(Color.red.opacity(0.4))
                                .frame(width: 110, height: 110)
                                .modifier(PulseAnimation())

                            Circle()
                                .fill(Color.red.opacity(0.7))
                                .frame(width: 95, height: 95)
                                .modifier(PulseAnimation(delay: 0.2))
                        }
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.red, lineWidth: isSOSActive ? 3 : 0)
                            .frame(width: 90, height: 90)
                            .animation(.easeInOut(duration: 0.3), value: isSOSActive)
                    )
                }
                .padding(.trailing, 20)
                .padding(.top, 60)
            }
            Spacer()
        }
        .alert("emergency_sos".localized, isPresented: $showSOSAlert) {
            Button("cancel".localized, role: .cancel) {}
            Button("activate_sos".localized, role: .destructive) {
                let sosMessage = "Emergency SOS triggered from SOSButtonOverlay"
                SOSManager.shared.triggerSOS(type: .other, severity: .high, message: sosMessage)
                isSOSActive = true
            }
        } message: {
            Text("sos_confirmation_message".localized)
        }
        .alert("cancel_sos".localized, isPresented: $showCancelConfirmation) {
            Button("keep_sos_active".localized, role: .cancel) {}
            Button("cancel_sos".localized, role: .destructive) {
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
    static let navigateToOfflineMaps = Notification.Name("navigateToOfflineMaps")
    static let navigateToWiFiDirect = Notification.Name("navigateToWiFiDirect")
    static let navigateToAddContact = Notification.Name("navigateToAddContact")
    static let navigateToFaceToFace = Notification.Name("navigateToFaceToFace")
    static let meshStatusChanged = Notification.Name("meshStatusChanged")
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
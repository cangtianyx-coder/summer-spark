import SwiftUI

// MARK: - ContentView

/// Main content view with TabBar navigation
/// Coordinates all major sections of the app
@available(iOS 13.0, *)
struct ContentView: View {
    @State private var selectedIndex: Int = 0
    @State private var showPTTOverlay: Bool = false

    var body: some View {
        ZStack {
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
            .accentColor(.blue)

            // Floating PTT Button Overlay
            PTTButtonOverlay(isVisible: MeshStatusManager.shared.isConnected)
                .allowsHitTesting(true)

            // SOS Emergency Button (top right corner)
            SOSButtonOverlay()
                .allowsHitTesting(true)
        }
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
                    EmergencyManager.shared.triggerSOS()
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
                    .frame(width: 10, height: 10)
            }

            if status.isConnected {
                Text("Connected to \(status.connectedNodes) nodes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Signal: \(status.signalStrength)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Searching for mesh network...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Location Card

@available(iOS 13.0, *)
struct LocationCard: View {
    var manager: LocationManager

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
            }

            if let location = manager.currentLocation {
                Text("Lat: \(String(format: "%.6f", location.latitude))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Lng: \(String(format: "%.6f", location.longitude))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Acquiring location...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
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
                ContentViewQuickActionButton(
                    icon: "map.fill",
                    title: "Map",
                    color: .blue
                ) {
                    NotificationCenter.default.post(name: .navigateToMap, object: nil)
                }

                ContentViewQuickActionButton(
                    icon: "person.2.fill",
                    title: "Groups",
                    color: .purple
                ) {
                    NotificationCenter.default.post(name: .navigateToGroups, object: nil)
                }

                ContentViewQuickActionButton(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Mesh",
                    color: .green
                ) {
                    NotificationCenter.default.post(name: .navigateToMesh, object: nil)
                }

                ContentViewQuickActionButton(
                    icon: "waveform",
                    title: "Voice",
                    color: .orange
                ) {
                    NotificationCenter.default.post(name: .navigateToVoice, object: nil)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
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
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - User Avatar

@available(iOS 13.0, *)
struct UserAvatar: View {
    let index: Int

    var body: some View {
        VStack {
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.blue)
                )
            Text("User \(index + 1)")
                .font(.caption2)
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
                    Button(action: {}) {
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

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { showSOSAlert = true }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 50, height: 50)
                            .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 3)

                        Text("SOS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
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
                EmergencyManager.shared.triggerSOS()
            }
        } message: {
            Text("sos_confirmation_message".localized)
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
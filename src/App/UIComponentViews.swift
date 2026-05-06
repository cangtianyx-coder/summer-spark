import SwiftUI

// MARK: - Mesh Status Detail View

struct MeshStatusDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var meshStatus = MeshStatusManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("network_status".localized) {
                    HStack {
                        Text("connected".localized)
                        Spacer()
                        Circle()
                            .fill(meshStatus.isConnected ? Color.fireflyGreen : Color.orange)
                            .frame(width: 12, height: 12)
                        Text(meshStatus.isConnected ? "yes".localized : "no".localized)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("active_nodes".localized)
                        Spacer()
                        Text("\(meshStatus.connectedNodes)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("signal_strength".localized)
                        Spacer()
                        Text("\(meshStatus.signalStrength)%")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("transport_medium".localized)
                        Spacer()
                        Text(mediumName(meshStatus.currentMedium))
                            .foregroundColor(.secondary)
                    }
                }

                Section("actions".localized) {
                    Button(action: {
                        MeshService.shared.start()
                        meshStatus.updateStatus()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("refresh_network".localized)
                        }
                    }

                    Button(action: {
                        MeshService.shared.stop()
                        meshStatus.updateStatus()
                    }) {
                        HStack {
                            Image(systemName: "stop.fill")
                                .foregroundColor(.red)
                            Text("stop_mesh".localized)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("mesh_network".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
            }
            .onAppear {
                meshStatus.updateStatus()
            }
        }
    }

    private func mediumName(_ medium: MeshNode.TransportMedium) -> String {
        switch medium {
        case .bluetoothLE: return "Bluetooth LE"
        case .wifi: return "WiFi"
        case .ethernet: return "Ethernet"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Groups List View

struct GroupsListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupList: [Group] = []
    @State private var selectedGroupId: String?
    @State private var showCreateGroupAlert = false
    @State private var newGroupName = ""

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if groupList.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("no_groups_yet".localized)
                            .font(.headline)
                        Text("create_or_join_group".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("create_group".localized) {
                            showCreateGroupAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .alert("create_group".localized, isPresented: $showCreateGroupAlert) {
                            TextField("group_name_placeholder".localized, text: $newGroupName)
                            Button("cancel".localized, role: .cancel) {
                                newGroupName = ""
                            }
                            Button("create".localized) {
                                createGroup()
                            }
                        } message: {
                            Text("enter_group_name".localized)
                        }
                    }
                } else {
                    List(groupList, id: \.id) { group in
                        // PTT-FIX: Make row selectable to set current group for PTT
                        Button(action: {
                            selectedGroupId = group.id
                            VoiceService.shared.setCurrentGroup(group.id, name: group.name)
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(group.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("\(group.members.count) members")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedGroupId == group.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.fireflyGreen)
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("groups_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        NotificationCenter.default.post(name: .navigateToFaceToFace, object: nil)
                    }) {
                        Image(systemName: "person.3.fill")
                    }
                }
            }
            .onAppear { loadGroups() }
        }
    }

    private func loadGroups() {
        groupList = GroupStore.shared.getAllGroups()
        // PTT-FIX: Pre-select current group if one is set
        selectedGroupId = VoiceService.shared.currentGroupId
    }

    private func createGroup() {
        let trimmedName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let _ = GroupStore.shared.createGroup(name: trimmedName) {
            loadGroups()
        }
        newGroupName = ""
    }
}

// MARK: - Voice Channel View

struct VoiceChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var voiceManager = VoiceCallManager.shared
    @State private var isTransmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Status
                VStack(spacing: 8) {
                    Image(systemName: voiceManager.isInCall ? "waveform" : "waveform.circle")
                        .font(.system(size: 60))
                        .foregroundColor(voiceManager.isInCall ? .fireflyGreen : .gray)
                    Text(voiceManager.isInCall ? "in_voice_channel".localized : "no_active_call".localized)
                        .font(.headline)
                    if let call = voiceManager.activeCall {
                        Text(String(format: "started_at".localized, call.startTime.formatted(date: .omitted, time: .shortened)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 40)

                Spacer()

                // PTT Button
                VStack(spacing: 16) {
                    Text("push_to_talk".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: {
                        if isTransmitting {
                            isTransmitting = false
                            VoiceService.shared.stopTransmitting()
                        } else {
                            isTransmitting = true
                            VoiceService.shared.startTransmitting()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                isTransmitting = false
                                VoiceService.shared.stopTransmitting()
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(isTransmitting ? Color.red : Color.fireflyOrange)
                                .frame(width: 100, height: 100)
                                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)

                            Image(systemName: "waveform")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        }
                    }
                    .scaleEffect(isTransmitting ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isTransmitting)

                    Text(isTransmitting ? "transmitting".localized : "tap_and_hold".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Participants
                if !voiceManager.groupMembers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: "participants".localized, voiceManager.groupMembers.count))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(voiceManager.groupMembers) { member in
                            HStack {
                                Circle()
                                    .fill(member.isOnline ? Color.fireflyGreen : Color.gray)
                                    .frame(width: 10, height: 10)
                                Text(member.name)
                                Spacer()
                                Button(action: {
                                    voiceManager.initiateCall(to: member)
                                }) {
                                    Image(systemName: "phone")
                                        .foregroundColor(.fireflyGreen)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 40)
            .navigationTitle("title_voice_call".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Offline Maps View

struct OfflineMapsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var downloadedRegions: [String] = []
    @State private var availableRegions: [OfflineMapInfo] = []
    @State private var isDownloading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Downloaded Regions") {
                    if downloadedRegions.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "map")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("No offline maps downloaded")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical)
                            Spacer()
                        }
                    } else {
                        ForEach(downloadedRegions, id: \.self) { region in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.fireflyGreen)
                                Text(region)
                                Spacer()
                                Button(action: {}) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                Section("Available Regions") {
                    ForEach(availableRegions) { region in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(region.name)
                                    .font(.headline)
                                Text("\(region.bounds.northEast.latitude, specifier: "%.2f")N, \(region.bounds.northEast.longitude, specifier: "%.2f")E")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if downloadedRegions.contains(region.name) {
                                Text("Downloaded")
                                    .font(.caption)
                                    .foregroundColor(.fireflyGreen)
                            } else {
                                Button(action: {
                                    downloadRegion(region)
                                }) {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Offline Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
            }
            .onAppear {
                loadDownloadedRegions()
                loadAvailableRegions()
            }
        }
    }

    private func loadDownloadedRegions() {
        downloadedRegions = OfflineMapManager.shared.getDownloadedRegions() ?? []
    }
    
    private func loadAvailableRegions() {
        availableRegions = OfflineMapManager.shared.getAvailableRegions()
    }

    private func downloadRegion(_ region: OfflineMapInfo) {
        isDownloading = true
        // Start offline map download with actual region bounds
        OfflineMapManager.shared.startDownload(region)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isDownloading = false
            if !downloadedRegions.contains(region.name) {
                downloadedRegions.append(region.name)
                // Persist to UserDefaults
                var regions = UserDefaults.standard.stringArray(forKey: "offlineMap.downloadedRegions") ?? []
                if !regions.contains(region.name) {
                    regions.append(region.name)
                    UserDefaults.standard.set(regions, forKey: "offlineMap.downloadedRegions")
                }
            }
        }
    }
}

// MARK: - WiFi Direct View

struct WiFiDirectView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSearching = false
    @State private var peers: [String] = []
    @State private var isEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section("WiFi Direct") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Circle()
                            .fill(isEnabled ? Color.fireflyGreen : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(isEnabled ? "Enabled" : "Disabled")
                            .foregroundColor(.secondary)
                    }

                    Button(action: toggleWiFiDirect) {
                        HStack {
                            Image(systemName: isEnabled ? "wifi.slash" : "wifi")
                            Text(isEnabled ? "Disable WiFi Direct" : "Enable WiFi Direct")
                        }
                    }
                }

                Section("Nearby Devices") {
                    if isSearching {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Searching...")
                                .foregroundColor(.secondary)
                        }
                    } else if peers.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("No devices found")
                                    .foregroundColor(.secondary)
                                Button("Search Again") {
                                    searchForPeers()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical)
                            Spacer()
                        }
                    } else {
                        ForEach(peers, id: \.self) { peer in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundColor(.blue)
                                Text(peer)
                                Spacer()
                                Button("Connect") {
                                    connectToPeer(peer)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .navigationTitle("WiFi Direct")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
            }
            .onAppear {
                checkStatus()
            }
        }
    }

    private func checkStatus() {
        // Check WiFi Direct status from WiFiService
        isEnabled = WiFiService.shared.isEnabled()
    }

    private func toggleWiFiDirect() {
        if isEnabled {
            WiFiService.shared.disable()
        } else {
            WiFiService.shared.enable()
        }
        isEnabled.toggle()
    }

    private func searchForPeers() {
        isSearching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isSearching = false
        }
    }

    private func connectToPeer(_ peer: String) {
        // Attempt connection via WiFiService
        Logger.shared.info("WiFiDirect: Connecting to \(peer)")
    }
}

// MARK: - Add Contact View

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var contactID: String = ""
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // QR Scanner placeholder
                VStack(spacing: 16) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 80))
                        .foregroundColor(.fireflyOrange)

                    Text("Scan QR Code")
                        .font(.headline)

                    Text("Point your camera at another user's QR code to add them to your mesh network.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: {
                        showScanner = true
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Open Scanner")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.fireflyOrange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                }
                .padding(.top, 40)

                Divider()

                // Manual ID entry
                VStack(spacing: 16) {
                    Text("Or enter ID manually")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("Enter User ID", text: $contactID)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    Button(action: addContactByID) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Add Contact")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(contactID.isEmpty ? Color.gray : Color.fireflyOrange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(contactID.isEmpty)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            ScannerView { result in
                showScanner = false
                if case .success(let code) = result {
                    contactID = code
                    addContactByID()
                }
            }
        }
    }

    private func addContactByID() {
        guard !contactID.isEmpty else { return }
        // Add contact via IdentityManager or GroupStore
        Logger.shared.info("AddContact: Adding contact with ID \(contactID)")
        contactID = ""
        dismiss()
    }
}

// MARK: - Credits History View

struct CreditsHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transactions: [CreditEngine.TransactionRecord] = []

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if transactions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No transactions yet")
                            .font(.headline)
                        Text("Your credit history will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(transactions, id: \.id) { tx in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tx.description)
                                    .font(.subheadline)
                                Text(tx.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(tx.amount >= 0 ? "+\(Int(tx.amount))" : "\(Int(tx.amount))")
                                .foregroundColor(tx.amount >= 0 ? .fireflyGreen : .red)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Credits History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
            }
            .onAppear {
                loadTransactions()
            }
        }
    }

    private func loadTransactions() {
        transactions = CreditEngine.shared.getTransactionHistory()
    }
}

// MARK: - Activity History View

struct ActivityHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var activities: [ActivityRecord] = []

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if activities.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No activity yet")
                            .font(.headline)
                        Text("Your mesh activity will be logged here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(activities, id: \.id) { activity in
                        HStack {
                            Image(systemName: activity.iconName)
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text(activity.title)
                                    .font(.subheadline)
                                Text(activity.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Account Settings View

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var identityManager = IdentityManager.shared
    @State private var username: String = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Identity") {
                    HStack {
                        Text("User ID")
                        Spacer()
                        Text(IdentityManager.shared.uid?.prefix(12).description ?? "Unknown")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    TextField("Username", text: $username)
                        .textContentType(.nickname)
                        .onChange(of: username) { newValue in
                            IdentityManager.shared.validateAndSetUsername(newValue)
                        }
                        .onAppear {
                            username = identityManager.username ?? ""
                        }
                }

                Section("Security") {
                    Button(action: {
                        // Export identity
                        Logger.shared.info("AccountSettings: Export identity requested")
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Identity")
                        }
                    }

                    Button(action: {
                        // Rotate identity keys
                        Logger.shared.info("AccountSettings: Rotate keys requested")
                    }) {
                        HStack {
                            Image(systemName: "key.horizontal")
                            Text("Rotate Keys")
                        }
                    }
                }

                Section("Data") {
                    Button(action: {
                        // Clear local data
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Clear Local Data")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Account Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized) { dismiss() }
                }
            }
            .alert("Clear Local Data?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    // Clear data
                    Logger.shared.info("AccountSettings: Clear local data requested")
                }
            } message: {
                Text("This will remove all locally stored data. This action cannot be undone.")
            }
        }
    }
}

// MARK: - Scanner View

import SwiftUI
import AVFoundation

struct ScannerView: View {
    let onResult: (Result<String, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = true

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerViewRepresentable { result in
                    isScanning = false
                    onResult(result)
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.fireflyOrange, lineWidth: 3)
                        .frame(width: 250, height: 250)

                    Spacer()

                    Text("Align QR code within the frame")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)

                    Spacer()
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QRScannerViewRepresentable: UIViewControllerRepresentable {
    let onResult: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onResult = onResult
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onResult: ((Result<String, Error>) -> Void)?
    private var captureSession: AVCaptureSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        self.captureSession = session

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            onResult?(.failure(NSError(domain: "Scanner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera not available"])))
            return
        }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            onResult?(.failure(error))
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            onResult?(.failure(NSError(domain: "Scanner", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not add video input"])))
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            onResult?(.failure(NSError(domain: "Scanner", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not add metadata output"])))
            return
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else {
            return
        }

        captureSession?.stopRunning()
        onResult?(.success(stringValue))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}

// MARK: - Supporting Data Types

struct ActivityRecord: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let timestamp: Date
}

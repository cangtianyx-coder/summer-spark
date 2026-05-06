import SwiftUI

// MARK: - FaceToFace Group View

/// 面对面建群主视图
struct FaceToFaceGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: FaceToFaceMode = .create
    @State private var groupName: String = ""
    @State private var numericCode: String = ""
    @State private var showScanner: Bool = false
    @State private var state: FaceToFaceGroupState = .idle
    @State private var createdGroup: Group?
    @State private var createdInvite: FaceToFaceInvite?
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showCopiedToast: Bool = false
    @State private var remainingSeconds: Int = 0
    @State private var countdownTimer: Timer?
    
    private let manager = FaceToFaceGroupManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode Selector
                Picker("Mode", selection: $mode) {
                    Text("发起建群").tag(FaceToFaceMode.create)
                    Text("加入群组").tag(FaceToFaceMode.join)
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // Content based on mode
                ScrollView {
                    switch mode {
                    case .create:
                        createGroupContent
                    case .join:
                        joinGroupContent
                    }
                }
            }
            .navigationTitle("面对面建群")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定") {}
            } message: {
                Text(errorMessage ?? "发生未知错误")
            }
            .overlay(
                SwiftUI.Group {
                    if showCopiedToast {
                        VStack {
                            Spacer()
                            Text("已复制到剪贴板")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(20)
                                .padding(.bottom, 100)
                        }
                        .transition(.opacity)
                    }
                }
            )
            .animation(.easeInOut, value: showCopiedToast)
            .sheet(isPresented: $showScanner) {
                ScannerView { result in
                    showScanner = false
                    handleScannedCode(result)
                }
            }
            .onChange(of: state) { newState in
                if case .success(let group) = newState, let invite = createdInvite {
                    startCountdown(expiresAt: invite.expiresAt)
                }
            }
            .onDisappear {
                countdownTimer?.invalidate()
            }
        }
    }
    
    // MARK: - Countdown Timer
    
    private func startCountdown(expiresAt: Date) {
        countdownTimer?.invalidate()
        updateRemainingSeconds(expiresAt: expiresAt)
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateRemainingSeconds(expiresAt: expiresAt)
        }
    }
    
    private func updateRemainingSeconds(expiresAt: Date) {
        let remaining = Int(expiresAt.timeIntervalSinceNow)
        remainingSeconds = max(0, remaining)
        
        if remainingSeconds == 0 {
            countdownTimer?.invalidate()
        }
    }
    
    // MARK: - Create Group Content
    
    @ViewBuilder
    private var createGroupContent: some View {
        VStack(spacing: 24) {
            if case .success(let group) = state, let invite = createdInvite {
                // Success State - Show QR Code
                successView(group: group, invite: invite)
            } else {
                // Initial State - Show Create Form
                createFormView
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var createFormView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.fireflyOrange)
                
                Text("创建面对面群组")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("与身边的人快速建立群组聊天")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Group Name Input
            VStack(alignment: .leading, spacing: 8) {
                Text("群组名称")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("默认：面对面群组", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
            }
            
            // Create Button
            Button(action: createGroup) {
                HStack {
                    if case .creating = state {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text("创建群组")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.fireflyOrange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(state == .creating)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func successView(group: Group, invite: FaceToFaceInvite) -> some View {
        VStack(spacing: 24) {
            // Success Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("群组已创建")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(group.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            // QR Code Section
            VStack(spacing: 16) {
                Text("扫码加入群组")
                    .font(.headline)
                
                if let qrImage = manager.generateQRCode(for: invite) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(radius: 10)
                }
                
                Text("或使用下方数字码加入")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Numeric Code Section
            VStack(spacing: 12) {
                Text("数字邀请码")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text(invite.numericCode)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.fireflyOrange)
                    
                    Button(action: {
                        UIPasteboard.general.string = invite.numericCode
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopiedToast = false
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.title3)
                            .foregroundColor(.fireflyOrange)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Expiry Info with Countdown
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                if remainingSeconds > 0 {
                    Text("邀请码还剩 \(remainingSeconds) 秒过期")
                        .font(.caption)
                        .foregroundColor(remainingSeconds <= 60 ? .red : .secondary)
                } else {
                    Text("邀请码已过期")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Done Button
            Button(action: {
                dismiss()
            }) {
                Text("完成")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.fireflyOrange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            // Create Another Button
            Button(action: {
                state = .idle
                createdGroup = nil
                createdInvite = nil
                groupName = ""
                manager.clearCurrentState()
            }) {
                Text("创建另一个群组")
                    .font(.subheadline)
                    .foregroundColor(.fireflyOrange)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Join Group Content
    
    @ViewBuilder
    private var joinGroupContent: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 60))
                    .foregroundColor(.fireflyOrange)
                
                Text("加入群组")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("扫描对方二维码或输入数字码")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Scan QR Button
            Button(action: {
                showScanner = true
            }) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("扫描二维码")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.fireflyOrange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            // Divider
            HStack {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
                Text("或")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
            }
            
            // Numeric Code Input
            VStack(alignment: .leading, spacing: 8) {
                Text("输入数字邀请码")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("6位数字码", text: $numericCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .onChange(of: numericCode) { newValue in
                        // Limit to 6 digits
                        if newValue.count > 6 {
                            numericCode = String(newValue.prefix(6))
                        }
                        // Only allow digits
                        numericCode = newValue.filter { $0.isNumber }
                    }
                
                Button(action: joinWithNumericCode) {
                    HStack {
                        if case .joining = state {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        Text("加入群组")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(numericCode.count == 6 ? Color.fireflyOrange : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(numericCode.count != 6 || state == .joining)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func createGroup() {
        state = .creating
        
        let name = groupName.isEmpty ? "面对面群组" : groupName
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let (group, invite) = manager.createFaceToFaceGroup(name: name) {
                createdGroup = group
                createdInvite = invite
                state = .success(group)
            } else {
                state = .idle
                errorMessage = "创建群组失败，请稍后重试"
                showError = true
            }
        }
    }
    
    private func joinWithNumericCode() {
        guard numericCode.count == 6 else { return }
        
        state = .joining
        
        let result = manager.joinGroup(withNumericCode: numericCode)
        switch result {
        case .success(let group):
            state = .success(group)
            createdGroup = group
        case .failure(let error):
            errorMessage = error.errorDescription
            showError = true
            state = .idle
        }
        
        // Clear the numeric code after attempt
        numericCode = ""
    }
    
    private func handleScannedCode(_ result: Result<String, Error>) {
        switch result {
        case .success(let code):
            if let invite = manager.parseQRCode(code) {
                if invite.isExpired {
                    errorMessage = FaceToFaceGroupError.inviteExpired.errorDescription
                    showError = true
                } else {
                    let joinResult = manager.joinGroup(with: invite)
                    switch joinResult {
                    case .success(let group):
                        state = .success(group)
                        createdGroup = group
                    case .failure(let error):
                        errorMessage = error.errorDescription
                        showError = true
                    }
                }
            } else {
                errorMessage = FaceToFaceGroupError.invalidInvite.errorDescription
                showError = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Preview

#Preview {
    FaceToFaceGroupView()
}

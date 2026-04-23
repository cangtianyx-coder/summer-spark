import SwiftUI

// MARK: - SOS Button

/// SOS紧急求救按钮组件
struct SOSButton: View {
    @State private var isPressed = false
    @State private var pressProgress: CGFloat = 0
    @State private var isShowingConfirmation = false
    @State private var selectedEmergencyType: EmergencyType = .other
    @State private var selectedSeverity: Severity = .high
    @State private var showErrorAlert = false  // P0-FIX: 错误提示状态
    @State private var errorMessage = ""       // P0-FIX: 错误消息
    
    private let pressDuration: CGFloat = 3.0  // 长按3秒触发
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 16) {
            // SOS按钮
            ZStack {
                // 外圈进度
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: pressProgress)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                // 内圈按钮
                Circle()
                    .fill(isPressed ? Color.red : Color.red.opacity(0.8))
                    .frame(width: 100, height: 100)
                    .overlay(
                        VStack(spacing: 4) {
                            Text("SOS")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            if isPressed {
                                Text("\(Int((1 - pressProgress) * pressDuration))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    )
            }
            .scaleEffect(isPressed ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            pressProgress = 0
                        }
                    }
                    .onEnded { _ in
                        if pressProgress >= 1.0 {
                            triggerSOS()
                        }
                        isPressed = false
                        pressProgress = 0
                    }
            )
            .onReceive(timer) { _ in
                if isPressed && pressProgress < 1.0 {
                    pressProgress += 0.1 / pressDuration
                    if pressProgress >= 1.0 {
                        triggerSOS()
                    }
                }
            }
            
            // 提示文字
            Text("sos_button_hint".localized)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        // P0-FIX: 无障碍支持
        .accessibilityElement(children: .contain)
        .accessibilityLabel("sos_button_label".localized)
        .accessibilityHint("sos_button_hint_accessibility".localized)
        .accessibilityValue(isPressed ? "sos_pressing".localized : "sos_not_pressed".localized)
        .sheet(isPresented: $isShowingConfirmation) {
            SOSConfirmationView(
                emergencyType: $selectedEmergencyType,
                severity: $selectedSeverity,
                onConfirm: { sendSOS() }
            )
        }
    }
    
    private func triggerSOS() {
        // 震动反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.critical)
        
        // 显示确认界面
        isShowingConfirmation = true
        
        Logger.shared.info("SOSButton: SOS triggered, showing confirmation")
    }
    
    private func sendSOS() {
        guard let location = LocationManager.shared.currentLocation else {
            // P0-FIX: 显示错误提示而不是静默失败
            errorMessage = "sos_error_no_location".localized
            showErrorAlert = true
            Logger.shared.warn("SOSButton: No location available for SOS")
            return
        }
        
        SOSManager.shared.triggerSOS(
            type: selectedEmergencyType,
            severity: selectedSeverity,
            location: location
        )
        
        isShowingConfirmation = false
    }
}

// MARK: - SOS Confirmation View

struct SOSConfirmationView: View {
    @Binding var emergencyType: EmergencyType
    @Binding var severity: Severity
    let onConfirm: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("紧急类型") {
                    Picker("类型", selection: $emergencyType) {
                        ForEach(EmergencyType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("紧急程度") {
                    Picker("程度", selection: $severity) {
                        ForEach(Severity.allCases.reversed(), id: \.self) { sev in
                            Text(sev.displayName).tag(sev)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("确认发送SOS")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.red)
                }
            }
            .navigationTitle("紧急求救")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Emergency Type Extension

extension EmergencyType: CaseIterable {
    static var allCases: [EmergencyType] {
        return [.injury, .lost, .trapped, .medical, .fire, .flood, .earthquake, .other]
    }
    
    var displayName: String {
        switch self {
        case .injury: return "受伤"
        case .lost: return "迷路"
        case .trapped: return "被困"
        case .medical: return "医疗急救"
        case .fire: return "火灾"
        case .flood: return "水灾"
        case .earthquake: return "地震"
        case .other: return "其他"
        }
    }
}

extension Severity: CaseIterable {
    static var allCases: [Severity] {
        return [.low, .medium, .high, .critical]
    }
    
    var displayName: String {
        switch self {
        case .low: return "轻度"
        case .medium: return "中度"
        case .high: return "重度"
        case .critical: return "危急"
        }
    }
}

// MARK: - Preview

#Preview {
    SOSButton()
}

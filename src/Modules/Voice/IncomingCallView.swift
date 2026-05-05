import SwiftUI

// MARK: - Incoming Call View

struct IncomingCallView: View {
    @ObservedObject var callManager = VoiceCallManager.shared
    @State private var isAnimating: Bool = true

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            if let incoming = callManager.incomingCall {
                VStack(spacing: 32) {
                    Spacer()

                    // 呼叫类型标签
                    Text(incoming.isGroupCall ? "GROUP CALL" : "VOICE CALL")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(4)

                    // 头像
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)

                        Image(systemName: "person.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 4)
                            .scaleEffect(isAnimating ? 1.2 : 1.0)
                            .opacity(isAnimating ? 0 : 0.5)
                            .animation(
                                Animation.easeOut(duration: 1.5)
                                    .repeatForever(autoreverses: false),
                                value: isAnimating
                            )
                    )

                    // 呼叫者名称
                    VStack(spacing: 8) {
                        Text(incoming.callerName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                        Text("calling...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    // 接听/拒绝按钮
                    HStack(spacing: 60) {
                        // 拒绝按钮
                        Button(action: {
                            callManager.declineCall()
                        }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 70, height: 70)

                                    Image(systemName: "phone.down.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                }
                                Text("Decline")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        // 接听按钮
                        Button(action: {
                            callManager.acceptCall()
                        }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 70, height: 70)

                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                }
                                Text("Accept")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(.bottom, 80)
                }
                .onAppear {
                    isAnimating = true
                }
            }
        }
    }
}

// MARK: - Active Call View

struct ActiveCallView: View {
    @ObservedObject var callManager = VoiceCallManager.shared
    @State private var callDuration: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                colors: [Color(hex: "1a2f4a"), Color(hex: "0a1628")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let activeCall = callManager.activeCall {
                VStack(spacing: 24) {
                    Spacer()

                    // 呼叫类型
                    Text(activeCall.isGroupCall ? "GROUP CALL" : "VOICE CALL")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(4)

                    // 头像
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)

                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }

                    // 呼叫者名称
                    Text(activeCall.callerName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    // 通话时长
                    Text(formatDuration(callDuration))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))

                    // 通话状态
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Spacer()

                    // 静音和结束按钮
                    HStack(spacing: 40) {
                        // 静音按钮
                        Button(action: {
                            // Toggle mute
                        }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 60, height: 60)

                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                }
                                Text("Mute")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }

                        // 结束通话按钮
                        Button(action: {
                            callManager.endCall()
                            stopTimer()
                        }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 70, height: 70)

                                    Image(systemName: "phone.down.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                }
                                Text("End")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }

                        // 扬声器按钮
                        Button(action: {
                            // Toggle speaker
                        }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 60, height: 60)

                                    Image(systemName: "speaker.wave.3.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                }
                                Text("Speaker")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            callDuration += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        callDuration = 0
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Call Overlay Modifier

struct CallOverlay: ViewModifier {
    @ObservedObject var callManager = VoiceCallManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            // 收到来电时显示来电界面
            if callManager.incomingCall != nil {
                IncomingCallView()
            }

            // 通话中显示通话界面
            if callManager.isInCall && callManager.incomingCall == nil {
                ActiveCallView()
            }
        }
    }
}

extension View {
    func callOverlay() -> some View {
        modifier(CallOverlay())
    }
}

// MARK: - Preview

#Preview {
    IncomingCallView()
}

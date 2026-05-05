import SwiftUI
import UIKit

// MARK: - Splash Screen View

struct SplashScreen: View {
    @State private var progress: Double = 0
    @State private var isAnimating: Bool = true
    @State private var showContent: Bool = true
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // 背景图片占位 - 萤火虫夏天夜晚
            ZStack {
                // 渐变背景 - 模拟夏夜
                LinearGradient(
                    colors: [
                        Color(hex: "0a1628"),  // 深蓝黑
                        Color(hex: "1a2f4a"),  // 暗蓝
                        Color(hex: "2d1f3d")   // 深紫
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 萤火虫效果
                FirefliesView()

                // Logo
                VStack(spacing: 30) {
                    // App Icon
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 120, height: 120)

                        // 火焰图标
                        Image(systemName: "flame.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.yellow, Color.orange, Color.red],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                    }

                    // App Name
                    VStack(spacing: 8) {
                        Text("SummerSpark")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("萤火星光 · 照亮希望")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .opacity(opacity)

            // 进度条
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    // 进度条背景
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 200, height: 8)
                        .overlay(
                            // 进度条填充
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.yellow, Color.orange],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * progress)
                            }
                            .frame(width: 200, height: 8)
                        )

                    // 进度文字
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 100)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startLoading()
        }
    }

    private func startLoading() {
        // 模拟加载进度
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            withAnimation(.linear(duration: 0.03)) {
                progress += 0.01
            }

            if progress >= 1.0 {
                timer.invalidate()
                // 加载完成，渐隐消失
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        opacity = 0
                    }
                }
            }
        }
    }
}

// MARK: - Fireflies View

struct FirefliesView: View {
    @State private var fireflies: [Firefly] = []

    var body: some View {
        ZStack {
            ForEach(fireflies) { firefly in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.yellow.opacity(firefly.opacity), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: firefly.radius
                        )
                    )
                    .frame(width: firefly.radius * 2, height: firefly.radius * 2)
                    .position(firefly.position)
                    .opacity(firefly.opacity)
            }
        }
        .onAppear {
            createFireflies()
        }
    }

    private func createFireflies() {
        var newFireflies: [Firefly] = []

        for i in 0..<30 {
            let firefly = Firefly(
                id: i,
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                ),
                radius: CGFloat.random(in: 3...8),
                opacity: Double.random(in: 0.3...1.0)
            )
            newFireflies.append(firefly)
        }

        fireflies = newFireflies

        // 动画效果
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 2.0)) {
                for i in fireflies.indices {
                    fireflies[i].position = CGPoint(
                        x: fireflies[i].position.x + CGFloat.random(in: -20...20),
                        y: fireflies[i].position.y + CGFloat.random(in: -30...10)
                    )
                    fireflies[i].opacity = Double.random(in: 0.2...1.0)

                    // 边界检查
                    if fireflies[i].position.x < 0 { fireflies[i].position.x = UIScreen.main.bounds.width }
                    if fireflies[i].position.x > UIScreen.main.bounds.width { fireflies[i].position.x = 0 }
                    if fireflies[i].position.y < 0 { fireflies[i].position.y = UIScreen.main.bounds.height }
                    if fireflies[i].position.y > UIScreen.main.bounds.height { fireflies[i].position.y = 0 }
                }
            }
        }
    }
}

struct Firefly: Identifiable {
    let id: Int
    var position: CGPoint
    var radius: CGFloat
    var opacity: Double
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    SplashScreen()
}

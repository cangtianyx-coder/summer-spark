import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @State private var currentPage: Int = 0
    @State private var username: String = ""
    @State private var isCompleted: Bool = false

    var onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "flame.fill",
            title: "Welcome to\n夏日萤火",
            description: "Your decentralized mesh networking companion for offline communication"
        ),
        OnboardingPage(
            icon: "antenna.radiowaves.left.and.right",
            title: "Mesh Networking",
            description: "Connect directly with other devices using Bluetooth and WiFi - no cellular network required"
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "End-to-End Encrypted",
            description: "Your communications are secured with ECDSA P-256 encryption and AES-256-GCM"
        ),
        OnboardingPage(
            icon: "map.fill",
            title: "Offline Maps",
            description: "Download contour maps for navigation even without internet connection"
        ),
        OnboardingPage(
            icon: "person.fill",
            title: "One Device, One ID",
            description: "Your unique identity is generated securely and stored in the Secure Enclave"
        )
    ]

    var body: some View {
        ZStack {
            // Dark background
            Color.nightDark
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding()
                }

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }

                    // Username setup page
                    UsernameSetupView(username: $username)
                        .tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<(pages.count + 1), id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.fireflyYellow : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.vertical, 20)

                // Next/Get Started button
                Button(action: {
                    if currentPage < pages.count {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                }) {
                    Text(currentPage < pages.count ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.fireflyYellow, Color.fireflyOrange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }

    private func completeOnboarding() {
        // Set username if provided
        if !username.isEmpty {
            IdentityManager.shared.validateAndSetUsername(username)
        }
        // Mark onboarding complete
        UserDefaults.standard.set(true, forKey: "onboarding.completed")
        onComplete()
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon with firefly glow effect
            ZStack {
                Circle()
                    .fill(Color.fireflyYellow.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.fireflyYellow, Color.fireflyOrange],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
            }

            // Title
            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            // Description
            Text(page.description)
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Username Setup View

struct UsernameSetupView: View {
    @Binding var username: String

    // P2-FIX: Firefly decoration particles for last onboarding page
    @State private var fireflies: [FireflyParticle] = []

    var body: some View {
        ZStack {
            // Firefly particles background
            ForEach(fireflies) { firefly in
                Circle()
                    .fill(Color.fireflyYellow)
                    .frame(width: firefly.size, height: firefly.size)
                    .blur(radius: firefly.blur)
                    .opacity(firefly.opacity)
                    .position(firefly.position)
                    .animation(
                        Animation.easeInOut(duration: firefly.duration)
                            .repeatForever(autoreverses: true)
                            .delay(firefly.delay),
                        value: firefly.id
                    )
            }

            VStack(spacing: 24) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.fireflyYellow.opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.fireflyYellow)
                }

                // Title
                Text("Choose Your Name")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                // Description
                Text("Pick a unique username for mesh networking\n(2-16 characters)")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                // Username input
                TextField("Username", text: $username)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Text("Leave empty for default name")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))

                Spacer()
            }
        }
        .onAppear {
            generateFireflies()
        }
    }

    private func generateFireflies() {
        fireflies = (0..<12).map { _ in
            FireflyParticle(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 50...300),
                    y: CGFloat.random(in: 100...600)
                ),
                size: CGFloat.random(in: 4...10),
                blur: CGFloat.random(in: 1...3),
                opacity: Double.random(in: 0.3...0.8),
                duration: Double.random(in: 2...4),
                delay: Double.random(in: 0...2)
            )
        }
    }
}

struct FireflyParticle: Identifiable {
    let id: UUID
    let position: CGPoint
    let size: CGFloat
    let blur: CGFloat
    let opacity: Double
    let duration: Double
    let delay: Double
}

// MARK: - Preview

#Preview {
    OnboardingView {
        print("Onboarding complete")
    }
}

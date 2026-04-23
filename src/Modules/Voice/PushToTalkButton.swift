import UIKit

@MainActor
protocol PushToTalkButtonDelegate: AnyObject {
    func pushToTalkButtonDidBegin(_ button: PushToTalkButton)
    func pushToTalkButtonDidEnd(_ button: PushToTalkButton)
    func pushToTalkButton(_ button: PushToTalkButton, didUpdateLevel level: Float)
}

@MainActor
final class PushToTalkButton: UIView {

    weak var delegate: PushToTalkButtonDelegate?

    var isEnabled: Bool = true {
        didSet {
            updateAppearance()
        }
    }

    var activeColor: UIColor = UIColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 1.0)
    var idleColor: UIColor = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    var speakingColor: UIColor = UIColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 1.0)

    private let iconImageView = UIImageView()
    private let levelIndicator = UIView()
    private let glowLayer = CAGradientLayer()

    private var feedbackGenerator: UIImpactFeedbackGenerator?
    private var longPressGesture: UILongPressGestureRecognizer!

    private(set) var isPressed: Bool = false
    private(set) var isSpeaking: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = idleColor
        layer.cornerRadius = 40
        clipsToBounds = false

        setupIconImageView()
        setupLevelIndicator()
        setupGlowLayer()
        setupGesture()
        setupFeedbackGenerator()
    }

    private func setupIconImageView() {
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white

        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        iconImageView.image = UIImage(systemName: "mic.fill", withConfiguration: config)

        addSubview(iconImageView)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func setupLevelIndicator() {
        levelIndicator.translatesAutoresizingMaskIntoConstraints = false
        levelIndicator.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        levelIndicator.layer.cornerRadius = 35
        levelIndicator.alpha = 0

        addSubview(levelIndicator)

        NSLayoutConstraint.activate([
            levelIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            levelIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            levelIndicator.widthAnchor.constraint(equalToConstant: 70),
            levelIndicator.heightAnchor.constraint(equalToConstant: 70)
        ])
    }

    private func setupGlowLayer() {
        glowLayer.type = .radial
        glowLayer.colors = [
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.clear.cgColor
        ]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        glowLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        glowLayer.position = CGPoint(x: 40, y: 40)
        glowLayer.opacity = 0

        layer.insertSublayer(glowLayer, at: 0)
    }

    private func setupGesture() {
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.15
        longPressGesture.allowableMovement = 50

        addGestureRecognizer(longPressGesture)
    }

    private func setupFeedbackGenerator() {
        feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator?.prepare()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard isEnabled else { return }

        switch gesture.state {
        case .began:
            beginPress()
        case .ended, .cancelled, .failed:
            endPress()
        default:
            break
        }
    }

    private func beginPress() {
        guard !isPressed else { return }

        isPressed = true
        isSpeaking = true

        feedbackGenerator?.impactOccurred()

        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
            self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            self.backgroundColor = self.activeColor
            self.iconImageView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }

        animateGlow(visible: true)
        showLevelIndicator()

        delegate?.pushToTalkButtonDidBegin(self)
    }

    private func endPress() {
        guard isPressed else { return }

        isPressed = false
        isSpeaking = false

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
            self.transform = .identity
            self.backgroundColor = self.idleColor
            self.iconImageView.transform = .identity
        }

        animateGlow(visible: false)
        hideLevelIndicator()

        delegate?.pushToTalkButtonDidEnd(self)
    }

    private func animateGlow(visible: Bool) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = glowLayer.opacity
        animation.toValue = visible ? 0.6 : 0.0
        animation.duration = 0.2
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        glowLayer.add(animation, forKey: "glowOpacity")

        if visible {
            glowLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        }
    }

    private func showLevelIndicator() {
        UIView.animate(withDuration: 0.2) {
            self.levelIndicator.alpha = 1.0
        }
    }

    private func hideLevelIndicator() {
        UIView.animate(withDuration: 0.2) {
            self.levelIndicator.alpha = 0
            self.levelIndicator.transform = .identity
        }
    }

    // MARK: - Public Methods

    func updateAudioLevel(_ level: Float) {
        guard isSpeaking else { return }

        let scale = 1.0 + CGFloat(level) * 0.3
        let normalizedLevel = min(1.0, max(0.0, level))

        levelIndicator.transform = CGAffineTransform(scaleX: scale, y: scale)
        levelIndicator.backgroundColor = speakingColor.withAlphaComponent(0.3 + CGFloat(normalizedLevel) * 0.4)

        delegate?.pushToTalkButton(self, didUpdateLevel: level)
    }

    func setIcon(_ systemName: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        iconImageView.image = UIImage(systemName: systemName, withConfiguration: config)
    }

    func setIdleState() {
        isPressed = false
        isSpeaking = false
        backgroundColor = idleColor
        transform = .identity
        iconImageView.transform = .identity
        levelIndicator.alpha = 0
        glowLayer.opacity = 0
    }

    private func updateAppearance() {
        alpha = isEnabled ? 1.0 : 0.5
        longPressGesture.isEnabled = isEnabled
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = bounds.width / 2

        glowLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 80, height: 80)
    }
}

// MARK: - Convenience Initializers

extension PushToTalkButton {
    convenience init(icon: String) {
        self.init(frame: .zero)
        setIcon(icon)
    }

    convenience init(icon: String, activeColor: UIColor, idleColor: UIColor) {
        self.init(frame: .zero)
        setIcon(icon)
        self.activeColor = activeColor
        self.idleColor = idleColor
        backgroundColor = idleColor
    }
}
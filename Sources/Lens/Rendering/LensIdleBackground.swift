import AppKit

/// No screenshot is retained here. The system supplies the frosted glass material.
@MainActor final class LensIdleBackground: NSView {
    let glass = NSGlassEffectView()
    private let solid = NSView()
    private let message = NSTextField(wrappingLabelWithString: L10n.text("Place Lens over the text you want to read"))
    private var accessibilityObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass.style = .regular
        glass.cornerRadius = 18
        glass.tintColor = .windowBackgroundColor.withAlphaComponent(0.8)
        solid.wantsLayer = true
        addSubview(solid); addSubview(glass)
        message.alignment = .center
        message.font = .systemFont(ofSize: 19, weight: .semibold)
        message.textColor = .labelColor
        let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
        let icon = NSImageView(image: appIcon ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: nil) ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        let caption = NSTextField(wrappingLabelWithString: L10n.text("Choose languages and turn on translation\nto see the screen underneath."))
        caption.font = .systemFont(ofSize: 13)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        let content = NSStackView(views: [icon, message, caption])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 10
        content.setCustomSpacing(18, after: icon)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
            message.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor),
            caption.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor)
        ])
        updateAccessibility()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateAccessibility() } }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    isolated deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
    func updateAccessibility(reduceTransparency: Bool? = nil) {
        let solidBackground = reduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        glass.isHidden = solidBackground
        solid.isHidden = !solidBackground
        solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAccessibility()
    }
    override func layout() {
        super.layout()
        glass.frame = bounds; solid.frame = bounds
    }
}

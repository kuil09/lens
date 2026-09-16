import AppKit

/// Disjoint WindowServer input regions. Only the body ignores mouse events;
/// no hit-test trick, global event tap, forwarding, or event reinjection is used.
@MainActor final class LensBodyPanel: NSPanel {
    var allowsTextInteraction = true
    override var canBecomeKey: Bool { allowsTextInteraction }
    override var canBecomeMain: Bool { false }
}

@MainActor final class LensPanel: NSPanel, NSWindowDelegate {
    var interactionSuspended = false
    private(set) var bodyPanel: LensBodyPanel?
    private(set) var resizePanels: [LensResizePanel] = []
    private(set) var edgeResizing = false
    private(set) var synchronizingBody = false
    var onBodyArrangement: ((Bool) -> Void)?
    var onMinimize: (() -> Void)?
    private var bodyHeight: CGFloat = 500
    private var unzoomedFrame: CGRect?
    override var canBecomeKey: Bool { !interactionSuspended }
    override var canBecomeMain: Bool { false }
    var pairFrame: CGRect { bodyPanel.map { frame.union($0.frame) } ?? frame }

    convenience init(lensRect: CGRect) {
        self.init(contentRect: lensRect, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    }
    func installBody(surface: NSView, size: CGSize) {
        let origin = frame.origin
        bodyHeight = size.height
        contentView = NSView()
        setContentSize(CGSize(width: size.width, height: 0))
        contentMinSize = CGSize(width: 320, height: 0)
        contentMaxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: 0)
        setFrameOrigin(CGPoint(x: origin.x, y: origin.y + bodyHeight))
        let body = LensBodyPanel(contentRect: .zero, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        body.isReleasedWhenClosed = false; body.hidesOnDeactivate = false
        body.isFloatingPanel = true; body.isOpaque = false; body.backgroundColor = .clear
        body.hasShadow = false; body.level = level
        body.collectionBehavior = collectionBehavior
        body.isExcludedFromWindowsMenu = true; body.tabbingMode = .disallowed
        body.contentMinSize = CGSize(width: 320, height: 240)
        body.contentView = surface; body.delegate = self
        bodyPanel = body
        resizePanels = LensResizeSide.allCases.map { LensResizePanel(side: $0, owner: self) }
        synchronizeBody()
    }
    func setBodyClickThrough(_ enabled: Bool) {
        ignoresMouseEvents = false
        bodyPanel?.ignoresMouseEvents = enabled
        bodyPanel?.allowsTextInteraction = !enabled
        (bodyPanel?.contentView as? LensSurface)?.overlay.interactionEnabled = !enabled
    }
    func synchronizeBody() {
        guard let bodyPanel, !synchronizingBody else { return }
        synchronizingBody = true
        bodyPanel.setFrame(CGRect(x: frame.minX, y: frame.minY - bodyHeight,
            width: frame.width, height: bodyHeight), display: true)
        bodyPanel.level = level
        synchronizingBody = false
        synchronizeEdges()
    }
    private func synchronizeEdges() {
        for panel in resizePanels {
            panel.setFrame(LensResizeGeometry.frame(side: panel.side, pair: pairFrame), display: true)
            panel.level = level; panel.collectionBehavior = collectionBehavior
            if let view = panel.contentView { panel.invalidateCursorRects(for: view); view.needsDisplay = true }
        }
    }
    func beginEdgeResize() {
        guard !interactionSuspended else { return }
        edgeResizing = true
        (bodyPanel?.contentView as? LensSurface)?.overlay.dismissPopover()
        onBodyArrangement?(false)
    }
    func resizePair(to rect: CGRect) {
        guard !interactionSuspended else { return }
        synchronizingBody = true
        bodyHeight = rect.height - frame.height
        super.setFrame(CGRect(x: rect.minX, y: rect.maxY - frame.height, width: rect.width, height: frame.height), display: true)
        synchronizingBody = false
        synchronizeBody()
    }
    func endEdgeResize() {
        guard edgeResizing else { return }
        edgeResizing = false
        if isVisible && !interactionSuspended { onBodyArrangement?(true) }
    }
    private func hideAuxiliaries(_ sender: Any?) {
        edgeResizing = false
        (bodyPanel?.contentView as? LensSurface)?.overlay.dismissPopover()
        resizePanels.forEach { $0.orderOut(sender) }
        bodyPanel?.orderOut(sender)
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        synchronizeBody()
    }
    override var level: NSWindow.Level {
        didSet { bodyPanel?.level = level; resizePanels.forEach { $0.level = level } }
    }
    override func orderFrontRegardless() {
        guard !interactionSuspended else { return }
        if isMiniaturized { super.deminiaturize(nil) }
        super.orderFrontRegardless()
        guard let bodyPanel else { return }
        synchronizeBody()
        if bodyPanel.parent !== self { addChildWindow(bodyPanel, ordered: .below) }
        bodyPanel.orderFrontRegardless()
        // Keep chrome as the frontmost accessible control window, not the
        // non-key body. The rectangles are disjoint so no content is occluded.
        super.orderFrontRegardless()
        for panel in resizePanels {
            if panel.parent !== self { addChildWindow(panel, ordered: .above) }
            panel.orderFrontRegardless()
        }
    }
    override func miniaturize(_ sender: Any?) {
        onMinimize?()
        hideAuxiliaries(sender)
        super.miniaturize(sender)
    }
    override func deminiaturize(_ sender: Any?) {
        super.deminiaturize(sender)
        if !interactionSuspended { orderFrontRegardless() }
    }
    override func orderOut(_ sender: Any?) {
        hideAuxiliaries(sender)
        super.orderOut(sender)
    }
    override func close() {
        hideAuxiliaries(nil)
        super.close()
    }
    func clampPair(to area: CGRect) {
        let pair = LensGeometry.clamped(pairFrame, to: area.insetBy(dx: LensResizeGeometry.thickness, dy: LensResizeGeometry.thickness))
        bodyHeight = max(1, pair.height - frame.height)
        setFrame(CGRect(x: pair.minX, y: pair.maxY - frame.height, width: pair.width, height: frame.height), display: true)
    }
    override func zoom(_ sender: Any?) {
        guard let screen else { return }
        onBodyArrangement?(false)
        let target: CGRect
        if let previous = unzoomedFrame { target = previous; unzoomedFrame = nil }
        else { unzoomedFrame = pairFrame; target = screen.visibleFrame.insetBy(dx: 12, dy: 12) }
        bodyHeight = max(240, target.height - frame.height)
        setFrame(CGRect(x: target.minX, y: target.maxY - frame.height, width: target.width, height: frame.height), display: true)
        onBodyArrangement?(true)
    }
    func windowWillStartLiveResize(_ notification: Notification) { onBodyArrangement?(false) }
    func windowDidResize(_ notification: Notification) {
        guard let bodyPanel, !synchronizingBody else { return }
        synchronizingBody = true
        bodyHeight = bodyPanel.frame.height
        super.setFrame(CGRect(x: bodyPanel.frame.minX, y: bodyPanel.frame.maxY,
            width: bodyPanel.frame.width, height: frame.height), display: true)
        synchronizingBody = false
        synchronizeEdges()
    }
    func windowDidEndLiveResize(_ notification: Notification) { onBodyArrangement?(true) }
}

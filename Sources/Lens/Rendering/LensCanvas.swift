import AppKit
import MetalKit
import CoreImage
import SwiftUI
import Combine

@MainActor
final class LensCanvas: MTKView, MTKViewDelegate {
    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue
    private var image: CIImage?
    var showsCapturedImage = true { didSet { draw() } }
    var onPresented: ((Double) -> Void)?
    private var capturedAt: Double = 0

    init() {
        let gpu = MTLCreateSystemDefaultDevice()!
        commandQueue = gpu.makeCommandQueue()!
        ciContext = CIContext(mtlDevice: gpu, options: [.cacheIntermediates: false])
        super.init(frame: .zero, device: gpu)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        wantsLayer = true
        layer?.isOpaque = false
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }

    func present(_ frame: CapturedFrame) {
        image = CIImage(cvPixelBuffer: frame.buffer)
        capturedAt = frame.capturedAt
        draw()
    }
    func clear() { image = nil; draw() }
    func snapshotImage() -> CGImage? {
        guard let image else { return nil }
        return ciContext.createCGImage(image, from: image.extent)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let command = commandQueue.makeCommandBuffer() else { return }
        let target = CGRect(origin: .zero, size: drawableSize)
        let output: CIImage
        if showsCapturedImage, let image {
            output = image.transformed(by: CGAffineTransform(scaleX: target.width / image.extent.width, y: target.height / image.extent.height))
        } else { output = CIImage(color: .clear).cropped(to: target) }
        ciContext.render(output, to: drawable.texture, commandBuffer: command, bounds: target,
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        command.present(drawable)
        command.commit()
        if capturedAt > 0 { onPresented?(max(0, ProcessInfo.processInfo.systemUptime - capturedAt)) }
    }
}

struct DisplayTranslation: Identifiable, Equatable {
    let block: TextBlock
    let text: String
    let background: NSColor
    var id: UUID { block.id }
}

/// Never clip translated glyphs with a pixel mask. Source-line invalidation
/// hides the entire corresponding translation and its source-cover rectangle.
struct TranslationDisplayMask {
    var hiddenIDs: Set<UUID> = []
    func applying(to reference: [DisplayTranslation]) -> [DisplayTranslation] {
        reference.filter { !hiddenIDs.contains($0.id) }
    }
}

@MainActor
final class TranslationOverlay: NSView, NSPopoverDelegate {
    var translations: [DisplayTranslation] = [] { didSet { if translations != oldValue { rebuild() } } }
    var maskOpacity: CGFloat = 1 {
        didSet { if maskOpacity != oldValue { finishTransitions(); needsDisplay = true } }
    }
    // Snapshot renderers deliberately keep this false and draw fully completed output.
    var usesLiveTransitions = false {
        didSet {
            guard usesLiveTransitions != oldValue else { return }
            motionObserver = nil
            if usesLiveTransitions {
                motionObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in MainActor.assumeIsolated { self?.finishTransitions() } }
            }
            rebuildGlyphs(); needsDisplay = true
        }
    }
    var transitionClock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var revealPolicy = TranslationRevealPolicy()
    private(set) var glyphViews: [UUID: TranslationGlyphView] = [:]
    private var motionObserver: AnyCancellable?
    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isHidden: Bool {
        didSet { if isHidden { resetTransitions() } }
    }
    var interactionEnabled = false {
        didSet {
            guard interactionEnabled != oldValue else { return }
            if !interactionEnabled { dismissPopover() }
            rebuildButtons()
        }
    }
    private(set) var layouts: [TranslationLayout] = []
    private(set) var layoutBuildCount = 0
    private var layoutSize = CGSize.zero
    private(set) var presentedID: UUID?
    private var presentedText: String?
    private var presentedBlock: TextBlock?
    private var popover: NSPopover?
    private var buttons: [UUID: TranslationOverflowButton] = [:]
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactionEnabled, !isHidden else { return nil }
        let local = convert(point, from: superview)
        return subviews.reversed().first { $0 is TranslationOverflowButton && !$0.isHidden && $0.frame.contains(local) }
    }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        if changed { dismissPopover(); resetTransitions() }
        super.setFrameSize(newSize)
        if changed { rebuild() }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { dismissPopover(); resetTransitions() }
        super.viewWillMove(toWindow: newWindow)
    }
    private func rebuild() {
        if let id = presentedID, !translations.contains(where: { $0.id == id && $0.text == presentedText && $0.block == presentedBlock }) {
            dismissPopover()
        }
        let geometryChanged = layoutSize != bounds.size
        let allowReveal = layoutSize == .zero || !geometryChanged
        let reusable = !geometryChanged ? Dictionary(layouts.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first }) : [:]
        layouts = translations.compactMap { item in
            if let cached = reusable[item.id], cached.item == item { return cached }
            layoutBuildCount += 1
            return TranslationLayout(item: item, size: bounds.size)
        }
        layoutSize = bounds.size
        rebuildGlyphs(allowAnimation: allowReveal); rebuildButtons(); needsDisplay = true
    }
    func finishTransitions() { glyphViews.values.forEach { $0.finishReveal() } }
    func resetTransitions() { finishTransitions(); revealPolicy.reset() }
    private func removeGlyph(_ id: UUID) {
        let glyph = glyphViews.removeValue(forKey: id)
        glyph?.finishReveal(); glyph?.removeFromSuperview()
    }
    private func rebuildGlyphs(allowAnimation: Bool = true) {
        let visible = usesLiveTransitions ? layouts : []
        let ids = Set(visible.map { $0.item.id })
        for id in Array(glyphViews.keys) where !ids.contains(id) {
            removeGlyph(id)
        }
        let now = transitionClock()
        let allowed = allowAnimation && window?.isVisible == true && !isHiddenOrHasHiddenAncestor && !reduceMotion() && maskOpacity >= 1
        // Decide all blocks against the previous update so neighboring new paragraphs
        // do not suppress each other's first reveal.
        let previousPolicy = revealPolicy
        for layout in visible {
            let id = layout.item.id
            if let existing = glyphViews[id], existing.layout.item == layout.item, existing.frame == layout.box { continue }
            removeGlyph(id)
            var policy = previousPolicy
            let duration = policy.duration(for: layout.item.block.bounds, at: now, allowed: allowed)
            _ = revealPolicy.duration(for: layout.item.block.bounds, at: now, allowed: allowed)
            let glyph = TranslationGlyphView(layout: layout)
            addSubview(glyph, positioned: .below, relativeTo: subviews.first)
            glyphViews[id] = glyph
            glyph.reveal(duration: duration)
        }
    }
    private func rebuildButtons() {
        let overflow = interactionEnabled ? layouts.filter(\.isTruncated) : []
        let ids = Set(overflow.map { $0.item.id })
        for id in Array(buttons.keys) where !ids.contains(id) { buttons.removeValue(forKey: id)?.removeFromSuperview() }
        for layout in overflow {
            let id = layout.item.id
            let button = buttons[id] ?? {
                let button = TranslationOverflowButton()
                button.activate = { [weak self] in self?.showPopover(for: id) }
                addSubview(button); buttons[id] = button
                return button
            }()
            button.frame = layout.box
            button.setAccessibilityValue(layout.item.text)
        }
    }
    func showPopover(for id: UUID) {
        guard interactionEnabled, !isHidden, window?.isVisible == true,
              let layout = layouts.first(where: { $0.item.id == id && $0.isTruncated }) else { return }
        dismissPopover()
        let popup = NSPopover()
        popup.behavior = .transient; popup.animates = false; popup.delegate = self
        let screen = window?.screen?.visibleFrame.size ?? CGSize(width: 800, height: 600)
        popup.contentSize = CGSize(width: min(380, screen.width - 40), height: min(300, screen.height - 80))
        popup.contentViewController = NSHostingController(rootView: TruncatedTranslationView(text: layout.item.text))
        presentedID = id; presentedText = layout.item.text; presentedBlock = layout.item.block
        popover = popup
        popup.show(relativeTo: layout.box, of: self, preferredEdge: .maxX)
    }
    func focusFirstOverflow() {
        guard interactionEnabled, let layout = layouts.first(where: \.isTruncated),
              let button = buttons[layout.item.id] else { return }
        window?.makeKey(); window?.makeFirstResponder(button)
    }
    func dismissPopover() {
        popover?.close(); popover = nil; presentedID = nil; presentedText = nil; presentedBlock = nil
    }
    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        popover = nil; presentedID = nil; presentedText = nil; presentedBlock = nil
    }
    override func draw(_ dirtyRect: NSRect) {
        for layout in layouts {
            if usesLiveTransitions { layout.drawCover(opacity: maskOpacity) }
            else { layout.draw(opacity: maskOpacity) }
        }
    }
}

@MainActor
final class LensBorder: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 4, bounds.height > 4 else { return }
        // Two contrasting strokes keep the boundary visible on light and dark content.
        for (inset, color) in [(CGFloat(0.5), NSColor.black.withAlphaComponent(0.65)),
                               (CGFloat(1.5), NSColor.white.withAlphaComponent(0.85))] {
            color.setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                                       xRadius: 18 - inset, yRadius: 18 - inset)
            outline.lineWidth = 1
            outline.stroke()
        }
    }
}

@MainActor
final class LensSurface: NSView {
    let canvas = LensCanvas()
    let overlay = TranslationOverlay()
    let border = LensBorder()
    let idleBackground = LensIdleBackground(frame: .zero)
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        overlay.usesLiveTransitions = true
        addSubview(canvas); addSubview(overlay); addSubview(idleBackground); addSubview(border)
        setTranslationActive(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        canvas.frame = bounds; overlay.frame = bounds; border.frame = bounds; idleBackground.frame = bounds
        border.needsDisplay = true
    }
    func setTranslationActive(_ active: Bool, arranging: Bool = false) {
        if !active { overlay.dismissPopover() }
        // The canvas still receives frames for OCR/export, but never reproduces them on screen.
        canvas.showsCapturedImage = false
        canvas.isHidden = !active
        overlay.isHidden = !active
        idleBackground.isHidden = active || arranging
    }
}

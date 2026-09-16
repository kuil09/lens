import AppKit
import QuartzCore

/// Bounded spatial history survives replacement IDs, but never stores source text.
struct TranslationRevealPolicy {
    static let duration = 0.14
    static let cooldown = 1.0
    private var appeared = Array(repeating: -Double.infinity, count: RegionalBackoff.columns * RegionalBackoff.rows)

    mutating func reset() { appeared = Array(repeating: -.infinity, count: appeared.count) }
    mutating func duration(for bounds: CGRect, at now: Double, allowed: Bool) -> Double {
        guard !bounds.isNull, !bounds.isInfinite, bounds.minX.isFinite, bounds.maxX.isFinite,
              bounds.minY.isFinite, bounds.maxY.isFinite else { return 0 }
        let x0 = Int(max(0, min(7, floor(bounds.minX * 8))))
        let x1 = Int(max(0, min(7, floor(bounds.maxX * 8))))
        let y0 = Int(max(0, min(4, floor(bounds.minY * 5))))
        let y1 = Int(max(0, min(4, floor(bounds.maxY * 5))))
        let cells = (y0...y1).flatMap { y in (x0...x1).map { y * 8 + $0 } }
        let repeated = cells.contains { now - appeared[$0] < Self.cooldown }
        for cell in cells { appeared[cell] = now }
        return allowed && !repeated ? Self.duration : 0
    }
}

/// Only glyph opacity is animated. The parent draws the source cover immediately.
@MainActor final class TranslationGlyphView: NSView {
    let layout: TranslationLayout
    init(layout: TranslationLayout) {
        self.layout = layout
        super.init(frame: layout.box)
        wantsLayer = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: -layout.box.minX, yBy: -layout.box.minY)
        transform.concat()
        layout.drawText()
        NSGraphicsContext.restoreGraphicsState()
    }
    func reveal(duration: Double) {
        layer?.removeAnimation(forKey: "translationReveal")
        guard duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0; animation.toValue = 1
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        layer?.add(animation, forKey: "translationReveal")
    }
    func finishReveal() { layer?.removeAnimation(forKey: "translationReveal") }
}

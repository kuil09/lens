import AppKit

enum LensResizeSide: CaseIterable { case left, right, top, bottom }

struct LensResizeDirection: OptionSet {
    let rawValue: Int
    static let left = Self(rawValue: 1), right = Self(rawValue: 2)
    static let top = Self(rawValue: 4), bottom = Self(rawValue: 8)
}

enum LensResizeGeometry {
    static let thickness: CGFloat = 8
    static let cornerLength: CGFloat = 20
    static func frame(side: LensResizeSide, pair: CGRect) -> CGRect {
        let t = thickness
        switch side {
        case .left: return CGRect(x: pair.minX - t, y: pair.minY - t, width: t, height: pair.height + t * 2)
        case .right: return CGRect(x: pair.maxX, y: pair.minY - t, width: t, height: pair.height + t * 2)
        case .top: return CGRect(x: pair.minX, y: pair.maxY, width: pair.width, height: t)
        case .bottom: return CGRect(x: pair.minX, y: pair.minY - t, width: pair.width, height: t)
        }
    }
    static func direction(side: LensResizeSide, point: CGPoint, pair: CGRect) -> LensResizeDirection {
        var result: LensResizeDirection
        switch side {
        case .left: result = .left
        case .right: result = .right
        case .top: result = .top
        case .bottom: result = .bottom
        }
        if side == .left || side == .right {
            if point.y >= pair.maxY - cornerLength { result.insert(.top) }
            if point.y <= pair.minY + cornerLength { result.insert(.bottom) }
        } else {
            if point.x <= pair.minX + cornerLength { result.insert(.left) }
            if point.x >= pair.maxX - cornerLength { result.insert(.right) }
        }
        return result
    }
    static func resized(_ initial: CGRect, delta: CGPoint, direction: LensResizeDirection, minimum: CGSize, screen: CGRect) -> CGRect {
        let area = screen.insetBy(dx: thickness, dy: thickness)
        var x0 = initial.minX, x1 = initial.maxX, y0 = initial.minY, y1 = initial.maxY
        if direction.contains(.left) { x0 = min(x1 - minimum.width, max(area.minX, x0 + delta.x)) }
        if direction.contains(.right) { x1 = max(x0 + minimum.width, min(area.maxX, x1 + delta.x)) }
        if direction.contains(.bottom) { y0 = min(y1 - minimum.height, max(area.minY, y0 + delta.y)) }
        if direction.contains(.top) { y1 = max(y0 + minimum.height, min(area.maxY, y1 + delta.y)) }
        return LensGeometry.clamped(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), to: area)
    }
}

/// A continuous rounded contour shared by all four disjoint input strips.
/// The entire stroke stays outside the pair, including the curved corners.
@MainActor enum LensResizeChrome {
    static let outset: CGFloat = 5.5
    static let radius: CGFloat = 12
    static let reach: CGFloat = 34
    static let outlineWidth: CGFloat = 4.5

    static func path(around pair: CGRect) -> NSBezierPath {
        let rect = pair.insetBy(dx: -outset, dy: -outset)
        let path = NSBezierPath()
        let tangent = radius * (1 - 0.5522847498307936)
        for (x, y, sx, sy) in [
            (rect.minX, rect.minY, CGFloat(1), CGFloat(1)),
            (rect.maxX, rect.minY, CGFloat(-1), CGFloat(1)),
            (rect.minX, rect.maxY, CGFloat(1), CGFloat(-1)),
            (rect.maxX, rect.maxY, CGFloat(-1), CGFloat(-1))
        ] {
            func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + sx * dx, y: y + sy * dy) }
            path.move(to: point(reach, 0))
            path.line(to: point(radius, 0))
            path.curve(to: point(0, radius), controlPoint1: point(tangent, 0), controlPoint2: point(0, tangent))
            path.line(to: point(0, reach))
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    static func draw(around pair: CGRect) {
        let contour = path(around: pair)
        NSColor(white: 0.08, alpha: 0.92).setStroke()
        contour.lineWidth = outlineWidth; contour.stroke()
        NSColor(white: 1, alpha: 1).setStroke()
        contour.lineWidth = 2.5; contour.stroke()
    }
}

/// Four narrow WindowServer regions outside the captured body. Never an input-catching full-screen view.
@MainActor final class LensResizePanel: NSPanel {
    let side: LensResizeSide
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init(side: LensResizeSide, owner: LensPanel) {
        self.side = side
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; hidesOnDeactivate = false
        isFloatingPanel = true; isOpaque = false; backgroundColor = .clear; hasShadow = false
        isExcludedFromWindowsMenu = true; tabbingMode = .disallowed
        contentView = LensResizeHandle(side: side, owner: owner)
    }
}

@MainActor private final class LensResizeHandle: NSView {
    let side: LensResizeSide
    weak var owner: LensPanel?
    private var initial: CGRect?
    private var start = CGPoint.zero
    private var direction: LensResizeDirection = []
    init(side: LensResizeSide, owner: LensPanel) {
        self.side = side; self.owner = owner
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.handle)
        setAccessibilityLabel(L10n.text("Resize Lens"))
        toolTip = L10n.text("Resize Lens")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func mouseDown(with event: NSEvent) {
        guard let owner, !owner.interactionSuspended else { return }
        initial = owner.pairFrame
        start = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        direction = LensResizeGeometry.direction(side: side, point: start, pair: owner.pairFrame)
        owner.beginEdgeResize()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let owner, let initial, !owner.interactionSuspended, owner.isVisible else { return }
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? start
        let screen = owner.screen?.visibleFrame ?? initial.insetBy(dx: -1000, dy: -1000)
        let next = LensResizeGeometry.resized(initial, delta: CGPoint(x: point.x - start.x, y: point.y - start.y),
            direction: direction, minimum: CGSize(width: 320, height: owner.frame.height + 240), screen: screen)
        owner.resizePair(to: next)
    }
    override func mouseUp(with event: NSEvent) {
        guard initial != nil else { return }
        initial = nil; owner?.endEdgeResize()
    }
    override func resetCursorRects() {
        guard let owner, let window else { return }
        let long = side == .top || side == .bottom ? bounds.width : bounds.height
        for (offset, length) in [(CGFloat(0), CGFloat(20)), (CGFloat(20), max(0, long - 40)), (max(0, long - 20), CGFloat(20))] {
            let rect = side == .top || side == .bottom
                ? CGRect(x: offset, y: 0, width: length, height: bounds.height)
                : CGRect(x: 0, y: offset, width: bounds.width, height: length)
            let point = window.convertPoint(toScreen: convert(CGPoint(x: rect.midX, y: rect.midY), to: nil))
            let direction = LensResizeGeometry.direction(side: side, point: point, pair: owner.pairFrame)
            let position: NSCursor.FrameResizePosition
            switch direction {
            case [.top, .left]: position = .topLeft
            case [.top, .right]: position = .topRight
            case [.bottom, .left]: position = .bottomLeft
            case [.bottom, .right]: position = .bottomRight
            case .left: position = .left
            case .right: position = .right
            case .top: position = .top
            default: position = .bottom
            }
            addCursorRect(rect, cursor: .frameResize(position: position, directions: .all))
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let owner else { return }
        let pair = owner.pairFrame
        let strip = LensResizeGeometry.frame(side: side, pair: pair)
        // Clip the same curve into each strip instead of joining separately capped lines.
        LensResizeChrome.draw(around: pair.offsetBy(dx: -strip.minX, dy: -strip.minY))
    }
}

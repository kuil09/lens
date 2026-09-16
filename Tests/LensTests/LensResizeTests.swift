import AppKit
import Testing
@testable import Lens

@Test @MainActor func roundedResizeCornersStayContinuousAcrossInputStrips() throws {
    _ = NSApplication.shared
    let pair = CGRect(x: 24, y: 24, width: 400, height: 300)
    let contour = LensResizeChrome.path(around: pair)
    #expect((0..<contour.elementCount).filter {
        contour.element(at: $0, associatedPoints: nil) == .curveTo
    }.count == 4)
    #expect(contour.lineCapStyle == .round && contour.lineJoinStyle == .round)
    #expect(LensResizeChrome.outset + LensResizeChrome.outlineWidth / 2 < LensResizeGeometry.thickness)

    let lens = LensPanel(lensRect: pair)
    lens.isReleasedWhenClosed = false
    lens.installBody(surface: NSView(), size: CGSize(width: 400, height: 260))
    lens.resizePair(to: pair)
    defer { lens.close() }
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("LensDesignRenders", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    for scale in [CGFloat(1), CGFloat(2)] {
        func render(strips: Bool, dark: Bool? = nil) throws -> (CGImage, [UInt8]) {
            let width = Int(448 * scale), height = Int(348 * scale)
            let context = try #require(CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            if let dark {
                NSColor(white: dark ? 0.09 : 0.94, alpha: 1).setFill()
                NSBezierPath(rect: CGRect(x: 0, y: 0, width: 448, height: 348)).fill()
                NSColor(white: dark ? 0.18 : 1, alpha: 1).setFill()
                NSBezierPath(roundedRect: pair, xRadius: 18, yRadius: 18).fill()
                ("Lens" as NSString).draw(at: CGPoint(x: 50, y: 283), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: dark ? NSColor.white : NSColor.black])
            }
            if strips {
                for panel in lens.resizePanels {
                    let view = try #require(panel.contentView)
                    context.saveGState()
                    context.clip(to: panel.frame)
                    context.translateBy(x: panel.frame.minX, y: panel.frame.minY)
                    view.draw(view.bounds)
                    context.restoreGState()
                }
            } else { LensResizeChrome.draw(around: pair) }
            let data = try #require(context.data)
            return (try #require(context.makeImage()), Array(UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4)))
        }
        let (_, continuous) = try render(strips: false)
        let (_, split) = try render(strips: true)
        // Rendering into four separate native views must not cut the curve or its stroke.
        #expect(zip(continuous, split).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        for dark in [false, true] {
            let (image, _) = try render(strips: true, dark: dark)
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("resize-corners-\(dark ? "dark" : "light")-\(Int(scale))x.png"))
        }
    }
}

@Test func resizeRingDoesNotCatchBodyOrHeaderAndHasDirectionalCorners() {
    let pair = CGRect(x: -600, y: 100, width: 500, height: 400)
    let panels = LensResizeSide.allCases.map { LensResizeGeometry.frame(side: $0, pair: pair) }
    for (index, frame) in panels.enumerated() {
        #expect(!frame.intersects(pair))
        for other in panels.dropFirst(index + 1) { #expect(!frame.intersects(other)) }
    }
    #expect(LensResizeGeometry.direction(side: .left, point: CGPoint(x: -604, y: 498), pair: pair) == [.left, .top])
    #expect(LensResizeGeometry.direction(side: .bottom, point: CGPoint(x: -104, y: 96), pair: pair) == [.right, .bottom])
    #expect(LensResizeGeometry.direction(side: .right, point: CGPoint(x: -96, y: 300), pair: pair) == .right)
}

@Test func resizeHonorsAnchorsMinimumAndDisplayBoundary() {
    let initial = CGRect(x: 100, y: 100, width: 600, height: 400)
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let minimum = CGSize(width: 320, height: 300)
    let shrink = LensResizeGeometry.resized(initial, delta: CGPoint(x: 500, y: 500), direction: [.bottom, .left], minimum: minimum, screen: screen)
    #expect(shrink.maxX == initial.maxX && shrink.maxY == initial.maxY)
    #expect(shrink.size == minimum)
    let grow = LensResizeGeometry.resized(initial, delta: CGPoint(x: 2000, y: 2000), direction: [.top, .right], minimum: minimum, screen: screen)
    #expect(grow.maxX == screen.maxX - 8 && grow.maxY == screen.maxY - 8)
}

@Test @MainActor func resizePanelsMoveHideAndSuspendWithLens() throws {
    _ = NSApplication.shared
    let lens = LensPanel(lensRect: CGRect(x: 100, y: 100, width: 600, height: 400))
    lens.isReleasedWhenClosed = false
    lens.installBody(surface: NSView(), size: CGSize(width: 600, height: 400))
    let handoff = LensSystemHandoff()
    handoff.show(window: lens); lens.setBodyClickThrough(true)
    defer { lens.close() }
    #expect(lens.resizePanels.count == 4)
    #expect(lens.resizePanels.allSatisfy { $0.isVisible && !$0.ignoresMouseEvents && !$0.canBecomeKey })
    var events: [Bool] = []
    lens.onBodyArrangement = { events.append($0) }
    lens.beginEdgeResize()
    lens.resizePair(to: CGRect(x: 150, y: 120, width: 500, height: 400))
    lens.endEdgeResize()
    #expect(events == [false, true])
    for panel in lens.resizePanels { #expect(panel.frame == LensResizeGeometry.frame(side: panel.side, pair: lens.pairFrame)) }
    #expect(lens.bodyPanel?.ignoresMouseEvents == true)
    handoff.begin(window: lens) {}
    #expect(lens.resizePanels.allSatisfy { !$0.isVisible })
    handoff.show(window: lens)
    #expect(lens.resizePanels.allSatisfy { $0.isVisible })
    lens.close()
    #expect(lens.resizePanels.allSatisfy { !$0.isVisible })
}

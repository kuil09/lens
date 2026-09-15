import AppKit
import Testing
@testable import Lens

@Test @MainActor func borderLeavesCenterTransparentAndDoesNotInterceptClicks() throws {
    let border = LensBorder(frame: CGRect(x: 0, y: 0, width: 80, height: 50))
    #expect(!border.isOpaque)
    #expect(border.hitTest(NSPoint(x: 1, y: 1)) == nil)
    #expect(border.hitTest(NSPoint(x: 40, y: 25)) == nil)
    for scale in [1, 2, 3] {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80 * scale,
            pixelsHigh: 50 * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = border.bounds.size
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The bitmap's point size already establishes the backing scale.
        border.draw(border.bounds)
        NSGraphicsContext.restoreGraphicsState()
        #expect(try #require(bitmap.colorAt(x: 40 * scale, y: 25 * scale)).alphaComponent == 0)
        for point in [(0, 25 * scale), (80 * scale - 1, 25 * scale),
                      (40 * scale, 0), (40 * scale, 50 * scale - 1)] {
            #expect(try #require(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent > 0.5)
        }
    }
}

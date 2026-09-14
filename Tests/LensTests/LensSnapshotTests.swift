import AppKit
import Testing
@testable import Lens

@Test @MainActor func snapshotKeepsCaptureResolutionAndCompositesTranslations() throws {
    for scale in [1, 2, 3] {
        let context = try #require(CGContext(data: nil, width: 80 * scale, height: 50 * scale,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 80 * scale, height: 50 * scale))
        let background = try #require(context.makeImage())
        let block = TextBlock(id: UUID(), text: "Source", bounds: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                              language: .english, confidence: 1)
        let item = DisplayTranslation(block: block, text: "", background: .white)
        for opacity: CGFloat in [0, 1] {
            let data = try #require(LensSnapshot.png(background: background, pointSize: CGSize(width: 80, height: 50),
                translations: [item], maskOpacity: opacity))
            let output = try #require(NSBitmapImageRep(data: data))
            #expect(output.pixelsWide == 80 * scale)
            #expect(output.pixelsHigh == 50 * scale)
            #expect(output.colorSpace == .sRGB)
            #expect(output.bitsPerSample == 8 && output.samplesPerPixel == 4)
            // colorAt returns calibrated RGB even for this sRGB bitmap. Inspect encoded samples directly.
            let offset = 25 * scale * output.bytesPerRow + 40 * scale * output.samplesPerPixel
            let bytes = try #require(output.bitmapData)
            #expect(bytes[offset] == 255)
            #expect(bytes[offset + 1] == UInt8(opacity * 255))
            #expect(bytes[offset + 2] == UInt8(opacity * 255))
            #expect(bytes[offset + 3] == 255)
        }
    }
}

@Test @MainActor func settingsWindowStartsClosedAndUsesStandardWindowBehavior() {
    _ = NSApplication.shared
    let window = LensSettingsWindow(autosaveName: "")
    #expect(!window.isVisible)
    #expect(window.level == .normal)
    #expect(window.styleMask.contains(.closable))
    #expect(!window.styleMask.contains(.miniaturizable))
    #expect(!window.styleMask.contains(.resizable))
    #expect(!window.styleMask.contains(.nonactivatingPanel))
    #expect(!window.isReleasedWhenClosed)
}

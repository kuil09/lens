import AppKit
import Testing
@testable import Lens

@MainActor private func overflowItem(text: String, bounds: CGRect = CGRect(x: 0.1, y: 0.4, width: 0.5, height: 0.08)) -> DisplayTranslation {
    .init(block: .init(text: "Original source text", bounds: bounds, language: .english, confidence: 1), text: text, background: .white)
}

@Test @MainActor func overflowMeasurementAndInteractiveRegionsShareLayout() throws {
    let overlay = TranslationOverlay(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let long = overflowItem(text: String(repeating: "Never delete the remaining 12 files. ", count: 12))
    let short = overflowItem(text: "Hi", bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1))
    overlay.translations = [long, short]
    #expect(overlay.layouts.map(\.isTruncated) == [true, false])
    #expect(overlay.subviews.isEmpty) // Export overlays never expose interactive affordances.
    overlay.interactionEnabled = true
    let button = try #require(overlay.subviews.first as? TranslationOverflowButton)
    #expect(overlay.subviews.count == 1)
    #expect(button.frame == overlay.layouts[0].box)
    overlay.interactionEnabled = false
    #expect(overlay.subviews.isEmpty && overlay.presentedID == nil)
    let word = overflowItem(text: String(repeating: "W", count: 200))
    #expect(TranslationLayout(item: word, size: overlay.bounds.size)?.isTruncated == true)
}

@Test @MainActor func popoverOnlyOpensForCurrentOverflowAndClosesOnInvalidationOrPassThrough() throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let overlay = TranslationOverlay(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    window.contentView = overlay
    let long = overflowItem(text: String(repeating: "A complete translation to read. ", count: 20))
    overlay.translations = [long]
    defer { overlay.dismissPopover(); window.orderOut(nil) }
    window.orderFrontRegardless()
    overlay.showPopover(for: long.id)
    #expect(overlay.presentedID == nil)
    overlay.interactionEnabled = true
    overlay.showPopover(for: long.id)
    #expect(overlay.presentedID == long.id)
    overlay.translations = [long]
    #expect(overlay.presentedID == long.id)
    overlay.translations = []
    #expect(overlay.presentedID == nil)
    overlay.translations = [long]; overlay.showPopover(for: long.id)
    overlay.interactionEnabled = false
    #expect(overlay.presentedID == nil)
    overlay.interactionEnabled = true; overlay.showPopover(for: long.id)
    overlay.setFrameSize(CGSize(width: 350, height: 300))
    #expect(overlay.presentedID == nil)
}

@Test @MainActor func sourceFilterRejectsUnknownOtherSourceAndTargetLanguage() {
    let context = RegionalTranslationPipeline.Context(source: .korean, target: .japanese, languages: [.english, .korean, .japanese])
    for language: LensLanguage? in [nil, .english, .korean, .japanese] {
        let block = TextBlock(text: "A source context", bounds: CGRect(x: 0, y: 0, width: 0.2, height: 0.1), language: language, confidence: 1)
        #expect(RegionalTranslationPipeline.accepts(block, in: context) == (language == .korean))
    }
}

@Test @MainActor func exportedTextRemainsUprightAndOverflowControlsAreNotComposited() async throws {
    let cg = try #require(CGContext(data: nil, width: 800, height: 320, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 800, height: 320))
    let item = overflowItem(text: "Please keep this document open.", bounds: CGRect(x: 0.05, y: 0.4, width: 0.85, height: 0.3))
    let background = try #require(cg.makeImage())
    let image = try #require(LensSnapshot.image(background: background, pointSize: CGSize(width: 800, height: 320), translations: [item], maskOpacity: 1))
    let result = try await OCRService().recognize(image, source: .english, languages: [.english])
    #expect(result.contains { $0.text.contains("Please keep this document open") })
    let overlay = TranslationOverlay(frame: CGRect(x: 0, y: 0, width: 800, height: 320))
    overlay.translations = [overflowItem(text: String(repeating: "Overflow text to inspect. ", count: 40))]
    #expect(overlay.layouts.first?.isTruncated == true && overlay.subviews.isEmpty)
}

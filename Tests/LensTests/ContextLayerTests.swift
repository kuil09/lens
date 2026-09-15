import AppKit
import CoreImage
import Testing
@testable import Lens

@Test @MainActor func realVisionKeepsWrappedProseTogetherBesideSmallClock() async throws {
    let cg = try #require(CGContext(data: nil, width: 1000, height: 400, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1000, height: 400))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
    for (index, text) in ["This paragraph must stay translated while the", "clock beside it keeps changing. Never delete", "the remaining files without permission."].enumerated() {
        (text as NSString).draw(at: CGPoint(x: 25, y: 310 - index * 34), withAttributes: [.font: NSFont.systemFont(ofSize: 23), .foregroundColor: NSColor.black])
    }
    ("Clock 1234" as NSString).draw(at: CGPoint(x: 700, y: 315), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    let blocks = try await OCRService().recognize(try #require(cg.makeImage()), source: .english, languages: [.english])
    let body = try #require(blocks.first { $0.text.contains("This paragraph") })
    #expect(body.sourceLines.count == 3)
    #expect(body.translationText.contains("while the clock beside"))
    #expect(body.translationText.contains("Never delete the remaining files without permission."))
    #expect(!body.translationText.contains("1234"))
}

@Test func wrappedContextPreservesShortTailsWithoutMergingControlsTablesOrColumns() throws {
    func line(_ text: String, _ y: CGFloat, width: CGFloat = 0.6, x: CGFloat = 0.05, language: LensLanguage? = nil) -> TextBlock {
        .init(text: text, bounds: CGRect(x: x, y: y, width: width, height: 0.03), language: language, confidence: 1)
    }
    for (language, first, tail, joined) in [
        (LensLanguage.english, "Do not delete any of the remaining", "12 files.", "Do not delete any of the remaining 12 files."),
        (.korean, "남아 있는 파일을 절대로 삭제하지", "마세요.", "남아 있는 파일을 절대로 삭제하지 마세요."),
        (.japanese, "残っているファイルを削除しないで", "ください。", "残っているファイルを削除しないでください。")
    ] {
        let blocks = OCRService.groupParagraphs([line(first, 0.8, language: language), line(tail, 0.76, width: 0.09, language: language)])
        let block = try #require(blocks.first)
        #expect(blocks.count == 1 && block.sourceLines.count == 2)
        #expect(block.translationText == joined)
        #expect(block.text.contains("\n"))
        #expect(block.bounds == block.sourceLines[0].bounds.union(block.sourceLines[1].bounds))
    }
    #expect(OCRService.groupParagraphs([line("Settings", 0.8), line("Continue", 0.76)]).count == 2)
    let heading = TextBlock(text: "Important guidelines for document security", bounds: CGRect(x: 0.05, y: 0.8, width: 0.6, height: 0.08), language: nil, confidence: 1)
    #expect(OCRService.groupParagraphs([heading, line("Please keep these original files safely in their current folder.", 0.75)]).count == 2)
    #expect(OCRService.groupParagraphs([line("1. Never delete these documents", 0.8), line("2. Keep the original files", 0.76)]).count == 2)
    let cells = [line("The product is available", 0.8, width: 0.3), line("12", 0.8, width: 0.1, x: 0.5),
                 line("The product is unavailable", 0.76, width: 0.3), line("13", 0.76, width: 0.1, x: 0.5)]
    #expect(OCRService.groupParagraphs(cells).count == 4)
    let columns = [line("Keep all of the original documents", 0.8, width: 0.35), line("safely.", 0.76, width: 0.1),
                   line("Never delete the remaining files", 0.8, width: 0.35, x: 0.6), line("without permission.", 0.76, width: 0.2, x: 0.6)]
    let contexts = OCRService.groupParagraphs(columns)
    #expect(contexts.count == 2 && contexts.allSatisfy { $0.sourceLines.count == 2 })
    #expect(contexts.allSatisfy { $0.bounds.width <= 0.36 })
}

@Test @MainActor func disjointPanelsKeepChromeInteractiveAndHideTogether() throws {
    _ = NSApplication.shared
    let panel = LensPanel(lensRect: CGRect(x: 100, y: 100, width: 800, height: 500))
    panel.isReleasedWhenClosed = false
    let toolbar = LensToolbar(onCapture: {}, onRecord: {})
    toolbar.attach(to: panel)
    panel.addTitlebarAccessoryViewController(LensLanguageBarController(model: LensModel(), onToggle: {}))
    let surface = NSView()
    panel.installBody(surface: surface, size: CGSize(width: 800, height: 500))
    let body = try #require(panel.bodyPanel)
    let handoff = LensSystemHandoff()
    defer { panel.orderOut(nil) }
    handoff.show(window: panel)
    #expect(body.isVisible && panel.isVisible && body.parent === panel)
    #expect(surface.window === body)
    #expect(panel.frame.intersection(body.frame).height == 0 || panel.frame.intersection(body.frame).isNull)
    #expect(abs(body.frame.maxY - panel.frame.minY) < 1)
    panel.setBodyClickThrough(true)
    #expect(body.ignoresMouseEvents && !panel.ignoresMouseEvents)
    #expect(panel.canBecomeKey && !body.canBecomeKey && !body.canBecomeMain)
    panel.setFrame(panel.frame.offsetBy(dx: 60, dy: 50), display: true)
    #expect(body.frame.minX == panel.frame.minX && body.frame.maxY == panel.frame.minY)
    var next = panel.frame; next.size.width = 600
    panel.setFrame(next, display: true)
    #expect(body.frame.width == 600)
    #expect(LensCaptureRegion.screenRect(surface: surface, window: body) == body.frame)
    handoff.begin(window: panel) {}
    #expect(!panel.isVisible && !body.isVisible && !panel.canBecomeKey)
    handoff.show(window: panel)
    #expect(body.isVisible && body.parent === panel && body.ignoresMouseEvents)
    panel.setBodyClickThrough(false)
    #expect(!body.ignoresMouseEvents)
    panel.close()
    #expect(!body.isVisible && !panel.isVisible)
}

// Foreground-sensitive: not part of unattended/parallel CI. A real input fixture
// is still needed to prove event delivery, rather than just window-number lookup.
@Test(.enabled(if: ProcessInfo.processInfo.environment["LENS_TEST_WINDOWSERVER"] == "1"))
@MainActor func windowServerHitRegionsExcludeLockedBodyButRetainHeader() async throws {
    _ = NSApplication.shared
    let behind = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 600, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
    behind.isReleasedWhenClosed = false
    behind.backgroundColor = .white
    let panel = LensPanel(lensRect: CGRect(x: 250, y: 250, width: 400, height: 300))
    panel.isReleasedWhenClosed = false; panel.level = .floating
    panel.installBody(surface: NSView(), size: CGSize(width: 400, height: 300))
    let body = try #require(panel.bodyPanel)
    defer { panel.orderOut(nil); behind.orderOut(nil) }
    NSApp.setActivationPolicy(.accessory)
    behind.makeKeyAndOrderFront(nil); NSApp.activate()
    try await Task.sleep(for: .milliseconds(200))
    let bodyPoint = CGPoint(x: body.frame.midX, y: body.frame.midY)
    let headerPoint = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
    // Establish the control window before attributing an unexpected hit to Lens.
    try #require(NSWindow.windowNumber(at: bodyPoint, belowWindowWithWindowNumber: 0) == behind.windowNumber)
    panel.orderFrontRegardless()
    try await Task.sleep(for: .milliseconds(100))
    panel.setBodyClickThrough(true)
    #expect(NSWindow.windowNumber(at: bodyPoint, belowWindowWithWindowNumber: 0) == behind.windowNumber)
    #expect(NSWindow.windowNumber(at: headerPoint, belowWindowWithWindowNumber: 0) == panel.windowNumber)
    panel.setBodyClickThrough(false)
    #expect(NSWindow.windowNumber(at: bodyPoint, belowWindowWithWindowNumber: 0) == body.windowNumber)
}

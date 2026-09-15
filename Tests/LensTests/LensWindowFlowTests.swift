import AppKit
import Testing
@testable import Lens

@Test @MainActor func pairedWindowSupportsMinimizeAndRejectsPresentationDuringHandoff() throws {
    _ = NSApplication.shared
    let panel = LensPanel(lensRect: CGRect(x: 100, y: 100, width: 400, height: 300))
    panel.isReleasedWhenClosed = false
    panel.installBody(surface: NSView(), size: CGSize(width: 400, height: 300))
    let body = try #require(panel.bodyPanel)
    let handoff = LensSystemHandoff()
    defer { panel.orderOut(nil) }
    #expect(panel.styleMask.contains(.miniaturizable))
    handoff.show(window: panel)
    var pausedBeforeMinimizing = false
    panel.onMinimize = { pausedBeforeMinimizing = true }
    panel.miniaturize(nil)
    #expect(pausedBeforeMinimizing)
    #expect(!body.isVisible)
    panel.deminiaturize(nil)
    #expect(panel.isVisible && body.isVisible && body.parent === panel)
    #expect(body.frame.maxY == panel.frame.minY)
    handoff.begin(window: panel) {}
    panel.orderFrontRegardless()
    #expect(!panel.isVisible && !body.isVisible)
    handoff.show(window: panel)
    #expect(panel.isVisible && body.isVisible && body.parent === panel)
}

@Test @MainActor func narrowWindowRetainsDisjointBodyAfterResizeAndZoom() throws {
    let panel = LensPanel(lensRect: CGRect(x: 100, y: 100, width: 800, height: 500))
    panel.isReleasedWhenClosed = false
    panel.installBody(surface: NSView(), size: CGSize(width: 800, height: 500))
    defer { panel.orderOut(nil) }
    let body = try #require(panel.bodyPanel)
    panel.setFrame(CGRect(x: 100, y: 500, width: 320, height: panel.frame.height), display: false)
    #expect(body.frame.width == panel.frame.width && body.frame.maxY == panel.frame.minY)
    panel.setBodyClickThrough(true)
    panel.zoom(nil)
    #expect(body.frame.width == panel.frame.width && body.frame.maxY == panel.frame.minY)
    #expect(body.ignoresMouseEvents && !panel.ignoresMouseEvents)
    panel.close()
    #expect(!panel.isVisible && !body.isVisible)
}

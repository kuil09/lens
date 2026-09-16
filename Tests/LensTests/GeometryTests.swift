import Testing
import Foundation
@testable import Lens

@Test func negativeDisplayAndRetinaCoordinates() {
    let display = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
    let rect = CGRect(x: -1800, y: 400, width: 800, height: 500)
    #expect(LensGeometry.captureRect(global: rect, display: display) == CGRect(x: 120, y: 380, width: 800, height: 500))
    #expect(LensGeometry.pixels(points: rect.size, scale: 1.5) == CGSize(width: 1200, height: 750))
    #expect(LensGeometry.localRect(CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1), size: rect.size) == CGRect(x: 80, y: 100, width: 400, height: 50))
}

@Test func clampOversizedWindow() {
    #expect(LensGeometry.clamped(CGRect(x: -100, y: 200, width: 900, height: 800), to: CGRect(x: 0, y: 0, width: 800, height: 600)) == CGRect(x: 0, y: 0, width: 800, height: 600))
}

@Test func captureLayoutIgnoresUnrelatedNotificationsButDetectsStreamChanges() {
    let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let region = CGRect(x: -1600, y: 200, width: 800, height: 500)
    let current = CaptureLayout(displayID: 1, displayFrame: display, globalRect: region, scale: 2)
    #expect(current == CaptureLayout(displayID: 1, displayFrame: display, globalRect: region, scale: 2))
    #expect(current != CaptureLayout(displayID: 2, displayFrame: display, globalRect: region, scale: 2))
    #expect(current != CaptureLayout(displayID: 1, displayFrame: display.offsetBy(dx: 100, dy: 0), globalRect: region, scale: 2))
    #expect(current != CaptureLayout(displayID: 1, displayFrame: display, globalRect: region.offsetBy(dx: 1, dy: 0), scale: 2))
    #expect(current != CaptureLayout(displayID: 1, displayFrame: display, globalRect: region.insetBy(dx: 1, dy: 0), scale: 2))
    #expect(current != CaptureLayout(displayID: 1, displayFrame: display, globalRect: region, scale: 1))
}

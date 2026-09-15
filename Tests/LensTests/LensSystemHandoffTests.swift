import AppKit
import Testing
@testable import Lens

@Test @MainActor func systemHandoffHidesLensAndRequiresExplicitRestoration() {
    _ = NSApplication.shared
    let panel = LensPanel(lensRect: CGRect(x: 0, y: 0, width: 320, height: 240))
    defer { panel.orderOut(nil) }
    let handoff = LensSystemHandoff()
    let model = LensModel()
    var pauses = 0
    model.begin()
    handoff.show(window: panel)
    #expect(panel.isVisible && panel.canBecomeKey)
    #expect(!panel.styleMask.contains(.nonactivatingPanel))
    handoff.begin(window: panel) { pauses += 1; model.suspend() }
    #expect(handoff.isActive && !panel.isVisible && !panel.isKeyWindow)
    #expect(!panel.canBecomeKey && panel.level == .normal)
    #expect(!model.running && !model.hasFrame)
    handoff.begin(window: panel) { pauses += 1 }
    #expect(pauses == 1)
    #expect(!panel.isVisible)
    #expect(handoff.needsReturnGuide)
    handoff.acknowledgeReturn()
    #expect(!handoff.needsReturnGuide && handoff.isActive)
    #expect(!panel.isVisible && !panel.canBecomeKey && !model.running)
    handoff.show(window: panel)
    #expect(!handoff.isActive && panel.isVisible && panel.canBecomeKey)
    #expect(panel.level == .floating)
    #expect(!model.running) // Showing the lens must not silently restart capture.
}

@Test func explicitReturnPolicyDoesNotInterruptAnOSRequest() {
    for hasWindows in [false, true] {
        #expect(LensReturnDestination.resolve(requestPending: true, handoffPending: true,
            hasVisibleWindows: hasWindows, onboardingCompleted: false) == .none)
        #expect(LensReturnDestination.resolve(requestPending: false, handoffPending: true,
            hasVisibleWindows: hasWindows, onboardingCompleted: true) == .guide)
    }
    #expect(LensReturnDestination.resolve(requestPending: false, handoffPending: false,
        hasVisibleWindows: false, onboardingCompleted: false) == .onboarding)
    #expect(LensReturnDestination.resolve(requestPending: false, handoffPending: false,
        hasVisibleWindows: false, onboardingCompleted: true) == .lens)
    #expect(LensReturnDestination.resolve(requestPending: false, handoffPending: false,
        hasVisibleWindows: true, onboardingCompleted: true) == .none)
}

@Test @MainActor func settingsHandoffDoesNotTriggerForOrdinaryApplications() {
    #expect(LensSystemHandoff.requiresHandoff(bundleIdentifier: "com.apple.systempreferences"))
    #expect(!LensSystemHandoff.requiresHandoff(bundleIdentifier: "com.apple.Safari"))
    #expect(!LensSystemHandoff.requiresHandoff(bundleIdentifier: "dev.local.lens"))
    #expect(!LensSystemHandoff.requiresHandoff(bundleIdentifier: nil))
}

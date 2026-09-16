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

@Test @MainActor func ordinaryReturnKeepsVisibleSessionAndPendingStart() {
    _ = NSApplication.shared
    let suite = "LensOrdinaryReturn.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = LensModel(defaults: defaults)
    let panel = LensPanel(lensRect: CGRect(x: 0, y: 0, width: 320, height: 240))
    defer { panel.orderOut(nil) }
    let handoff = LensSystemHandoff()
    handoff.show(window: panel)
    for running in [false, true] {
        for recording in [false, true] {
            if running { model.begin() } else { model.suspend() }
            panel.setRecordingGeometryLocked(recording)
            _ = model.startRequest.request(.checking)
            for _ in 0..<3 {
                #expect(LensReturnDestination.resolve(requestPending: false,
                    handoffPending: handoff.needsReturnGuide, hasVisibleWindows: panel.isVisible,
                    onboardingCompleted: true, permissionGranted: true) == .none)
                #expect(!handoff.isActive && !handoff.needsReturnGuide)
                #expect(panel.isVisible && panel.level == .floating)
                #expect(model.running == running && model.startRequest.pending)
                #expect(panel.recordingGeometryLocked == recording)
            }
        }
    }
}

@Test func appActivationHasNoImplicitPermissionHandoffWiring() throws {
    // Structural regression at the removed observer boundary, not a native focus test.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let main = try String(contentsOf: root.appendingPathComponent("Sources/Lens/App/Main.swift"), encoding: .utf8)
    #expect(!main.contains("NSWorkspace.didActivateApplicationNotification"))
    #expect(main.components(separatedBy: "yieldForScreenPermission()").count == 3) // one call and one declaration
    let permissionAction = try #require(main.range(of: "@objc private func openPermissionSettings()"))
    let handoffCall = try #require(main.range(of: "        yieldForScreenPermission()", range: permissionAction.upperBound..<main.endIndex))
    let nextMethod = try #require(main.range(of: "    private func yieldForScreenPermission()", range: permissionAction.upperBound..<main.endIndex))
    #expect(handoffCall.lowerBound < nextMethod.lowerBound)
}

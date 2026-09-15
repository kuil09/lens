import AppKit
import Testing
@testable import Lens

@Test func languagePairStaysSymmetricAndClearOfTranslationSwitch() {
    for windowWidth: CGFloat in [320, 400, 520, 540, 600, 800, 1200] {
        let available = windowWidth - 24 - 28 // Glass inset and content padding.
        let layout = LensLanguageBarLayout(width: available)
        let left = layout.pairCenter - layout.pairWidth / 2
        let right = layout.pairCenter + layout.pairWidth / 2
        let sourceCenter = left + layout.fieldWidth / 2
        let targetCenter = right - layout.fieldWidth / 2
        #expect(abs((layout.pairCenter - sourceCenter) - (targetCenter - layout.pairCenter)) < 0.01)
        #expect(left >= 0 && right <= available - 60)
        #expect(layout.fieldWidth >= 82)
        if available >= 480 { #expect(layout.pairCenter == available / 2) }
    }
}

@Test @MainActor func toolbarActionsFollowCaptureAndRecordingState() throws {
    _ = NSApplication.shared
    var actions: [String] = []
    let toolbar = LensToolbar(onCapture: { actions.append("capture") }, onRecord: { actions.append("record") })
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    toolbar.attach(to: window)
    let capture = try #require(toolbar.items["capture"])
    let record = try #require(toolbar.items["record"])
    #expect(!capture.isEnabled && !record.isEnabled)
    #expect(window.toolbarStyle == .unified)
    #expect(capture.isBordered)
    toolbar.update(.init(running: true, hasFrame: true))
    #expect(capture.isEnabled && record.isEnabled)
    for item in [capture, record] {
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
    }
    #expect(actions == ["capture", "record"])
    toolbar.update(.init(recording: true, choosingDestination: true))
    #expect(record.isEnabled && record.label == L10n.text("Stop Recording"))
    #expect(record.style == .prominent && record.backgroundTintColor == .systemRed)
    #expect(!capture.isEnabled)
    toolbar.update(.init(hasFrame: true, finishing: true))
    #expect(!record.isEnabled && record.label == L10n.text("Saving…"))
    #expect(record.style == .plain && record.backgroundTintColor == nil)
    toolbar.update(.init(hasFrame: true, locked: true))
    #expect(toolbar.items.values.allSatisfy { $0.isEnabled })
    #expect(toolbar.items["lock"]?.style == .prominent)
    _ = NSApp.sendAction(try #require(record.action), to: record.target, from: record)
    #expect(actions.count == 3)
    toolbar.update(.init(recording: true, locked: true))
    #expect(record.isEnabled && !capture.isEnabled)
    toolbar.update(.init(finishing: true, locked: true))
    #expect(!record.isEnabled && !capture.isEnabled)
}

@Test @MainActor func toolbarDoesNotEnterCaptureSurfaceAtAnyWindowSize() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: CGRect(x: 180, y: 130, width: 800, height: 500),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let surface = NSView()
    window.contentView = surface
    let toolbar = LensToolbar(onCapture: {}, onRecord: {})
    toolbar.attach(to: window)
    let model = LensModel()
    let languageBar = LensLanguageBarController(model: model, onToggle: {})
    window.addTitlebarAccessoryViewController(languageBar)
    for size in [CGSize(width: 800, height: 500), CGSize(width: 320, height: 240)] {
        window.setContentSize(size)
        let rect = LensCaptureRegion.screenRect(surface: surface, window: window)
        #expect(rect.size == size)
        #expect(abs(rect.minX - window.frame.minX) < 1)
        #expect(abs(rect.minY - window.frame.minY) < 1)
        let languageRect = window.convertToScreen(languageBar.view.convert(languageBar.view.bounds, to: nil))
        #expect(languageRect.minY >= rect.maxY - 1)
        #expect(window.frame.maxY - rect.maxY >= languageBar.view.bounds.height)
        #expect(languageBar.view.bounds.height >= 80)
        #expect(!surface.subviews.contains { $0 is NSButton })
    }
}

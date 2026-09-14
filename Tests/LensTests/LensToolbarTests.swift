import AppKit
import Testing
@testable import Lens

@Test @MainActor func toolbarActionsFollowCaptureAndRecordingState() throws {
    _ = NSApplication.shared
    var actions: [String] = []
    let toolbar = LensToolbar(onTranslate: { actions.append("translate") }, onCapture: { actions.append("capture") }, onRecord: { actions.append("record") })
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    toolbar.attach(to: window)
    let translate = try #require(toolbar.items["translate"])
    let capture = try #require(toolbar.items["capture"])
    let record = try #require(toolbar.items["record"])
    #expect(translate.isEnabled && !capture.isEnabled && !record.isEnabled)
    toolbar.update(.init(running: true, hasFrame: true))
    #expect(translate.label == "번역 일시정지")
    #expect(capture.isEnabled && record.isEnabled)
    for item in [translate, capture, record] {
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
    }
    #expect(actions == ["translate", "capture", "record"])
    toolbar.update(.init(recording: true, choosingDestination: true))
    #expect(record.isEnabled && record.label == "녹화 중지")
    #expect(!capture.isEnabled)
    toolbar.update(.init(hasFrame: true, finishing: true))
    #expect(!record.isEnabled && record.label == "저장 중…")
    toolbar.update(.init(hasFrame: true, locked: true))
    #expect(toolbar.items.values.allSatisfy { !$0.isEnabled })
    #expect(record.toolTip?.contains("메뉴 막대") == true)
    _ = NSApp.sendAction(try #require(record.action), to: record.target, from: record)
    #expect(actions.count == 3)
}

@Test @MainActor func toolbarDoesNotEnterCaptureSurfaceAtAnyWindowSize() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: CGRect(x: 180, y: 130, width: 800, height: 500),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let surface = NSView()
    window.contentView = surface
    let toolbar = LensToolbar(onTranslate: {}, onCapture: {}, onRecord: {})
    toolbar.attach(to: window)
    for size in [CGSize(width: 800, height: 500), CGSize(width: 320, height: 240)] {
        window.setContentSize(size)
        let rect = LensCaptureRegion.screenRect(surface: surface, window: window)
        #expect(rect.size == size)
        #expect(abs(rect.minX - window.frame.minX) < 1)
        #expect(abs(rect.minY - window.frame.minY) < 1)
        #expect(window.frame.maxY - rect.maxY > 40)
        #expect(!surface.subviews.contains { $0 is NSButton })
    }
}

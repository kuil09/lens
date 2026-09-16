import AppKit
import SwiftUI
import Testing
@testable import Lens

@Test @MainActor func auxiliaryWindowsReuseContentWithoutChangingReaderState() {
    _ = NSApplication.shared
    let windows = LensAuxiliaryWindows()
    for kind in LensAuxiliaryWindows.Kind.allCases {
        var creations = 0
        let first = windows.prepare(kind, delegate: nil) { _ in
            creations += 1
            return Text("Synthetic content")
        }
        let content = first.contentView
        let second = windows.prepare(kind, delegate: nil) { _ in
            creations += 1
            return Text("Must not replace reading content")
        }
        #expect(first === second && first.contentView === content)
        #expect(creations == 1)
        #expect(!windows.isPresented(kind)) // Preparation alone must not focus/show a window.
        #expect(first.contentMinSize == kind.minimumSize)
        #expect(first.tabbingMode == .disallowed && !first.isReleasedWhenClosed)
        first.close()
        if kind == .languageGuide {
            #expect(windows.didClose(first))
            #expect(windows.window(for: kind) == nil && first.contentView == nil)
            let replacement = windows.prepare(kind, delegate: nil) { _ in Text("New guide") }
            #expect(replacement !== first)
            replacement.close()
        } else {
            #expect(!windows.didClose(first))
            #expect(windows.window(for: kind) === first && first.contentView === content)
        }
    }
    #expect(!windows.didClose(nil))
}

@Test @MainActor func languageGuideReleasesItsContentAfterClose() {
    _ = NSApplication.shared
    let windows = LensAuxiliaryWindows()
    weak var releasedContent: NSView?
    autoreleasepool {
        let window = windows.prepare(.languageGuide, delegate: nil) { _ in Text("Synthetic guide") }
        releasedContent = window.contentView
        window.close()
        windows.didClose(window)
    }
    #expect(releasedContent == nil)
}

@Test func toolbarAndMenuEligibilityPreservesAllExistingConditions() {
    for bits in 0..<256 {
        let state = LensToolbarState(running: bits & 1 != 0, permissionNeeded: bits & 2 != 0,
            hasFrame: bits & 4 != 0, recording: bits & 8 != 0, finishing: bits & 16 != 0,
            choosingDestination: bits & 32 != 0, locked: bits & 64 != 0, captureSucceeded: bits & 128 != 0)
        #expect(state.canCapture == (state.hasFrame && !state.choosingDestination))
        #expect(state.canToggleRecording == (state.recording ||
            (!state.finishing && state.hasFrame && !state.choosingDestination)))
        if state.recording { #expect(state.canToggleRecording) }
    }
}

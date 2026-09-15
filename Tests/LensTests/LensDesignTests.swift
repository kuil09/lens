import AppKit
import SwiftUI
import Testing
@testable import Lens

@Test @MainActor func settingsToolbarUsesNativeCategoriesAndStaysSynchronized() throws {
    _ = NSApplication.shared
    let selection = LensSettingsSelection()
    let window = LensSettingsWindow(autosaveName: "", selection: selection)
    let toolbar = try #require(window.toolbar)
    #expect(window.toolbarStyle == .unified)
    #expect(window.titleVisibility == .hidden)
    #expect(window.tabbingMode == .disallowed)
    #expect(!toolbar.allowsUserCustomization)
    #expect(toolbar.items.map(\.itemIdentifier.rawValue) == LensSettingsPage.allCases.map(\.rawValue))
    for page in LensSettingsPage.allCases {
        window.select(page)
        #expect(selection.page == page)
        #expect(window.title == page.title)
        #expect(toolbar.selectedItemIdentifier?.rawValue == page.rawValue)
        #expect(toolbar.items.filter { $0.style == .prominent }.map(\.itemIdentifier.rawValue) == [page.rawValue])
        #expect(NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil) != nil)
    }
    // Navigation from a content button must update the native toolbar as well.
    selection.page = .translation
    #expect(window.title == L10n.text("Translation"))
    #expect(toolbar.selectedItemIdentifier?.rawValue == "translation")
    #expect(toolbar.items.first?.style == .prominent)
    #expect(!window.isVisible)
}

/// Native view renders for manual light/dark and layout inspection; never captures the screen.
@Test @MainActor func renderSettingsAndReaderInBothAppearances() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LensDesignRenders", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let model = LensModel()
    model.permissionNeeded = true
    let recording = LensRecording()
    let selection = LensSettingsSelection()
    for dark in [false, true] {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        for page in LensSettingsPage.allCases {
            selection.page = page
            let view = NSHostingView(rootView: LensControls(model: model, languages: model.languages, recording: recording, selection: selection, exports: LensExportStore(),
                onToggle: {}, onLock: {}, onPrepare: {}, onReader: {}, onCapture: {}, onRecord: {}, onPermissionSettings: {})
                .environment(\.colorScheme, dark ? .dark : .light))
            view.appearance = appearance
            view.frame = CGRect(x: 0, y: 0, width: 580, height: 600)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            #expect(bitmap.pixelsWide >= 580 && bitmap.pixelsHigh >= 600)
            try data.write(to: directory.appendingPathComponent("\(page.rawValue)-\(dark ? "dark" : "light").png"))
        }
        model.translations = [DisplayTranslation(
            block: TextBlock(text: "You can read the entire translation here, even when it does not fit inside the lens.",
                bounds: .zero, language: .english, confidence: 1),
            text: "렌즈 안에 모두 표시되지 않는 긴 번역도 이 창에서 끝까지 읽을 수 있습니다. 원문을 숨기거나 필요한 번역만 복사할 수도 있습니다.", background: .white)]
        let reader = NSHostingView(rootView: TranslationReader(model: model, onShowLens: {}, onSettings: {})
            .environment(\.colorScheme, dark ? .dark : .light))
        reader.appearance = appearance
        reader.frame = CGRect(x: 0, y: 0, width: 440, height: 500)
        reader.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        let bitmap = try #require(reader.bitmapImageRepForCachingDisplay(in: reader.bounds))
        reader.cacheDisplay(in: reader.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("reader-\(dark ? "dark" : "light").png"))
    }
}

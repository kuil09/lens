import AppKit
import Testing
@testable import Lens

@Test @MainActor func translationToggleControlsGlassAndTransparentPresentation() {
    _ = NSApplication.shared
    let model = LensModel()
    let surface = LensSurface(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    model.attach(surface)
    #expect(!model.running && !surface.idleBackground.isHidden)
    model.begin()
    #expect(surface.idleBackground.isHidden && !surface.overlay.isHidden)
    #expect(!surface.canvas.showsCapturedImage)
    model.suspend()
    #expect(!surface.idleBackground.isHidden && surface.overlay.isHidden)
    surface.setTranslationActive(false, arranging: true)
    #expect(surface.idleBackground.isHidden)
    surface.setTranslationActive(false)
    #expect(!surface.idleBackground.isHidden)
    surface.idleBackground.updateAccessibility(reduceTransparency: true)
    #expect(surface.idleBackground.glass.isHidden)
    surface.idleBackground.updateAccessibility(reduceTransparency: false)
    #expect(!surface.idleBackground.glass.isHidden)
    model.begin(); model.running = false // Capture failures also restore the glass.
    #expect(!surface.idleBackground.isHidden)
}

@Test @MainActor func swappingLanguagesInvalidatesOnceAndRejectsAutomaticSource() async {
    let catalog = LanguageCatalog(languageLoader: { [.korean, .english, .japanese] },
                                  recognitionLoader: { ["ko-KR", "en-US"] },
                                  routeResolver: { _ in .init(status: .installed, strategy: .lowLatency) })
    await catalog.load()
    let name = "LensGlassTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let model = LensModel(defaults: defaults, languages: catalog)
    model.targetPreference = .korean
    #expect(!model.canSwapLanguages)
    let automaticVersion = model.regionVersion
    model.swapLanguages()
    #expect(model.regionVersion == automaticVersion)
    model.source = .english
    model.begin()
    var restarts = 0
    model.onRestart = { restarts += 1 }
    let previousVersion = model.regionVersion
    model.swapLanguages()
    #expect(model.source == .korean && model.target == .english)
    #expect(model.regionVersion == previousVersion + 1 && restarts == 1)
    model.targetPreference = .japanese // Not recognized by this fixture's OCR catalog.
    #expect(!model.canSwapLanguages)
    model.suspend()
}

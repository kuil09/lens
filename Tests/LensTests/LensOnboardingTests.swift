import AppKit
import SwiftUI
import Testing
@preconcurrency import Translation
@testable import Lens

@MainActor private final class MutableFlag {
    var value = true
}

@Test @MainActor func sharedIntelligenceAvailabilityDoesNotCountAsDownloadedPacks() {
    // The user's machine: fr/de/zh are .installed for highFidelity but only
    // .supported for lowLatency. The download policy must preserve .supported.
    #expect(AppleLanguageSupport.downloadedRoute(lowLatency: .supported) ==
        TranslationRoute(status: .supported, strategy: .lowLatency))
    #expect(AppleLanguageSupport.downloadedRoute(lowLatency: .installed) ==
        TranslationRoute(status: .installed, strategy: .lowLatency))
    #expect(AppleLanguageSupport.downloadedRoute(lowLatency: .unsupported).status == .unsupported)
}

@Test @MainActor func onboardingCompletionRequiresPermissionAndInstalledRoute() throws {
    let name = "LensOnboardingTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let state = LensOnboardingState(defaults: defaults)
    #expect(!state.completed)
    #expect(!state.finish(languagesReady: true))
    state.permissionGranted = true
    #expect(!state.finish(languagesReady: false))
    #expect(!LensOnboardingState(defaults: defaults).completed)
    #expect(state.finish(languagesReady: true))
    #expect(LensOnboardingState(defaults: defaults).completed)
}

@Test @MainActor func reselectingCurrentLanguagesDoesNotInvalidateOrStopRecording() async throws {
    let name = "LensSameSelection.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let catalog = LanguageCatalog(languageLoader: { [.english, .korean] },
        recognitionLoader: { ["en-US", "ko-KR"] },
        routeResolver: { _ in .init(status: .installed, strategy: .lowLatency) })
    let model = LensModel(defaults: defaults, languages: catalog)
    await model.refreshLanguages()
    model.targetPreference = .korean; model.source = .english
    var invalidations = 0
    model.onRegionInvalidated = { invalidations += 1 }
    model.targetPreference = .korean; model.source = .english
    #expect(invalidations == 0)
}

@Test @MainActor func installedCatalogDoesNotAssumeEnglishOrExposeUnsupportedModels() async {
    let hindi = LensLanguage(rawValue: "hi")!
    let catalog = LanguageCatalog(languageLoader: { [.english, .korean, .japanese, hindi] },
        recognitionLoader: { ["en-US", "ko-KR", "ja-JP"] }, routeResolver: { pair in
            let installed = pair.source != .english && pair.target != .english
            return .init(status: installed ? .installed : .supported, strategy: .lowLatency)
        })
    await catalog.load()
    #expect(catalog.installedTargets == [.korean, .japanese, hindi])
    await catalog.refresh(target: .korean)
    #expect(catalog.installedSources(to: .korean) == [.japanese])
    #expect(!catalog.sourceLanguages.contains(hindi))
    #expect(catalog.installedSources(to: .english).isEmpty)
}

@Test @MainActor func removedModelsClearSavedSelectionAndDisableTranslation() async throws {
    let installed = MutableFlag()
    let catalog = LanguageCatalog(languageLoader: { [.english, .korean, .japanese] },
        recognitionLoader: { ["en-US", "ko-KR", "ja-JP"] }, routeResolver: { _ in
            .init(status: installed.value ? .installed : .supported, strategy: .lowLatency)
        })
    let name = "LensRemovedModels.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("ja", forKey: "target"); defaults.set("ko", forKey: "source")
    let model = LensModel(defaults: defaults, languages: catalog)
    await model.refreshLanguages()
    #expect(model.canTranslate)
    installed.value = false
    model.begin()
    await model.refreshLanguages()
    #expect(!model.canTranslate && !model.running)
    #expect(model.source == nil && model.targetPreference == nil)
    #expect(catalog.installedTargets.isEmpty && model.selectableSources.isEmpty)
    #expect(defaults.string(forKey: "target") == nil && defaults.string(forKey: "source") == nil)
}

@Test @MainActor func staleInstallationCensusCannotReplaceNewerResults() async {
    var release: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    let delay = MutableFlag()
    let catalog = LanguageCatalog(languageLoader: {
        if delay.value {
            await withCheckedContinuation { continuation in
                release = continuation; started?.resume(); started = nil
            }
            return [.english, .japanese]
        }
        return [.english, .korean]
    }, recognitionLoader: { ["en-US", "ko-KR", "ja-JP"] },
       routeResolver: { _ in .init(status: .installed, strategy: .lowLatency) })
    let old = Task { await catalog.load() }
    await withCheckedContinuation { continuation in
        if release != nil { continuation.resume() } else { started = continuation }
    }
    delay.value = false
    await catalog.load()
    release?.resume(); await old.value
    #expect(catalog.installedTargets == [.english, .korean])
    #expect(!catalog.checkingInstallation)
}

@Test @MainActor func onboardingAllStepsFitTheFixedWindow() async throws {
    _ = NSApplication.shared
    let name = "LensOnboardingLayout.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let state = LensOnboardingState(defaults: defaults)
    let catalog = LanguageCatalog(languageLoader: { [.english, .korean] },
        recognitionLoader: { ["en-US", "ko-KR"] },
        routeResolver: { _ in .init(status: .installed, strategy: .lowLatency) })
    let model = LensModel(defaults: defaults, languages: catalog)
    await model.refreshLanguages()
    for step in LensOnboardingState.Step.allCases {
        state.permissionGranted = true
        state.step = step
        let view = NSHostingView(rootView: LensOnboardingView(state: state, model: model, catalog: catalog,
            exports: LensExportStore(defaults: defaults), onPermission: {}, onRefresh: {},
            onPrepare: {}, onDirectory: {}, onFinish: {}, onLater: {}))
        #expect(view.fittingSize == CGSize(width: 540, height: 460))
        view.frame = CGRect(x: 0, y: 0, width: 540, height: 460)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        // Offscreen layout evidence, not screen capture or live-permission evidence.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LensDesignRenders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("onboarding-\(step.rawValue).png"))
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LENS_TEST_INSTALLED_LANGUAGES"] == "1"))
@MainActor func actualInstalledCatalogOnlyOffersReadyRoutes() async {
    let catalog = LanguageCatalog()
    let started = ProcessInfo.processInfo.systemUptime
    await catalog.load()
    print("CATALOG_SECONDS \(ProcessInfo.processInfo.systemUptime - started)")
    print("INSTALLED_TARGETS \(catalog.installedTargets.map(\.rawValue).joined(separator: ","))")
    for target in catalog.installedTargets {
        await catalog.refresh(target: target)
        #expect(!catalog.installedSources(to: target).isEmpty)
        for source in catalog.installedSources(to: target) {
            // Independent oracle: do not validate a catalog with the same route helper.
            let raw = await LanguageAvailability(preferredStrategy: .lowLatency)
                .status(from: source.locale, to: target.locale)
            #expect(raw == .installed)
        }
    }
}

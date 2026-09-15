import AppKit
import SwiftUI
import Testing
@testable import Lens

@Test @MainActor func permissionRecoveryPreservesProgressButNeverPersistsAGrant() throws {
    let name = "LensPermissionRecovery.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("en", forKey: "source")
    defaults.set("ko", forKey: "target")
    defaults.set(Data([1, 2, 3]), forKey: "exportDirectoryBookmark")
    var granted = false
    var requests = 0
    let access = ScreenRecordingAccess(preflight: { granted }, request: { requests += 1; return false })
    let state = LensOnboardingState(defaults: defaults)
    state.step = .saving
    state.refreshPermission(using: access)
    #expect(state.visibleStep == .permission && state.step == .saving)
    state.deferred = true
    for _ in 0..<10 { state.refreshPermission(using: access) }
    #expect(requests == 0 && !state.completed)
    let resumed = LensOnboardingState(defaults: defaults)
    #expect(resumed.step == .saving && !resumed.permissionGranted && !resumed.completed)
    granted = true
    resumed.refreshPermission(using: access)
    #expect(resumed.visibleStep == .saving && requests == 0)
    #expect(resumed.finish(languagesReady: true))
    let relaunched = LensOnboardingState(defaults: defaults)
    #expect(relaunched.completed && !relaunched.permissionGranted)
    granted = false
    relaunched.refreshPermission(using: access)
    #expect(relaunched.visibleStep == .permission)
    #expect(defaults.string(forKey: "source") == "en")
    #expect(defaults.string(forKey: "target") == "ko")
    #expect(defaults.data(forKey: "exportDirectoryBookmark") == Data([1, 2, 3]))
    #expect(requests == 0)
}

@Test @MainActor func permissionGuideStatesFitANormalWindowWithoutStartingCapture() throws {
    _ = NSApplication.shared
    let name = "LensPermissionGuideLayout.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let state = LensOnboardingState(defaults: defaults)
    let model = LensModel(defaults: defaults)
    let recording = LensRecording()
    for granted in [false, true] {
        for deferred in [false, true] {
            state.permissionGranted = granted
            state.deferred = deferred
            let view = NSHostingView(rootView: LensPermissionGuide(state: state, model: model,
                catalog: model.languages, recording: recording, onSettings: {}, onRefresh: {}, onContinue: {}, onQuit: {}))
            #expect(view.fittingSize == CGSize(width: 520, height: 390))
            #expect(!model.running && !model.hasFrame && !recording.isRecording)
        }
    }
}

@Test @MainActor func permissionGuideReadinessRequiresInstalledLanguagesNotOnlyScreenAccess() async throws {
    let name = "LensPermissionGuideReadiness.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("en", forKey: "source")
    defaults.set("ko", forKey: "target")
    let catalog = LanguageCatalog(languageLoader: { [.english, .korean] },
        recognitionLoader: { ["en-US", "ko-KR"] },
        routeResolver: { _ in .init(status: .installed, strategy: .lowLatency) })
    let model = LensModel(defaults: defaults, languages: catalog)
    let state = LensOnboardingState(defaults: defaults)
    state.permissionGranted = true
    let guide = LensPermissionGuide(state: state, model: model, catalog: catalog,
        recording: LensRecording(), onSettings: {}, onRefresh: {}, onContinue: {}, onQuit: {})
    #expect(guide.title == L10n.text("Checking installed languages…"))
    await model.refreshLanguages()
    #expect(model.canTranslate)
    #expect(guide.title == L10n.text("Ready when you are"))
    #expect(!model.running && !model.hasFrame)
    state.deferred = true
    #expect(guide.title == L10n.text("Lens is paused"))
    state.deferred = false
    state.permissionGranted = false
    #expect(guide.title == L10n.text("Allow screen access to translate"))
}

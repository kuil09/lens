import Foundation
import Testing
@testable import Lens

@Test func completedLaunchAndReturnUsePausedLensUnlessPermissionIsMissing() {
    #expect(LensReturnDestination.resolve(requestPending: false, handoffPending: false,
        hasVisibleWindows: false, onboardingCompleted: true, permissionGranted: true) == .lens)
    #expect(LensReturnDestination.resolve(requestPending: false, handoffPending: false,
        hasVisibleWindows: false, onboardingCompleted: true, permissionGranted: false) == .guide)
    #expect(LensReturnDestination.resolve(requestPending: false, handoffPending: false,
        hasVisibleWindows: false, onboardingCompleted: false, permissionGranted: true) == .onboarding)
    #expect(LensReturnDestination.resolve(requestPending: false, handoffPending: true,
        hasVisibleWindows: true, onboardingCompleted: true, permissionGranted: true) == .guide)
}

@Test func checkingNeverMeansMissingAndOnlyOneExplicitStartIsConsumed() {
    var intent = TranslationStartRequest()
    #expect(intent.resolve(.ready) == .none)
    for _ in 0..<10 { #expect(intent.request(.checking) == .wait) }
    #expect(intent.pending)
    #expect(intent.resolve(.ready) == .start)
    #expect(!intent.pending && intent.resolve(.ready) == .none)
    #expect(intent.request(.missing) == .guide)
    #expect(intent.request(.failed("test")) == .retry)
    #expect(!intent.pending)
    #expect(intent.request(.checking) == .wait)
    intent.cancel()
    #expect(intent.resolve(.ready) == .none)
    #expect(intent.resolve(.missing) == .none)
}

@MainActor private final class LanguageCheckBarrier {
    var enabled = false
    var release: CheckedContinuation<Void, Never>?
    var entered: CheckedContinuation<Void, Never>?
    func pauseIfEnabled() async {
        guard enabled else { return }
        await withCheckedContinuation { release = $0; entered?.resume(); entered = nil }
    }
    func waitUntilEntered() async {
        if release != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func resume() { enabled = false; release?.resume(); release = nil }
}

@Test @MainActor func installedLanguagesStaySelectedDuringDelayedRecheckAndStartOnce() async throws {
    let suite = "LensStartFlow.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("ko", forKey: "target"); defaults.set("en", forKey: "source")
    let barrier = LanguageCheckBarrier()
    let catalog = LanguageCatalog(languageLoader: {
        await barrier.pauseIfEnabled(); return [.english, .korean]
    }, recognitionLoader: { ["en-US", "ko-KR"] },
       routeResolver: { _ in .init(status: .installed, strategy: .lowLatency) })
    let model = LensModel(defaults: defaults, languages: catalog)
    await model.refreshLanguages()
    #expect(model.readiness == .ready)
    barrier.enabled = true
    let refresh = Task { await model.refreshLanguages() }
    await barrier.waitUntilEntered()
    #expect(model.readiness == .checking && !model.canTranslate)
    #expect(model.source == .english && model.targetPreference == .korean)
    #expect(model.startRequest.request(model.readiness) == .wait)
    barrier.resume(); await refresh.value
    #expect(model.readiness == .ready)
    #expect(model.startRequest.resolve(model.readiness) == .start)
    #expect(model.startRequest.resolve(model.readiness) == .none)
    #expect(!model.running) // Only the app coordinator may start actual capture.
}

@Test @MainActor func failedCensusPreservesPreferencesAndRetryRecovers() async throws {
    enum Failure: Error { case recognition }
    var fail = false
    let suite = "LensStartFailure.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("ja", forKey: "target"); defaults.set("en", forKey: "source")
    let catalog = LanguageCatalog(languageLoader: { [.english, .japanese] },
        recognitionLoader: { if fail { throw Failure.recognition }; return ["en-US", "ja-JP"] },
        routeResolver: { _ in .init(status: .installed, strategy: .lowLatency) })
    let model = LensModel(defaults: defaults, languages: catalog)
    await model.refreshLanguages()
    fail = true
    await model.refreshLanguages()
    guard case .failed = model.readiness else { Issue.record("Failure is not a missing pack"); return }
    #expect(model.source == .english && model.targetPreference == .japanese)
    #expect(catalog.installedTargets == [.english, .japanese])
    fail = false
    await model.refreshLanguages()
    #expect(model.readiness == .ready)
    _ = model.startRequest.request(.checking)
    model.source = nil
    #expect(!model.startRequest.pending)
    _ = model.startRequest.request(.checking)
    model.suspend()
    #expect(!model.startRequest.pending)
}

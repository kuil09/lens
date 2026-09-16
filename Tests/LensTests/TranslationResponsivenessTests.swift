import AppKit
import Combine
import CoreImage
import Testing
@testable import Lens

private func refreshFrame(_ changed: Bool = false) -> FrameFingerprint {
    var bytes = Array(repeating: UInt8(255), count: 128 * 80 * 4)
    if changed { bytes[(40 * 128 + 112) * 4] = 0 }
    return .init(bytes: bytes)
}

@Test func profilesPreserveBudgetFairnessAndQuietRecovery() {
    var counts: [TranslationResponsiveness: Int] = [:]
    for profile in TranslationResponsiveness.allCases {
        var grid = RegionalBackoff(); grid.responsiveness = profile
        grid.observe(refreshFrame(), at: 0)
        let initial = grid.due(at: 0.12)
        grid.dispatched(initial, at: 0.12); grid.checked(initial, submitted: grid.generation, at: 0.12)
        var attempts: [Double] = []
        for tick in 1...600 {
            let now = Double(tick) / 30
            grid.observe(refreshFrame(tick.isMultiple(of: 2)), at: now)
            let due = grid.due(at: now)
            if !due.isEmpty {
                #expect(due == [23])
                grid.dispatched(due, at: now); attempts.append(now)
            }
        }
        #expect(zip(attempts, attempts.dropFirst()).allSatisfy { $1 - $0 >= 0.25 - 0.000001 })
        #expect(zip(attempts, attempts.dropFirst()).allSatisfy { $1 - $0 <= profile.intervals.last! + 0.034 })
        #expect(grid.regions[0].attempts == 1)
        let recovered = grid.due(at: 20.26)
        #expect(recovered.contains(23))
        grid.dispatched(recovered, at: 20.26)
        grid.checked(recovered, submitted: grid.generation, at: 20.26)
        #expect(!grid.hasPending && grid.regions[23].level == 0)
        counts[profile] = attempts.count
        print("Synthetic 20s scheduling: \(profile) requests=\(attempts.count)")
    }
    #expect(counts[.calm]! < counts[.balanced]! && counts[.balanced]! < counts[.fast]!)
}

@Test @MainActor func responsivenessPersistsWithoutRestartOrInvalidation() throws {
    let name = "LensResponsivenessTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(TranslationResponsiveness.load(from: defaults) == .balanced)
    defaults.set(99, forKey: TranslationResponsiveness.preferenceKey)
    #expect(TranslationResponsiveness.load(from: defaults) == .balanced)
    let model = LensModel(defaults: defaults)
    var invalidations = 0, restarts = 0
    model.onRegionInvalidated = { invalidations += 1 }; model.onRestart = { restarts += 1 }
    model.running = true
    let version = model.regionVersion
    model.responsiveness = .fast
    #expect(model.running && model.regionVersion == version)
    #expect(invalidations == 0 && restarts == 0)
    #expect(LensModel(defaults: defaults).responsiveness == .fast)
}

@Test func profileChangesPreserveDirtyHistoryAndValidity() {
    var grid = RegionalBackoff()
    grid.observe(refreshFrame(), at: 0)
    let epoch = grid.epoch, generation = grid.generation
    grid.observe(refreshFrame(true), at: 0.1)
    let revisions = grid.regions.map(\.revision)
    for profile in TranslationResponsiveness.allCases {
        grid.responsiveness = profile
        #expect(grid.epoch == epoch && grid.regions.map(\.revision) == revisions)
        #expect(!grid.unchanged(CGRect(x: 0.85, y: 0.45, width: 0.1, height: 0.1), since: generation, epoch: epoch))
        #expect(grid.unchanged(CGRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1), since: generation, epoch: epoch))
    }
}

@Test func revealPolicyBoundsFrequencyAndRespectsMotionAndCover() {
    var policy = TranslationRevealPolicy()
    let bounds = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)
    #expect(policy.duration(for: bounds, at: 0, allowed: true) == 0.14)
    for tick in 1...30 { #expect(policy.duration(for: bounds, at: Double(tick) / 10, allowed: true) == 0) }
    #expect(policy.duration(for: bounds, at: 4.1, allowed: true) == 0.14)
    #expect(policy.duration(for: bounds, at: 6, allowed: false) == 0)
    policy.reset()
    #expect(policy.duration(for: bounds, at: 6, allowed: true) == 0.14)
}

@MainActor private func revealItem(_ number: Int, x: CGFloat = 0.1) -> DisplayTranslation {
    .init(block: .init(text: "Do not delete \(number) files.", bounds: CGRect(x: x, y: 0.4, width: 0.3, height: 0.15),
                      language: .english, confidence: 1), text: "파일 \(number)개를 삭제하지 마세요.", background: .white)
}

@Test @MainActor func liveRevealKeepsUnchangedViewsAndCancelsInvalidTextImmediately() throws {
    _ = NSApplication.shared
    let overlay = TranslationOverlay(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    let window = NSWindow(contentRect: overlay.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = overlay; window.orderFront(nil)
    defer { window.close() }
    var now = 0.0
    overlay.transitionClock = { now }; overlay.reduceMotion = { false }; overlay.usesLiveTransitions = true
    let a = revealItem(12), b = revealItem(10, x: 0.6)
    overlay.translations = [a, b]
    let first = try #require(overlay.glyphViews[a.id])
    #expect(first.layer?.animation(forKey: "translationReveal")?.duration == 0.14)
    overlay.translations = [a]
    #expect(overlay.glyphViews[a.id] === first && overlay.glyphViews[b.id] == nil)
    now = 0.1
    let changed = revealItem(13)
    overlay.translations = [changed]
    #expect(first.superview == nil && overlay.glyphViews[a.id] == nil)
    #expect(overlay.glyphViews[changed.id]?.layer?.animation(forKey: "translationReveal") == nil)
    now = 2
    overlay.translations = [a]
    #expect(overlay.glyphViews[a.id]?.layer?.animation(forKey: "translationReveal") != nil)
    overlay.isHidden = true
    #expect(overlay.glyphViews[a.id]?.layer?.animation(forKey: "translationReveal") == nil)
    overlay.isHidden = false; overlay.reduceMotion = { true }; now = 4
    overlay.translations = [b]
    #expect(overlay.glyphViews[b.id]?.layer?.animation(forKey: "translationReveal") == nil)
    overlay.reduceMotion = { false }; overlay.maskOpacity = 0.5; now = 6
    overlay.translations = [a]
    #expect(overlay.glyphViews[a.id]?.layer?.animation(forKey: "translationReveal") == nil)
    overlay.translations = []
    #expect(overlay.layouts.isEmpty && overlay.glyphViews.isEmpty)
}

@Test @MainActor func exportOverlayNeverUsesIntermediateOpacity() throws {
    let overlay = TranslationOverlay(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    overlay.translations = [revealItem(12)]
    #expect(!overlay.usesLiveTransitions && overlay.glyphViews.isEmpty && overlay.layouts.count == 1)
    let context = CIContext()
    let image = try #require(context.createCGImage(CIImage(color: .white).cropped(to: overlay.bounds), from: overlay.bounds))
    let first = try #require(LensSnapshot.png(background: image, pointSize: overlay.bounds.size, translations: overlay.translations, maskOpacity: 1))
    let second = try #require(LensSnapshot.png(background: image, pointSize: overlay.bounds.size, translations: overlay.translations, maskOpacity: 1))
    #expect(first == second)
}

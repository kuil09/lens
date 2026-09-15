import AppKit
import Combine
import CoreImage

@MainActor
final class LensModel: ObservableObject {
    @Published var source: LensLanguage? {
        didSet {
            guard source != oldValue else { return }
            defaults.set(source?.rawValue, forKey: "source"); settingsChanged()
        }
    }
    @Published var targetPreference: LensLanguage? {
        didSet {
            guard targetPreference != oldValue else { return }
            defaults.set(targetPreference?.rawValue, forKey: "target")
            applyLanguagePreferences()
            settingsChanged()
            if !changingLanguagePair { refreshLanguageRoutes() }
        }
    }
    @Published private(set) var target: LensLanguage
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity"); surface?.overlay.maskOpacity = opacity } }
    @Published var locked = false
    @Published var status = L10n.text("Prepare language packs before starting.")
    @Published var running = false { didSet { surface?.setTranslationActive(running) } }
    @Published var permissionNeeded = false
    @Published var hasFrame = false
    @Published var translations: [DisplayTranslation] = []
    @Published var metrics = L10n.text("Waiting for measurements")
    var onRestart: (() -> Void)?
    var onRegionInvalidated: (() -> Void)?
    weak var surface: LensSurface?
    let capture = ScreenCapture()
    let languages: LanguageCatalog
    private let translator: any TranslationEngine
    private lazy var pipeline = RegionalTranslationPipeline(translator: translator)
    private let defaults: UserDefaults
    private let preferredLanguages: @MainActor () -> [String]
    private var languageRefresh: Task<Void, Never>?
    private var gate = ResultGate()
    private var renderSamples = LatencySamples()
    private var translationSamples = LatencySamples()
    private var lastMetricUpdate: Double = 0
    private var changingLanguagePair = false
    private var refreshGeneration = UUID()
    private(set) var frameCount = 0
    var recognitionCount: Int { pipeline.diagnostics.ocrRequests }

    init(translator: (any TranslationEngine)? = nil, defaults: UserDefaults = .standard,
         languages: LanguageCatalog? = nil, preferredLanguages: @escaping @MainActor () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.languages = languages ?? LanguageCatalog()
        self.preferredLanguages = preferredLanguages
        self.translator = translator ?? AppleTranslationEngine()
        source = defaults.string(forKey: "source").flatMap(LensLanguage.init(rawValue:))
        let savedTarget = defaults.string(forKey: "target").flatMap(LensLanguage.init(rawValue:))
        targetPreference = savedTarget
        target = savedTarget ?? preferredLanguages().first.flatMap(LensLanguage.init(rawValue:)) ?? .english
        opacity = defaults.object(forKey: "opacity") as? Double ?? 1
        pipeline.onDisplay = { [weak self] display in
            self?.translations = display; self?.surface?.overlay.translations = display
        }
        pipeline.onStatus = { [weak self] status in self?.status = status }
        pipeline.onLatency = { [weak self] elapsed in
            self?.translationSamples.append(elapsed); self?.updateMetrics()
        }
        capture.onFrame = { [weak self] in self?.receive($0) }
        capture.onFailure = { [weak self] error in
            self?.running = false; self?.invalidate(); self?.hasFrame = false; self?.surface?.canvas.clear()
            self?.status = L10n.text("Capture stopped: %1$@ · Start again to retry.", String(describing: error))
        }
    }
    var regionVersion: UInt64 { gate.version.region }
    var selectableSources: [LensLanguage] { languages.installedSources(to: target) }
    var canTranslate: Bool {
        guard !languages.checkingInstallation, !languages.loading,
              languages.installedTargets.contains(target) else { return false }
        return source.map { selectableSources.contains($0) } ?? !selectableSources.isEmpty
    }
    var systemTarget: LensLanguage {
        LensLanguage.systemDefault(preferred: preferredLanguages(), supported: languages.installedTargets)
    }
    var canSwapLanguages: Bool {
        guard let source, !source.isSameLanguage(as: target) else { return false }
        return languages.sourceLanguages.contains { $0.isSameLanguage(as: target) }
            && languages.installedTargets.contains { $0.isSameLanguage(as: source) }
    }
    func swapLanguages() {
        guard canSwapLanguages, let previousSource = source else { return }
        changingLanguagePair = true
        source = target
        targetPreference = previousSource
        changingLanguagePair = false
        settingsChanged()
        refreshLanguageRoutes()
    }
    func refreshLanguages() async {
        let token = UUID(); refreshGeneration = token
        languageRefresh?.cancel()
        let previousSources = selectableSources
        await languages.load()
        guard refreshGeneration == token, !Task.isCancelled else { return }
        let oldTarget = target
        changingLanguagePair = true
        applyLanguagePreferences()
        changingLanguagePair = false
        if oldTarget != target { settingsChanged() }
        await languages.refresh(target: target)
        guard refreshGeneration == token, !Task.isCancelled else { return }
        reconcileSource()
        if running && !canTranslate { suspend() }
        else if previousSources != selectableSources { settingsChanged() }
    }
    private func applyLanguagePreferences() {
        guard languages.hasLoaded else { return }
        if let preference = targetPreference {
            if let installed = LensLanguage.match(preference.rawValue, in: languages.installedTargets) { target = installed }
            else { targetPreference = nil }
        } else {
            target = systemTarget
        }
    }
    private func refreshLanguageRoutes() {
        refreshGeneration = UUID()
        languageRefresh?.cancel()
        languageRefresh = Task { [weak self] in
            guard let self else { return }
            await languages.refresh(target: target)
            guard !Task.isCancelled else { return }
            reconcileSource()
            if running && !canTranslate { suspend() }
        }
    }
    private func reconcileSource() {
        if let source, !selectableSources.contains(source) { self.source = nil }
    }
    func attach(_ view: LensSurface) {
        surface = view; view.setTranslationActive(running); view.overlay.maskOpacity = opacity
        view.canvas.onPresented = { [weak self] latency in self?.renderSamples.append(latency); self?.updateMetrics() }
    }
    func invalidate() {
        onRegionInvalidated?()
        hasFrame = false
        gate.regionChanged(); pipeline.reset()
        translations = []; surface?.overlay.translations = []
    }
    func begin() { running = true; status = L10n.text("Connecting to the screen…") }
    func suspend() { running = false; hasFrame = false; invalidate(); surface?.canvas.clear(); status = L10n.text("Pause") }
    private func settingsChanged() {
        guard !changingLanguagePair else { return }
        invalidate(); if running { onRestart?() }
    }
    private func receive(_ frame: CapturedFrame) {
        guard running, frame.version == gate.version.region else { return }
        frameCount += 1; surface?.canvas.present(frame); hasFrame = true
        pipeline.receive(CIImage(cvPixelBuffer: frame.buffer),
            context: .init(source: source, target: target, languages: languages.sourceLanguages))
    }
    private func updateMetrics() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMetricUpdate > 1 else { return }; lastMetricUpdate = now
        func ms(_ v: Double?) -> String { v.map { String(format: "%.0f ms", $0 * 1000) } ?? "—" }
        metrics = L10n.text("Render submission p95 %1$@ · Translation p50 %2$@ / p95 %3$@", String(describing: ms(renderSamples.percentile(0.95))), String(describing: ms(translationSamples.percentile(0.5))), String(describing: ms(translationSamples.percentile(0.95))))
    }
}

enum PipelineError: LocalizedError {
    case languageNotReady
    var errorDescription: String? { L10n.text("Language packs are not ready. Open Language Packs to prepare them.") }
}

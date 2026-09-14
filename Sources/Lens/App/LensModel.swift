import AppKit
import Combine
import CoreImage

@MainActor
final class LensModel: ObservableObject {
    @Published var source: LensLanguage? { didSet { defaults.set(source?.rawValue, forKey: "source"); settingsChanged() } }
    @Published var targetPreference: LensLanguage? {
        didSet {
            defaults.set(targetPreference?.rawValue, forKey: "target")
            applyLanguagePreferences()
            settingsChanged()
            refreshLanguageRoutes()
        }
    }
    @Published private(set) var target: LensLanguage
    @Published var reproduced: Bool { didSet { defaults.set(reproduced, forKey: "reproduced"); surface?.canvas.showsCapturedImage = reproduced } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity"); surface?.overlay.maskOpacity = opacity } }
    @Published var locked = false
    @Published var status = "언어 팩을 준비한 뒤 시작하세요."
    @Published var running = false
    @Published var permissionNeeded = false
    @Published var hasFrame = false
    @Published var translations: [DisplayTranslation] = []
    @Published var metrics = "측정 대기"
    var onRestart: (() -> Void)?
    var onRegionInvalidated: (() -> Void)?
    weak var surface: LensSurface?
    let capture = ScreenCapture()
    let languages: LanguageCatalog
    private let ocr = OCRService()
    private let translator: any TranslationEngine
    private let analysis = FrameAnalysis()
    private let defaults: UserDefaults
    private let preferredLanguages: @MainActor () -> [String]
    private var languageRefresh: Task<Void, Never>?
    private var gate = ResultGate()
    private var fingerprint: FrameFingerprint?
    private var pending: (CapturedFrame, WorkVersion, Double)?
    private var worker: Task<Void, Never>?
    private var lastOCR: Double = 0
    private var changedAt: Double = 0
    private var renderSamples = LatencySamples()
    private var translationSamples = LatencySamples()
    private var lastMetricUpdate: Double = 0
    private(set) var frameCount = 0
    private(set) var recognitionCount = 0

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
        reproduced = defaults.object(forKey: "reproduced") as? Bool ?? true
        opacity = defaults.object(forKey: "opacity") as? Double ?? 1
        capture.onFrame = { [weak self] in self?.receive($0) }
        capture.onFailure = { [weak self] error in
            self?.running = false; self?.invalidate(); self?.hasFrame = false; self?.surface?.canvas.clear()
            self?.status = "캡처 중지: \(error) · 다시 시작을 눌러 주세요."
        }
    }
    var regionVersion: UInt64 { gate.version.region }
    func refreshLanguages() async {
        await languages.load()
        guard !Task.isCancelled else { return }
        let oldTarget = target
        applyLanguagePreferences()
        if oldTarget != target { settingsChanged() }
        await languages.refresh(target: target)
    }
    private func applyLanguagePreferences() {
        if let preference = targetPreference {
            target = LensLanguage.match(preference.rawValue, in: languages.languages) ?? preference
        } else {
            target = LensLanguage.systemDefault(preferred: preferredLanguages(), supported: languages.languages)
        }
    }
    private func refreshLanguageRoutes() {
        languageRefresh?.cancel()
        languageRefresh = Task { [weak self] in
            guard let self else { return }
            await languages.refresh(target: target)
        }
    }
    func attach(_ view: LensSurface) {
        surface = view; view.canvas.showsCapturedImage = reproduced; view.overlay.maskOpacity = opacity
        view.canvas.onPresented = { [weak self] latency in self?.renderSamples.append(latency); self?.updateMetrics() }
    }
    func invalidate() {
        onRegionInvalidated?()
        hasFrame = false
        gate.regionChanged(); fingerprint = nil; pending = nil
        worker?.cancel(); translator.cancel()
        translations = []; surface?.overlay.translations = []
    }
    func begin() { running = true; status = "화면 연결 중…"; surface?.canvas.showsCapturedImage = reproduced }
    func suspend() { running = false; hasFrame = false; invalidate(); surface?.canvas.clear(); status = "일시정지" }
    private func settingsChanged() { invalidate(); if running { onRestart?() } }
    private func receive(_ frame: CapturedFrame) {
        guard running, frame.version == gate.version.region else { return }
        frameCount += 1; surface?.canvas.present(frame); hasFrame = true
        let now = ProcessInfo.processInfo.systemUptime
        let next = analysis.fingerprint(CIImage(cvPixelBuffer: frame.buffer))
        guard fingerprint.map({ next.differs(from: $0) }) ?? true else { return }
        fingerprint = next; gate.contentChanged(); changedAt = now; translator.cancel()
        translations = []; surface?.overlay.translations = []
        pending = (frame, gate.version, now); status = "화면 인식 중…"; startWorker()
    }
    private func startWorker() {
        guard worker == nil, running else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            defer { worker = nil; if pending != nil && running { startWorker() } }
            while pending != nil && running && !Task.isCancelled {
                let wait = max(0, max(lastOCR + 0.25, changedAt + 0.12) - ProcessInfo.processInfo.systemUptime)
                if wait > 0 {
                    do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                    if ProcessInfo.processInfo.systemUptime < changedAt + 0.12 { continue }
                }
                guard let (frame, submitted, started) = pending else { continue }
                pending = nil
                let image = CIImage(cvPixelBuffer: frame.buffer)
                guard let cg = analysis.cgImage(image) else { continue }
                lastOCR = ProcessInfo.processInfo.systemUptime; recognitionCount += 1
                do {
                    let blocks = try await ocr.recognize(cg, source: source,
                        languages: languages.languages.isEmpty ? nil : languages.sourceLanguages)
                    guard gate.accepts(submitted), !Task.isCancelled else { continue }
                    let candidates = blocks.filter { $0.language.map { !$0.isSameLanguage(as: target) } == true && $0.confidence >= 0.3 }
                    var installed: Set<LensLanguage> = []
                    var unavailable: Set<LensLanguage> = []
                    for language in Set(candidates.compactMap(\.language)) {
                        if await translator.availability(source: language, target: target) == .installed { installed.insert(language) }
                        else { unavailable.insert(language) }
                        guard gate.accepts(submitted), !Task.isCancelled else { break }
                    }
                    guard gate.accepts(submitted), !Task.isCancelled else { continue }
                    let eligible = candidates.filter { $0.language.map(installed.contains) ?? false }
                    if eligible.isEmpty {
                        status = !unavailable.isEmpty ? "선택한 번역 언어로 사용할 모델이 없습니다. 언어 팩 관리에서 준비해 주세요." : (blocks.isEmpty ? "번역할 텍스트가 없습니다." : "번역할 다른 언어가 없습니다. 필요하면 원문 언어를 지정하세요.")
                        continue
                    }
                    status = "\(eligible.count)개 영역 번역 중…"
                    var complete: [DisplayTranslation] = []
                    for offset in stride(from: 0, to: eligible.count, by: 4) {
                        guard gate.accepts(submitted), !Task.isCancelled else { break }
                        let batch = Array(eligible[offset..<min(offset + 4, eligible.count)])
                        let inputs = batch.map { TranslationInput(id: $0.id, text: $0.text, source: $0.language!, target: target) }
                        for language in Set(inputs.map(\.source)) {
                            guard await translator.availability(source: language, target: target) == .installed else { throw PipelineError.languageNotReady }
                        }
                        let output = try await translator.translate(inputs)
                        guard gate.accepts(submitted), !Task.isCancelled else { break }
                        for result in output {
                            guard let block = batch.first(where: { $0.id == result.id }) else { continue }
                            let (r,g,b) = analysis.background(image, normalized: block.bounds)
                            complete.append(DisplayTranslation(block: block, text: result.text, background: NSColor(srgbRed: r, green: g, blue: b, alpha: 1)))
                        }
                        translations = complete; surface?.overlay.translations = complete
                        translationSamples.append(ProcessInfo.processInfo.systemUptime - started); updateMetrics()
                    }
                    if gate.accepts(submitted) {
                        status = "\(complete.count)개 영역 번역됨 · 기기에서 처리"
                        if !unavailable.isEmpty { status += " · 일부 원문은 언어 팩 준비 필요" }
                    }
                } catch is CancellationError { continue }
                catch { if gate.accepts(submitted), !Task.isCancelled { status = error.localizedDescription } }
            }
        }
    }
    private func updateMetrics() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMetricUpdate > 1 else { return }; lastMetricUpdate = now
        func ms(_ v: Double?) -> String { v.map { String(format: "%.0f ms", $0 * 1000) } ?? "—" }
        metrics = "렌더 제출 p95 \(ms(renderSamples.percentile(0.95))) · 번역 p50 \(ms(translationSamples.percentile(0.5))) / p95 \(ms(translationSamples.percentile(0.95)))"
    }
}

enum PipelineError: LocalizedError {
    case languageNotReady
    var errorDescription: String? { "언어 팩이 준비되지 않았습니다. ‘언어 준비’를 눌러 주세요." }
}

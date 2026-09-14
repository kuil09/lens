import AppKit
import Combine
import CoreImage

@MainActor
final class LensModel: ObservableObject {
    @Published var source: LensLanguage? { didSet { defaults.set(source?.rawValue, forKey: "source"); settingsChanged() } }
    @Published var target: LensLanguage { didSet { defaults.set(target.rawValue, forKey: "target"); settingsChanged() } }
    @Published var reproduced: Bool { didSet { defaults.set(reproduced, forKey: "reproduced"); surface?.canvas.showsCapturedImage = reproduced } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity"); surface?.overlay.maskOpacity = opacity } }
    @Published var locked = false
    @Published var status = "언어 팩을 준비한 뒤 시작하세요."
    @Published var running = false
    @Published var permissionNeeded = false
    @Published var translations: [DisplayTranslation] = []
    @Published var metrics = "측정 대기"
    var onRestart: (() -> Void)?
    weak var surface: LensSurface?
    let capture = ScreenCapture()
    private let ocr = OCRService()
    private let translator: any TranslationEngine
    private let analysis = FrameAnalysis()
    private let defaults = UserDefaults.standard
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

    init(translator: (any TranslationEngine)? = nil) {
        self.translator = translator ?? AppleTranslationEngine()
        source = UserDefaults.standard.string(forKey: "source").flatMap(LensLanguage.init(rawValue:))
        target = UserDefaults.standard.string(forKey: "target").flatMap(LensLanguage.init(rawValue:)) ?? .korean
        reproduced = UserDefaults.standard.object(forKey: "reproduced") as? Bool ?? true
        opacity = UserDefaults.standard.object(forKey: "opacity") as? Double ?? 1
        capture.onFrame = { [weak self] in self?.receive($0) }
        capture.onFailure = { [weak self] error in
            self?.running = false; self?.invalidate(); self?.surface?.canvas.clear()
            self?.status = "캡처 중지: \(error) · 다시 시작을 눌러 주세요."
        }
    }
    var regionVersion: UInt64 { gate.version.region }
    func attach(_ view: LensSurface) {
        surface = view; view.canvas.showsCapturedImage = reproduced; view.overlay.maskOpacity = opacity
        view.canvas.onPresented = { [weak self] latency in self?.renderSamples.append(latency); self?.updateMetrics() }
    }
    func invalidate() {
        gate.regionChanged(); fingerprint = nil; pending = nil
        worker?.cancel(); translator.cancel()
        translations = []; surface?.overlay.translations = []
    }
    func begin() { running = true; status = "화면 연결 중…"; surface?.canvas.showsCapturedImage = reproduced }
    func suspend() { running = false; invalidate(); surface?.canvas.clear(); status = "일시정지" }
    private func settingsChanged() { invalidate(); if running { onRestart?() } }
    private func receive(_ frame: CapturedFrame) {
        guard running, frame.version == gate.version.region else { return }
        frameCount += 1; surface?.canvas.present(frame)
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
                    let blocks = try await ocr.recognize(cg, source: source)
                    guard gate.accepts(submitted), !Task.isCancelled else { continue }
                    let eligible = blocks.filter { $0.language != nil && $0.language != target && $0.confidence >= 0.3 }
                    if eligible.isEmpty {
                        status = blocks.isEmpty ? "번역할 텍스트가 없습니다." : "번역할 다른 언어가 없습니다. 필요하면 원문 언어를 지정하세요."
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
                    if gate.accepts(submitted) { status = "\(complete.count)개 영역 번역됨 · 기기에서 처리" }
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

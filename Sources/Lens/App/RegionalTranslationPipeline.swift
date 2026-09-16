import AppKit
import CoreImage

/// One OCR operation, one translation batch, one latest frame, and a bounded current-text table.
/// Pixel changes invalidate only intersecting text, not unrelated in-flight translations.
@MainActor final class RegionalTranslationPipeline {
    typealias Recognizer = @MainActor (CGImage, LensLanguage?, [LensLanguage]) async throws -> [TextBlock]
    struct Context: Equatable {
        let source: LensLanguage?
        let target: LensLanguage
        let languages: [LensLanguage]
    }
    private struct Record {
        var block: TextBlock
        var generation: UInt64
        var epoch: UInt64
        var translated: String?
        var background: NSColor
        var visible = false
        var needsTranslation = true
        var waitingSince: Double
        var observedAt: Double
    }
    struct Diagnostics {
        var ocrRequests = 0
        var translationBatches = 0
        var discardedResults = 0
        var reusedTranslations = 0
        var sceneResets = 0
        var retainedFrames = 0
        var activeOCR = 0
        var activeTranslation = 0
        var maxActiveOCR = 0
        var maxActiveTranslation = 0
        var translationQueueWait = 0.0
    }
    private let analysis: FrameAnalysis
    private let translator: any TranslationEngine
    private let recognize: Recognizer
    private let now: @MainActor () -> Double
    private let automatic: Bool
    private var latest: CIImage?
    private var context: Context?
    private var records: [Record] = []
    private var ocrTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private(set) var scheduler = RegionalBackoff()
    private(set) var diagnostics = Diagnostics()
    private(set) var display: [DisplayTranslation] = []
    /// Completed reference translations survive local invalidation. Only the
    /// visibility mask is applied to the live overlay, PNG, and MP4 paths, not the reader.
    private(set) var referenceLayer: [DisplayTranslation] = []
    private(set) var displayMask = TranslationDisplayMask()
    var onDisplay: (([DisplayTranslation]) -> Void)?
    var onReading: (([ReadingSource], UInt64) -> Void)?
    var onStatus: ((String) -> Void)?
    var onLatency: ((Double) -> Void)?
    var recordCount: Int { records.count }

    init(translator: any TranslationEngine, analysis: FrameAnalysis = FrameAnalysis(),
         automatic: Bool = true, now: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime },
         recognize: Recognizer? = nil) {
        self.translator = translator; self.analysis = analysis
        self.automatic = automatic; self.now = now
        let ocr = OCRService()
        self.recognize = recognize ?? { image, source, languages in
            try await ocr.recognize(image, source: source, languages: languages)
        }
    }
    func reset() {
        scheduler.reset(); context = nil; latest = nil; records = []
        diagnostics.retainedFrames = 0
        ocrTask?.cancel(); translationTask?.cancel(); translator.cancel()
        publish()
    }
    func receive(_ image: CIImage, context nextContext: Context, fingerprint: FrameFingerprint? = nil) {
        if let context, context != nextContext { reset() }
        context = nextContext
        latest = image; diagnostics.retainedFrames = 1
        if scheduler.observe(fingerprint ?? analysis.fingerprint(image), at: now()) {
            records = []; diagnostics.sceneResets += 1
            // Broad scene replacement is a global invalidation, unlike a local animation.
            translator.cancel()
        }
        var hidden = false
        for index in records.indices {
            if !valid(records[index]) {
                hidden = hidden || records[index].visible
                records[index].visible = false
                records[index].needsTranslation = false
            }
        }
        if hidden || records.isEmpty { publish() }
        startWorkers()
    }
    private func valid(_ record: Record) -> Bool {
        unchanged(record.block, since: record.generation, epoch: record.epoch)
    }
    private func unchanged(_ block: TextBlock, since generation: UInt64, epoch: UInt64) -> Bool {
        // The output covers the union, so newly appearing content between lines
        // must also hide the whole translated block, not be painted over.
        scheduler.unchanged(block.bounds, since: generation, epoch: epoch) &&
            block.sourceLines.allSatisfy { scheduler.unchanged($0.bounds, since: generation, epoch: epoch) }
    }
    private func sameParagraph(_ lhs: TextBlock, _ rhs: TextBlock) -> Bool {
        lhs.text.utf8.elementsEqual(rhs.text.utf8) && lhs.language == rhs.language &&
            lhs.sourceLines.count == rhs.sourceLines.count &&
            zip(lhs.sourceLines, rhs.sourceLines).allSatisfy { a, b in
                a.text.utf8.elementsEqual(b.text.utf8) && abs(a.bounds.minX - b.bounds.minX) <= 0.002 &&
                abs(a.bounds.minY - b.bounds.minY) <= 0.002 && abs(a.bounds.width - b.bounds.width) <= 0.002 &&
                abs(a.bounds.height - b.bounds.height) <= 0.002
            } &&
            abs(lhs.bounds.minX - rhs.bounds.minX) <= 0.002 &&
            abs(lhs.bounds.minY - rhs.bounds.minY) <= 0.002 &&
            abs(lhs.bounds.width - rhs.bounds.width) <= 0.002 &&
            abs(lhs.bounds.height - rhs.bounds.height) <= 0.002
    }
    private func publish() {
        referenceLayer = records.compactMap { record in
            record.translated.map { DisplayTranslation(block: record.block, text: $0, background: record.background) }
        }
        displayMask.hiddenIDs = Set(records.filter { !$0.visible || !valid($0) }.map { $0.block.id })
        display = displayMask.applying(to: referenceLayer)
        onDisplay?(display)
        onReading?(records.map { .init(block: $0.block, text: $0.translated, isCurrent: $0.visible && valid($0)) }, scheduler.epoch)
    }
    private func startWorkers() {
        guard automatic, context != nil else { return }
        if ocrTask == nil, scheduler.hasPending {
            ocrTask = Task { [weak self] in
                guard let self else { return }
                defer { ocrTask = nil; startWorkers() }
                while context != nil && scheduler.hasPending && !Task.isCancelled {
                    if !(await recognizeNext()) {
                        do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
                    }
                }
            }
        }
        if translationTask == nil, records.contains(where: { $0.needsTranslation && valid($0) }) {
            translationTask = Task { [weak self] in
                guard let self else { return }
                defer { translationTask = nil; startWorkers() }
                while !Task.isCancelled, await translateNext() { }
            }
        }
    }

    /// Explicit stepping is also used by tests with an injected monotonic clock.
    @discardableResult func recognizeNext() async -> Bool {
        guard diagnostics.activeOCR == 0, let context, let image = latest else { return false }
        let selected = scheduler.due(at: now())
        guard !selected.isEmpty, let cg = analysis.cgImage(image) else { return false }
        let generation = scheduler.generation, epoch = scheduler.epoch
        let observedAt = now()
        scheduler.dispatched(selected, at: observedAt)
        diagnostics.ocrRequests += 1; diagnostics.activeOCR += 1
        diagnostics.maxActiveOCR = max(diagnostics.maxActiveOCR, diagnostics.activeOCR)
        defer { diagnostics.activeOCR -= 1 }
        do {
            let blocks = try await recognize(cg, context.source, context.languages)
            guard scheduler.epoch == epoch, self.context == context, !Task.isCancelled else { return true }
            // Full-frame context avoids slicing a paragraph at a scheduling-grid boundary.
            let observed = blocks.filter { !scheduler.cells(intersecting: $0.bounds).isDisjoint(with: selected) }
            let previous = records
            records.removeAll { record in
                !scheduler.cells(intersecting: record.block.bounds).isDisjoint(with: selected) &&
                scheduler.canInspect(record.block.bounds, selected: selected) &&
                scheduler.unchanged(record.block.bounds, since: generation, epoch: epoch)
            }
            for block in observed {
                guard scheduler.canInspect(block.bounds, selected: selected) else { continue }
                let cells = scheduler.cells(intersecting: block.bounds)
                guard unchanged(block, since: generation, epoch: epoch) else {
                    diagnostics.discardedResults += 1; scheduler.retry(cells, at: now(), sourceChanged: true); continue
                }
                guard Self.accepts(block, in: context), let language = block.language else { continue }
                let old = previous.first { sameParagraph($0.block, block) }
                let (r, g, b) = analysis.background(image, normalized: block.bounds)
                let stableBlock = TextBlock(id: old?.block.id ?? block.id, text: block.text, bounds: block.bounds,
                                           language: language, confidence: block.confidence, sourceLines: block.sourceLines)
                // A new observation supersedes the old record; never accumulate queued versions.
                records.removeAll { $0.block.id == stableBlock.id }
                var record = Record(block: stableBlock, generation: generation, epoch: epoch,
                    translated: old?.translated, background: NSColor(srgbRed: r, green: g, blue: b, alpha: 1),
                    waitingSince: old?.waitingSince ?? observedAt, observedAt: observedAt)
                if record.translated != nil {
                    record.visible = true; record.needsTranslation = false
                    diagnostics.reusedTranslations += 1
                }
                records.append(record)
            }
            scheduler.checked(selected, submitted: generation, at: now())
            publish()
            if records.isEmpty { onStatus?(L10n.text("No text to translate.")) }
            startWorkers()
        } catch {
            if scheduler.epoch == epoch, !Task.isCancelled {
                scheduler.retry(selected, at: now()); onStatus?(error.localizedDescription)
            }
        }
        return true
    }

    @discardableResult func translateNext() async -> Bool {
        guard diagnostics.activeTranslation == 0, let context else { return false }
        let pending = records.filter { $0.needsTranslation && valid($0) && Self.accepts($0.block, in: context) }.sorted {
            if $0.waitingSince != $1.waitingSince { return $0.waitingSince < $1.waitingSince }
            return $0.block.id.uuidString < $1.block.id.uuidString
        }
        guard !pending.isEmpty else { return false }
        
        let translationSource = pending.first?.block.language
        guard let language = translationSource else { return false }
        
        let batch = Array(pending.filter { $0.block.language == language }.prefix(4))
        for record in batch {
            if let index = records.firstIndex(where: { $0.block.id == record.block.id }) { records[index].needsTranslation = false }
            diagnostics.translationQueueWait = max(diagnostics.translationQueueWait, now() - record.waitingSince)
        }
        let epoch = scheduler.epoch
        diagnostics.activeTranslation += 1
        diagnostics.maxActiveTranslation = max(diagnostics.maxActiveTranslation, diagnostics.activeTranslation)
        defer { diagnostics.activeTranslation -= 1 }
        do {
            guard await translator.availability(source: language, target: context.target) == .installed else { throw PipelineError.languageNotReady }
            guard epoch == scheduler.epoch, self.context == context, !Task.isCancelled else { return true }
            let current = batch.filter(valid)
            for stale in batch where !valid(stale) {
                diagnostics.discardedResults += 1
                scheduler.retry(scheduler.cells(intersecting: stale.block.bounds), at: now(), sourceChanged: true)
            }
            guard !current.isEmpty else { return true }
            diagnostics.translationBatches += 1
            onStatus?(L10n.text("Translating areas: %1$@…", String(describing: current.count)))
            let outputs = try await translator.translate(current.map {
                TranslationInput(id: $0.block.id, text: $0.block.translationText, source: language, target: context.target)
            })
            guard epoch == scheduler.epoch, self.context == context, !Task.isCancelled else { return true }
            for record in current {
                guard valid(record), let index = records.firstIndex(where: {
                    $0.block.id == record.block.id && sameParagraph($0.block, record.block) && valid($0)
                }) else {
                    diagnostics.discardedResults += 1
                    scheduler.retry(scheduler.cells(intersecting: record.block.bounds), at: now(), sourceChanged: true)
                    continue
                }
                guard let output = outputs.first(where: { $0.id == record.block.id }) else {
                    scheduler.retry(scheduler.cells(intersecting: record.block.bounds), at: now()); continue
                }
                records[index].translated = output.text; records[index].visible = true
                records[index].needsTranslation = false
                scheduler.settled(record.block.bounds, submitted: record.generation, at: now())
                onLatency?(now() - record.observedAt)
            }
            publish()
            onStatus?(L10n.text("Translated areas: %1$@ · On device", String(describing: display.count)))
        } catch {
            if epoch == scheduler.epoch, !Task.isCancelled {
                // Missing packs need user action, not a background polling loop.
                if !(error is PipelineError) {
                    for record in batch { scheduler.retry(scheduler.cells(intersecting: record.block.bounds), at: now()) }
                }
                onStatus?(error.localizedDescription)
            }
        }
        return true
    }

    static func accepts(_ block: TextBlock, in context: Context) -> Bool {
        guard let language = block.language, block.confidence >= 0.3,
              !language.isSameLanguage(as: context.target) else { return false }
        return context.source.map { language.isSameLanguage(as: $0) } ?? true
    }
}

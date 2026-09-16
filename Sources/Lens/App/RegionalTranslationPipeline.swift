import AppKit
import CoreImage
import Combine

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
        var ocrProcessingTime = 0.0
        var translationProcessingTime = 0.0
    }
    private let analysis: FrameAnalysis
    private let translator: any TranslationEngine
    private let recognize: Recognizer
    private let now: @MainActor () -> Double
    private let automatic: Bool
    private var latest: CIImage?
    private var context: Context?
    private var records: [Record] = []
    private struct RecordingRequest {
        let block: TextBlock
        let observationID: UUID
        let contextID: UInt64
    }
    private struct FrameStamp {
        let id: UInt64
        let contextID: UInt64
        let capturedAt: Double
        let pointSize: CGSize
    }
    private var recordingPending: [RecordingRequest] = []
    private var frameStamp: FrameStamp?
    private var hardGeneration: UInt64 = 0
    private var recordingActive = false
    var onRecordingObservation: ((RecordingObservation) -> Void)?
    var onRecordingTranslation: ((RecordingTranslation) -> Void)?
    private var ocrTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    typealias WakeScheduler = @MainActor (Double, @escaping @MainActor @Sendable () -> Void) -> AnyCancellable
    private let scheduleWake: WakeScheduler
    private var ocrWake: AnyCancellable?
    private var wakeDeadline: Double?
    private var wakeGeneration: UInt64 = 0
    private var retryNotBefore = -Double.infinity
    private var publishedReading: [ReadingSource] = []
    private var publishedEpoch: UInt64?
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
         recognize: Recognizer? = nil, scheduleWake: WakeScheduler? = nil) {
        self.translator = translator; self.analysis = analysis
        self.automatic = automatic; self.now = now
        self.scheduleWake = scheduleWake ?? { delay, action in
            let task = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                action()
            }
            return AnyCancellable { task.cancel() }
        }
        let ocr = OCRService()
        self.recognize = recognize ?? { image, source, languages in
            try await ocr.recognize(image, source: source, languages: languages)
        }
    }
    func reset() {
        hardGeneration &+= 1
        recordingPending = []; frameStamp = nil
        cancelWake(); retryNotBefore = -.infinity
        scheduler.reset(); context = nil; latest = nil; records = []
        diagnostics.retainedFrames = 0
        ocrTask?.cancel(); translationTask?.cancel(); translator.cancel()
        publish()
    }
    func setRecordingActive(_ active: Bool) {
        guard active != recordingActive else { return }
        recordingActive = active; recordingPending = []
        if active {
            // Seed the worker from a new, exact OCR observation even on an idle screen.
            scheduler.retry(Set(0..<(RegionalBackoff.columns * RegionalBackoff.rows)), at: now(), sourceChanged: true)
            startWorkers()
        }
    }
    func setResponsiveness(_ value: TranslationResponsiveness) {
        guard scheduler.responsiveness != value else { return }
        scheduler.responsiveness = value
        // Replace only the inspection wake, never valid results or active services.
        cancelWake()
        startWorkers()
    }
    func receive(_ image: CIImage, context nextContext: Context, fingerprint: FrameFingerprint? = nil,
                 recordingFrame: RecordingFrame? = nil) {
        if let context, context != nextContext { reset() }
        context = nextContext
        frameStamp = recordingFrame.map { FrameStamp(id: $0.id, contextID: $0.contextID,
            capturedAt: $0.capturedAt, pointSize: $0.pointSize) }
        latest = image; diagnostics.retainedFrames = 1
        if scheduler.observe(fingerprint ?? analysis.fingerprint(image), at: now()) {
            records = []; diagnostics.sceneResets += 1
            // Broad scene replacement is a global invalidation, unlike a local animation.
            if !recordingActive { translator.cancel() }
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
        let nextDisplay = displayMask.applying(to: referenceLayer)
        if display != nextDisplay {
            display = nextDisplay
            onDisplay?(display)
        }
        let reading = records.map { ReadingSource(block: $0.block, text: $0.translated, isCurrent: $0.visible && valid($0)) }
        if publishedReading != reading || publishedEpoch != scheduler.epoch {
            publishedReading = reading; publishedEpoch = scheduler.epoch
            onReading?(reading, scheduler.epoch)
        }
    }
    private func cancelWake() {
        wakeGeneration &+= 1
        ocrWake?.cancel(); ocrWake = nil; wakeDeadline = nil
    }
    private func waitForOCR(until deadline: Double) {
        // Keep an earlier wake; a new quiet frame may pull a later wake forward.
        if let wakeDeadline, wakeDeadline <= deadline { return }
        cancelWake()
        let generation = wakeGeneration
        wakeDeadline = deadline
        ocrWake = scheduleWake(max(0, deadline - now())) { [weak self] in
            guard let self, wakeGeneration == generation else { return }
            cancelWake()
            startWorkers()
        }
    }
    private func startWorkers() {
        guard automatic, context != nil else { return }
        if ocrTask == nil, let due = scheduler.nextDeadline {
            let deadline = max(due, retryNotBefore)
            if deadline > now() + 0.000_001 {
                waitForOCR(until: deadline)
            } else {
                cancelWake()
                ocrTask = Task { [weak self] in
                    guard let self else { return }
                    defer { ocrTask = nil; startWorkers() }
                    guard !Task.isCancelled, context != nil else { return }
                    if !(await recognizeNext()), !Task.isCancelled {
                        // A failed image conversion must not create an immediate task loop.
                        retryNotBefore = now() + RegionalBackoff.intervals[0]
                    }
                }
            }
        }
        if translationTask == nil, records.contains(where: { $0.needsTranslation && valid($0) }) || !recordingPending.isEmpty {
            translationTask = Task { [weak self] in
                guard let self else { return }
                defer { translationTask = nil; startWorkers() }
                while !Task.isCancelled, await translateNext() { }
            }
        }
    }

    isolated deinit {
        ocrWake?.cancel()
        ocrTask?.cancel()
        translationTask?.cancel()
    }

    /// Explicit stepping is also used by tests with an injected monotonic clock.
    @discardableResult func recognizeNext() async -> Bool {
        guard diagnostics.activeOCR == 0, let context, let image = latest else { return false }
        let selected = scheduler.due(at: now())
        guard !selected.isEmpty, let cg = analysis.cgImage(image) else { return false }
        let generation = scheduler.generation, epoch = scheduler.epoch
        let hardGeneration = self.hardGeneration, stamp = frameStamp
        let observedAt = now()
        scheduler.dispatched(selected, at: observedAt)
        diagnostics.ocrRequests += 1; diagnostics.activeOCR += 1
        diagnostics.maxActiveOCR = max(diagnostics.maxActiveOCR, diagnostics.activeOCR)
        defer {
            diagnostics.activeOCR -= 1
            diagnostics.ocrProcessingTime = max(diagnostics.ocrProcessingTime, now() - observedAt)
        }
        do {
            let blocks = try await recognize(cg, context.source, context.languages)
            guard self.hardGeneration == hardGeneration, self.context == context, !Task.isCancelled else { return true }
            if recordingActive, let stamp {
                let id = UUID()
                let accepted = Array(blocks.filter { Self.accepts($0, in: context) }.prefix(32))
                onRecordingObservation?(.init(id: id, contextID: stamp.contextID, frameID: stamp.id,
                    capturedAt: stamp.capturedAt, image: cg, pointSize: stamp.pointSize,
                    blocks: accepted, target: context.target))
                // One latest observation, not a queue of obsolete OCR requests.
                recordingPending = accepted.map { .init(block: $0, observationID: id, contextID: stamp.contextID) }
                let cached = accepted.compactMap { block -> TranslationOutput? in
                    guard let text = records.first(where: { sameParagraph($0.block, block) })?.translated else { return nil }
                    return .init(id: block.id, text: text)
                }
                if !cached.isEmpty {
                    onRecordingTranslation?(.init(observationID: id, contextID: stamp.contextID, outputs: cached))
                    let completed = Set(cached.map(\.id))
                    recordingPending.removeAll { completed.contains($0.block.id) }
                }
                startWorkers()
            }
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
                    waitingSince: old.flatMap { $0.needsTranslation ? $0.waitingSince : nil } ?? observedAt, observedAt: observedAt)
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
        guard !pending.isEmpty else { return await translateRecordingNext(context: context) }
        
        let translationSource = pending.first?.block.language
        guard let language = translationSource else { return false }
        
        let batch = Array(pending.filter { $0.block.language == language }.prefix(4))
        let recordingRequests = recordingActive ? recordingPending.filter { request in
            batch.contains { sameParagraph($0.block, request.block) }
        } : []
        recordingPending.removeAll { request in recordingRequests.contains { $0.block.id == request.block.id && $0.observationID == request.observationID } }
        let hardGeneration = self.hardGeneration
        for record in batch {
            if let index = records.firstIndex(where: { $0.block.id == record.block.id }) { records[index].needsTranslation = false }
            diagnostics.translationQueueWait = max(diagnostics.translationQueueWait, now() - record.waitingSince)
        }
        let epoch = scheduler.epoch
        diagnostics.activeTranslation += 1
        let translationStartedAt = now()
        diagnostics.maxActiveTranslation = max(diagnostics.maxActiveTranslation, diagnostics.activeTranslation)
        defer {
            diagnostics.activeTranslation -= 1
            diagnostics.translationProcessingTime = max(diagnostics.translationProcessingTime, now() - translationStartedAt)
        }
        do {
            guard await translator.availability(source: language, target: context.target) == .installed else { throw PipelineError.languageNotReady }
            guard self.hardGeneration == hardGeneration, self.context == context, !Task.isCancelled else { return true }
            if epoch != scheduler.epoch && recordingRequests.isEmpty { return true }
            let current = batch.filter { record in
                valid(record) || recordingRequests.contains { sameParagraph($0.block, record.block) }
            }
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
            if self.hardGeneration == hardGeneration, self.context == context, !Task.isCancelled, recordingActive {
                for request in recordingRequests {
                    guard let record = current.first(where: { sameParagraph($0.block, request.block) }),
                          let output = outputs.first(where: { $0.id == record.block.id }) else { continue }
                    onRecordingTranslation?(.init(observationID: request.observationID, contextID: request.contextID,
                        outputs: [.init(id: request.block.id, text: output.text)]))
                }
            }
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

    /// Shares the same translation slot with the live overlay. A scroll can invalidate
    /// live coordinates without invalidating the exact source evidence held by the recorder.
    private func translateRecordingNext(context: Context) async -> Bool {
        guard recordingActive, let language = recordingPending.first?.block.language else { return false }
        let batch = Array(recordingPending.filter { $0.block.language == language }.prefix(4))
        let ids = Set(batch.map { $0.block.id })
        recordingPending.removeAll { ids.contains($0.block.id) }
        let generation = hardGeneration
        diagnostics.activeTranslation += 1
        diagnostics.maxActiveTranslation = max(diagnostics.maxActiveTranslation, diagnostics.activeTranslation)
        let started = now()
        defer {
            diagnostics.activeTranslation -= 1
            diagnostics.translationProcessingTime = max(diagnostics.translationProcessingTime, now() - started)
        }
        do {
            guard await translator.availability(source: language, target: context.target) == .installed else { return true }
            guard generation == hardGeneration, recordingActive, !Task.isCancelled else { return true }
            diagnostics.translationBatches += 1
            let outputs = try await translator.translate(batch.map {
                .init(id: $0.block.id, text: $0.block.translationText, source: language, target: context.target)
            })
            guard generation == hardGeneration, self.context == context, recordingActive, !Task.isCancelled else { return true }
            for request in batch {
                guard let output = outputs.first(where: { $0.id == request.block.id }) else { continue }
                onRecordingTranslation?(.init(observationID: request.observationID, contextID: request.contextID, outputs: [output]))
            }
        } catch {
            // The next observation may retry. Do not spin or retain obsolete input batches.
        }
        return true
    }

    static func accepts(_ block: TextBlock, in context: Context) -> Bool {
        guard let language = block.language, block.confidence >= 0.3,
              !language.isSameLanguage(as: context.target) else { return false }
        return context.source.map { language.isSameLanguage(as: $0) } ?? true
    }
}

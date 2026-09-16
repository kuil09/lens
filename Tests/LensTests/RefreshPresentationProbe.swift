import AppKit
import CoreImage
import Darwin
import Testing
@testable import Lens

@MainActor private final class RefreshProbeEngine: TranslationEngine {
    func availability(source: LensLanguage, target: LensLanguage) async -> LanguagePairStatus { .installed }
    func cancel() {}
    func translate(_ inputs: [TranslationInput]) async throws -> [TranslationOutput] {
        try await Task.sleep(for: .milliseconds(80))
        return inputs.map { .init(id: $0.id, text: "파일을 삭제하지 마세요. " + $0.text) }
    }
}

private func processCost() -> (cpu: Double, resident: Double) {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return (cpu, result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1)
}

/// Opt-in native presentation comparison, not an end-to-end OCR/Apple Translation benchmark.
/// Uses fixed 12 ms OCR and 80 ms translation doubles, no screen permission or user data.
@Test(.enabled(if: ProcessInfo.processInfo.environment["LENS_REFRESH_PRESENTATION_PROBE"] == "1"))
@MainActor func compareRefreshPresentationOnMac() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.regular)
    let area = CGRect(x: 80, y: 160, width: 800, height: 500)
    let window = NSWindow(contentRect: area, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.isMovable = false
    window.orderFrontRegardless()
    let initialFrame = window.frame
    let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
    let boxes = [CGRect(x: 0.06, y: 0.7, width: 0.65, height: 0.14),
                 CGRect(x: 0.78, y: 0.45, width: 0.18, height: 0.15),
                 CGRect(x: 0.06, y: 0.22, width: 0.65, height: 0.14)]
    let ids = boxes.map { _ in UUID() }
    for (name, profile, fade) in [("Current", TranslationResponsiveness.balanced, false),
                                   ("Fast", .fast, false), ("Fast + Reveal", .fast, true)] {
        let surface = NSView(frame: CGRect(origin: .zero, size: area.size))
        surface.wantsLayer = true; surface.layer?.backgroundColor = NSColor.white.cgColor
        let source = NSTextField(wrappingLabelWithString: "Synthetic screen • same 800 × 500pt area\nStatic paragraph / changing clock / numbers and negation\nNo real screen or translation content is logged.")
        source.frame = CGRect(x: 35, y: 10, width: 720, height: 75); surface.addSubview(source)
        let sourceLabels = boxes.map { box in
            let label = NSTextField(wrappingLabelWithString: "")
            label.frame = LensGeometry.localRect(box, size: area.size)
            label.font = .systemFont(ofSize: 18); label.textColor = .black
            surface.addSubview(label)
            return label
        }
        let overlay = TranslationOverlay(frame: surface.bounds)
        overlay.usesLiveTransitions = fade; surface.addSubview(overlay)
        window.contentView = surface; window.title = "Lens comparison — \(name)"
        window.orderFrontRegardless()
        var blocks: [TextBlock] = []
        let pipeline = RegionalTranslationPipeline(translator: RefreshProbeEngine(), recognize: { _, _, _ in
            let submitted = blocks
            try await Task.sleep(for: .milliseconds(12))
            return submitted
        })
        pipeline.setResponsiveness(profile)
        pipeline.onDisplay = { overlay.translations = $0 }
        let before = processCost(), started = ProcessInfo.processInfo.systemUptime
        var peak = before.resident
        for tick in 0..<900 {
            #expect(window.frame == initialFrame, "Discard a sample if its window geometry changes")
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - started
            // Dynamic clock stops for the final two seconds; body remains unchanged.
            let pulse = tick < 840 ? (tick / 3) % 2 : 0
            let brief = tick >= 180 && tick < 186 ? 1 : 0
            blocks = boxes.enumerated().map { index, box in
                let text = index == 0 ? "Keep this static paragraph. Do not delete 12 files." :
                    index == 1 ? "Clock \(pulse)" : "Do not delete \(12 + brief) files."
                return TextBlock(id: ids[index], text: text, bounds: box, language: .english, confidence: 1)
            }
            for (label, block) in zip(sourceLabels, blocks) { label.stringValue = block.text }
            var bytes = Array(repeating: UInt8(255), count: 128 * 80 * 4)
            bytes[(40 * 128 + 112) * 4] = pulse == 0 ? 255 : 0
            bytes[(24 * 128 + 20) * 4] = brief == 0 ? 255 : 0
            pipeline.receive(image, context: .init(source: .english, target: .korean, languages: [.english]), fingerprint: .init(bytes: bytes))
            peak = max(peak, processCost().resident)
            if tick.isMultiple(of: 300) { print("Presentation probe \(name): \(Int(elapsed))s") }
            if tick == 60 {
                let bitmap = try #require(surface.bitmapImageRepForCachingDisplay(in: surface.bounds))
                surface.cacheDisplay(in: surface.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Lens-refresh-\(name.replacingOccurrences(of: " ", with: "-")).png"))
            }
            try await Task.sleep(for: .seconds(max(0, started + Double(tick + 1) / 30 - ProcessInfo.processInfo.systemUptime)))
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started, after = processCost()
        #expect(window.frame == initialFrame, "Moved-window sample must not be used for performance claims")
        #expect(pipeline.diagnostics.maxActiveOCR <= 1 && pipeline.diagnostics.maxActiveTranslation <= 1 && pipeline.diagnostics.retainedFrames == 1)
        print("Presentation probe RESULT \(name): seconds=\(elapsed), cpuPercent=\((after.cpu-before.cpu)/elapsed*100), rssStartMiB=\(before.resident), rssEndMiB=\(after.resident), peakMiB=\(peak), ocr=\(pipeline.diagnostics.ocrRequests), batches=\(pipeline.diagnostics.translationBatches), ocrMax=\(pipeline.diagnostics.ocrProcessingTime), translationMax=\(pipeline.diagnostics.translationProcessingTime), saturation=\(pipeline.scheduler.saturationWait), queue=\(pipeline.diagnostics.translationQueueWait)")
        pipeline.reset()
    }
}

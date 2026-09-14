import AppKit
import Combine

@MainActor
final class LensRecording: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var message = "화면과 번역을 무음 MP4로 저장합니다."
    var onStateChange: (() -> Void)?
    var onError: ((String) -> Void)?
    private var writer: LensVideoWriter?
    private var ticker: Task<Void, Never>?
    private var finalization: Task<Void, Never>?
    private var startedAt: Double = 0

    var durationText: String {
        let seconds = Int(elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func start(destination: URL, firstFrame: CGImage, frame: @escaping @MainActor () -> CGImage?) throws {
        guard !isRecording, !isFinishing else { return }
        writer = try LensVideoWriter(destination: destination, width: firstFrame.width, height: firstFrame.height)
        startedAt = ProcessInfo.processInfo.systemUptime
        elapsed = 0
        isRecording = true
        message = "녹화 중 · \(destination.lastPathComponent)"
        onStateChange?()
        do { try writer?.append(firstFrame, seconds: 0) }
        catch { stop(); throw error }
        // Sample the latest composed scene even if ScreenCaptureKit reports an idle desktop.
        // One task, no frame queue, and no catch-up loop after a delayed tick.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(67)) } catch { return }
                guard let self, isRecording, let writer else { return }
                elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                do {
                    if let failure = writer.failure { throw failure }
                    if writer.ready {
                        guard let image = frame() else { stop(); return }
                        try writer.append(image, seconds: elapsed)
                    }
                } catch {
                    stop()
                    onError?("녹화가 중지되었습니다. \(error.localizedDescription)")
                    return
                }
            }
        }
    }

    @discardableResult
    func stop() -> Task<Void, Never>? {
        guard isRecording, let writer else { return finalization }
        elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        ticker?.cancel(); ticker = nil
        isRecording = false; isFinishing = true
        message = "동영상 저장 중…"
        onStateChange?()
        let duration = elapsed
        finalization = Task { [self] in
            do {
                try await writer.finish(seconds: duration)
                message = "동영상 저장 완료 · \(durationText)"
            } catch {
                message = "동영상을 저장하지 못했습니다."
                var detail = error.localizedDescription
                if FileManager.default.fileExists(atPath: writer.temporaryURL.path) {
                    detail += "\n복구용 임시 파일: \(writer.temporaryURL.path)"
                }
                onError?(detail)
            }
            self.writer = nil
            isFinishing = false; finalization = nil
            onStateChange?()
        }
        return finalization
    }
}

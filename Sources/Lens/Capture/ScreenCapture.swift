import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage

/// Pixel buffers are retained, read-only after delivery from ScreenCaptureKit.
struct CapturedFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let version: UInt64
    let capturedAt: Double
}

@MainActor
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let access = ScreenRecordingAccess()
    private var stream: SCStream?
    private var regionVersion: UInt64 = 0
    private var requestSerial: UInt64 = 0
    var onFrame: ((CapturedFrame) -> Void)?
    var onFailure: ((String) -> Void)?

    func start(globalRect: CGRect, screen: NSScreen, version: UInt64) async throws {
        requestSerial &+= 1
        let request = requestSerial
        let old = stream
        stream = nil
        try? await old?.stopCapture()
        guard request == requestSerial, !Task.isCancelled else { throw CancellationError() }
        guard access.isGranted else { throw CaptureError.permissionRequired }
        regionVersion = version
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard request == requestSerial, !Task.isCancelled else { throw CancellationError() }
        guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == screenID.uint32Value }) else {
            throw CaptureError.displayUnavailable
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = LensGeometry.captureRect(global: globalRect, display: screen.frame)
        let pixelSize = LensGeometry.pixels(points: globalRect.size, scale: screen.backingScaleFactor)
        config.width = max(1, Int(pixelSize.width)); config.height = max(1, Int(pixelSize.height))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.colorSpaceName = CGColorSpace.sRGB
        let next = SCStream(filter: filter, configuration: config, delegate: self)
        try next.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        stream = next
        do {
            try await next.startCapture()
            guard request == requestSerial, !Task.isCancelled else {
                try? await next.stopCapture()
                throw CancellationError()
            }
        } catch { if stream === next { stream = nil }; throw error }
    }

    func stop() async {
        requestSerial &+= 1
        let old = stream
        stream = nil
        try? await old?.stopCapture()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let identity = ObjectIdentifier(stream)
        let delivered = CapturedFrame(buffer: buffer, version: 0, capturedAt: time)
        // The stream output is explicitly registered on DispatchQueue.main.
        MainActor.assumeIsolated {
            guard self.stream.map(ObjectIdentifier.init) == identity else { return }
            onFrame?(CapturedFrame(buffer: delivered.buffer, version: regionVersion, capturedAt: delivered.capturedAt))
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let description = error.localizedDescription
        let identity = ObjectIdentifier(stream)
        Task { @MainActor in
            guard self.stream.map(ObjectIdentifier.init) == identity else { return }
            self.stream = nil
            self.onFailure?(description)
        }
    }
}

enum CaptureError: LocalizedError {
    case displayUnavailable
    case permissionRequired
    var errorDescription: String? {
        switch self {
        case .displayUnavailable: "디스플레이를 찾을 수 없습니다. 렌즈를 화면 안으로 이동한 뒤 다시 시작하세요."
        case .permissionRequired: "현재 빌드의 화면 기록 권한이 필요합니다. ‘화면 권한 확인’을 눌러 주세요. 이미 허용했다면 Lens를 종료 후 다시 여세요."
        }
    }
}

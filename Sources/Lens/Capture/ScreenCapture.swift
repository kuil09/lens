import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage

/// Pixel buffers are retained, read-only after delivery from ScreenCaptureKit.
struct CapturedFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let version: UInt64
    let capturedAt: Double
    var id: UInt64 = 0
}

/// Display notifications can change unrelated desktop configuration. Only the inputs
/// that define this stream's pixels require invalidating its recording coordinate space.
struct CaptureLayout: Equatable {
    let displayID: UInt32
    let displayFrame: CGRect
    let globalRect: CGRect
    let scale: CGFloat

    @MainActor init?(globalRect: CGRect, screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        self.init(displayID: number.uint32Value, displayFrame: screen.frame,
                  globalRect: globalRect, scale: screen.backingScaleFactor)
    }

    init(displayID: UInt32, displayFrame: CGRect, globalRect: CGRect, scale: CGFloat) {
        self.displayID = displayID; self.displayFrame = displayFrame
        self.globalRect = globalRect; self.scale = scale
    }
}

@MainActor
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let access = ScreenRecordingAccess()
    private var stream: SCStream?
    private var regionVersion: UInt64 = 0
    private var requestSerial: UInt64 = 0
    private var frameSerial: UInt64 = 0
    private(set) var activeLayout: CaptureLayout?
    var onFrame: ((CapturedFrame) -> Void)?
    var onFailure: ((String) -> Void)?

    func start(globalRect: CGRect, screen: NSScreen, version: UInt64) async throws {
        requestSerial &+= 1
        let request = requestSerial
        let old = stream
        stream = nil
        activeLayout = nil
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
            activeLayout = CaptureLayout(globalRect: globalRect, screen: screen)
        } catch { if stream === next { stream = nil }; throw error }
    }

    func stop() async {
        requestSerial &+= 1
        let old = stream
        stream = nil
        activeLayout = nil
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
            frameSerial &+= 1
            onFrame?(CapturedFrame(buffer: delivered.buffer, version: regionVersion, capturedAt: delivered.capturedAt, id: frameSerial))
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let description = error.localizedDescription
        let identity = ObjectIdentifier(stream)
        Task { @MainActor in
            guard self.stream.map(ObjectIdentifier.init) == identity else { return }
            self.stream = nil
            self.activeLayout = nil
            self.onFailure?(description)
        }
    }
}

enum CaptureError: LocalizedError {
    case displayUnavailable
    case permissionRequired
    var errorDescription: String? {
        switch self {
        case .displayUnavailable: L10n.text("Display not found. Move the lens onto a display and start again.")
        case .permissionRequired: L10n.text("Screen Recording access is required")
        }
    }
}

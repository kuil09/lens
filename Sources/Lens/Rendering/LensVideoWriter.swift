import AppKit
@preconcurrency import AVFoundation

/// AVAssetWriter encodes asynchronously. All submissions are serialized on MainActor;
/// backpressure drops frames rather than queuing screenshots in memory.
@MainActor
final class LensVideoWriter {
    let width: Int
    let height: Int
    let temporaryURL: URL
    private let destination: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var lastTime: CMTime?
    private var finishing = false

    init(destination: URL, width: Int, height: Int) throws {
        guard width >= 2, height >= 2 else { throw VideoError.invalidSize }
        // H.264 needs even dimensions. At most one pixel is rescaled at each edge.
        self.width = width - width % 2
        self.height = height - height % 2
        self.destination = destination
        temporaryURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".Lens-recording-\(UUID().uuidString).mp4")
        writer = try AVAssetWriter(outputURL: temporaryURL, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: self.width, AVVideoHeightKey: self.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(20_000_000, max(1_000_000, self.width * self.height * 4)),
                AVVideoExpectedSourceFrameRateKey: 15,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: self.width,
                kCVPixelBufferHeightKey as String: self.height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
        guard writer.canAdd(input) else { throw VideoError.encoding(L10n.text("The H.264 encoder is unavailable.")) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoError.encoding(L10n.text("Could not start recording.")) }
        writer.startSession(atSourceTime: .zero)
    }

    var ready: Bool { !finishing && input.isReadyForMoreMediaData }
    var failure: Error? { writer.status == .failed ? writer.error ?? VideoError.encoding(L10n.text("The encoder stopped.")) : nil }

    @discardableResult
    func append(_ image: CGImage, seconds: Double) throws -> Bool {
        if let failure { throw failure }
        guard seconds.isFinite, seconds >= 0, !finishing else { return false }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard lastTime.map({ time > $0 }) ?? true, ready,
              let pool = adaptor.pixelBufferPool else { return false }
        var optionalBuffer: CVPixelBuffer?
        // A fixed pool ceiling prevents slow encoders from retaining unlimited frames.
        let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 4] as CFDictionary
        let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, attributes, &optionalBuffer)
        if result == kCVReturnWouldExceedAllocationThreshold { return false }
        guard result == kCVReturnSuccess, let buffer = optionalBuffer else { throw VideoError.encoding(L10n.text("Could not create a video buffer.")) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw VideoError.encoding(L10n.text("Could not render the video frame.")) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw writer.error ?? VideoError.encoding(L10n.text("Could not write the video frame."))
        }
        lastTime = time
        return true
    }

    @discardableResult func finish(seconds: Double) async throws -> URL {
        guard !finishing else { throw VideoError.encoding(L10n.text("Already saving.")) }
        finishing = true
        if let failure { throw failure }
        guard let lastTime else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw VideoError.encoding(L10n.text("There are no video frames to save."))
        }
        let end = max(CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                      lastTime + CMTime(value: 1, timescale: 15))
        writer.endSession(atSourceTime: end)
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? VideoError.encoding(L10n.text("Could not finish saving the video."))
        }
        return try LensExportFiles.publish(temporaryURL, to: destination)
    }
}

enum VideoError: LocalizedError {
    case invalidSize
    case encoding(String)
    var errorDescription: String? {
        switch self {
        case .invalidSize: L10n.text("The recording size is invalid.")
        case .encoding(let message): message
        }
    }
}

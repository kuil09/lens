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
        guard writer.canAdd(input) else { throw VideoError.encoding("H.264 인코더를 사용할 수 없습니다.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoError.encoding("녹화를 시작하지 못했습니다.") }
        writer.startSession(atSourceTime: .zero)
    }

    var ready: Bool { !finishing && input.isReadyForMoreMediaData }
    var failure: Error? { writer.status == .failed ? writer.error ?? VideoError.encoding("인코더가 중지되었습니다.") : nil }

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
        guard result == kCVReturnSuccess, let buffer = optionalBuffer else { throw VideoError.encoding("영상 버퍼를 만들지 못했습니다.") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw VideoError.encoding("영상 프레임을 그리지 못했습니다.") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw writer.error ?? VideoError.encoding("영상 프레임을 기록하지 못했습니다.")
        }
        lastTime = time
        return true
    }

    func finish(seconds: Double) async throws {
        guard !finishing else { throw VideoError.encoding("이미 저장 중입니다.") }
        finishing = true
        if let failure { throw failure }
        guard let lastTime else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw VideoError.encoding("저장할 영상 프레임이 없습니다.")
        }
        let end = max(CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                      lastTime + CMTime(value: 1, timescale: 15))
        writer.endSession(atSourceTime: end)
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? VideoError.encoding("영상 저장을 마치지 못했습니다.")
        }
        // The destination is untouched until a complete MP4 exists. NSSavePanel confirms overwrites.
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        }
    }
}

enum VideoError: LocalizedError {
    case invalidSize
    case encoding(String)
    var errorDescription: String? {
        switch self {
        case .invalidSize: "녹화할 화면 크기가 올바르지 않습니다."
        case .encoding(let message): message
        }
    }
}

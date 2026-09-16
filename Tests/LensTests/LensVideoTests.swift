import AppKit
@preconcurrency import AVFoundation
import Testing
@testable import Lens

@MainActor private func videoTestImage() throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 162, height: 102,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: 162, height: 102))
    let block = TextBlock(id: UUID(), text: "Source", bounds: CGRect(x: 0.2, y: 0.6, width: 0.6, height: 0.3),
                          language: .english, confidence: 1)
    let background = try #require(context.makeImage())
    return try #require(LensSnapshot.image(background: background,
        pointSize: CGSize(width: 162, height: 102),
        translations: [DisplayTranslation(block: block, text: "", background: .white)], maskOpacity: 1))
}

@MainActor private func videoTestDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("LensVideoTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

@Test @MainActor func videoEncodesSilentMP4WithCorrectDurationOrientationAndOverlay() async throws {
    let directory = try videoTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("test.mp4")
    // Existing content must survive until the complete recording is finalized.
    let original = Data("existing destination".utf8)
    try original.write(to: destination)
    let writer = try LensVideoWriter(destination: destination, width: 163, height: 103)
    #expect(writer.width == 162 && writer.height == 102)
    let image = try videoTestImage()
    #expect(try writer.append(image, seconds: 0))
    #expect(try !writer.append(image, seconds: 0))
    #expect(try !writer.append(image, seconds: -1))
    #expect(try !writer.append(image, seconds: .nan))
    #expect(try Data(contentsOf: destination) == original)
    // The final static frame must last until stop, not end at the last capture callback.
    let saved = try await writer.finish(seconds: 1.2)
    #expect(saved != destination)
    #expect(try Data(contentsOf: destination) == original)
    #expect(!FileManager.default.fileExists(atPath: writer.temporaryURL.path))
    let asset = AVURLAsset(url: saved)
    let tracks = try await asset.load(.tracks)
    #expect(tracks.count == 1)
    let track = try #require(tracks.first)
    #expect(track.mediaType == .video)
    let size = try await track.load(.naturalSize)
    #expect(size == CGSize(width: 162, height: 102))
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 1.2) < 0.08)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    #expect(reader.startReading())
    let sample = try #require(output.copyNextSampleBuffer())
    let pixels = try #require(CMSampleBufferGetImageBuffer(sample))
    CVPixelBufferLockBaseAddress(pixels, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
    let bytes = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixels)
    // The white translated mask is near the top, not vertically flipped to the bottom.
    let top = 25 * stride + 81 * 4
    let bottom = 80 * stride + 81 * 4
    #expect(bytes[top] > 220 && bytes[top + 1] > 220 && bytes[top + 2] > 220)
    #expect(bytes[bottom] < 35 && bytes[bottom + 1] < 35 && bytes[bottom + 2] > 220)
    reader.cancelReading()
}

@Test @MainActor func recordingRepeatsIdleFramesAndFinalizesOnceOnRegionInvalidation() async throws {
    let directory = try videoTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("idle.mp4")
    let image = try videoTestImage()
    let recording = LensRecording()
    let model = LensModel()
    var failures: [String] = []
    recording.onError = { failures.append($0) }
    model.onRegionInvalidated = { recording.stop() }
    try recording.start(destination: destination, firstFrame: image, frame: { image })
    #expect(recording.isRecording)
    try await Task.sleep(for: .milliseconds(320))
    model.invalidate()
    let stoppedAt = recording.elapsed
    #expect(!recording.isRecording && recording.isFinishing)
    // Repeated stop, pause, or quit must share the pending finalization.
    let finish = try #require(recording.stop())
    await finish.value
    #expect(!recording.isFinishing && failures.isEmpty)
    #expect(recording.stop() == nil)
    let asset = AVURLAsset(url: destination)
    let duration = try await asset.load(.duration).seconds
    // Task.sleep is a lower bound; a loaded CI main actor can resume much later.
    // Validate the encoded duration against the actual stop time, not scheduler speed.
    #expect(duration >= 0.30 && abs(duration - stoppedAt) < 0.15)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    #expect(reader.startReading())
    var frames = 0
    while output.copyNextSampleBuffer() != nil { frames += 1 }
    #expect(frames >= 2)
}

@Test @MainActor func emptyRecordingDoesNotReplaceDestination() async throws {
    let directory = try videoTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("keep.mp4")
    let original = Data("keep this".utf8)
    try original.write(to: destination)
    let writer = try LensVideoWriter(destination: destination, width: 160, height: 100)
    await #expect(throws: (any Error).self) { try await writer.finish(seconds: 0) }
    #expect(try Data(contentsOf: destination) == original)
    #expect(!FileManager.default.fileExists(atPath: writer.temporaryURL.path))
}

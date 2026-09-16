import Foundation
import CoreGraphics
import CoreVideo

/// Buffers are immutable while shared. The recording worker copies incoming capture buffers
/// into its own bounded storage rather than retaining ScreenCaptureKit's pool as a delay queue.
struct RecordingFrame: @unchecked Sendable {
    let id: UInt64
    let contextID: UInt64
    let capturedAt: Double
    let buffer: CVPixelBuffer
    let pointSize: CGSize
    let opacity: Double
    var dirtyRects: [CGRect]? = nil
}

/// Exact image and source blocks from one OCR operation; not a later live screenshot.
struct RecordingObservation: @unchecked Sendable {
    let id: UUID
    let contextID: UInt64
    let frameID: UInt64
    let capturedAt: Double
    let image: CGImage
    let pointSize: CGSize
    let blocks: [TextBlock]
    let target: LensLanguage
}

struct RecordingTranslation: Sendable {
    let observationID: UUID
    let contextID: UInt64
    let outputs: [TranslationOutput]
}

struct RecordingBlock: Sendable {
    let id: UUID
    let source: TextBlock
    let text: String
    /// sRGB components, independent of AppKit/main-actor color objects.
    let background: [Double]
}

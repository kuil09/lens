import AppKit
@testable import Lens

/// Test-only experiment. Not linked into the app or enabled in default recording.
/// Canonical RGBA rows are top-down; source bounds remain Vision lower-left coordinates.
struct ScrollRaster {
    let width: Int
    let height: Int
    let bytes: Data
    var cost: Int { bytes.count }

    init?(image: CGImage) {
        guard image.width > 0, image.height > 0, image.width <= 4096, image.height <= 4096,
              image.width * image.height * 4 <= 24 * 1_048_576 else { return nil }
        width = image.width; height = image.height
        var data = Data(count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { pixels -> Bool in
            guard let context = CGContext(data: pixels.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        bytes = data
    }
    func image() -> CGImage? {
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

private struct ScrollPatch {
    let x: Int, y: Int, width: Int, height: Int
    let bytes: Data
    let anchorX: Int, anchorY: Int
    let anchorLength: Int

    init?(raster: ScrollRaster, bounds: CGRect, pointSize: CGSize) {
        guard pointSize.width > 0, pointSize.height > 0, bounds.minX.isFinite, bounds.maxX.isFinite,
              bounds.minY.isFinite, bounds.maxY.isFinite, bounds.width > 0, bounds.height > 0,
              CGRect(x: 0, y: 0, width: 1, height: 1).contains(bounds) else { return nil }
        // Include the entire export cover, plus one physical guard pixel.
        let paddingX = Int(ceil(2 * Double(raster.width) / pointSize.width)) + 1
        let paddingY = Int(ceil(2 * Double(raster.height) / pointSize.height)) + 1
        let x = Int(floor(bounds.minX * Double(raster.width))) - paddingX
        let y = Int(floor((1 - bounds.maxY) * Double(raster.height))) - paddingY
        let width = Int(ceil(bounds.maxX * Double(raster.width))) + paddingX - x
        let height = Int(ceil((1 - bounds.minY) * Double(raster.height))) + paddingY - y
        guard x >= 0, y >= 0, width >= 8, height >= 4,
              x + width <= raster.width, y + height <= raster.height else { return nil }
        var patch = Data(count: width * height * 4)
        patch.withUnsafeMutableBytes { destination in
            raster.bytes.withUnsafeBytes { source in
                for row in 0..<height {
                    memcpy(destination.baseAddress!.advanced(by: row * width * 4),
                           source.baseAddress!.advanced(by: ((y + row) * raster.width + x) * 4), width * 4)
                }
            }
        }
        // Flat perimeter is a conservative supported-domain check, not an OCR claim.
        let background = Array(patch.prefix(4))
        func differs(_ px: Int, _ py: Int) -> Bool {
            let offset = (py * width + px) * 4
            return (0..<4).contains { patch[offset + $0] != background[$0] }
        }
        guard (0..<width).allSatisfy({ !differs($0, 0) && !differs($0, height - 1) }),
              (0..<height).allSatisfy({ !differs(0, $0) && !differs(width - 1, $0) }) else { return nil }
        var strongest = 0, selectedY = 0, selectedX = 0
        for row in 1..<(height - 1) {
            var count = 0, first: Int?
            for column in 1..<(width - 1) where differs(column, row) {
                count += 1; if first == nil { first = column }
            }
            if count > strongest { strongest = count; selectedY = row; selectedX = first ?? 0 }
        }
        guard strongest >= 3 else { return nil } // Blank or almost featureless patches are ambiguous.
        self.x = x; self.y = y; self.width = width; self.height = height
        anchorX = min(selectedX, width - 8); anchorY = selectedY; anchorLength = min(32, (width - anchorX) * 4)
        bytes = patch
    }

    /// Search all vertical positions, rejecting duplicates even at the original position.
    /// Every pixel in the cover must match. No tolerance for changed digits/negation.
    func uniqueY(in raster: ScrollRaster, remainingWork: inout Int) -> Int? {
        guard width + x <= raster.width, height <= raster.height else { return nil }
        var found: Int?
        return raster.bytes.withUnsafeBytes { frame in
            bytes.withUnsafeBytes { patch in
                for candidate in 0...(raster.height - height) {
                    guard remainingWork >= anchorLength else { return nil }
                    remainingWork -= anchorLength
                    let anchor = ((candidate + anchorY) * raster.width + x + anchorX) * 4
                    guard memcmp(frame.baseAddress!.advanced(by: anchor),
                                 patch.baseAddress!.advanced(by: (anchorY * width + anchorX) * 4), anchorLength) == 0 else { continue }
                    var exact = true
                    for row in 0..<height {
                        guard remainingWork >= width * 4 else { return nil }
                        remainingWork -= width * 4
                        if memcmp(frame.baseAddress!.advanced(by: ((candidate + row) * raster.width + x) * 4),
                                  patch.baseAddress!.advanced(by: row * width * 4), width * 4) != 0 { exact = false; break }
                    }
                    if exact {
                        guard found == nil else { return nil }
                        found = candidate
                    }
                }
                return found
            }
        }
    }
}

@MainActor final class ScrollRecordingExperiment {
    struct Limits {
        var wait = 0.8
        var frames = 12
        var frameBytes = 96 * 1_048_576
        var references = 32
        var referenceBytes = 16 * 1_048_576
        var comparedBytesPerFrame = 8 * 1_048_576
    }
    struct Frame {
        let id: Int
        let timestamp: Double
        let epoch: UInt64
        let raster: ScrollRaster
        let pointSize: CGSize
        // The experiment supplies its known clipping viewport. Production must establish it safely.
        let scrollBounds: CGRect
        var opacity: CGFloat = 1
    }
    struct Output {
        let id: Int
        let timestamp: Double
        let image: CGImage
        let translations: [DisplayTranslation]
    }
    struct Stats {
        var emitted = 0, rejectedResults = 0, rejectedFrames = 0
        var peakFrames = 0, peakFrameBytes = 0, peakReferenceBytes = 0
        var maxComparedBytes = 0
        var maxMatchSeconds = 0.0
    }
    private struct Reference {
        let item: DisplayTranslation
        let patch: ScrollPatch
        let epoch: UInt64
        let width: Int, height: Int
        let pointSize: CGSize
        let scrollBounds: CGRect
        let belongsToScroll: Bool
        var cost: Int { patch.bytes.count + item.text.utf8.count + item.block.text.utf8.count }
    }
    let limits: Limits
    private var pending: [Frame] = []
    private var references: [Reference] = []
    private var lastTimestamp = -Double.infinity
    private var lastID = -1
    private var epoch: UInt64?
    private var previousSize: CGSize?
    private var previousPointSize: CGSize?
    private var processing = false
    private var cancellation: UInt64 = 0
    private(set) var stats = Stats()
    var frameCount: Int { pending.count }
    var frameBytes: Int { pending.reduce(0) { $0 + $1.raster.cost } }
    var referenceBytes: Int { references.reduce(0) { $0 + $1.cost } }
    init(limits: Limits = Limits()) { self.limits = limits }

    /// Emit one frame at a time. Caller owns one serial encoder worker.
    /// A full/expired buffer falls back to proven matches or original pixels, never old positions.
    func append(_ frame: Frame, at now: Double, emit: (Output) async throws -> Void) async rethrows {
        guard !processing else { stats.rejectedFrames += 1; return }
        processing = true
        defer { processing = false }
        let token = cancellation
        guard frame.timestamp.isFinite, now.isFinite, frame.timestamp <= now,
              frame.timestamp > lastTimestamp, frame.id > lastID,
              frame.raster.cost <= limits.frameBytes, limits.frames > 0 else {
            stats.rejectedFrames += 1; return
        }
        let size = CGSize(width: frame.raster.width, height: frame.raster.height)
        if epoch != frame.epoch || previousSize != size || previousPointSize != frame.pointSize {
            // Flush the previous scene before clearing its evidence; never retime it.
            try await drain(at: now, force: true, emit: emit)
            references.removeAll()
            epoch = frame.epoch; previousSize = size; previousPointSize = frame.pointSize
        }
        try await drain(at: now, emit: emit)
        while !pending.isEmpty && (pending.count >= limits.frames || frameBytes + frame.raster.cost > limits.frameBytes) {
            try await emitFirst(emit)
        }
        guard token == cancellation else { return }
        pending.append(frame); lastTimestamp = frame.timestamp; lastID = frame.id
        stats.peakFrames = max(stats.peakFrames, pending.count)
        stats.peakFrameBytes = max(stats.peakFrameBytes, frameBytes)
    }
    func learn(_ item: DisplayTranslation, observedFrameID: Int, epoch: UInt64) {
        // A result without its retained exact source frame cannot establish pixel correspondence.
        guard let frame = pending.first(where: { $0.id == observedFrameID && $0.epoch == epoch }),
              item.text.utf8.count <= 16_384, item.block.text.utf8.count <= 16_384,
              let patch = ScrollPatch(raster: frame.raster, bounds: item.block.bounds, pointSize: frame.pointSize) else {
            stats.rejectedResults += 1; return
        }
        let reference = Reference(item: item, patch: patch, epoch: epoch, width: frame.raster.width,
                                  height: frame.raster.height, pointSize: frame.pointSize, scrollBounds: frame.scrollBounds,
                                  belongsToScroll: frame.scrollBounds.contains(item.block.bounds))
        guard reference.cost <= limits.referenceBytes, limits.references > 0 else { stats.rejectedResults += 1; return }
        // Retain one visual observation per exact source/version, not every raster rounding variant.
        references.removeAll { $0.item.id == item.id && $0.item.block.text == item.block.text }
        while !references.isEmpty && (references.count >= limits.references || referenceBytes + reference.cost > limits.referenceBytes) {
            references.removeFirst()
        }
        references.append(reference)
        stats.peakReferenceBytes = max(stats.peakReferenceBytes, referenceBytes)
    }
    func flush(at now: Double, force: Bool = false, emit: (Output) async throws -> Void) async rethrows {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        try await drain(at: now, force: force, emit: emit)
    }
    private func drain(at now: Double, force: Bool, emit: (Output) async throws -> Void) async rethrows {
        while let first = pending.first, force || now - first.timestamp >= limits.wait { try await emitFirst(emit) }
    }
    private func drain(at now: Double, emit: (Output) async throws -> Void) async rethrows {
        try await drain(at: now, force: false, emit: emit)
    }
    private func emitFirst(_ emit: (Output) async throws -> Void) async rethrows {
        let frame = pending.removeFirst()
        let began = ProcessInfo.processInfo.systemUptime
        var work = limits.comparedBytesPerFrame
        var mapped: [DisplayTranslation] = []
        for reference in references where reference.epoch == frame.epoch && reference.width == frame.raster.width &&
            reference.height == frame.raster.height && reference.pointSize == frame.pointSize && reference.scrollBounds == frame.scrollBounds {
            guard let row = reference.patch.uniqueY(in: frame.raster, remainingWork: &work) else { continue }
            let dy = Double(reference.patch.y - row) / Double(frame.raster.height)
            let old = reference.item.block
            let bounds = old.bounds.offsetBy(dx: 0, dy: dy)
            // Matching ink alone does not prove that a larger cover stays inside the scroll viewport.
            if reference.belongsToScroll && !frame.scrollBounds.contains(bounds.insetBy(
                dx: -2 / frame.pointSize.width, dy: -2 / frame.pointSize.height)) { continue }
            if !reference.belongsToScroll && row != reference.patch.y { continue }
            let moved = TextBlock(id: old.id, text: old.text, bounds: bounds,
                language: old.language, confidence: old.confidence,
                sourceLines: old.sourceLines.map { .init(text: $0.text, bounds: $0.bounds.offsetBy(dx: 0, dy: dy)) })
            mapped.append(.init(block: moved, text: reference.item.text, background: reference.item.background))
        }
        // Conflicting evidence must not paint overlapping translations.
        let safe = mapped.enumerated().filter { index, item in
            !mapped.enumerated().contains { $0.offset != index && $0.element.block.bounds.intersects(item.block.bounds) }
        }.map(\.element)
        stats.maxComparedBytes = max(stats.maxComparedBytes, limits.comparedBytesPerFrame - work)
        stats.maxMatchSeconds = max(stats.maxMatchSeconds, ProcessInfo.processInfo.systemUptime - began)
        let image = autoreleasepool { () -> CGImage? in
            guard let background = frame.raster.image() else { return nil }
            return LensSnapshot.image(background: background, pointSize: frame.pointSize, translations: safe, maskOpacity: frame.opacity)
        }
        if let image {
            stats.emitted += 1
            try await emit(.init(id: frame.id, timestamp: frame.timestamp, image: image, translations: safe))
        }
    }
    func cancel() { cancellation &+= 1; pending.removeAll(); references.removeAll(); epoch = nil }
}

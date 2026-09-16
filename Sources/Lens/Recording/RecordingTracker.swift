import Foundation
import CoreGraphics
import CoreVideo
import Vision

/// Exclusively owned by the serial recording worker. No actors, tasks, or frame queue.
/// Only detached source crops and reduced images survive observe/map calls.
final class RecordingTracker {
    struct Diagnostics {
        var recordCount = 0
        var pendingCount = 0
        /// Conservatively charged bytes, including a reserved result for every pending crop.
        var evidenceBytes = 0
        var peakEvidenceBytes = 0
        var peakRecordCount = 0
        var rejectedObservations = 0
        var rejectedGeometry = 0
        var rejectedSurface = 0
        var rejectedTranslations = 0
        var resolvedRecords = 0
        var mapCalls = 0
        var incompatibleComparisons = 0
        var samePositionMatches = 0
        var movedMatches = 0
        var unmatchedComparisons = 0
        var deduplicatedMatches = 0
        var geometryDeduplicatedMatches = 0
        var overlapRejections = 0
        var mappedBlocks = 0
        var evictedCompleted = 0
        var evictedPending = 0
        var registrationRequests = 0
        var registrationCacheHits = 0
        var registrationFailures = 0
        var lastRegistrationError: String?
        var lastDisplacement: CGSize?
        var maxRegistrationsPerFrame = 0
        var maxComparedBytesPerFrame = 0
    }

    private static let byteLimit = 16 * 1_048_576
    private static let thumbnailLimit = 320 * 320 * 4
    // Reserve space for a thumbnail under construction and the current map thumbnail.
    private static let retainedLimit = byteLimit - 2 * thumbnailLimit
    private static let resultLimit = 16_384
    private static let comparisonLimit = 32 * 1_048_576
    private static let registrationLimit = 4
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let bitmapInfo = CGBitmapInfo(rawValue:
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

    private struct Raster {
        let width: Int
        let height: Int
        let bytes: Data

        static func draw(_ image: CGImage, width: Int, height: Int) -> Raster? {
            var bytes = Data(count: width * height * 4)
            let success = bytes.withUnsafeMutableBytes { pixels -> Bool in
                guard let context = CGContext(data: pixels.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: RecordingTracker.colorSpace,
                    bitmapInfo: RecordingTracker.bitmapInfo.rawValue) else { return false }
                context.interpolationQuality = .none
                context.setBlendMode(.copy)
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            return success ? Raster(width: width, height: height, bytes: bytes) : nil
        }

        static func thumbnail(_ image: CGImage) -> Raster? {
            let scale = min(1, 320 / Double(max(image.width, image.height)))
            return draw(image, width: max(1, Int(Double(image.width) * scale)),
                        height: max(1, Int(Double(image.height) * scale)))
        }

        func image() -> CGImage? {
            guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: RecordingTracker.colorSpace,
                bitmapInfo: RecordingTracker.bitmapInfo, provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    private struct Patch {
        let rect: CGRect // Integral top-down pixel coordinates, including cover and guard.
        let raster: Raster
        let background: [Double]
        let anchor: Int
        /// Exact extent of every non-background pixel, in full-image top-down coordinates.
        let inkBounds: CGRect

        static func rectangle(_ block: TextBlock, image: CGImage, pointSize: CGSize) -> CGRect? {
            let bounds = block.bounds
            guard RecordingTracker.valid(bounds), !block.sourceLines.isEmpty,
                  block.sourceLines.allSatisfy({ RecordingTracker.valid($0.bounds) && bounds.contains($0.bounds) })
            else { return nil }
            // TranslationLayout uses two points of cover padding. Two additional physical
            // pixels must also match, including at the destination, to reject clipped covers.
            let px = ceil(2 * Double(image.width) / pointSize.width) + 2
            let py = ceil(2 * Double(image.height) / pointSize.height) + 2
            let x = floor(bounds.minX * Double(image.width)) - px
            let y = floor((1 - bounds.maxY) * Double(image.height)) - py
            let rect = CGRect(x: x, y: y,
                width: ceil(bounds.maxX * Double(image.width)) + px - x,
                height: ceil((1 - bounds.minY) * Double(image.height)) + py - y)
            guard rect.width >= 8, rect.height >= 4,
                  CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(rect) else { return nil }
            return rect
        }

        init?(image: CGImage, rect: CGRect) {
            guard let crop = image.cropping(to: rect),
                  let raster = Raster.draw(crop, width: Int(rect.width), height: Int(rect.height)) else { return nil }
            // Rendering the crop into new Data severs any CGImage subimage/backing-store link.
            let bytes = raster.bytes, width = raster.width, height = raster.height
            let color = Array(bytes.prefix(4))
            func differs(_ x: Int, _ y: Int) -> Bool {
                let i = (y * width + x) * 4
                return (0..<4).contains { bytes[i + $0] != color[$0] }
            }
            guard color[3] == 255,
                  (0..<width).allSatisfy({ !differs($0, 0) && !differs($0, height - 1) }),
                  (0..<height).allSatisfy({ !differs(0, $0) && !differs(width - 1, $0) }) else { return nil }
            var ink = 0, first: Int?
            var minX = width, minY = height, maxX = 0, maxY = 0
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) where differs(x, y) {
                    ink += 1
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                    if first == nil { first = (y * width + x) * 4 }
                }
            }
            guard ink >= 3, let first else { return nil }
            self.rect = rect; self.raster = raster; anchor = first
            inkBounds = CGRect(x: Int(rect.minX) + minX, y: Int(rect.minY) + minY,
                               width: maxX - minX + 1, height: maxY - minY + 1)
            background = [Double(color[2]) / 255, Double(color[1]) / 255, Double(color[0]) / 255, 1]
        }

        func matches(_ pixels: UnsafeRawPointer, stride: Int, width: Int, height: Int,
                     dx: Int, dy: Int, work: inout Int) -> Bool {
            let x = Int(rect.minX) + dx, y = Int(rect.minY) + dy
            guard x >= 0, y >= 0, x + raster.width <= width, y + raster.height <= height,
                  work >= 4 else { return false }
            return raster.bytes.withUnsafeBytes { source in
                let ax = (anchor / 4) % raster.width, ay = (anchor / 4) / raster.width
                work -= 4
                guard memcmp(pixels.advanced(by: (y + ay) * stride + (x + ax) * 4),
                             source.baseAddress!.advanced(by: anchor), 4) == 0 else { return false }
                for row in 0..<raster.height {
                    let count = raster.width * 4
                    guard work >= count else { return false }
                    work -= count
                    guard memcmp(pixels.advanced(by: (y + row) * stride + x * 4),
                                 source.baseAddress!.advanced(by: row * count), count) == 0 else { return false }
                }
                return true
            }
        }
    }

    private struct Record {
        let observationID: UUID
        let contextID: UInt64
        let source: TextBlock
        let width: Int
        let height: Int
        let pointSize: CGSize
        let patch: Patch
        let thumbnail: Raster
        let cost: Int
        var text: String?
    }

    private struct Motion {
        let dx: Int
        let dy: Int
        // 4x4 cells: 0 unknown/mixed, 1 flat, 2 moving, 3 static.
        let cells: [Int]

        func supports(_ rect: CGRect, width: Int, height: Int) -> Bool {
            var moving = false
            for row in 0..<4 {
                for column in 0..<4 {
                    let cell = CGRect(x: Double(column * width) / 4, y: Double(row * height) / 4,
                                      width: Double(width) / 4, height: Double(height) / 4)
                    guard cell.intersects(rect) else { continue }
                    let state = cells[row * 4 + column]
                    guard state == 1 || state == 2 else { return false }
                    moving = moving || state == 2
                }
            }
            return moving
        }
    }

    private var records: [Record] = []
    private struct Registration { let motion: Motion? }
    // One destination thumbnail and at most 32 tiny source->destination proposals. Cache
    // validity is byte equality, never frame ordering; exact full-resolution checks still run.
    private var cachedDestination: Raster?
    private var cachedRegistrations: [UUID: Registration] = [:]
    private(set) var diagnostics = Diagnostics()

    init() {}

    func observe(_ observation: RecordingObservation) {
        autoreleasepool {
            guard Self.valid(observation.pointSize), observation.capturedAt.isFinite,
                  observation.image.width <= 16_384, observation.image.height <= 16_384,
                  !records.contains(where: { $0.observationID == observation.id }) else {
                diagnostics.rejectedObservations += 1; return
            }
            guard let thumbnail = Raster.thumbnail(observation.image) else { return }
            for block in observation.blocks.prefix(32) {
                guard block.text.utf8.count <= Self.resultLimit, block.sourceLines.count <= 64
                else { diagnostics.rejectedObservations += 1; continue }
                guard let rect = Patch.rectangle(block, image: observation.image, pointSize: observation.pointSize) else {
                    diagnostics.rejectedGeometry += 1; diagnostics.rejectedObservations += 1; continue
                }
                let strings = block.text.utf8.count + block.sourceLines.reduce(0) { $0 + $1.text.utf8.count }
                // Charge each record for its thumbnail even when Data shares a backing store.
                let cost = Int(rect.width * rect.height) * 4 + thumbnail.bytes.count + strings +
                    Self.resultLimit + 512 + block.sourceLines.count * 128
                guard strings <= 2 * Self.resultLimit, cost <= Self.retainedLimit else {
                    diagnostics.rejectedObservations += 1; continue
                }
                makeRoom(for: cost)
                diagnostics.peakEvidenceBytes = max(diagnostics.peakEvidenceBytes,
                    diagnostics.evidenceBytes + cost + 2 * Self.thumbnailLimit)
                guard let patch = Patch(image: observation.image, rect: rect) else {
                    diagnostics.rejectedSurface += 1; diagnostics.rejectedObservations += 1; continue
                }
                records.append(Record(observationID: observation.id, contextID: observation.contextID,
                    source: block, width: observation.image.width, height: observation.image.height,
                    pointSize: observation.pointSize, patch: patch, thumbnail: thumbnail, cost: cost))
                updateCounts()
            }
            diagnostics.rejectedObservations += max(0, observation.blocks.count - 32)
        }
    }

    /// An observation UUID is the source version. Block UUIDs alone never resolve evidence.
    /// Completed records are emitted by map only after checking the destination pixels.
    func resolve(_ translation: RecordingTranslation) {
        guard translation.outputs.count <= 32 else { diagnostics.rejectedTranslations += 1; return }
        var resolved = false
        for output in translation.outputs.prefix(32) {
            guard !output.text.isEmpty, output.text.utf8.count <= Self.resultLimit,
                  translation.outputs.lazy.filter({ $0.id == output.id }).prefix(2).count == 1,
                  let index = records.firstIndex(where: {
                      $0.observationID == translation.observationID && $0.contextID == translation.contextID &&
                      $0.source.id == output.id && $0.text == nil
                  }) else { diagnostics.rejectedTranslations += 1; continue }
            records[index].text = output.text
            diagnostics.resolvedRecords += 1
            resolved = true
        }
        if !resolved && translation.outputs.isEmpty { diagnostics.rejectedTranslations += 1 }
        updateCounts()
    }

    func map(_ frame: RecordingFrame) -> [RecordingBlock] {
        diagnostics.mapCalls += 1
        let blocks = autoreleasepool { mapPixels(frame) }
        diagnostics.mappedBlocks += blocks.count
        return blocks
    }

    private func mapPixels(_ frame: RecordingFrame) -> [RecordingBlock] {
        guard Self.valid(frame.pointSize), frame.capturedAt.isFinite,
              CVPixelBufferGetPixelFormatType(frame.buffer) == kCVPixelFormatType_32BGRA,
              !CVPixelBufferIsPlanar(frame.buffer),
              CVPixelBufferLockBaseAddress(frame.buffer, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(frame.buffer, .readOnly) }
        guard let pixels = CVPixelBufferGetBaseAddress(frame.buffer) else { return [] }
        let width = CVPixelBufferGetWidth(frame.buffer), height = CVPixelBufferGetHeight(frame.buffer)
        let stride = CVPixelBufferGetBytesPerRow(frame.buffer)
        guard width > 0, height > 0, width <= 16_384, height <= 16_384, stride >= width * 4 else { return [] }
        var thumbnail: Raster?
        var motions: [UUID: Motion] = [:]
        var attempted = Set<UUID>()
        var registrations = 0, work = Self.comparisonLimit
        var mapped: [RecordingBlock] = []
        var mappedInk: [CGRect] = []
        // Recent evidence gets first use of the bounded registration/byte work budget.
        for record in records.reversed() {
            guard let text = record.text else { continue }
            guard record.contextID == frame.contextID && record.width == width &&
                record.height == height && record.pointSize == frame.pointSize else {
                diagnostics.incompatibleComparisons += 1; continue
            }
            let same = record.patch.matches(pixels, stride: stride, width: width, height: height,
                                            dx: 0, dy: 0, work: &work)
            var offset: (Int, Int)? = same ? (0, 0) : nil
            if !same && !attempted.contains(record.observationID) {
                attempted.insert(record.observationID)
                if thumbnail == nil {
                    // Borrow the locked buffer only for this draw. The provider never owns it.
                    if let provider = CGDataProvider(dataInfo: nil, data: pixels, size: stride * height,
                                                    releaseData: { _, _, _ in }),
                       let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: stride, space: Self.colorSpace, bitmapInfo: Self.bitmapInfo,
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
                        thumbnail = Raster.thumbnail(image)
                        diagnostics.peakEvidenceBytes = max(diagnostics.peakEvidenceBytes,
                            diagnostics.evidenceBytes + (thumbnail?.bytes.count ?? 0) +
                            (cachedDestination?.bytes.count ?? 0))
                        if cachedDestination?.width != thumbnail?.width || cachedDestination?.height != thumbnail?.height ||
                            cachedDestination?.bytes != thumbnail?.bytes {
                            cachedRegistrations.removeAll(keepingCapacity: true)
                            cachedDestination = thumbnail
                        }
                    }
                }
                if let thumbnail {
                    if let cached = cachedRegistrations[record.observationID] {
                        motions[record.observationID] = cached.motion
                        diagnostics.registrationCacheHits += 1
                    } else if record.thumbnail.bytes == thumbnail.bytes {
                        cachedRegistrations[record.observationID] = Registration(motion: nil)
                    } else if registrations < Self.registrationLimit {
                        registrations += 1
                        let motion = register(record.thumbnail, to: thumbnail, width: width, height: height)
                        motions[record.observationID] = motion
                        cachedRegistrations[record.observationID] = Registration(motion: motion)
                    }
                }
            }
            if !same, let motion = motions[record.observationID],
               motion.supports(record.patch.rect, width: width, height: height) {
                // Vision is a proposal only. A fixed 5x5 integer neighborhood absorbs reduced
                // registration rounding; never scan the full-resolution frame in two dimensions.
                var matches: [(Int, Int)] = []
                for dy in (motion.dy - 2)...(motion.dy + 2) {
                    for dx in (motion.dx - 2)...(motion.dx + 2) {
                        guard abs(dx) <= width / 4, abs(dy) <= height / 4,
                              motion.supports(record.patch.rect.offsetBy(dx: Double(dx), dy: Double(dy)), width: width, height: height),
                              record.patch.matches(pixels, stride: stride, width: width, height: height,
                                                   dx: dx, dy: dy, work: &work) else { continue }
                        matches.append((dx, dy))
                    }
                }
                if matches.count == 1 && work > 0 { offset = matches[0] }
            }
            guard let offset else { diagnostics.unmatchedComparisons += 1; continue }
            if same { diagnostics.samePositionMatches += 1 } else { diagnostics.movedMatches += 1 }
            let dx = Double(offset.0) / Double(width), dy = -Double(offset.1) / Double(height)
            let old = record.source
            let source = TextBlock(id: old.id, text: old.text, bounds: old.bounds.offsetBy(dx: dx, dy: dy),
                language: old.language, confidence: old.confidence,
                sourceLines: old.sourceLines.map { SourceLine(text: $0.text, bounds: $0.bounds.offsetBy(dx: dx, dy: dy)) })
            let block = RecordingBlock(id: old.id, source: source, text: text, background: record.patch.background)
            let ink = record.patch.inkBounds.offsetBy(dx: Double(offset.0), dy: Double(offset.1))
            // OCR boxes may move in their blank margins between observations. Both complete
            // crops already matched the destination byte-for-byte. If their background and
            // full ink extent coincide, each contains the SAME destination pixels throughout
            // that extent and only background outside it. This is exact evidence, not an IoU,
            // coordinate tolerance, or text similarity test. Keep the newest safe cover.
            if let duplicate = mapped.indices.first(where: { index in
                let existing = mapped[index]
                return mappedInk[index] == ink && existing.background == block.background &&
                    existing.source.text == block.source.text && existing.source.language == block.source.language &&
                    existing.source.sourceLines.elementsEqual(block.source.sourceLines, by: { $0.text == $1.text }) &&
                    existing.text == block.text
            }) {
                diagnostics.deduplicatedMatches += 1
                if mapped[duplicate].source.bounds != block.source.bounds ||
                    mapped[duplicate].source.sourceLines != block.source.sourceLines {
                    diagnostics.geometryDeduplicatedMatches += 1
                }
            } else {
                mapped.append(block); mappedInk.append(ink)
            }
        }
        diagnostics.registrationRequests += registrations
        diagnostics.maxRegistrationsPerFrame = max(diagnostics.maxRegistrationsPerFrame, registrations)
        diagnostics.maxComparedBytesPerFrame = max(diagnostics.maxComparedBytesPerFrame, Self.comparisonLimit - work)
        // Conflicting versions and overlapping covers cannot be composited safely.
        let safe = mapped.enumerated().filter { index, item in
            let cover = item.source.bounds.insetBy(dx: -2 / frame.pointSize.width, dy: -2 / frame.pointSize.height)
            return !mapped.enumerated().contains { other, value in
                other != index && (value.id == item.id || cover.intersects(value.source.bounds.insetBy(
                    dx: -2 / frame.pointSize.width, dy: -2 / frame.pointSize.height)))
            }
        }.map(\.element)
        diagnostics.overlapRejections += mapped.count - safe.count
        return safe
    }

    private func register(_ source: Raster, to destination: Raster, width: Int, height: Int) -> Motion? {
        guard source.width == destination.width, source.height == destination.height,
              let from = source.image(), let to = destination.image() else { return nil }
        // A fixed central sample reduces stationary window chrome's influence. It is only a
        // registration proposal, not a supplied/inferred scroll viewport. The full-image grid
        // and full-resolution source/cover still decide which blocks may actually move.
        let sample = CGRect(x: source.width / 8, y: source.height / 6,
                            width: source.width * 3 / 4, height: source.height * 2 / 3)
        guard let floating = from.cropping(to: sample), let reference = to.cropping(to: sample) else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: floating, options: [:])
        do { try VNImageRequestHandler(cgImage: reference, options: [:]).perform([request]) }
        catch {
            diagnostics.registrationFailures += 1
            let error = error as NSError
            diagnostics.lastRegistrationError = "\(error.domain):\(error.code)"
            return nil
        }
        guard let transform = request.results?.first?.alignmentTransform,
              transform.tx.isFinite, transform.ty.isFinite else { return nil }
        // Vision maps the floating source into the destination in lower-left coordinates.
        let dx = transform.tx * Double(width) / Double(source.width)
        let dy = -transform.ty * Double(height) / Double(source.height)
        diagnostics.lastDisplacement = CGSize(width: dx, height: dy)
        guard abs(dx) <= Double(width) * 0.25, abs(dy) <= Double(height) * 0.25,
              abs(dx) + abs(dy) >= 0.5 else { return nil }
        let sx = Int(transform.tx.rounded()), sy = Int(-transform.ty.rounded())
        var cells = [Int](repeating: 0, count: 16)
        for row in 0..<4 {
            for column in 0..<4 {
                var still = 0, moved = 0, count = 0, low = 255, high = 0
                var clipped = false
                // Fixed grid with bounded samples, independent of the full image resolution.
                for y in stride(from: row * source.height / 4, to: (row + 1) * source.height / 4, by: 2) {
                    for x in stride(from: column * source.width / 4, to: (column + 1) * source.width / 4, by: 2) {
                        let tx = x + sx, ty = y + sy
                        guard tx >= 0, ty >= 0, tx < source.width, ty < source.height else { clipped = true; continue }
                        let a = (y * source.width + x) * 4, b = (ty * source.width + tx) * 4
                        for channel in 0..<3 {
                            let value = Int(source.bytes[a + channel])
                            low = min(low, value); high = max(high, value)
                            still += abs(value - Int(destination.bytes[a + channel]))
                            moved += abs(value - Int(destination.bytes[b + channel]))
                            count += 1
                        }
                    }
                }
                guard count > 0, !clipped else { continue }
                if high - low < 8 && still <= count * 2 && moved <= count * 2 { cells[row * 4 + column] = 1 }
                else if moved <= count * 12 && moved * 2 < still { cells[row * 4 + column] = 2 }
                else if still <= count * 2 && still * 2 < moved { cells[row * 4 + column] = 3 }
            }
        }
        guard cells.contains(2) else { return nil }
        return Motion(dx: Int(dx.rounded()), dy: Int(dy.rounded()), cells: cells)
    }

    private func makeRoom(for cost: Int) {
        while !records.isEmpty && (records.count >= 32 || diagnostics.evidenceBytes + cost > Self.retainedLimit) {
            if let completed = records.firstIndex(where: { $0.text != nil }) {
                records.remove(at: completed); diagnostics.evictedCompleted += 1
            } else { records.removeFirst(); diagnostics.evictedPending += 1 }
            updateCounts()
        }
    }

    private func updateCounts() {
        diagnostics.recordCount = records.count
        diagnostics.pendingCount = records.lazy.filter { $0.text == nil }.count
        diagnostics.evidenceBytes = records.reduce(0) { $0 + $1.cost }
        diagnostics.peakRecordCount = max(diagnostics.peakRecordCount, records.count)
        diagnostics.peakEvidenceBytes = max(diagnostics.peakEvidenceBytes, diagnostics.evidenceBytes)
        let active = Set(records.map(\.observationID))
        cachedRegistrations = cachedRegistrations.filter { active.contains($0.key) }
    }

    func reset() {
        records.removeAll(keepingCapacity: false)
        cachedDestination = nil
        cachedRegistrations.removeAll(keepingCapacity: false)
        diagnostics = Diagnostics()
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite &&
        rect.width > 0 && rect.height > 0 && CGRect(x: 0, y: 0, width: 1, height: 1).contains(rect)
    }
}

import Foundation
import CoreGraphics

/// The grid schedules shared OCR observations; it never crops paragraphs.
/// All times are monotonic seconds supplied by the caller.
struct RegionalBackoff {
    static let width = 128, height = 80, columns = 8, rows = 5
    static let intervals = [0.25, 0.5, 1.0, 2.0]
    static let quietPeriod = 0.12
    var responsiveness: TranslationResponsiveness = .balanced
    struct Region {
        var level = 0
        var dirtySince: Double?
        var changedAt = -Double.infinity
        var lastAttempt = -Double.infinity
        var lastEscalation = -Double.infinity
        var revision: UInt64 = 0
        var attempts = 0
        var allowEarlyCheck = true
        func interval(for responsiveness: TranslationResponsiveness) -> Double { responsiveness.intervals[level] }
        func deadline(_ responsiveness: TranslationResponsiveness) -> Double? {
            guard let dirtySince else { return nil }
            // Changes do not keep pushing this deadline into the future.
            let paced = max(dirtySince, lastAttempt) + responsiveness.intervals[level]
            return allowEarlyCheck ? min(paced, changedAt + RegionalBackoff.quietPeriod) : paced
        }
    }
    private(set) var regions = Array(repeating: Region(), count: columns * rows)
    private(set) var generation: UInt64 = 0
    private(set) var epoch: UInt64 = 0
    private(set) var pixels = Array(repeating: UInt64(0), count: width * height)
    private var reference: [UInt8]?
    private var lastBroadChangeAt = -Double.infinity
    private(set) var lastOCR = -Double.infinity
    private(set) var saturationWait = 0.0
    private(set) var lastChangedPixels = 0

    mutating func reset() {
        epoch &+= 1
        reference = nil
        lastBroadChangeAt = -Double.infinity
        regions = Array(repeating: Region(), count: Self.columns * Self.rows)
        pixels = Array(repeating: generation, count: Self.width * Self.height)
        // Do not reset lastOCR: rapid scene changes cannot bypass the global budget.
    }

    /// Returns true for a conservative broad scene transition, not an animation classification.
    @discardableResult mutating func observe(_ frame: FrameFingerprint, at now: Double) -> Bool {
        guard frame.bytes.count == Self.width * Self.height * 4 else { return false }
        generation &+= 1
        guard var previous = reference else {
            reference = frame.bytes
            pixels = Array(repeating: generation, count: pixels.count)
            for index in regions.indices {
                regions[index].dirtySince = now
                regions[index].changedAt = now
                regions[index].lastEscalation = now
                regions[index].revision = generation
            }
            return false
        }
        var changed: Set<Int> = []
        var count = 0
        for index in pixels.indices {
            let offset = index * 4
            let delta = (0..<3).reduce(0) { $0 + abs(Int(frame.bytes[offset + $1]) - Int(previous[offset + $1])) }
            guard delta > 24 else { continue }
            count += 1
            pixels[index] = generation
            changed.insert((index / Self.width / 16) * Self.columns + (index % Self.width / 16))
            for channel in 0..<4 { previous[offset + channel] = frame.bytes[offset + channel] }
        }
        lastChangedPixels = count
        reference = previous // Accumulate slow fades against the last significant pixel value.
        let broadPixels = changed.count >= 24 && count >= Self.width * Self.height / 25
        let broad = broadPixels && now - lastBroadChangeAt > Self.intervals[0]
        if broadPixels { lastBroadChangeAt = now }
        if broad {
            epoch &+= 1
            regions = Array(repeating: Region(), count: regions.count)
            for index in regions.indices {
                regions[index].dirtySince = now
                regions[index].changedAt = now
                regions[index].lastEscalation = now
                regions[index].revision = generation
            }
            return true
        }
        for index in changed {
            if regions[index].dirtySince != nil { escalate(index, at: now) }
            else { regions[index].dirtySince = now; regions[index].lastEscalation = now }
            regions[index].changedAt = now
            regions[index].revision = generation
            regions[index].allowEarlyCheck = true
        }
        return false
    }

    private mutating func escalate(_ index: Int, at now: Double) {
        guard now - regions[index].lastEscalation >= responsiveness.escalationPeriod - 0.000_001 else { return }
        regions[index].level = min(3, regions[index].level + 1)
        regions[index].lastEscalation = now
    }
    mutating func retry(_ indices: Set<Int>, at now: Double, sourceChanged: Bool = false) {
        for index in indices {
            if regions[index].dirtySince == nil { regions[index].dirtySince = now }
            escalate(index, at: now)
            // Stale replies are not new pixel changes. Preserve the last observed
            // change time so an already quiet source can recover before the cap.
            // Service errors instead remain paced to avoid an immediate retry loop.
            if !sourceChanged { regions[index].changedAt = now }
            regions[index].allowEarlyCheck = sourceChanged
        }
    }
    var hasPending: Bool { regions.contains { $0.dirtySince != nil } }
    var nextDeadline: Double? {
        var earliest: Double?
        for region in regions {
            if let deadline = region.deadline(responsiveness) { earliest = min(earliest ?? deadline, deadline) }
        }
        return earliest.map { max($0, lastOCR + Self.intervals[0]) }
    }
    func due(at now: Double) -> Set<Int> {
        guard now + 0.000_001 >= lastOCR + Self.intervals[0] else { return [] }
        // All due cells share one full-frame request; no region can be displaced by another.
        return Set(regions.indices.filter { regions[$0].deadline(responsiveness).map { now + 0.000_001 >= $0 } ?? false })
    }
    mutating func dispatched(_ indices: Set<Int>, at now: Double) {
        let budgetAvailableAt = lastOCR + Self.intervals[0]
        lastOCR = now
        for index in indices {
            if let deadline = regions[index].deadline(responsiveness) {
                saturationWait = max(saturationWait, max(0, now - max(deadline, budgetAvailableAt)))
            }
            regions[index].lastAttempt = now
            regions[index].attempts += 1
            regions[index].allowEarlyCheck = false
        }
    }
    mutating func checked(_ indices: Set<Int>, submitted: UInt64, at now: Double) {
        for index in indices where regions[index].revision <= submitted {
            regions[index].dirtySince = nil
            if now - regions[index].changedAt >= Self.quietPeriod { regions[index].level = 0 }
        }
    }
    func canInspect(_ bounds: CGRect, selected: Set<Int>) -> Bool {
        let dirty = cells(intersecting: bounds).filter { regions[$0].dirtySince != nil }
        return Set(dirty).isSubset(of: selected)
    }
    mutating func settled(_ bounds: CGRect, submitted: UInt64, at now: Double) {
        for index in cells(intersecting: bounds) where regions[index].revision <= submitted &&
            now - regions[index].changedAt >= Self.quietPeriod {
            regions[index].level = 0
        }
    }
    func cells(intersecting bounds: CGRect) -> Set<Int> {
        guard let range = pixelRange(in: bounds) else { return [] }
        var result = Set<Int>()
        for row in (range.y.lowerBound / 16)...((range.y.upperBound - 1) / 16) {
            for column in (range.x.lowerBound / 16)...((range.x.upperBound - 1) / 16) {
                result.insert(row * Self.columns + column)
            }
        }
        return result
    }
    func unchanged(_ bounds: CGRect, since submitted: UInt64, epoch submittedEpoch: UInt64) -> Bool {
        guard epoch == submittedEpoch, let range = pixelRange(in: bounds) else { return false }
        for y in range.y {
            for x in range.x where pixels[y * Self.width + x] > submitted { return false }
        }
        return true
    }
    private func pixelRange(in bounds: CGRect) -> (x: Range<Int>, y: Range<Int>)? {
        guard !bounds.isNull, !bounds.isInfinite, bounds.width > 0, bounds.height > 0,
              bounds.minX.isFinite, bounds.maxX.isFinite, bounds.minY.isFinite, bounds.maxY.isFinite else { return nil }
        // One reduced pixel of padding covers anti-aliased glyph edges.
        // Clamp before conversion to avoid overflow for finite off-screen rectangles.
        let x0 = Int(max(0, min(Double(Self.width), floor(bounds.minX * Double(Self.width)) - 1)))
        let x1 = Int(max(0, min(Double(Self.width), ceil(bounds.maxX * Double(Self.width)) + 1)))
        let y0 = Int(max(0, min(Double(Self.height), floor(bounds.minY * Double(Self.height)) - 1)))
        let y1 = Int(max(0, min(Double(Self.height), ceil(bounds.maxY * Double(Self.height)) + 1)))
        guard x0 < x1, y0 < y1 else { return nil }
        return (x0..<x1, y0..<y1)
    }
}

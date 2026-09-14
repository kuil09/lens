import CoreImage
import Foundation

/// Deliberately insensitive to tiny compositor noise; cursor is excluded upstream.
struct FrameFingerprint: Equatable {
    let bytes: [UInt8]
    func differs(from other: Self) -> Bool {
        guard bytes.count == other.bytes.count else { return true }
        var changed = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let delta = abs(Int(bytes[i]) - Int(other.bytes[i])) + abs(Int(bytes[i+1]) - Int(other.bytes[i+1])) + abs(Int(bytes[i+2]) - Int(other.bytes[i+2]))
            if delta > 24 { changed += 1 }
        }
        return changed >= 2
    }
}

@MainActor
final class FrameAnalysis {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    func fingerprint(_ image: CIImage) -> FrameFingerprint {
        let size = CGSize(width: 128, height: 80)
        let small = image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width, y: size.height / image.extent.height))
        var bytes = [UInt8](repeating: 0, count: 128 * 80 * 4)
        bytes.withUnsafeMutableBytes { context.render(small, toBitmap: $0.baseAddress!, rowBytes: 128 * 4, bounds: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: colorSpace) }
        return FrameFingerprint(bytes: bytes)
    }
    func cgImage(_ image: CIImage) -> CGImage? { context.createCGImage(image, from: image.extent) }
    func background(_ image: CIImage, normalized: CGRect) -> (CGFloat, CGFloat, CGFloat) {
        let rect = LensGeometry.localRect(normalized, size: image.extent.size).intersection(image.extent)
        guard !rect.isEmpty else { return (1, 1, 1) }
        // Sample a thin strip just above the text, rather than averaging its glyphs.
        let strip = CGRect(x: rect.minX, y: min(image.extent.maxY - 2, rect.maxY + 1), width: rect.width, height: 2)
        guard let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: strip)]).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)) as CIImage? else { return (1,1,1) }
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { context.render(average, toBitmap: $0.baseAddress!, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: colorSpace) }
        return (CGFloat(rgba[0])/255, CGFloat(rgba[1])/255, CGFloat(rgba[2])/255)
    }
}

import CoreGraphics
import CoreImage
import CoreText
import CoreVideo
import Metal

/// Confined to RecordingWorker's serial queue. No AppKit or live-view state enters export.
final class RecordingCompositor {
    static let maximumGlyphs = 32
    static let maximumGlyphBytes = 16 * 1_024 * 1_024
    private struct Key: Hashable {
        let text: String
        let width: Double
        let height: Double
        let scaleX: Double
        let scaleY: Double
        let light: Bool
    }
    private struct Glyph {
        let image: CGImage
        let bytes: Int
        var used: UInt64
    }
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var glyphs: [Key: Glyph] = [:]
    private var clock: UInt64 = 0
    private(set) var glyphBytes = 0
    private(set) var rasterizations = 0
    var glyphCount: Int { glyphs.count }

    init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    func copy(_ frame: RecordingFrame) throws -> RecordingFrame {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(nil, CVPixelBufferGetWidth(frame.buffer),
            CVPixelBufferGetHeight(frame.buffer), kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
             kCVPixelBufferMetalCompatibilityKey as String: true] as CFDictionary, &buffer)
        guard result == kCVReturnSuccess, let buffer else {
            throw VideoError.encoding("Could not copy the recording frame.")
        }
        context.render(CIImage(cvPixelBuffer: frame.buffer), to: buffer,
                       bounds: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer),
                                      height: CVPixelBufferGetHeight(buffer)), colorSpace: colorSpace)
        return RecordingFrame(id: frame.id, contextID: frame.contextID, capturedAt: frame.capturedAt,
            buffer: buffer, pointSize: frame.pointSize, opacity: frame.opacity, dirtyRects: frame.dirtyRects)
    }

    func render(_ frame: RecordingFrame, blocks: [RecordingBlock], into buffer: CVPixelBuffer) {
        let width = CGFloat(CVPixelBufferGetWidth(buffer)), height = CGFloat(CVPixelBufferGetHeight(buffer))
        let sx = width / frame.pointSize.width, sy = height / frame.pointSize.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var scene = CIImage(cvPixelBuffer: frame.buffer).transformed(by: CGAffineTransform(
            scaleX: width / CGFloat(CVPixelBufferGetWidth(frame.buffer)),
            y: height / CGFloat(CVPixelBufferGetHeight(frame.buffer))))
        for block in blocks {
            let box = LensGeometry.localRect(block.source.bounds, size: frame.pointSize)
                .insetBy(dx: -2, dy: -2).intersection(CGRect(origin: .zero, size: frame.pointSize))
            guard !box.isNull, box.width > 4, box.height > 4 else { continue }
            let rgb = block.background.count >= 3 ? block.background : [1, 1, 1]
            let opacity = frame.opacity.isFinite ? min(1, max(0, frame.opacity)) : 1
            let rect = box.applying(CGAffineTransform(scaleX: sx, y: sy))
            let cover = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                "inputExtent": CIVector(cgRect: rect), "inputRadius": 2 * min(sx, sy),
                "inputColor": CIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: opacity)
            ])?.outputImage ?? CIImage(color: CIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: opacity)).cropped(to: rect)
            scene = cover.composited(over: scene)
            let area = box.insetBy(dx: 2, dy: 1)
            let light = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722 > 0.5
            if let glyph = glyph(text: block.text, size: area.size, scaleX: sx, scaleY: sy, light: light) {
                let image = CIImage(cgImage: glyph).transformed(by: CGAffineTransform(
                    translationX: area.minX * sx, y: area.minY * sy))
                scene = image.cropped(to: area.applying(CGAffineTransform(scaleX: sx, y: sy))).composited(over: scene)
            }
        }
        context.render(scene, to: buffer, bounds: bounds, colorSpace: colorSpace)
    }

    /// Position and opacity are deliberately absent: scrolling and mask changes reuse glyphs.
    private func glyph(text: String, size: CGSize, scaleX: CGFloat, scaleY: CGFloat, light: Bool) -> CGImage? {
        guard !text.isEmpty, text.utf8.count <= 65_536 else { return nil }
        let width = Int((size.width * scaleX).rounded()), height = Int((size.height * scaleY).rounded())
        let key = Key(text: text, width: Double(width), height: Double(height), scaleX: scaleX, scaleY: scaleY, light: light)
        clock &+= 1
        if var cached = glyphs[key] {
            cached.used = clock; glyphs[key] = cached
            return cached.image
        }
        guard width > 0, height > 0, width <= Self.maximumGlyphBytes / 4 / height else { return nil }
        let cost = width * height * 4
        // Reserve before rasterizing, so a miss cannot temporarily double retained glyph pixels.
        while glyphs.count >= Self.maximumGlyphs || glyphBytes + cost > Self.maximumGlyphBytes {
            guard let oldest = glyphs.min(by: { $0.value.used < $1.value.used }) else { break }
            glyphBytes -= oldest.value.bytes; glyphs.removeValue(forKey: oldest.key)
        }
        guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        canvas.scaleBy(x: scaleX, y: scaleY)
        canvas.clip(to: CGRect(origin: .zero, size: size))
        var fontSize = min(22, max(11, (size.height + 2) * 0.68))
        var attributed: NSAttributedString
        while true {
            let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)!
            attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(gray: light ? 0 : 1, alpha: 1)
            ])
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(attributed),
                CFRange(location: 0, length: 0), nil, CGSize(width: size.width, height: .greatestFiniteMagnitude), nil)
            if suggested.height <= size.height || fontSize <= 11 { break }
            fontSize = max(11, fontSize - 1)
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)!
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let step = ceil(ascent + descent + CTFontGetLeading(font))
        var index = 0, baseline = size.height - ascent
        while index < attributed.length, baseline + ascent > 0 {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, index, size.width))
            let lastVisible = baseline - step < descent
            var line = CTTypesetterCreateLine(typesetter, CFRange(location: index, length: min(count, attributed.length - index)))
            if lastVisible && index + count < attributed.length {
                let rest = attributed.attributedSubstring(from: NSRange(location: index, length: attributed.length - index))
                let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributed.attributes(at: index, effectiveRange: nil)))
                line = CTLineCreateTruncatedLine(CTLineCreateWithAttributedString(rest), size.width, .end, token) ?? token
            }
            canvas.textPosition = CGPoint(x: 0, y: baseline)
            CTLineDraw(line, canvas)
            if lastVisible { break }
            index += count; baseline -= step
        }
        guard let image = canvas.makeImage() else { return nil }
        glyphs[key] = Glyph(image: image, bytes: cost, used: clock)
        glyphBytes += cost; rasterizations += 1
        return image
    }

    func reset() {
        glyphs.removeAll(); glyphBytes = 0
        context.clearCaches()
    }
}

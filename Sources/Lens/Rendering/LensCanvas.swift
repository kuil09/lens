import AppKit
import MetalKit
import CoreImage

@MainActor
final class LensCanvas: MTKView, MTKViewDelegate {
    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue
    private var image: CIImage?
    var showsCapturedImage = true { didSet { draw() } }
    var onPresented: ((Double) -> Void)?
    private var capturedAt: Double = 0

    init() {
        let gpu = MTLCreateSystemDefaultDevice()!
        commandQueue = gpu.makeCommandQueue()!
        ciContext = CIContext(mtlDevice: gpu, options: [.cacheIntermediates: false])
        super.init(frame: .zero, device: gpu)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        wantsLayer = true
        layer?.isOpaque = false
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }

    func present(_ frame: CapturedFrame) {
        image = CIImage(cvPixelBuffer: frame.buffer)
        capturedAt = frame.capturedAt
        draw()
    }
    func clear() { image = nil; draw() }
    func snapshotImage() -> CGImage? {
        guard let image else { return nil }
        return ciContext.createCGImage(image, from: image.extent)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let command = commandQueue.makeCommandBuffer() else { return }
        let target = CGRect(origin: .zero, size: drawableSize)
        let output: CIImage
        if showsCapturedImage, let image {
            output = image.transformed(by: CGAffineTransform(scaleX: target.width / image.extent.width, y: target.height / image.extent.height))
        } else { output = CIImage(color: .clear).cropped(to: target) }
        ciContext.render(output, to: drawable.texture, commandBuffer: command, bounds: target,
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        command.present(drawable)
        command.commit()
        if capturedAt > 0 { onPresented?(max(0, ProcessInfo.processInfo.systemUptime - capturedAt)) }
    }
}

struct DisplayTranslation: Identifiable {
    let block: TextBlock
    let text: String
    let background: NSColor
    var id: UUID { block.id }
}

/// Never clip translated glyphs with a pixel mask. Source-line invalidation
/// hides the entire corresponding translation and its source-cover rectangle.
struct TranslationDisplayMask {
    var hiddenIDs: Set<UUID> = []
    func applying(to reference: [DisplayTranslation]) -> [DisplayTranslation] {
        reference.filter { !hiddenIDs.contains($0.id) }
    }
}

@MainActor
final class TranslationOverlay: NSView {
    var translations: [DisplayTranslation] = [] { didSet { needsDisplay = true } }
    var maskOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        for item in translations {
            let box = LensGeometry.localRect(item.block.bounds, size: bounds.size).insetBy(dx: -2, dy: -2).intersection(bounds)
            guard box.width > 4, box.height > 4 else { continue }
            item.background.withAlphaComponent(maskOpacity).setFill()
            NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let rgb = item.background.usingColorSpace(.deviceRGB) ?? .white
            let light = rgb.redComponent * 0.2126 + rgb.greenComponent * 0.7152 + rgb.blueComponent * 0.0722
            let foreground: NSColor = light > 0.5 ? .black : .white
            let area = box.insetBy(dx: 2, dy: 1)
            var fontSize = min(22, max(11, box.height * 0.68))
            var attributes: [NSAttributedString.Key: Any] = [:]
            var measured = CGRect.zero
            repeat {
                attributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: foreground, .paragraphStyle: paragraph]
                measured = (item.text as NSString).boundingRect(with: CGSize(width: area.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
                if measured.height <= area.height || fontSize <= 11 { break }
                fontSize -= 1
            } while true
            if measured.height > area.height {
                paragraph.lineBreakMode = .byTruncatingTail
                attributes[.paragraphStyle] = paragraph
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: area).addClip()
            (item.text as NSString).draw(with: area, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], attributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
            if measured.height > area.height {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: CGRect(x: box.maxX - 5, y: box.minY, width: 5, height: 5)).fill()
            }
        }
    }
}

@MainActor
final class LensBorder: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 4, bounds.height > 4 else { return }
        // Two contrasting strokes keep the boundary visible on light and dark content.
        for (inset, color) in [(CGFloat(0.5), NSColor.black.withAlphaComponent(0.65)),
                               (CGFloat(1.5), NSColor.white.withAlphaComponent(0.85))] {
            color.setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                                       xRadius: 18 - inset, yRadius: 18 - inset)
            outline.lineWidth = 1
            outline.stroke()
        }
    }
}

@MainActor
final class LensSurface: NSView {
    let canvas = LensCanvas()
    let overlay = TranslationOverlay()
    let border = LensBorder()
    let idleBackground = LensIdleBackground(frame: .zero)
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(canvas); addSubview(overlay); addSubview(idleBackground); addSubview(border)
        setTranslationActive(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        canvas.frame = bounds; overlay.frame = bounds; border.frame = bounds; idleBackground.frame = bounds
        border.needsDisplay = true
    }
    func setTranslationActive(_ active: Bool, arranging: Bool = false) {
        // The canvas still receives frames for OCR/export, but never reproduces them on screen.
        canvas.showsCapturedImage = false
        canvas.isHidden = !active
        overlay.isHidden = !active
        idleBackground.isHidden = active || arranging
    }
}

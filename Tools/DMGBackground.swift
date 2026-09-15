import AppKit

// Finder owns the draggable icons. This is only the Retina backing artwork.
let destination = CommandLine.arguments.dropFirst().first!
let size = NSSize(width: 720, height: 440)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 880,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let top = NSColor(calibratedRed: 0.98, green: 0.99, blue: 1, alpha: 1)
let bottom = NSColor(calibratedRed: 0.90, green: 0.95, blue: 0.99, alpha: 1)
NSGradient(starting: bottom, ending: top)!.draw(in: NSRect(origin: .zero, size: size), angle: 90)

func text(_ value: String, y: CGFloat, size fontSize: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = NSColor(calibratedRed: 0.17, green: 0.22, blue: 0.29, alpha: 1)) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (value as NSString).draw(in: NSRect(x: 30, y: y, width: 660, height: fontSize * 1.6),
        withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                         .foregroundColor: color, .paragraphStyle: style])
}

text("Lens", y: 354, size: 36, weight: .semibold)
text("Translate what you see.", y: 320, size: 17)

// A standard SF Symbol indicates the direction; it is never a fake draggable target.
let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)!
    .withSymbolConfiguration(.init(pointSize: 29, weight: .medium))!
let arrowRect = NSRect(x: 338, y: 212, width: 44, height: 34)
NSColor(calibratedRed: 0.16, green: 0.44, blue: 0.70, alpha: 1).setFill()
arrow.draw(in: arrowRect)

text("Drag Lens into Applications", y: 114, size: 19, weight: .medium)
text("Lens를 응용 프로그램 폴더로 드래그하세요", y: 83, size: 13)
text("LensをApplicationsフォルダへドラッグ", y: 59, size: 13)
text("Open Lens from Applications when the copy finishes.", y: 19, size: 11,
     color: NSColor(calibratedRed: 0.33, green: 0.39, blue: 0.46, alpha: 1))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .tiff, properties: [.compressionMethod: 5])!
    .write(to: URL(fileURLWithPath: destination), options: .atomic)

import AppKit

@MainActor
enum LensSnapshot {
    /// Compose from the retained capture, not a second screenshot of the app's windows.
    static func png(background: CGImage, pointSize: CGSize,
                    translations: [DisplayTranslation], maskOpacity: CGFloat) -> Data? {
        guard let result = image(background: background, pointSize: pointSize,
                                 translations: translations, maskOpacity: maskOpacity) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: result)
        bitmap.size = pointSize
        return bitmap.representation(using: .png, properties: [:])
    }

    static func image(background: CGImage, pointSize: CGSize,
                      translations: [DisplayTranslation], maskOpacity: CGFloat) -> CGImage? {
        guard pointSize.width > 0, pointSize.height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let pixels = CGContext(data: nil, width: background.width, height: background.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        pixels.draw(background, in: CGRect(x: 0, y: 0, width: background.width, height: background.height))
        pixels.scaleBy(x: CGFloat(background.width) / pointSize.width,
                       y: CGFloat(background.height) / pointSize.height)
        let context = NSGraphicsContext(cgContext: pixels, flipped: false)
        let rect = CGRect(origin: .zero, size: pointSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let overlay = TranslationOverlay(frame: rect)
        overlay.translations = translations
        overlay.maskOpacity = maskOpacity
        overlay.draw(rect)
        LensBorder(frame: rect).draw(rect)
        NSGraphicsContext.restoreGraphicsState()
        return pixels.makeImage()
    }
}

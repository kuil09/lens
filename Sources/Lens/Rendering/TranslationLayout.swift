import AppKit
import SwiftUI

/// Drawing, overflow affordances, and hit regions share this exact layout.
@MainActor struct TranslationLayout {
    let item: DisplayTranslation
    let box: CGRect
    let area: CGRect
    let isTruncated: Bool
    let manager: NSLayoutManager
    let storage: NSTextStorage
    let container: NSTextContainer

    init?(item: DisplayTranslation, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        let box = LensGeometry.localRect(item.block.bounds, size: size).insetBy(dx: -2, dy: -2).intersection(bounds)
        guard box.width > 4, box.height > 4 else { return nil }
        self.item = item; self.box = box
        area = box.insetBy(dx: 2, dy: 1)
        storage = NSTextStorage(string: item.text)
        manager = NSLayoutManager(); container = NSTextContainer(size: CGSize(width: area.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let rgb = item.background.usingColorSpace(.deviceRGB) ?? .white
        let light = rgb.redComponent * 0.2126 + rgb.greenComponent * 0.7152 + rgb.blueComponent * 0.0722
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        var fontSize = min(22, max(11, box.height * 0.68))
        var measured = CGRect.zero
        repeat {
            storage.setAttributes([.font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: light > 0.5 ? NSColor.black : .white, .paragraphStyle: paragraph],
                range: NSRange(location: 0, length: storage.length))
            manager.ensureLayout(for: container)
            measured = manager.usedRect(for: container)
            if measured.height <= area.height && measured.width <= area.width || fontSize <= 11 { break }
            fontSize -= 1
        } while true
        isTruncated = measured.height > area.height || measured.width > area.width
        if isTruncated {
            paragraph.lineBreakMode = .byTruncatingTail
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
            container.containerSize = area.size
            manager.ensureLayout(for: container)
        }
    }

    func draw(opacity: CGFloat) {
        item.background.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: area).addClip()
        // Preserve the same coordinate-aware AppKit text drawing used by PNG/MP4.
        storage.draw(with: area, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct TruncatedTranslationView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Full Translation")).font(.headline)
                Spacer()
                Button(L10n.text("Copy Translation")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(16)
    }
}

@MainActor final class TranslationOverflowButton: NSButton {
    var activate: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""; isBordered = false; target = self; action = #selector(pressed)
        setAccessibilityLabel(L10n.text("Read Full Translation"))
        toolTip = L10n.text("Read Full Translation")
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { activate?() }
    override func draw(_ dirtyRect: NSRect) {
        // Only the interactive screen view draws this affordance, never the export renderer.
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: CGRect(x: bounds.maxX - 6, y: 1, width: 5, height: 5)).fill()
    }
}

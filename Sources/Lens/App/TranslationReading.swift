import AppKit
import Combine
import SwiftUI

struct ReadingSource: Equatable {
    let block: TextBlock
    let text: String?
    let isCurrent: Bool
}

struct ReadingRow: Identifiable, Equatable {
    let id: UUID
    let block: TextBlock
    let text: String
    var isPrevious = false
}

/// Only the latest source state and one explicitly accepted reading snapshot are retained.
@MainActor final class TranslationReading: ObservableObject {
    @Published private(set) var rows: [ReadingRow] = []
    @Published private(set) var hasUpdates = false
    @Published private(set) var previousScreen = false
    @Published private(set) var appliedAt: Date?
    private var latest: [ReadingSource] = []
    private var epoch: UInt64 = 0
    private var snapshotEpoch: UInt64 = 0
    private var accepted: [ReadingSource] = []

    func receive(_ sources: [ReadingSource], epoch: UInt64) {
        latest = sources; self.epoch = epoch
        previousScreen = !rows.isEmpty && snapshotEpoch != epoch
        hasUpdates = (snapshotEpoch != epoch || accepted != latest) &&
            (!rows.isEmpty || latest.contains { $0.isCurrent && $0.text != nil })
    }

    func open() {
        rows = []; accepted = []; snapshotEpoch = epoch
        apply()
    }

    func apply(at date: Date = Date()) {
        let old = snapshotEpoch == epoch ? rows : []
        var next: [ReadingRow] = []
        for source in latest {
            let exact = old.first { $0.block.id == source.block.id }
            // Spatial matching preserves reading position only, never translation validity.
            let candidates = old.filter { Self.corresponds($0.block.bounds, source.block.bounds) }
            let spatial = candidates.count == 1 ? candidates.first : nil
            let match = exact ?? spatial.flatMap { candidate in
                latest.filter { Self.corresponds(candidate.block.bounds, $0.block.bounds) }.count == 1 ? candidate : nil
            }
            if source.isCurrent, let text = source.text {
                next.append(.init(id: match?.id ?? source.block.id, block: source.block, text: text))
            } else if let match {
                var previous = match; previous.isPrevious = true
                next.append(previous)
            }
        }
        next.sort {
            if $0.block.bounds.maxY != $1.block.bounds.maxY { return $0.block.bounds.maxY > $1.block.bounds.maxY }
            return $0.block.bounds.minX < $1.block.bounds.minX
        }
        if rows != next { rows = next }
        snapshotEpoch = epoch; accepted = latest; previousScreen = false
        appliedAt = date; hasUpdates = false
    }

    static func corresponds(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height >= max(a.width * a.height, b.width * b.height) * 0.7
    }
}

/// Reuses native text views by reading ID, preserving selection in untouched paragraphs.
struct ReadingDocumentView: NSViewRepresentable {
    let rows: [ReadingRow]
    let showOriginal: Bool
    func makeNSView(context: Context) -> ReadingScrollView { ReadingScrollView() }
    func updateNSView(_ view: ReadingScrollView, context: Context) { view.update(rows, original: showOriginal) }
}

@MainActor final class ReadingScrollView: NSScrollView {
    private let document = ReadingDocument()
    private var textViews: [UUID: NSTextView] = [:]
    private var orderedIDs: [UUID] = []
    private var lastWidth: CGFloat = 0
    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = true; drawsBackground = false
        documentView = document
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ rows: [ReadingRow], original: Bool) {
        let anchor = currentAnchor()
        let oldOrder = orderedIDs
        let ids = Set(rows.map(\.id))
        for id in Array(textViews.keys) where !ids.contains(id) { textViews.removeValue(forKey: id)?.removeFromSuperview() }
        for row in rows {
            let view = textViews[row.id] ?? {
                let text = NSTextView()
                text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
                text.autoresizingMask = []
                text.isVerticallyResizable = false; text.isHorizontallyResizable = false
                text.textContainer?.widthTracksTextView = false
                text.textContainerInset = .zero; text.textContainer?.lineFragmentPadding = 0
                text.setAccessibilityLabel(L10n.text("Full Translation"))
                document.addSubview(text); textViews[row.id] = text
                return text
            }()
            let string = NSMutableAttributedString(string: "")
            if original {
                string.append(NSAttributedString(string: row.block.text + "\n\n",
                    attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]))
            }
            if row.isPrevious {
                string.append(NSAttributedString(string: L10n.text("Previous translation") + "\n",
                    attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
            }
            string.append(NSAttributedString(string: row.text,
                attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor]))
            if view.attributedString() != string { view.textStorage?.setAttributedString(string) }
        }
        orderedIDs = rows.map(\.id)
        reflow()
        restore(anchor, oldOrder: oldOrder)
    }

    override func layout() {
        super.layout()
        if abs(contentSize.width - lastWidth) > 0.5 {
            let anchor = currentAnchor()
            reflow(); restore(anchor, oldOrder: orderedIDs)
        }
    }
    private func currentAnchor() -> (UUID, CGFloat)? {
        let top = contentView.bounds.minY
        guard let id = orderedIDs.first(where: { (textViews[$0]?.frame.maxY ?? 0) > top }) else { return nil }
        return (id, top - (textViews[id]?.frame.minY ?? 0))
    }
    private func restore(_ anchor: (UUID, CGFloat)?, oldOrder: [UUID]) {
        guard let (id, offset) = anchor else { return }
        let oldIndex = oldOrder.firstIndex(of: id) ?? 0
        let replacement = textViews[id] != nil ? id : oldOrder.enumerated()
            .filter { textViews[$0.element] != nil }.min { abs($0.offset - oldIndex) < abs($1.offset - oldIndex) }?.element
        guard let replacement, let view = textViews[replacement] else { return }
        let y = max(0, min(document.frame.height - contentSize.height, view.frame.minY + offset))
        contentView.scroll(to: CGPoint(x: 0, y: y)); reflectScrolledClipView(contentView)
    }
    private func reflow() {
        lastWidth = contentSize.width
        let width = max(1, lastWidth - 48)
        var y: CGFloat = 24
        for id in orderedIDs {
            guard let view = textViews[id], let container = view.textContainer, let manager = view.layoutManager else { continue }
            container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            let height = ceil(manager.usedRect(for: container).height) + 4
            view.frame = CGRect(x: 24, y: y, width: width, height: height)
            y += height + 28
        }
        document.setFrameSize(CGSize(width: lastWidth, height: max(contentSize.height, y)))
    }
}

@MainActor private final class ReadingDocument: NSView {
    override var isFlipped: Bool { true }
}

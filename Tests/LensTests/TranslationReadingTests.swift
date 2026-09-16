import AppKit
import Testing
@testable import Lens

private func readingSource(_ text: String = "Do not delete the remaining 12 files.", translation: String? = "Keep 12 files.",
                           current: Bool = true, x: CGFloat = 0.1, y: CGFloat = 0.7) -> ReadingSource {
    .init(block: .init(text: text, bounds: CGRect(x: x, y: y, width: 0.3, height: 0.06), language: .english, confidence: 1),
          text: translation, isCurrent: current)
}

@Test @MainActor func readerNeverChangesTextUntilExplicitApply() throws {
    let reading = TranslationReading()
    let first = readingSource(), second = readingSource("A static paragraph stays here.", translation: "Static", y: 0.4)
    reading.receive([first, second], epoch: 1); reading.open()
    let snapshot = reading.rows
    for number in 13...50 {
        reading.receive([readingSource("Delete \(number) files.", translation: "Delete \(number)"), second], epoch: 1)
        #expect(reading.rows == snapshot)
        #expect(reading.hasUpdates)
    }
    let date = Date(timeIntervalSince1970: 100)
    reading.apply(at: date)
    #expect(reading.rows.count == 2)
    #expect(reading.rows[0].text == "Delete 50")
    #expect(reading.rows[0].id == snapshot[0].id)
    #expect(reading.rows[1] == snapshot[1])
    #expect(reading.appliedAt == date && !reading.hasUpdates)
}

@Test @MainActor func readerRetainsMarkedPreviousTextWhilePendingAndAppliesConfirmedDeletion() throws {
    let reading = TranslationReading(), original = readingSource()
    reading.receive([original], epoch: 3); reading.open()
    let pending = readingSource("Delete the remaining 13 files.", translation: nil, current: false)
    reading.receive([pending], epoch: 3)
    #expect(reading.rows.first?.text == original.text)
    reading.apply()
    #expect(reading.rows.first?.isPrevious == true)
    let completed = ReadingSource(block: pending.block, text: "Delete 13 files", isCurrent: true)
    reading.receive([completed], epoch: 3)
    #expect(reading.rows.first?.text == original.text)
    reading.apply()
    #expect(reading.rows.first?.text == "Delete 13 files")
    #expect(reading.rows.first?.isPrevious == false)
    reading.receive([], epoch: 3)
    #expect(!reading.rows.isEmpty)
    reading.apply(); #expect(reading.rows.isEmpty)
}

@Test @MainActor func readerDistinguishesNewScreenAndDoesNotReusePriorScenePositions() {
    let reading = TranslationReading(), old = readingSource()
    reading.receive([old], epoch: 1); reading.open()
    let previousID = reading.rows.first?.id
    let new = readingSource("Another document with another language.", translation: "New document")
    reading.receive([new], epoch: 2)
    #expect(reading.previousScreen && reading.rows.first?.text == old.text)
    reading.apply()
    #expect(reading.rows.first?.id != previousID)
    #expect(!reading.previousScreen)
    reading.receive([], epoch: 3); reading.open()
    #expect(reading.rows.isEmpty)
    reading.receive([new], epoch: 3)
    #expect(reading.rows.isEmpty && reading.hasUpdates)
}

@Test @MainActor func readerSplitOrMergeDoesNotDuplicateReadingIDs() {
    let reading = TranslationReading(), old = readingSource()
    reading.receive([old], epoch: 1); reading.open()
    let next = [readingSource("First replacement", translation: "A"), readingSource("Second replacement", translation: "B", y: 0.69)]
    reading.receive(next, epoch: 1); reading.apply()
    #expect(Set(reading.rows.map(\.id)).count == 2)
    #expect(reading.rows.allSatisfy { $0.id != old.block.id })
}

@Test @MainActor func nativeReaderKeepsSelectionAndScrollAcrossUnrelatedUpdates() throws {
    _ = NSApplication.shared
    let view = ReadingScrollView(frame: CGRect(x: 0, y: 0, width: 460, height: 240))
    let rows = (0..<20).map { index in
        ReadingRow(id: UUID(), block: readingSource(y: CGFloat(index) / 20).block,
            text: "Paragraph \(index): " + String(repeating: "This text remains readable. ", count: 4))
    }
    view.update(rows, original: false); view.layoutSubtreeIfNeeded()
    let document = try #require(view.documentView)
    let views = document.subviews.compactMap { $0 as? NSTextView }
    let selected = try #require(views.dropFirst(5).first)
    selected.setSelectedRange(NSRange(location: 4, length: 10))
    view.contentView.scroll(to: CGPoint(x: 0, y: selected.frame.minY + 5))
    let beforeY = view.contentView.bounds.minY
    var changed = rows
    changed[19] = ReadingRow(id: rows[19].id, block: rows[19].block, text: "Only the last paragraph changes.")
    view.update(changed, original: false)
    #expect(selected.selectedRange() == NSRange(location: 4, length: 10))
    #expect(abs(view.contentView.bounds.minY - beforeY) < 1)
}

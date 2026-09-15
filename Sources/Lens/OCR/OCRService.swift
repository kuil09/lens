import CoreGraphics
import Foundation
import NaturalLanguage
import Vision

enum OCRServiceError: Error, Equatable {
    case unsupportedRecognitionLanguages([String])
}

/// Vision work is serialized off the main actor. Bounds retain Vision's lower-left origin.
actor OCRService {
    func recognize(_ image: CGImage, source: LensLanguage? = nil, languages: [LensLanguage]? = nil) async throws -> [TextBlock] {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        // Fast recognition does not support Korean and Japanese.
        request.recognitionLevel = .accurate
        request.recognitionLanguages = try Self.recognitionLanguages(
            supported: request.supportedRecognitionLanguages(), source: source)
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = source == nil
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()
        let lines = (request.results ?? []).compactMap { observation -> TextBlock? in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TextBlock(text: candidate.string, bounds: observation.boundingBox,
                             language: Self.detectLanguage(candidate.string, source: source, languages: languages), confidence: candidate.confidence)
        }
        // Establish layout context before language classification: a wrapped tail
        // such as "it." cannot reliably identify its language independently.
        return Self.assignLanguages(to: Self.groupParagraphs(lines), source: source, languages: languages)
    }

    nonisolated static func recognitionLanguages(supported: [String], source: LensLanguage?) throws -> [String] {
        guard let source else { return supported }
        guard let identifier = supported.first(where: { LensLanguage.match($0, in: [source]) != nil }) else {
            throw OCRServiceError.unsupportedRecognitionLanguages([source.rawValue])
        }
        return [identifier]
    }

    /// Detect without constraining NL hypotheses, then match to the runtime translation catalog.
    nonisolated static func detectLanguage(_ text: String, source: LensLanguage? = nil, languages: [LensLanguage]? = nil) -> LensLanguage? {
        if let source { return source }
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let best = hypotheses.max { $0.value < $1.value }
        let hasHangul = letters.contains { isHangul($0.value) }
        let hasKana = letters.contains { isKana($0.value) }
        func accepted(_ identifier: String) -> LensLanguage? {
            if let languages { return LensLanguage.match(identifier, in: languages) }
            return LensLanguage(rawValue: identifier)
        }
        if hasHangul && !hasKana { return accepted("ko") }
        if hasKana && !hasHangul { return accepted("ja") }
        // Single short labels are ambiguous across languages. Scripts without spaces
        // can still identify longer lines; nearby Han-only labels retain the context rule below.
        guard letters.count >= 8, let best, best.value >= 0.85 else { return nil }
        if letters.allSatisfy({ $0.value < 0x0250 }), text.split(whereSeparator: \.isWhitespace).count < 3 { return nil }
        return accepted(best.key.rawValue)
    }

    /// Only ambiguous Han labels inherit Japanese context; digits and short Latin labels stay unknown.
    /// Context must come from directly detected, nearby lines in the same column, without propagation.
    nonisolated static func assignLanguages(to lines: [TextBlock], source: LensLanguage? = nil, languages: [LensLanguage]? = nil) -> [TextBlock] {
        let detected = lines.map { detectLanguage($0.translationText, source: source, languages: languages) }
        return lines.enumerated().map { index, line in
            var language = detected[index]
            let letters = line.text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            if language == nil, !letters.isEmpty, letters.count <= 6,
               letters.allSatisfy({ isHan($0.value) }) {
                let nearby = lines.indices.filter { other in
                    other != index && sameColumn(line.bounds, lines[other].bounds)
                        && verticalGap(line.bounds, lines[other].bounds) <= max(line.bounds.height, lines[other].bounds.height) * 2
                }
                // Conflicting or unsupported textual neighbors are not evidence for Japanese.
                if !nearby.isEmpty && nearby.allSatisfy({ detected[$0] == .japanese }) {
                    language = .japanese
                }
            }
            return TextBlock(id: line.id, text: line.text, bounds: line.bounds,
                             language: language, confidence: line.confidence, sourceLines: line.sourceLines)
        }
    }

    /// Layout context is independent of scheduling cells and output line wrapping.
    nonisolated static func groupParagraphs(_ input: [TextBlock]) -> [TextBlock] {
        let lines = input.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.bounds.isNull && !$0.bounds.isInfinite && $0.bounds.width > 0 && $0.bounds.height > 0
        }.sorted { lhs, rhs in
            if lhs.bounds.maxY != rhs.bounds.maxY { return lhs.bounds.maxY > rhs.bounds.maxY }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        var groups: [[TextBlock]] = []
        for line in lines {
            let candidate = groups.indices.filter { index in
                guard let last = groups[index].last else { return false }
                let height = max(last.bounds.height, line.bounds.height)
                let gap = last.bounds.minY - line.bounds.maxY
                let first = groups[index][0]
                let columnWidth = groups[index].map(\.bounds.width).max() ?? first.bounds.width
                let aligned = abs(first.bounds.minX - line.bounds.minX) <= height * 0.6
                    && line.bounds.maxX <= first.bounds.minX + columnWidth + height
                let continuation = !endsSentence(last.text) || paragraphLine(line.text)
                let contextLanguage = groups[index].compactMap(\.language).first
                let compatible = contextLanguage == nil || line.language == nil || contextLanguage == line.language
                return compatible && paragraphLine(first.text) && continuation
                    && aligned && !startsListItem(first.text) && !startsListItem(line.text)
                    && !tabularRow(last, in: lines) && !tabularRow(line, in: lines)
                    && comparableTypeSize(last, line)
                    && gap >= -height * 0.1 && gap <= height * 0.8
            }.min { verticalGap(groups[$0].last!.bounds, line.bounds) < verticalGap(groups[$1].last!.bounds, line.bounds) }
            if let candidate { groups[candidate].append(line) } else { groups.append([line]) }
        }
        return groups.map { group in
            let first = group[0]
            let weight = group.reduce(0) { $0 + $1.text.count }
            let confidence = group.reduce(Float(0)) { $0 + $1.confidence * Float($1.text.count) } / Float(weight)
            return TextBlock(id: first.id, text: group.map(\.text).joined(separator: "\n"),
                             bounds: group.dropFirst().reduce(first.bounds) { $0.union($1.bounds) },
                             language: group.compactMap(\.language).first, confidence: confidence,
                             sourceLines: group.flatMap(\.sourceLines))
        }
    }

    private nonisolated static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".!?。！？:：".contains(last)
    }
    private nonisolated static func comparableTypeSize(_ a: TextBlock, _ b: TextBlock) -> Bool {
        let heightRatio = min(a.bounds.height, b.bounds.height) / max(a.bounds.height, b.bounds.height)
        if heightRatio >= 0.75 { return true }
        // Real Vision observations can have inflated vertical boxes even for
        // identical fonts. Mean advance is independent supporting evidence, not
        // permission to merge a large heading into smaller body text.
        let advanceA = a.bounds.width / CGFloat(max(1, a.text.count))
        let advanceB = b.bounds.width / CGFloat(max(1, b.text.count))
        return heightRatio >= 0.55 && min(advanceA, advanceB) / max(advanceA, advanceB) >= 0.8
    }
    private nonisolated static func startsListItem(_ text: String) -> Bool {
        text.range(of: #"^\s*(?:[-•●▪·]|\d+[.)]|[A-Za-z][.)])\s+"#, options: .regularExpression) != nil
    }
    private nonisolated static func tabularRow(_ line: TextBlock, in lines: [TextBlock]) -> Bool {
        let peers = lines.filter {
            $0.id != line.id && abs($0.bounds.midY - line.bounds.midY) < line.bounds.height * 0.35 &&
            min($0.bounds.height, line.bounds.height) >= max($0.bounds.height, line.bounds.height) * 0.75 &&
            ($0.bounds.minX > line.bounds.maxX + line.bounds.height || line.bounds.minX > $0.bounds.maxX + line.bounds.height)
        }
        // Aligned short cells / multiple peers are table evidence. Two prose
        // columns are not automatically a table merely because baselines align.
        func cellLabel(_ text: String) -> Bool {
            !endsSentence(text) && text.split(whereSeparator: \.isWhitespace).count == 1
        }
        return peers.count >= 2 || (!peers.isEmpty &&
            (cellLabel(line.text) || peers.contains { cellLabel($0.text) }))
    }

    private nonisolated static func sameColumn(_ a: CGRect, _ b: CGRect) -> Bool {
        let height = max(a.height, b.height)
        let overlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        return abs(a.minX - b.minX) <= height * 0.6
            && overlap >= min(a.width, b.width) * 0.8
            && min(a.width, b.width) >= max(a.width, b.width) * 0.55
    }

    private nonisolated static func verticalGap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))
    }

    private nonisolated static func paragraphLine(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let cjk = letters.filter { isHangul($0.value) || isKana($0.value) || isHan($0.value) }.count
        return cjk >= 8 || (letters.count >= 16 && text.split(whereSeparator: \.isWhitespace).count >= 3)
    }

    private nonisolated static func isHangul(_ value: UInt32) -> Bool {
        (0xAC00...0xD7AF).contains(value) || (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value)
    }
    private nonisolated static func isKana(_ value: UInt32) -> Bool {
        (0x3041...0x3096).contains(value) || (0x30A1...0x30FA).contains(value) || (0xFF66...0xFF9D).contains(value)
    }
    private nonisolated static func isHan(_ value: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value) || (0x20000...0x2FA1F).contains(value)
    }
}

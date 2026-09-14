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
                             language: nil, confidence: candidate.confidence)
        }
        return Self.groupParagraphs(Self.assignLanguages(to: lines, source: source, languages: languages))
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
        let detected = lines.map { detectLanguage($0.text, source: source, languages: languages) }
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
                             language: language, confidence: line.confidence)
        }
    }

    /// Conservative geometry-only layout plus text-length evidence avoids joining ordinary controls.
    /// Short labels remain separate even if visually aligned; paragraph line breaks are preserved.
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
                return last.language == line.language && paragraphLine(last.text) && paragraphLine(line.text)
                    && sameColumn(last.bounds, line.bounds)
                    && sameColumn(groups[index][0].bounds, line.bounds)
                    && min(last.bounds.height, line.bounds.height) >= height * 0.75
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
                             language: first.language, confidence: confidence)
        }
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

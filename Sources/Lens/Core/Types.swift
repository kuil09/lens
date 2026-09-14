import Foundation
import CoreGraphics

enum LensLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case korean = "ko", japanese = "ja", english = "en"
    var id: String { rawValue }
    var title: String {
        switch self { case .korean: "한국어"; case .japanese: "日本語"; case .english: "English" }
    }
    var locale: Locale.Language { Locale.Language(identifier: rawValue) }
    var recognitionIdentifier: String {
        switch self { case .korean: "ko-KR"; case .japanese: "ja-JP"; case .english: "en-US" }
    }
}

struct TextBlock: Identifiable, Sendable, Equatable {
    let id: UUID
    let text: String
    /// Normalized image coordinates, lower-left origin (Vision convention).
    let bounds: CGRect
    let language: LensLanguage?
    let confidence: Float
    init(id: UUID = UUID(), text: String, bounds: CGRect, language: LensLanguage?, confidence: Float) {
        self.id = id; self.text = text; self.bounds = bounds
        self.language = language; self.confidence = confidence
    }
}

struct TranslationInput: Sendable {
    let id: UUID
    let text: String
    let source: LensLanguage
    let target: LensLanguage
}

struct TranslationOutput: Sendable {
    let id: UUID
    let text: String
}

enum LanguagePairStatus: Sendable, Equatable { case installed, supported, unsupported }

@MainActor
protocol TranslationEngine: AnyObject {
    func availability(source: LensLanguage, target: LensLanguage) async -> LanguagePairStatus
    func translate(_ inputs: [TranslationInput]) async throws -> [TranslationOutput]
    func cancel()
}

/// Both counters must match before a result is allowed onto the live screen.
struct WorkVersion: Sendable, Equatable {
    var region: UInt64 = 0
    var content: UInt64 = 0
}

enum LensGeometry {
    static func localRect(_ normalized: CGRect, size: CGSize) -> CGRect {
        CGRect(x: normalized.minX * size.width, y: normalized.minY * size.height,
               width: normalized.width * size.width, height: normalized.height * size.height)
    }
    /// AppKit global bottom-left coordinates to display-local top-left points.
    static func captureRect(global: CGRect, display: CGRect) -> CGRect {
        CGRect(x: global.minX - display.minX, y: display.maxY - global.maxY,
               width: global.width, height: global.height)
    }
    static func pixels(points: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
    }
    static func clamped(_ rect: CGRect, to area: CGRect) -> CGRect {
        let size = CGSize(width: min(rect.width, area.width), height: min(rect.height, area.height))
        return CGRect(x: min(max(rect.minX, area.minX), area.maxX - size.width),
                      y: min(max(rect.minY, area.minY), area.maxY - size.height),
                      width: size.width, height: size.height)
    }
}

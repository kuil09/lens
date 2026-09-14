import Foundation
import CoreGraphics

struct LensLanguage: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    let rawValue: String
    init?(rawValue: String) {
        guard !rawValue.isEmpty, rawValue.count <= 64,
              rawValue.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" })
        else { return nil }
        let language = Locale.Language(identifier: rawValue.replacingOccurrences(of: "_", with: "-"))
        guard language.languageCode != nil else { return nil }
        self.rawValue = language.minimalIdentifier
    }
    init(_ language: Locale.Language) { rawValue = language.minimalIdentifier }
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let language = Self(rawValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid language identifier"))
        }
        self = language
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    static let korean = Self(rawValue: "ko")!
    static let japanese = Self(rawValue: "ja")!
    static let english = Self(rawValue: "en")!
    var id: String { rawValue }
    var title: String {
        Locale.current.localizedString(forIdentifier: rawValue) ?? rawValue
    }
    var locale: Locale.Language { Locale.Language(identifier: rawValue) }
    var languageCode: String { locale.languageCode?.identifier ?? rawValue }
    func isSameLanguage(as other: Self) -> Bool {
        locale.languageCode == other.locale.languageCode && locale.script == other.locale.script
    }

    /// Keep script variants distinct (for example, Simplified and Traditional Chinese).
    static func match(_ identifier: String, in supported: [Self]) -> Self? {
        guard let wanted = Self(rawValue: identifier) else { return nil }
        if let exact = supported.first(where: { $0 == wanted }) { return exact }
        return supported.first {
            $0.locale.languageCode == wanted.locale.languageCode && $0.locale.script == wanted.locale.script
        }
    }
    static func systemDefault(preferred: [String] = Locale.preferredLanguages, supported: [Self]) -> Self {
        for identifier in preferred {
            if let language = match(identifier, in: supported) { return language }
        }
        return match("en", in: supported) ?? supported.first ?? .english
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

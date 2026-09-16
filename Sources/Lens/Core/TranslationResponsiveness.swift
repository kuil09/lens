import Foundation

/// Controls inspection pacing only. Pixel validity and the global OCR budget are invariant.
enum TranslationResponsiveness: Int, CaseIterable, Sendable {
    case calm = 0, balanced = 1, fast = 2

    static let preferenceKey = "translationResponsiveness"
    static func load(from defaults: UserDefaults) -> Self {
        (defaults.object(forKey: preferenceKey) as? Int).flatMap(Self.init(rawValue:)) ?? .balanced
    }
    var intervals: [Double] {
        switch self {
        case .calm: [0.5, 1, 2, 3]
        case .balanced: [0.25, 0.5, 1, 2]
        case .fast: [0.25, 0.375, 0.5, 0.75]
        }
    }
    var escalationPeriod: Double { self == .fast ? 0.5 : 0.25 }
    var title: String {
        switch self {
        case .calm: L10n.text("Calmer")
        case .balanced: L10n.text("Balanced (Default)")
        case .fast: L10n.text("Faster")
        }
    }
}

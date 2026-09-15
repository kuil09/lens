import Foundation

/// One resolver for AppKit strings, SwiftUI strings, and displayed language names.
/// UI language never depends on downloaded translation packs or the target picker.
enum L10n {
    static let supportedLanguages = ["en", "ko", "ja"]
    static var resources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
    static let current = Catalog(preferences: resources.preferredLocalizations)
    static var locale: Locale { Locale(identifier: current.language) }

    static func text(_ key: String, _ arguments: String...) -> String {
        current.text(key, arguments: arguments)
    }

    struct Catalog: Sendable {
        let language: String
        private let bundle: Bundle
        init(preferences: [String], resources: Bundle = L10n.resources) {
            language = Self.resolve(preferences)
            bundle = resources.url(forResource: language, withExtension: "lproj")
                .flatMap(Bundle.init(url:)) ?? resources
        }
        static func resolve(_ preferences: [String]) -> String {
            for identifier in preferences {
                let code = Locale.Language(identifier: identifier).languageCode?.identifier
                if let code, L10n.supportedLanguages.contains(code) { return code }
            }
            return "en"
        }
        func text(_ key: String, arguments: [String] = []) -> String {
            let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
            guard !arguments.isEmpty else { return format }
            return String(format: format, locale: Locale(identifier: language), arguments: arguments)
        }
    }
}

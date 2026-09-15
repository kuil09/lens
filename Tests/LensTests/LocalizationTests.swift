import Foundation
import Testing
@testable import Lens

private func table(_ language: String) throws -> [String: String] {
    let url = try #require(L10n.resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj"))
    let data = try Data(contentsOf: url)
    return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

@Test func localizedResourcesHaveMatchingKeysAndFormatArguments() throws {
    let base = try table("en")
    #expect(base.count >= 233) // Source-call coverage below catches missing new keys.
    let pattern = try NSRegularExpression(pattern: "%[0-9]+\\$@")
    func arguments(_ text: String) -> [String] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }.sorted()
    }
    for language in L10n.supportedLanguages {
        let translated = try table(language)
        #expect(Set(translated.keys) == Set(base.keys))
        for (key, value) in translated {
            #expect(!value.isEmpty)
            #expect(arguments(value) == arguments(key))
            if language == "en" { #expect(value == key) }
        }
    }
}

@Test func uiLocaleResolutionHandlesRegionalPreferencesAndEnglishFallback() {
    #expect(L10n.Catalog.resolve(["ja-JP", "en-US"]) == "ja")
    #expect(L10n.Catalog.resolve(["ko-KR"]) == "ko")
    #expect(L10n.Catalog.resolve(["fr-FR", "ja-JP"]) == "ja")
    #expect(L10n.Catalog.resolve(["en-GB", "ko-KR"]) == "en")
    #expect(L10n.Catalog.resolve(["de-DE"]) == "en")
    #expect(L10n.Catalog.resolve([]) == "en")
}

@Test func stringsResolveFromRealResourcesWithoutLeakingPlaceholders() {
    let en = L10n.Catalog(preferences: ["en-US"])
    let ko = L10n.Catalog(preferences: ["ko-KR"])
    let ja = L10n.Catalog(preferences: ["ja-JP"])
    #expect(en.text("Settings…") == "Settings…")
    #expect(ko.text("Settings…") == "설정…")
    #expect(ja.text("Settings…") == "設定…")
    #expect(ja.text("Welcome to Lens") == "Lensへようこそ")
    #expect(ko.text("Ready for %1$@: %2$@ source languages", arguments: ["한국어", "2"]) == "한국어로 바로 번역 가능한 원문 2개")
    #expect(en.text("Image saved · %1$@", arguments: ["100%_日本語.png"]) == "Image saved · 100%_日本語.png")
    #expect(ja.text("Saved · %1$@", arguments: ["가나다.mp4"]) == "保存しました · 가나다.mp4")
}

@Test func everyLocalizedCallHasAResourceAndUICopyIsNotHardCodedInKorean() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Lens")
    let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    let base = try table("en")
    let pattern = try NSRegularExpression(pattern: #"L10n\.text\("((?:\\.|[^"\\])*)""#)
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        if url.lastPathComponent == "TranslationBenchmark.swift" { continue }
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.range(of: "[가-힣]", options: .regularExpression) == nil, "Hard-coded UI copy in \(url.lastPathComponent)")
        let ns = source as NSString
        for match in pattern.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let escaped = ns.substring(with: match.range(at: 1))
            let key = try JSONDecoder().decode(String.self, from: Data("\"\(escaped)\"".utf8))
            #expect(base[key] != nil, "Missing localization: \(key)")
        }
    }
}

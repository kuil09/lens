import Foundation
import Combine
import Vision
@preconcurrency import Translation

struct TranslationRoute: Equatable, Sendable {
    let status: LanguagePairStatus
    let strategy: TranslationCacheStrategy

    static func choose(lowLatency: LanguagePairStatus, highFidelity: LanguagePairStatus) -> Self {
        if lowLatency == .installed { return Self(status: .installed, strategy: .lowLatency) }
        if highFidelity == .installed { return Self(status: .installed, strategy: .highFidelity) }
        if lowLatency == .supported { return Self(status: .supported, strategy: .lowLatency) }
        if highFidelity == .supported { return Self(status: .supported, strategy: .highFidelity) }
        return Self(status: .unsupported, strategy: .lowLatency)
    }
}

@MainActor enum AppleLanguageSupport {
    static func supportedLanguages() async -> [LensLanguage] {
        let low = await LanguageAvailability(preferredStrategy: .lowLatency).supportedLanguages
        let high = await LanguageAvailability(preferredStrategy: .highFidelity).supportedLanguages
        return Array(Set((low + high).map(LensLanguage.init)))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    static func route(_ pair: TranslationPair) async -> TranslationRoute {
        let low = await status(pair, strategy: .lowLatency)
        if low == .installed { return .choose(lowLatency: low, highFidelity: .unsupported) }
        let high = await status(pair, strategy: .highFidelity)
        return .choose(lowLatency: low, highFidelity: high)
    }
    private static func status(_ pair: TranslationPair, strategy: TranslationSession.Strategy) async -> LanguagePairStatus {
        switch await LanguageAvailability(preferredStrategy: strategy).status(from: pair.source.locale, to: pair.target.locale) {
        case .installed: .installed
        case .supported: .supported
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }
}

@MainActor final class LanguageCatalog: ObservableObject {
    @Published private(set) var languages: [LensLanguage] = []
    @Published private(set) var recognitionIdentifiers: [String] = []
    @Published private(set) var routes: [LensLanguage: TranslationRoute] = [:]
    @Published private(set) var checkedTarget: LensLanguage?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var generation = UUID()
    private let languageLoader: @MainActor () async -> [LensLanguage]
    private let recognitionLoader: @MainActor () throws -> [String]
    private let routeResolver: @MainActor (TranslationPair) async -> TranslationRoute

    init(languageLoader: @escaping @MainActor () async -> [LensLanguage] = { await AppleLanguageSupport.supportedLanguages() },
         recognitionLoader: @escaping @MainActor () throws -> [String] = {
             let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
             return try request.supportedRecognitionLanguages()
         }, routeResolver: @escaping @MainActor (TranslationPair) async -> TranslationRoute = { await AppleLanguageSupport.route($0) }) {
        self.languageLoader = languageLoader; self.recognitionLoader = recognitionLoader; self.routeResolver = routeResolver
    }

    var sourceLanguages: [LensLanguage] {
        languages.filter { language in recognitionIdentifiers.contains {
            LensLanguage.match($0, in: [language]) != nil
        } }
    }
    func load() async {
        let fetched = await languageLoader()
        guard !Task.isCancelled else { return }
        languages = fetched
        do { recognitionIdentifiers = try recognitionLoader(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func refresh(target: LensLanguage) async {
        let token = UUID(); generation = token
        loading = true; checkedTarget = target; routes = [:]
        defer { if generation == token { loading = false } }
        var result: [LensLanguage: TranslationRoute] = [:]
        for language in languages where !language.isSameLanguage(as: target) {
            let route = await routeResolver(TranslationPair(source: language, target: target))
            guard generation == token, !Task.isCancelled else { return }
            result[language] = route
        }
        guard generation == token, !Task.isCancelled else { return }
        routes = result; loading = false
    }
    func route(from source: LensLanguage, to target: LensLanguage) -> TranslationRoute? {
        checkedTarget == target ? routes[source] : nil
    }
}

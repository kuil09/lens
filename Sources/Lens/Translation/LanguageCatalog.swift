import Foundation
import Combine
import Vision
@preconcurrency import Translation

struct TranslationRoute: Equatable, Sendable {
    let status: LanguagePairStatus
    let strategy: TranslationCacheStrategy
}

@MainActor enum AppleLanguageSupport {
    static func supportedLanguages() async -> [LensLanguage] {
        let low = await LanguageAvailability(preferredStrategy: .lowLatency).supportedLanguages
        return Array(Set(low.map(LensLanguage.init)))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    static func route(_ pair: TranslationPair) async -> TranslationRoute {
        let low = await status(pair, strategy: .lowLatency)
        return downloadedRoute(lowLatency: low)
    }
    // Apple Intelligence can report .installed for a shared multilingual model.
    // That is not evidence of a downloaded per-language translation pack.
    static func downloadedRoute(lowLatency: LanguagePairStatus) -> TranslationRoute {
        .init(status: lowLatency, strategy: .lowLatency)
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
    @Published private(set) var installedTargets: [LensLanguage] = []
    @Published private(set) var checkingInstallation = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var recognitionIdentifiers: [String] = []
    @Published private(set) var routes: [LensLanguage: TranslationRoute] = [:]
    @Published private(set) var checkedTarget: LensLanguage?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var generation = UUID()
    private var loadGeneration = UUID()
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
    func load(checkInstallation: Bool = true) async {
        let token = UUID(); loadGeneration = token
        checkingInstallation = true
        defer { if loadGeneration == token { checkingInstallation = false } }
        let fetched = await languageLoader()
        guard loadGeneration == token, !Task.isCancelled else { return }
        languages = fetched
        do { recognitionIdentifiers = try recognitionLoader(); error = nil }
        catch { recognitionIdentifiers = []; self.error = error.localizedDescription }
        guard checkInstallation else { return }
        // A target is usable only when at least one OCR source has an installed
        // route to it. Never infer installation from supportedLanguages or an
        // English hub: machines can have only non-English models installed.
        var installed: [LensLanguage] = []
        for target in fetched {
            for source in sourceLanguages where !source.isSameLanguage(as: target) {
                let route = await routeResolver(.init(source: source, target: target))
                guard loadGeneration == token, !Task.isCancelled else { return }
                if route.status == .installed { installed.append(target); break }
            }
        }
        guard loadGeneration == token, !Task.isCancelled else { return }
        installedTargets = installed
        hasLoaded = true
    }
    func installedSources(to target: LensLanguage) -> [LensLanguage] {
        sourceLanguages.filter { route(from: $0, to: target)?.status == .installed }
    }
    func refresh(target: LensLanguage) async {
        let token = UUID(); generation = token
        loading = true
        if checkedTarget != target { routes = [:] }
        checkedTarget = target
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

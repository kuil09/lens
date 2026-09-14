import Foundation
// Apple's session/request interfaces lack Sendable annotations in this SDK.
// Session ownership and all client access remain on MainActor.
@preconcurrency import Translation

enum TranslationCacheStrategy: Hashable, Sendable {
    case lowLatency, highFidelity
    var appleStrategy: TranslationSession.Strategy { self == .lowLatency ? .lowLatency : .highFidelity }
}

struct TranslationCacheKey: Hashable {
    // UTF-8 preserves exact spelling, including canonically equivalent Unicode.
    let bytes: Data
    let source: LensLanguage
    let target: LensLanguage
    let strategy: TranslationCacheStrategy

    init(text: String, source: LensLanguage, target: LensLanguage,
         strategy: TranslationCacheStrategy = .lowLatency) {
        bytes = Data(text.utf8)
        self.source = source
        self.target = target
        self.strategy = strategy
    }
}

struct TranslationMemoryCache {
    let capacity: Int
    private var values: [TranslationCacheKey: String] = [:]
    private var recency: [TranslationCacheKey] = []
    var count: Int { values.count }

    init(capacity: Int = 1_000) { self.capacity = max(0, capacity) }

    mutating func value(for key: TranslationCacheKey) -> String? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    mutating func insert(_ value: String, for key: TranslationCacheKey) {
        guard capacity > 0 else { return }
        values[key] = value
        touch(key)
        if recency.count > capacity { values.removeValue(forKey: recency.removeFirst()) }
    }

    private mutating func touch(_ key: TranslationCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

struct TranslationPair: Hashable {
    let source: LensLanguage
    let target: LensLanguage
    static func directions(in languages: [LensLanguage]) -> [Self] {
        languages.flatMap { source in
            languages.filter { $0 != source }.map { Self(source: source, target: $0) }
        }
    }
}

@MainActor
protocol TranslationBatchSession: AnyObject {
    func translate(_ texts: [String]) async throws -> [String]
    func cancel()
}

@MainActor
private final class InstalledTranslationSession: TranslationBatchSession {
    private let session: TranslationSession
    init(pair: TranslationPair, strategy: TranslationCacheStrategy) {
        session = TranslationSession(installedSource: pair.source.locale, target: pair.target.locale,
                                     preferredStrategy: strategy.appleStrategy)
    }

    func translate(_ texts: [String]) async throws -> [String] {
        var requests: [TranslationSession.Request] = []
        for (index, text) in texts.enumerated() {
            requests.append(TranslationSession.Request(sourceText: text, clientIdentifier: String(index)))
        }
        let responses = try await session.translations(from: requests)
        var ordered = [String?](repeating: nil, count: texts.count)
        for response in responses {
            guard let identifier = response.clientIdentifier, let index = Int(identifier),
                  ordered.indices.contains(index), ordered[index] == nil else {
                throw AppleTranslationEngine.Failure.invalidResponse
            }
            ordered[index] = response.targetText
        }
        guard ordered.allSatisfy({ $0 != nil }) else { throw AppleTranslationEngine.Failure.invalidResponse }
        return ordered.compactMap { $0 }
    }
    func cancel() { session.cancel() }
}

@MainActor
final class AppleTranslationEngine: TranslationEngine {
    enum Failure: Error { case invalidResponse, languageNotInstalled }
    typealias SessionFactory = @MainActor (TranslationPair) -> any TranslationBatchSession
    typealias RouteResolver = @MainActor (TranslationPair) async -> TranslationRoute
    private let factory: @MainActor (TranslationPair, TranslationCacheStrategy) -> any TranslationBatchSession
    private let resolve: RouteResolver
    private let batchSize: Int
    private struct SessionKey: Hashable { let pair: TranslationPair; let strategy: TranslationCacheStrategy }
    private var sessions: [SessionKey: any TranslationBatchSession] = [:]
    private var cache = TranslationMemoryCache()
    private var epoch: UInt64 = 0

    init() {
        batchSize = 8
        factory = { InstalledTranslationSession(pair: $0, strategy: $1) }
        resolve = { await AppleLanguageSupport.route($0) }
    }

    // Injection keeps tests independent of installed packs and system downloads.
    init(batchSize: Int = 8, sessionFactory: @escaping SessionFactory) {
        self.batchSize = max(1, batchSize)
        factory = { pair, _ in sessionFactory(pair) }
        resolve = { _ in TranslationRoute(status: .installed, strategy: .lowLatency) }
    }

    init(routeResolver: @escaping RouteResolver,
         sessionFactory: @escaping @MainActor (TranslationPair, TranslationCacheStrategy) -> any TranslationBatchSession) {
        batchSize = 8; resolve = routeResolver; factory = sessionFactory
    }

    func availability(source: LensLanguage, target: LensLanguage) async -> LanguagePairStatus {
        if source == target { return .installed }
        return await resolve(TranslationPair(source: source, target: target)).status
    }

    func cancel() {
        epoch &+= 1
        for session in sessions.values { session.cancel() }
        sessions.removeAll()
    }

    func translate(_ inputs: [TranslationInput]) async throws -> [TranslationOutput] {
        let started = epoch
        try validate(started)
        var results = [String?](repeating: nil, count: inputs.count)
        var groups: [TranslationPair: [Int]] = [:]
        var pairs: [TranslationPair] = []
        var pending: [(TranslationCacheKey, String)] = []
        var strategies: [TranslationPair: TranslationCacheStrategy] = [:]
        for input in inputs where input.source != input.target {
            let pair = TranslationPair(source: input.source, target: input.target)
            if strategies[pair] == nil {
                let route = await resolve(pair)
                try validate(started)
                guard route.status == .installed else { throw Failure.languageNotInstalled }
                strategies[pair] = route.strategy
            }
        }
        for (index, input) in inputs.enumerated() {
            let pair = TranslationPair(source: input.source, target: input.target)
            let key = TranslationCacheKey(text: input.text, source: input.source, target: input.target,
                                          strategy: strategies[pair] ?? .lowLatency)
            if input.source == input.target { results[index] = input.text }
            else if let hit = cache.value(for: key) { results[index] = hit }
            else {
                let pair = TranslationPair(source: input.source, target: input.target)
                if groups[pair] == nil { pairs.append(pair) }
                groups[pair, default: []].append(index)
            }
        }
        for pair in pairs {
            let strategy = strategies[pair]!
            let sessionKey = SessionKey(pair: pair, strategy: strategy)
            let session: any TranslationBatchSession
            if let existing = sessions[sessionKey] { session = existing }
            else { session = factory(pair, strategy); sessions[sessionKey] = session }
            let indices = groups[pair]!
            for offset in stride(from: 0, to: indices.count, by: batchSize) {
                try validate(started)
                let batch = Array(indices[offset..<min(offset + batchSize, indices.count)])
                let translated = try await session.translate(batch.map { inputs[$0].text })
                try validate(started)
                guard translated.count == batch.count else { throw Failure.invalidResponse }
                for (index, text) in zip(batch, translated) {
                    results[index] = text
                    let input = inputs[index]
                    pending.append((TranslationCacheKey(text: input.text, source: input.source,
                                                        target: input.target, strategy: strategy), text))
                }
            }
        }
        try validate(started)
        guard results.allSatisfy({ $0 != nil }) else { throw Failure.invalidResponse }
        for (key, text) in pending { cache.insert(text, for: key) }
        return zip(inputs, results).map { TranslationOutput(id: $0.0.id, text: $0.1!) }
    }

    private func validate(_ started: UInt64) throws {
        try Task.checkCancellation()
        guard epoch == started else { throw CancellationError() }
    }
}

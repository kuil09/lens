import Foundation
// Apple's session/request interfaces lack Sendable annotations in this SDK.
// Session ownership and all client access remain on MainActor.
@preconcurrency import Translation

enum TranslationCacheStrategy: Hashable { case lowLatency, highFidelity }

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
    static var allDirections: [Self] {
        LensLanguage.allCases.flatMap { source in
            LensLanguage.allCases.filter { $0 != source }.map { Self(source: source, target: $0) }
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
    init(pair: TranslationPair) {
        session = TranslationSession(installedSource: pair.source.locale, target: pair.target.locale,
                                     preferredStrategy: .lowLatency)
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
    enum Failure: Error { case invalidResponse }
    typealias SessionFactory = @MainActor (TranslationPair) -> any TranslationBatchSession
    private let factory: SessionFactory
    private let batchSize: Int
    private var sessions: [TranslationPair: any TranslationBatchSession] = [:]
    private var cache = TranslationMemoryCache()
    private var epoch: UInt64 = 0

    init() {
        batchSize = 8
        factory = { InstalledTranslationSession(pair: $0) }
    }

    // Injection keeps tests independent of installed packs and system downloads.
    init(batchSize: Int = 8, sessionFactory: @escaping SessionFactory) {
        self.batchSize = max(1, batchSize)
        factory = sessionFactory
    }

    func availability(source: LensLanguage, target: LensLanguage) async -> LanguagePairStatus {
        if source == target { return .installed }
        let checker = LanguageAvailability(preferredStrategy: .lowLatency)
        switch await checker.status(from: source.locale, to: target.locale) {
        case .installed: return .installed
        case .supported: return .supported
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
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
        for (index, input) in inputs.enumerated() {
            let key = TranslationCacheKey(text: input.text, source: input.source, target: input.target)
            if input.source == input.target { results[index] = input.text }
            else if let hit = cache.value(for: key) { results[index] = hit }
            else {
                let pair = TranslationPair(source: input.source, target: input.target)
                if groups[pair] == nil { pairs.append(pair) }
                groups[pair, default: []].append(index)
            }
        }
        for pair in pairs {
            let session: any TranslationBatchSession
            if let existing = sessions[pair] { session = existing }
            else { session = factory(pair); sessions[pair] = session }
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
                                                        target: input.target), text))
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

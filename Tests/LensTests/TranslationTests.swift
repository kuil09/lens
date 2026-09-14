import Foundation
import Testing
@testable import Lens

private func key(_ text: String, source: LensLanguage = .korean,
                 target: LensLanguage = .english,
                 strategy: TranslationCacheStrategy = .lowLatency) -> TranslationCacheKey {
    TranslationCacheKey(text: text, source: source, target: target, strategy: strategy)
}

@Test func translationCacheSeparatesExactTextLanguagesAndStrategy() {
    var cache = TranslationMemoryCache()
    cache.insert("hit", for: key("é"))
    #expect(cache.value(for: key("é")) == "hit")
    #expect(cache.value(for: key("e\u{301}")) == nil)
    #expect(cache.value(for: key("é ")) == nil)
    #expect(cache.value(for: key("é", source: .japanese)) == nil)
    #expect(cache.value(for: key("é", target: .japanese)) == nil)
    #expect(cache.value(for: key("é", strategy: .highFidelity)) == nil)
}

@Test func translationCacheEvictsLeastRecentlyUsedAt1000() {
    var cache = TranslationMemoryCache()
    for index in 0..<1_000 { cache.insert(String(index), for: key(String(index))) }
    #expect(cache.value(for: key("0")) == "0")
    cache.insert("new", for: key("1000"))
    #expect(cache.count == 1_000)
    #expect(cache.value(for: key("1")) == nil)
    #expect(cache.value(for: key("0")) == "0")
    cache.insert("updated", for: key("0"))
    #expect(cache.count == 1_000)
    #expect(cache.value(for: key("0")) == "updated")
}

@MainActor
private final class FakeTranslationSession: TranslationBatchSession {
    var batches: [[String]] = []
    var cancelled = false
    var action: (@MainActor () async throws -> Void)?
    func translate(_ texts: [String]) async throws -> [String] {
        batches.append(texts)
        try await action?()
        return texts.map { "translated:\($0)" }
    }
    func cancel() { cancelled = true }
}

private func input(_ text: String, source: LensLanguage = .korean,
                   target: LensLanguage = .english) -> TranslationInput {
    TranslationInput(id: UUID(), text: text, source: source, target: target)
}

@Test @MainActor func translationGroupsBatchesPreservesOrderAndReusesSessions() async throws {
    var sessions: [TranslationPair: FakeTranslationSession] = [:]
    let engine = AppleTranslationEngine(batchSize: 2) { pair in
        let session = FakeTranslationSession()
        #expect(sessions[pair] == nil)
        sessions[pair] = session
        return session
    }
    let inputs = [input("a"), input("b", source: .japanese), input("c"),
                  input("d"), input("same", target: .korean)]
    let outputs = try await engine.translate(inputs)
    #expect(outputs.map(\.id) == inputs.map(\.id))
    #expect(outputs.map(\.text) == ["translated:a", "translated:b", "translated:c", "translated:d", "same"])
    let koreanSession = try #require(sessions[TranslationPair(source: .korean, target: .english)])
    #expect(koreanSession.batches == [["a", "c"], ["d"]])
    #expect(sessions.count == 2)
    _ = try await engine.translate([input("a"), input("new")])
    #expect(koreanSession.batches == [["a", "c"], ["d"], ["new"]])
}

@Test @MainActor func translationEpochCancellationDiscardsEntireCall() async throws {
    var created: [FakeTranslationSession] = []
    let engine = AppleTranslationEngine(batchSize: 1) { _ in
        let session = FakeTranslationSession()
        created.append(session)
        return session
    }
    // The second batch cancels after the first has completed.
    let warm = input("warm")
    _ = try await engine.translate([warm])
    let first = try #require(created.first)
    first.action = {
        if first.batches.last == ["b"] { engine.cancel() }
    }
    do {
        _ = try await engine.translate([input("a"), input("b")])
        Issue.record("Cancelled epoch returned results")
    } catch is CancellationError { }
    #expect(first.cancelled)
    _ = try await engine.translate([input("a"), input("b"), warm])
    #expect(created.count == 2)
    #expect(created[1].batches == [["a"], ["b"]])
    first.action = nil
}

@Test @MainActor func translationTaskCancellationDiscardsLateResponse() async throws {
    let session = FakeTranslationSession()
    var response: CheckedContinuation<Void, Never>?
    var entered: CheckedContinuation<Void, Never>?
    session.action = {
        await withCheckedContinuation { continuation in
            response = continuation
            entered?.resume()
            entered = nil
        }
    }
    let engine = AppleTranslationEngine { _ in session }
    let task = Task { try await engine.translate([input("late")]) }
    await withCheckedContinuation { continuation in
        if response != nil { continuation.resume() } else { entered = continuation }
    }
    task.cancel()
    response?.resume()
    do {
        _ = try await task.value
        Issue.record("Cancelled task returned results")
    } catch is CancellationError { }
    session.action = nil
    _ = try await engine.translate([input("late")])
    #expect(session.batches == [["late"], ["late"]])
}

@Test @MainActor func translationBenchmarkHas30TriplesAnd180Directions() async throws {
    #expect(TranslationBenchmark.corpus.count == 30)
    #expect(Set(TranslationBenchmark.corpus.map(\.number)).count == 30)
    #expect(TranslationBenchmark.directions.count == 6)
    let engine = AppleTranslationEngine { _ in FakeTranslationSession() }
    let results = try await TranslationBenchmark.run(engine: engine)
    #expect(results.count == 180)
    #expect(results.allSatisfy { !$0.reference.isEmpty && $0.source != $0.target })
}

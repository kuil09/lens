import SwiftUI
@preconcurrency import Translation

@MainActor
struct LanguagePreparationView: View {
    let onReady: () -> Void
    @State private var configuration: TranslationSession.Configuration?
    @State private var message = "한국어·일본어·영어 언어 팩을 확인해 주세요."
    @State private var statuses: [TranslationPair: LanguagePairStatus] = [:]
    @State private var busy = false
    @State private var ready = false
    @State private var generation = UUID()
    @State private var active = true
    @State private var attempted: Set<TranslationPair> = []

    init(onReady: @escaping () -> Void) { self.onReady = onReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("번역 언어 준비").font(.title2)
            Text("한국어·일본어·영어 3개 언어 팩을 준비합니다. 다운로드에는 인터넷 연결이 필요합니다.")
            ForEach(LensLanguage.allCases) { language in
                HStack {
                    Text(language.title)
                    Spacer()
                    Text(packReady(language) ? "설치됨" : "준비 필요")
                }
            }
            Text(message).accessibilityLabel(message)
            if busy { ProgressView() }
            HStack {
                Button("언어 팩 준비") { start() }.disabled(busy || ready)
                Button("설치 상태 확인") {
                    let token = generation
                    Task { await check(token: token) }
                }.disabled(busy)
                if busy {
                    Button("준비 중단") {
                        generation = UUID()
                        configuration = nil
                        busy = false
                        message = "앱 준비를 중단했습니다. 이미 시작된 시스템 다운로드는 백그라운드에서 계속될 수 있습니다."
                    }
                }
                if ready { Button("시작", action: onReady) }
            }
        }
        .padding(24)
        .onAppear { active = true }
        .task { await check(token: generation) }
        .onDisappear { active = false; generation = UUID(); configuration = nil; busy = false }
        .translationTask(configuration) { session in
            // This session belongs only to this SwiftUI task; never retain it.
            let token = generation
            do {
                try await session.prepareTranslation()
                try Task.checkCancellation()
                guard active, token == generation else { return }
                await check(token: token)
                guard active, token == generation, !Task.isCancelled else { return }
                if ready { configuration = nil; busy = false }
                else if let pair = TranslationPair.allDirections.first(where: {
                    statuses[$0] == .supported && !attempted.contains($0)
                }) {
                    attempted.insert(pair)
                    configuration = .init(source: pair.source.locale, target: pair.target.locale,
                                          preferredStrategy: .lowLatency)
                } else {
                    busy = false
                    configuration = nil
                    message = "모든 번역 방향의 설치를 확인하지 못했습니다. 설치 상태를 다시 확인해 주세요."
                }
            } catch {
                guard active, token == generation else { return }
                busy = false
                configuration = nil
                if error is CancellationError || TranslationError.alreadyCancelled ~= error || Task.isCancelled {
                    message = "다운로드가 취소되었습니다. 다시 준비할 수 있습니다."
                } else {
                    message = "언어 팩 준비에 실패했습니다: \(error.localizedDescription)"
                }
            }
        }
    }

    private func packReady(_ language: LensLanguage) -> Bool {
        TranslationPair.allDirections.filter { $0.source == language || $0.target == language }
            .allSatisfy { statuses[$0] == .installed }
    }

    private func start() {
        generation = UUID()
        busy = true
        message = "언어 팩을 준비하고 있습니다. 시스템 다운로드 안내를 확인해 주세요."
        let pair = TranslationPair.allDirections.first { statuses[$0] != .installed }
            ?? TranslationPair(source: .korean, target: .japanese)
        attempted = [pair]
        configuration = .init(source: pair.source.locale, target: pair.target.locale,
                              preferredStrategy: .lowLatency)
    }

    private func check(token: UUID) async {
        let engine = AppleTranslationEngine()
        var checked: [TranslationPair: LanguagePairStatus] = [:]
        for pair in TranslationPair.allDirections {
            checked[pair] = await engine.availability(source: pair.source, target: pair.target)
            guard active, token == generation, !Task.isCancelled else { return }
        }
        statuses = checked
        ready = checked.count == 6 && checked.values.allSatisfy { $0 == .installed }
        if ready { message = "6개 번역 방향이 모두 준비되었습니다." }
        else if !busy { message = "아직 준비되지 않은 언어 팩이 있습니다." }
    }
}

import SwiftUI
@preconcurrency import Translation

@MainActor
struct LanguagePreparationView: View {
    @ObservedObject var model: LensModel
    @ObservedObject var catalog: LanguageCatalog
    let onReady: () -> Void
    @State private var selectedSource: LensLanguage?
    @State private var search = ""
    @State private var configuration: TranslationSession.Configuration?
    @State private var message = "번역할 원문 언어를 선택하세요."
    @State private var busy = false
    @State private var generation = UUID()
    @State private var active = true

    private var sources: [LensLanguage] {
        catalog.sourceLanguages.filter {
            !$0.isSameLanguage(as: model.target) &&
                (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.rawValue.localizedCaseInsensitiveContains(search))
        }
    }
    private var selectedRoute: TranslationRoute? {
        selectedSource.flatMap { catalog.route(from: $0, to: model.target) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("번역 언어", selection: $model.targetPreference) {
                    Text("macOS 언어 사용").tag(nil as LensLanguage?)
                    ForEach(catalog.languages) { Text($0.title).tag(Optional($0)) }
                }.disabled(busy)
                Text("\(model.target.title)로 번역할 때의 설치 상태입니다.").foregroundStyle(.secondary)
            }.formStyle(.grouped).frame(height: 110)
            HStack {
                TextField("원문 언어 검색", text: $search).textFieldStyle(.roundedBorder)
                if catalog.loading { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 20).padding(.bottom, 12)
            List(selection: $selectedSource) {
                ForEach(sources) { language in
                    HStack {
                        Text(language.title)
                        Spacer()
                        if let route = catalog.route(from: language, to: model.target) {
                            Label(statusLabel(route), systemImage: route.status == .installed ? "checkmark.circle" : "arrow.down.circle")
                                .foregroundStyle(.secondary).font(.callout)
                        } else { Text("확인 중…").foregroundStyle(.secondary) }
                    }.tag(language)
                }
            }.listStyle(.inset).frame(minHeight: 200).disabled(busy)
            VStack(alignment: .leading, spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                Text("화면 인식이 가능한 원문 언어만 표시합니다. macOS 표시 언어·키보드·음성 다운로드와 번역 모델 설치는 별개입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            Divider()
            HStack {
                Button("다시 확인") { Task { await model.refreshLanguages() } }.disabled(busy || catalog.loading)
                Spacer()
                if busy {
                    Button("준비 중단") { cancelPreparation() }
                } else {
                    Button("선택한 언어 준비") { start() }
                        .disabled(selectedRoute?.status != .supported)
                }
                Button("완료", action: onReady).keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .task {
            active = true
            selectedSource = model.source
            await model.refreshLanguages()
        }
        .onChange(of: selectedSource) { _, _ in
            cancelPreparation()
            if let route = selectedRoute {
                message = route.status == .installed ? "선택한 언어는 바로 사용할 수 있습니다." :
                    (route.status == .supported ? "선택한 언어 쌍을 준비하려면 ‘선택한 언어 준비’를 누르세요." : "이 언어 쌍은 현재 macOS에서 지원하지 않습니다.")
            }
        }
        .onChange(of: model.targetPreference) { _, _ in cancelPreparation() }
        .onDisappear { active = false; cancelPreparation() }
        .translationTask(configuration) { session in
            let token = generation
            do {
                try await session.prepareTranslation()
                try Task.checkCancellation()
                guard active, token == generation else { return }
                await model.refreshLanguages()
                guard active, token == generation, !Task.isCancelled else { return }
                busy = false; configuration = nil
                message = selectedRoute?.status == .installed ? "준비되었습니다. 설정에서 이 원문 언어를 선택하거나 자동 감지를 사용하세요." :
                    "아직 준비가 끝나지 않았습니다. 잠시 후 다시 확인하세요."
            } catch {
                guard active, token == generation else { return }
                busy = false; configuration = nil
                message = error is CancellationError || TranslationError.alreadyCancelled ~= error
                    ? "다운로드가 취소되었습니다. 다시 준비할 수 있습니다."
                    : "언어 준비에 실패했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func statusLabel(_ route: TranslationRoute) -> String {
        switch route.status {
        case .installed: route.strategy == .lowLatency ? "사용 가능" : "사용 가능 · Apple Intelligence"
        case .supported: "준비 필요"
        case .unsupported: "번역 미지원"
        }
    }
    private func start() {
        guard let source = selectedSource, let route = selectedRoute, route.status == .supported else { return }
        generation = UUID(); busy = true
        message = "macOS의 언어 준비 안내를 확인하세요. 진행률은 시스템에서 표시합니다."
        configuration = .init(source: source.locale, target: model.target.locale,
                              preferredStrategy: route.strategy.appleStrategy)
    }
    private func cancelPreparation() {
        generation = UUID(); configuration = nil
        if busy { message = "준비를 중단했습니다. 이미 시작된 시스템 다운로드는 계속될 수 있습니다." }
        busy = false
    }
}

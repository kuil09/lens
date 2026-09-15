import SwiftUI
@preconcurrency import Translation

@MainActor
struct LanguagePreparationView: View {
    @ObservedObject var model: LensModel
    @StateObject private var catalog = LanguageCatalog()
    @State private var target: LensLanguage
    let onReady: () -> Void
    @State private var selectedSource: LensLanguage?
    @State private var search = ""
    @State private var configuration: TranslationSession.Configuration?
    @State private var message = L10n.text("Select the source language to translate.")
    @State private var busy = false
    @State private var generation = UUID()
    @State private var active = true

    init(model: LensModel, onReady: @escaping () -> Void) {
        self.model = model; self.onReady = onReady
        _target = State(initialValue: model.target)
    }

    private var sources: [LensLanguage] {
        catalog.sourceLanguages.filter {
            !$0.isSameLanguage(as: target) &&
                (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.rawValue.localizedCaseInsensitiveContains(search))
        }
    }
    private var selectedRoute: TranslationRoute? {
        selectedSource.flatMap { catalog.route(from: $0, to: target) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(L10n.text("Target language to download"), selection: $target) {
                    ForEach(catalog.languages) { Text($0.title).tag($0) }
                }.disabled(busy)
                Text(L10n.text("Add languages here without changing the lens selection.")).foregroundStyle(.secondary)
            }.formStyle(.grouped).frame(height: 110)
            HStack {
                TextField(L10n.text("Search source languages"), text: $search).textFieldStyle(.roundedBorder)
                if catalog.loading { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 20).padding(.bottom, 12)
            List(selection: $selectedSource) {
                ForEach(sources) { language in
                    HStack {
                        Text(language.title)
                        Spacer()
                        if let route = catalog.route(from: language, to: target) {
                            Label(statusLabel(route), systemImage: route.status == .installed ? "checkmark.circle" : "arrow.down.circle")
                                .foregroundStyle(.secondary).font(.callout)
                        } else { Text(L10n.text("Checking…")).foregroundStyle(.secondary) }
                    }.tag(language)
                }
            }.listStyle(.inset).frame(minHeight: 200).disabled(busy)
            VStack(alignment: .leading, spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                Text(L10n.text("Only OCR-compatible source languages appear here. Display, keyboard, and voice languages are separate from translation packs."))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            Divider()
            HStack {
                Button(L10n.text("Check Again")) { Task { await refresh() } }.disabled(busy || catalog.loading)
                Spacer()
                if busy {
                    Button(L10n.text("Stop Preparation")) { cancelPreparation() }
                } else {
                    Button(L10n.text("Prepare Selected Languages")) { start() }
                        .disabled(selectedRoute?.status != .supported)
                }
                Button(L10n.text("Done"), action: onReady).keyboardShortcut(.defaultAction).disabled(busy)
            }.padding(16)
        }
        .task(id: target) {
            active = true
            await refresh()
        }
        .onChange(of: selectedSource) { _, _ in
            cancelPreparation()
            if let route = selectedRoute {
                message = route.status == .installed ? L10n.text("The selected languages are ready to use.") :
                    (route.status == .supported ? L10n.text("Click “Prepare Selected Languages” to download this pair.") : L10n.text("This language pair is not supported by this version of macOS."))
            }
        }
        .onChange(of: target) { _, _ in cancelPreparation(); selectedSource = nil }
        .onDisappear { active = false; cancelPreparation() }
        .translationTask(configuration) { session in
            let token = generation
            do {
                try await session.prepareTranslation()
                try Task.checkCancellation()
                guard active, token == generation else { return }
                await model.refreshLanguages()
                await refresh()
                guard active, token == generation, !Task.isCancelled else { return }
                busy = false; configuration = nil
                message = selectedRoute?.status == .installed ? L10n.text("Ready. Select this source language in settings or use automatic detection.") :
                    L10n.text("Not ready yet. Check again shortly.")
            } catch {
                guard active, token == generation else { return }
                busy = false; configuration = nil
                message = error is CancellationError || TranslationError.alreadyCancelled ~= error
                    ? L10n.text("Download canceled. You can try again.")
                    : L10n.text("Language preparation failed: %1$@", String(describing: error.localizedDescription))
            }
        }
    }

    private func statusLabel(_ route: TranslationRoute) -> String {
        switch route.status {
        case .installed: route.strategy == .lowLatency ? L10n.text("Ready") : L10n.text("Ready · Apple Intelligence")
        case .supported: L10n.text("Download Needed")
        case .unsupported: L10n.text("Translation Unavailable")
        }
    }
    private func start() {
        guard let source = selectedSource, let route = selectedRoute, route.status == .supported else { return }
        generation = UUID(); busy = true
        message = L10n.text("Follow the macOS language download instructions. Progress is shown by the system.")
        configuration = .init(source: source.locale, target: target.locale,
                              preferredStrategy: route.strategy.appleStrategy)
    }
    private func refresh() async {
        await catalog.load(checkInstallation: false)
        guard !Task.isCancelled else { return }
        await catalog.refresh(target: target)
    }
    private func cancelPreparation() {
        generation = UUID(); configuration = nil
        if busy { message = L10n.text("Preparation stopped. A system download already in progress may continue.") }
        busy = false
    }
}

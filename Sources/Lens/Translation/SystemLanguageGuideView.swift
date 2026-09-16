import SwiftUI
@preconcurrency import Translation

@MainActor
struct SystemLanguageGuideView: View {
    @ObservedObject var model: LensModel
    @StateObject private var catalog = LanguageCatalog()
    let onReady: () -> Void
    @State private var target: LensLanguage
    @State private var checking = false
    @State private var message = L10n.text("Click the button below to open the system Translation Languages settings.")
    @State private var hasInstalledRoute = false

    init(model: LensModel, onReady: @escaping () -> Void) {
        self.model = model; self.onReady = onReady
        _target = State(initialValue: model.target)
    }

    private var canOpenSystemSettings: Bool {
        URL(string: "x-apple.systempreferences:com.apple.Localization") != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(L10n.text("Target language to download"), selection: $target) {
                    ForEach(catalog.languages) { Text($0.title).tag($0) }
                }.disabled(checking)
                Text(L10n.text("Add languages here without changing the lens selection.")).foregroundStyle(.secondary)
            }.formStyle(.grouped).frame(height: 110)

            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("Download translation languages from macOS System Settings"))
                    .font(.headline)

                Text(L10n.text("Open System Settings → General → Language & Region → Translation Languages"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(L10n.text("Click the button below to open the system Translation Languages settings."))
                    .foregroundStyle(.secondary)

                if canOpenSystemSettings {
                    Button(L10n.text("Open System Settings…")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .modifier(LensGlassAction(prominent: true))
                }

                Divider()

                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.text("You can continue using installed languages without downloading."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(L10n.text("Only OCR-compatible source languages appear here. Display, keyboard, and voice languages are separate from translation packs."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()

            HStack {
                Button(L10n.text("Check Again")) { Task { await refresh() } }
                    .disabled(checking || catalog.loading)
                Spacer()
                Button(L10n.text("Done"), action: onReady)
                    .keyboardShortcut(.defaultAction)
                    .disabled(checking)
            }
            .padding(16)
        }
        .task(id: target) {
            checking = true
            await refresh()
            checking = false
        }
        .onDisappear { }
    }

    private func refresh() async {
        await catalog.load(checkInstallation: false)
        await catalog.refresh(target: target)

        // Check if there's at least one installed source route to this target
        var installed = false
        for source in catalog.sourceLanguages where !source.isSameLanguage(as: target) {
            let route = catalog.route(from: source, to: target)
            if route?.status == .installed { installed = true; break }
        }
        hasInstalledRoute = installed

        if installed {
            message = L10n.text("Translation languages are ready.")
        } else {
            message = L10n.text("Some translation languages need to be downloaded.")
        }
    }
}
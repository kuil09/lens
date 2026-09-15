import AppKit
import SwiftUI

struct LensLanguageBar: View {
    @ObservedObject var model: LensModel
    @ObservedObject var catalog: LanguageCatalog
    let onToggle: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let layout = LensLanguageBarLayout(width: geometry.size.width)
            ZStack {
                Grid(horizontalSpacing: LensLanguageBarLayout.gap, verticalSpacing: 4) {
                    GridRow {
                        Text(L10n.text("Source")).font(.caption).foregroundStyle(.secondary)
                        Color.clear.frame(width: LensLanguageBarLayout.swapWidth, height: 0)
                            .accessibilityHidden(true)
                        Text(L10n.text("Target")).font(.caption).foregroundStyle(.secondary)
                    }
                    GridRow {
                        sourcePicker.frame(width: layout.fieldWidth, height: 24)
                        Button(action: model.swapLanguages) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: LensLanguageBarLayout.swapWidth, height: 24)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(L10n.text("Swap Source and Target"))
                        .help(model.source == nil ? L10n.text("Choose a source language instead of Auto Detect to swap languages.") : L10n.text("Swap the languages. The new source must support OCR."))
                        .disabled(!model.canSwapLanguages)
                        .buttonStyle(.borderless)
                        targetPicker.frame(width: layout.fieldWidth, height: 24)
                    }
                }
                .frame(width: layout.pairWidth, height: geometry.size.height)
                .position(x: layout.pairCenter, y: geometry.size.height / 2)
                HStack { Divider() }.frame(width: 1, height: 28)
                    .position(x: geometry.size.width - 56, y: geometry.size.height / 2)
                VStack(spacing: 4) {
                    Text(L10n.text("Translation")).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8).accessibilityHidden(true)
                    Toggle(L10n.text("Translation"), isOn: Binding(get: { model.running }, set: { if $0 != model.running { onToggle() } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(!model.running && !model.canTranslate)
                        .frame(height: 24)
                        .help(model.running ? L10n.text("Turn translation off and show the frosted background.") : L10n.text("Reveal the screen underneath and start translating."))
                }
                .frame(width: 44, height: geometry.size.height)
                .position(x: geometry.size.width - 22, y: geometry.size.height / 2)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(height: 64)
    }

    private var sourcePicker: some View {
        Picker(L10n.text("Source"), selection: $model.source) {
            Text(L10n.text("Auto Detect")).tag(nil as LensLanguage?)
            ForEach(model.selectableSources) { Text($0.title).tag(Optional($0)) }
        }.labelsHidden().pickerStyle(.menu)
            .disabled(catalog.checkingInstallation || catalog.loading || model.selectableSources.isEmpty)
    }

    private var targetPicker: some View {
        Picker(L10n.text("Target"), selection: $model.targetPreference) {
            Text(catalog.installedTargets.isEmpty ? L10n.text("No Installed Languages") : L10n.text("System · %1$@", String(describing: model.systemTarget.title))).tag(nil as LensLanguage?)
            ForEach(catalog.installedTargets) { Text($0.title).tag(Optional($0)) }
        }.labelsHidden().pickerStyle(.menu).disabled(catalog.checkingInstallation || catalog.installedTargets.isEmpty)
    }
}

/// Equal language columns around the swap control, independent of the selected text.
struct LensLanguageBarLayout {
    static let gap: CGFloat = 8
    static let swapWidth: CGFloat = 28
    let pairWidth: CGFloat
    let pairCenter: CGFloat
    var fieldWidth: CGFloat { (pairWidth - Self.swapWidth - 2 * Self.gap) / 2 }

    init(width: CGFloat) {
        let centered = width >= 480
        pairWidth = min(364, max(44, width - (centered ? 120 : 60)))
        // Compact windows reserve space for the switch; wide windows center on the lens.
        pairCenter = centered ? width / 2 : pairWidth / 2
    }
}

/// A titlebar accessory keeps all language controls outside captured pixels.
@MainActor final class LensLanguageBarController: NSTitlebarAccessoryViewController {
    init(model: LensModel, onToggle: @escaping () -> Void) {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .bottom
        automaticallyAdjustsSize = false
        let hosting = NSHostingView(rootView: LensLanguageBar(model: model, catalog: model.languages, onToggle: onToggle))
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 576, height: 64)
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 16
        glass.contentView = hosting
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 80))
        container.autoresizingMask = [.width]
        glass.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(glass)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 80),
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            glass.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            glass.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            glass.heightAnchor.constraint(equalToConstant: 64)
        ])
        view = container
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

import SwiftUI

enum LensSettingsPage: String, CaseIterable, Identifiable {
    case translation, appearance, capture
    var id: String { rawValue }
    var title: String {
        switch self { case .translation: L10n.text("Translation"); case .appearance: L10n.text("Appearance"); case .capture: L10n.text("Capture") }
    }
    var symbol: String {
        switch self { case .translation: "character.bubble"; case .appearance: "viewfinder"; case .capture: "camera" }
    }
    var summary: String {
        switch self {
        case .translation: L10n.text("Choose the languages to read and translate into.")
        case .appearance: L10n.text("Adjust how the screen and translations appear.")
        case .capture: L10n.text("Save what you see in the lens as images and videos.")
        }
    }
}

@MainActor final class LensSettingsSelection: ObservableObject {
    @Published var page: LensSettingsPage = .translation
}

struct LensControls: View {
    @ObservedObject var model: LensModel
    @ObservedObject var languages: LanguageCatalog
    @ObservedObject var recording: LensRecording
    @ObservedObject var selection: LensSettingsSelection
    @ObservedObject var exports: LensExportStore
    let onToggle: () -> Void
    let onLock: () -> Void
    let onPrepare: () -> Void
    let onReader: () -> Void
    let onCapture: () -> Void
    let onRecord: () -> Void
    let onPermissionSettings: () -> Void
    var onCheckPermission: () -> Void = {}
    var onChooseDirectory: () -> Void = {}
    var onOpenDirectory: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selection.page.title).font(.system(size: 26, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(selection.page.summary).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
            Form {
                switch selection.page {
                case .translation: translation
                case .appearance: appearance
                case .capture: capture
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 500, minHeight: 440)
    }

    private var translation: some View {
        Group {
            if model.permissionNeeded {
                Section {
                    Label(L10n.text("Screen Recording access is required"), systemImage: "lock.shield")
                        .font(.headline)
                    Text(L10n.text("Allow Lens in System Settings to read text behind the lens."))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.text("Open System Settings…"), action: onPermissionSettings)
                            .modifier(LensGlassAction(prominent: true))
                        Button(L10n.text("Check Again"), action: onCheckPermission)
                            .modifier(LensGlassAction())
                    }
                } footer: {
                    Text(L10n.text("Return to Lens from the Dock when finished. Translation stays paused. Quit and reopen only if macOS asks you to."))
                }
            }
            Section {
                Picker(L10n.text("Source"), selection: $model.source) {
                    Text(L10n.text("Auto Detect")).tag(nil as LensLanguage?)
                    Divider()
                    ForEach(model.selectableSources) { Text($0.title).tag(Optional($0)) }
                }.disabled(languages.checkingInstallation || languages.loading || model.selectableSources.isEmpty)
                Picker(L10n.text("Target"), selection: $model.targetPreference) {
                    Text(languages.installedTargets.isEmpty ? L10n.text("No Installed Languages") : L10n.text("Use macOS Language (%1$@)", String(describing: model.systemTarget.title))).tag(nil as LensLanguage?)
                    Divider()
                    ForEach(languages.installedTargets) { Text($0.title).tag(Optional($0)) }
                }.disabled(languages.checkingInstallation || languages.installedTargets.isEmpty)
            } header: { Text(L10n.text("Languages")) } footer: {
                Text(L10n.text("Only installed translation packs appear here. Sources must support OCR and translation into the selected target. Add languages in Language Packs."))
            }
            Section {
                LabeledContent(L10n.text("On-Device Translation")) {
                    Button(L10n.text("Language Packs…"), action: onPrepare)
                        .modifier(LensGlassAction())
                }
                if languages.loading || languages.checkingInstallation {
                    ProgressView(L10n.text("Checking available languages…")).controlSize(.small)
                } else if let error = languages.error {
                    Text(L10n.text("Could not check OCR languages: %1$@", String(describing: error))).foregroundStyle(.secondary)
                } else if model.source?.isSameLanguage(as: model.target) == true {
                    Text(L10n.text("The source and target languages are the same.")).foregroundStyle(.secondary)
                } else if let source = model.source, let route = languages.route(from: source, to: model.target) {
                    Label(route.status == .installed ? L10n.text("The selected languages are ready") : L10n.text("Check readiness in Language Packs"),
                          systemImage: route.status == .installed ? "checkmark.circle" : "arrow.down.circle")
                } else {
                    Text(L10n.text("Ready for %1$@: %2$@ source languages", String(describing: model.target.title), String(describing: languages.sourceLanguages.filter { languages.route(from: $0, to: model.target)?.status == .installed }.count)))
                        .foregroundStyle(.secondary)
                }
            } footer: { Text(L10n.text("Uses individually downloaded translation packs on this Mac, not the full Apple Intelligence language list. Languages are never downloaded automatically.")) }
            Section {
                LabeledContent {
                    Button(model.running ? L10n.text("Pause") : L10n.text("Start Translation"), action: onToggle)
                        .modifier(LensGlassAction(prominent: !model.running))
                        .disabled(!model.running && (!model.canTranslate || model.permissionNeeded))
                } label: {
                    Label(model.permissionNeeded ? L10n.text("Permission Needed") : (model.running ? L10n.text("Translating") : L10n.text("Paused")),
                          systemImage: model.permissionNeeded ? "exclamationmark.circle" : (model.running ? "play.circle" : "pause.circle"))
                }
                if !model.permissionNeeded {
                    Text(model.status).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text(L10n.text("Current Status")) }
        }
    }

    private var appearance: some View {
        Group {
            Section {
                Label(L10n.text("Transparent While Translating"), systemImage: "viewfinder")
                Text(L10n.text("When translation is off, the lens has a frosted glass background. Turn it on to reveal the screen and translate text in place."))
                    .foregroundStyle(.secondary)
            } header: { Text(L10n.text("Lens Background")) } footer: { Text(L10n.text("The lens border stays visible. Reduce Transparency replaces glass with a solid background.")) }
            Section {
                LabeledContent(L10n.text("Cover Original Text")) {
                    Text(model.opacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.opacity, in: 0...1) {
                    Text(L10n.text("Cover Original Text"))
                } minimumValueLabel: { Text("0%") } maximumValueLabel: { Text("100%") }
                .labelsHidden()
                .accessibilityValue(L10n.text("%1$@ percent", String(describing: Int(model.opacity * 100))))
            } footer: { Text(L10n.text("How much background color covers the original text. Translation text opacity stays unchanged.")) }
            Section {
                Toggle(L10n.text("Pass Through Clicks and Scrolling"), isOn: $model.locked)
                    .onChange(of: model.locked) { _, _ in onLock() }
            } header: { Text(L10n.text("Mouse")) } footer: {
                Text(L10n.text("Clicks and scrolling in the lens body go to the app behind it. The toolbar stays available. Turn off to resize from the body."))
            }
        }
    }

    private var capture: some View {
        Group {
            Section {
                Label(exports.directory.lastPathComponent, systemImage: "folder")
                    .font(.headline)
                Text(exports.directory.path).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L10n.text("Change Folder…"), action: onChooseDirectory).modifier(LensGlassAction())
                    Button(L10n.text("Open in Finder"), action: onOpenDirectory).modifier(LensGlassAction())
                }
            } header: { Text(L10n.text("Save Folder")) } footer: {
                Text(L10n.text("Images and videos are saved with date and time in their names. Existing files are never replaced. Folder changes apply to the next capture or recording."))
            }
            if !model.hasFrame && !recording.isRecording {
                Section {
                    Label(L10n.text("Saving is available once the screen connects"), systemImage: "info.circle")
                    Button(L10n.text("Open Translation Settings")) { selection.page = .translation }
                }
            }
            Section {
                LabeledContent(L10n.text("PNG Image")) {
                    Button(L10n.text("Save Image"), action: onCapture).disabled(!model.hasFrame)
                        .modifier(LensGlassAction())
                }
            } header: { Text(L10n.text("Image")) } footer: { Text(L10n.text("Save the current lens view and translations as one image.")) }
            Section {
                LabeledContent(L10n.text("MP4 Video"), value: L10n.text("Up to 15 fps · No audio"))
                HStack {
                    if recording.isRecording {
                        Label(L10n.text("Recording %1$@", String(describing: recording.durationText)), systemImage: "record.circle")
                            .foregroundStyle(.red).monospacedDigit()
                    } else if recording.isFinishing {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("Saving video…"))
                    }
                    Spacer()
                    Button(recording.isRecording ? L10n.text("Stop Recording and Save") : L10n.text("Start Recording"), action: onRecord)
                        .modifier(LensGlassAction(prominent: recording.isRecording))
                        .tint(recording.isRecording ? .red : .accentColor)
                        .disabled(recording.isFinishing || (!recording.isRecording && !model.hasFrame))
                }
                if !recording.isRecording && !recording.isFinishing && recording.elapsed > 0 {
                    Text(recording.message).foregroundStyle(.secondary)
                }
            } header: { Text(L10n.text("Video")) } footer: {
                Text(L10n.text("Moving or resizing the lens, changing languages, pausing, or quitting ends and saves the recording. Closing settings does not stop it."))
            }
            Section {
                Label(L10n.text("Transparent mode also saves the background"), systemImage: "rectangle.on.rectangle")
                Text(L10n.text("The title bar and other Lens windows are excluded. Saving does not ask for a path or filename."))
                    .foregroundStyle(.secondary)
            }
            if let saved = exports.lastSavedURL {
                Section(L10n.text("Recently Saved")) {
                    Text(saved.lastPathComponent).textSelection(.enabled)
                    Button(L10n.text("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
                        .modifier(LensGlassAction())
                }
            }
        }
    }
}

struct TranslationReader: View {
    @ObservedObject var model: LensModel
    let onShowLens: () -> Void
    let onSettings: () -> Void
    @State private var showOriginal = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Full Translation")).font(.headline)
                    Text(L10n.text("Translations: %1$@", String(describing: model.translations.count))).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 14) {
                    Toggle(L10n.text("Show Original"), isOn: $showOriginal).toggleStyle(.checkbox)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.translations.map(\.text).joined(separator: "\n\n"), forType: .string)
                    } label: { Label(L10n.text("Copy All"), systemImage: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .disabled(model.translations.isEmpty)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .modifier(LensGlassControlGroup())
            }.padding(16)
            Divider()
            if model.translations.isEmpty {
                ContentUnavailableView {
                    Label(L10n.text("No translations yet"), systemImage: "character.bubble")
                } description: {
                    Text(model.permissionNeeded ? L10n.text("Allow Screen Recording access, then place the lens over text.") : L10n.text("Place the lens over text. You can read the full translation here even if it is truncated in the lens."))
                } actions: {
                    Button(model.permissionNeeded ? L10n.text("Open Settings…") : L10n.text("Show Lens"), action: model.permissionNeeded ? onSettings : onShowLens)
                        .modifier(LensGlassAction(prominent: true))
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(model.translations) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                if showOriginal { Text(item.block.text).foregroundStyle(.secondary) }
                                Text(item.text).font(.body)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button(L10n.text("Copy Translation")) {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.text, forType: .string)
                                    }
                                }
                            Divider()
                        }
                    }.padding(24)
                }
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct LensHelpView: View {
    var body: some View {
        Form {
            Section(L10n.text("Translate on Your Screen")) {
                Text(L10n.text("1. Prepare screen access and language packs in settings."))
                Text(L10n.text("2. Place the lens over text and adjust its size."))
                Text(L10n.text("3. Enable click-through to interact with the app underneath."))
            }
            Section(L10n.text("Keyboard Shortcuts")) {
                LabeledContent(L10n.text("Settings"), value: "⌘,")
                LabeledContent(L10n.text("Show Lens"), value: "⌘L")
                LabeledContent(L10n.text("Start / Pause Translation"), value: "⌘R")
                LabeledContent(L10n.text("Pass Through Clicks and Scrolling"), value: "⌘K")
                LabeledContent(L10n.text("Full Translation"), value: "⌘T")
                LabeledContent(L10n.text("Save Image"), value: "⇧⌘S")
                LabeledContent(L10n.text("Start / Stop Recording"), value: "⇧⌘R")
                Text(L10n.text("Shortcuts work while Lens is active. When using another app, use the Lens icon in the menu bar.")).foregroundStyle(.secondary)
            }
            Section(L10n.text("Privacy and Saving")) {
                Text(L10n.text("Text recognition and translation happen on device. Images and videos are saved only when requested. Audio is never recorded."))
                Text(L10n.text("Choose a save folder in Settings → Capture. Images and videos accumulate there without a filename dialog. The default is Pictures/Lens."))
                Text(L10n.text("The menu bar shows recording status. Force-quitting may prevent a video from being saved correctly."))
            }
        }.formStyle(.grouped).frame(minWidth: 460, minHeight: 500)
    }
}

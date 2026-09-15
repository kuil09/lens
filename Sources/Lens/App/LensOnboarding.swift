import AppKit
import SwiftUI

@MainActor final class LensOnboardingState: ObservableObject {
    enum Step: Int, CaseIterable { case permission, languages, saving }
    @Published var step: Step { didSet { defaults.set(step.rawValue, forKey: "onboardingStep") } }
    @Published var permissionGranted = false
    @Published var deferred = false
    @Published var requestingPermission = false
    @Published var recoveryNotice: String?
    @Published private(set) var completed: Bool
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completed = defaults.bool(forKey: "onboardingCompleted")
        step = Step(rawValue: defaults.integer(forKey: "onboardingStep")) ?? .permission
    }
    // A missing grant gates the view without erasing the user's saved progress.
    var visibleStep: Step { permissionGranted ? step : .permission }
    func refreshPermission(using access: ScreenRecordingAccess) { permissionGranted = access.isGranted }
    func finish(languagesReady: Bool) -> Bool {
        guard permissionGranted, languagesReady else { return false }
        completed = true
        defaults.set(true, forKey: "onboardingCompleted")
        return true
    }
}

struct LensOnboardingView: View {
    @ObservedObject var state: LensOnboardingState
    @ObservedObject var model: LensModel
    @ObservedObject var catalog: LanguageCatalog
    @ObservedObject var exports: LensExportStore
    let onPermission: () -> Void
    let onRefresh: () -> Void
    let onPrepare: () -> Void
    let onDirectory: () -> Void
    let onFinish: () -> Void
    let onLater: () -> Void

    private var title: String {
        switch state.visibleStep {
        case .permission: L10n.text("Translate right on your screen")
        case .languages: L10n.text("Which language would you like to read?")
        case .saving: L10n.text("Save the moments you want to keep")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("Welcome to Lens")).font(.headline)
                    Text("\(state.visibleStep.rawValue + 1) / 3").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.bottom, 24)
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                .padding(.bottom, 16)
            ScrollView {
                Group {
                    switch state.visibleStep {
                    case .permission: permission
                    case .languages: languages
                    case .saving: saving
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 20)
            }
            Divider().padding(.bottom, 16)
            HStack {
                Button(L10n.text("Later"), action: onLater)
                Spacer()
                if state.visibleStep != .permission {
                    Button(L10n.text("Back")) { state.step = .init(rawValue: state.step.rawValue - 1)! }
                }
                Button(state.visibleStep == .saving ? L10n.text("Open Lens") : L10n.text("Continue")) {
                    if state.visibleStep == .saving { onFinish() }
                    else { state.step = .init(rawValue: state.step.rawValue + 1)! }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.requestingPermission || (state.visibleStep == .permission ? !state.permissionGranted : !model.canTranslate))
            }
        }.padding(28).frame(width: 540, height: 460)
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Place the lens where you want to read. It recognizes text underneath and translates it in place."))
            Label(state.permissionGranted ? L10n.text("Screen Recording access is allowed") : L10n.text("Screen Recording access is required"),
                  systemImage: state.permissionGranted ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                .font(.headline)
            Text(L10n.text("The screen is read only while translation is on. Screen text and translations are processed on device. Files are saved only when you capture or record."))
                .foregroundStyle(.secondary)
            HStack {
                if !state.permissionGranted { Button(L10n.text("Open System Settings…"), action: onPermission) }
                Button(L10n.text("Check Permission Again"), action: onRefresh)
            }.disabled(state.requestingPermission)
            Text(L10n.text("Return to Lens from the Dock when finished. Translation stays paused. Quit and reopen only if macOS asks you to."))
                .font(.caption).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var languages: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Choose from translation packs installed on this Mac. The default is the installed language closest to your macOS preference."))
                .foregroundStyle(.secondary)
            Picker(L10n.text("Target"), selection: $model.targetPreference) {
                Text(catalog.installedTargets.isEmpty ? L10n.text("No Installed Languages") : L10n.text("System · %1$@", String(describing: model.systemTarget.title)))
                    .tag(nil as LensLanguage?)
                ForEach(catalog.installedTargets) { Text($0.title).tag(Optional($0)) }
            }.disabled(catalog.checkingInstallation || catalog.installedTargets.isEmpty)
            Picker(L10n.text("Source"), selection: $model.source) {
                Text(L10n.text("Auto Detect")).tag(nil as LensLanguage?)
                ForEach(model.selectableSources) { Text($0.title).tag(Optional($0)) }
            }.disabled(catalog.checkingInstallation || catalog.loading || model.selectableSources.isEmpty)
            if catalog.checkingInstallation || catalog.loading {
                ProgressView(L10n.text("Checking installed languages…")).controlSize(.small)
            } else if !model.canTranslate {
                Label(L10n.text("Prepare a translation language pack first"), systemImage: "arrow.down.circle")
            } else {
                Label(L10n.text("The selected languages are ready"), systemImage: "checkmark.circle")
            }
            HStack {
                Button(L10n.text("Add Language Packs…"), action: onPrepare)
                Button(L10n.text("Check Again"), action: onRefresh).disabled(catalog.checkingInstallation || catalog.loading)
            }
            Text(L10n.text("Internet access is needed only to download new language packs. Display, keyboard, and voice languages are separate."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var saving: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(exports.directory.lastPathComponent, systemImage: "folder").font(.headline)
            Text(exports.directory.path).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(3).truncationMode(.middle)
            Button(L10n.text("Change Save Folder…"), action: onDirectory)
            Text(L10n.text("Use the camera button for PNG images and the record button for silent MP4 videos. No filename prompts or overwriting existing files."))
            Text(L10n.text("Open the lens and turn on Translation at the right. You can toggle click-through from the menu bar."))
                .foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

import AppKit
import SwiftUI

/// A normal window, never a floating overlay or an automatic permission prompt.
struct LensPermissionGuide: View {
    @ObservedObject var state: LensOnboardingState
    @ObservedObject var model: LensModel
    @ObservedObject var catalog: LanguageCatalog
    @ObservedObject var recording: LensRecording
    let onSettings: () -> Void
    let onRefresh: () -> Void
    let onContinue: () -> Void
    let onQuit: () -> Void

    var title: String {
        if state.deferred { return L10n.text("Lens is paused") }
        guard state.permissionGranted else { return L10n.text("Allow screen access to translate") }
        if checkingLanguages { return L10n.text("Checking installed languages…") }
        return model.canTranslate ? L10n.text("Ready when you are") : L10n.text("Continue Setup")
    }
    private var checkingLanguages: Bool { catalog.loading || catalog.checkingInstallation }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("Translation and recording are stopped. Your language choices and save folder are kept."))
                    if state.deferred {
                        Text(L10n.text("You can continue setup here or quit Lens and pick up where you left off next time."))
                            .foregroundStyle(.secondary)
                        Button(L10n.text("Resume Setup")) { state.deferred = false; onRefresh() }
                    } else {
                        Label(state.permissionGranted ? L10n.text("Screen Recording access is allowed") : L10n.text("Screen Recording access is required"),
                              systemImage: state.permissionGranted ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                        if !state.permissionGranted {
                            Text(L10n.text("Return to Lens from the Dock when finished. Translation stays paused. Quit and reopen only if macOS asks you to."))
                                .foregroundStyle(.secondary)
                            Button(L10n.text("Open System Settings…"), action: onSettings)
                                .disabled(state.requestingPermission || recording.isFinishing)
                        } else if checkingLanguages {
                            ProgressView(L10n.text("Checking installed languages…")).controlSize(.small)
                        } else if !model.canTranslate {
                            Text(L10n.text("Prepare a translation language pack first")).foregroundStyle(.secondary)
                        }
                        Button(L10n.text("Check Permission Again"), action: onRefresh)
                            .disabled(state.requestingPermission)
                    }
                    if recording.isFinishing { ProgressView(L10n.text("Saving video…")) }
                    if let notice = state.recoveryNotice {
                        Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            }
            Divider()
            HStack {
                Button(L10n.text("Quit Lens"), action: onQuit)
                Spacer()
                if !state.deferred {
                    Button(L10n.text("Later")) { state.deferred = true }
                    if state.permissionGranted {
                        Button(state.completed && model.canTranslate ? L10n.text("Start Translation") : L10n.text("Continue Setup"), action: onContinue)
                            .keyboardShortcut(.defaultAction)
                            .disabled(state.requestingPermission || recording.isFinishing || checkingLanguages)
                    }
                }
            }
        }.padding(28).frame(width: 520, height: 390)
    }
}

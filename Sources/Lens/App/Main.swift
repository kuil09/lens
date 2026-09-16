import AppKit
import SwiftUI
import Combine
import OSLog

@main
enum LensMain {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--benchmark") {
            Task { @MainActor in await BenchmarkCommand.run(arguments: CommandLine.arguments); exit(0) }
            RunLoop.main.run()
            return
        }
        let delegate = LensAppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class LensAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let model = LensModel()
    private lazy var exportCoordinator: LensExportCoordinator = {
        let coordinator = LensExportCoordinator(recordingFrame: { [weak self] in self?.model.latestRecordingFrame }, scene: { [weak self] in
            guard let self, model.hasFrame, let image = surface.canvas.snapshotImage() else { return nil }
            return .init(background: image, pointSize: surface.bounds.size,
                         translations: model.translations, opacity: model.opacity)
        })
        coordinator.onStatus = { [weak self] in self?.model.status = $0 }
        coordinator.onError = { [weak self] in self?.showExportError($0, title: $1) }
        coordinator.onChoosingDirectoryChanged = { [weak self] in self?.refreshToolbar() }
        return coordinator
    }()
    private var recording: LensRecording { exportCoordinator.recording }
    private var exports: LensExportStore { exportCoordinator.store }
    private var captureFeedback: LensCaptureFeedback { exportCoordinator.feedback }
    private let systemHandoff = LensSystemHandoff()
    private let onboarding = LensOnboardingState()
    private var onboardingWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private var terminating = false
    private let settingsSelection = LensSettingsSelection()
    private let surface = LensSurface(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    private var lens: LensPanel!
    private var lensToolbar: LensToolbar?
    private var settingsWindow: LensSettingsWindow?
    private let auxiliaryWindows = LensAuxiliaryWindows()
    private var modelObservers = Set<AnyCancellable>()
    private var directoryPanel: NSOpenPanel? { exportCoordinator.directoryPanel }
    private let menus = LensMenuController()
    private var statusItem: NSStatusItem? { menus.statusItem }
    private var restartTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var languageCatalogTask: Task<Void, Never>?
    private var arranging = false
    private var resumeAfterArrangement = false
    private let observations = LensObservationBag()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let area = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let rect = CGRect(x: area.midX - 400, y: area.midY - 250, width: 800, height: 500)
        lens = LensPanel(lensRect: rect)
        lens.title = "Lens"; lens.isReleasedWhenClosed = false
        lens.hidesOnDeactivate = false; lens.isFloatingPanel = true; lens.level = .floating
        // The pair is an overlay in other apps' Spaces, not an independently tiled document.
        lens.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        lens.isOpaque = false; lens.backgroundColor = .clear
        lens.delegate = self; model.attach(surface)
        let toolbar = LensToolbar(onCapture: { [weak self] in self?.saveCapture() },
                                  onRecord: { [weak self] in self?.toggleRecording() },
                                  onReader: { [weak self] in self?.showReader() },
                                  onSettings: { [weak self] in self?.showSettings() },
                                  onLock: { [weak self] in self?.toggleLock() },
                                  onOpenFolder: { [weak self] in self?.openExportDirectory() })
        lensToolbar = toolbar
        toolbar.attach(to: lens)
        lens.addTitlebarAccessoryViewController(LensLanguageBarController(model: model, onToggle: { [weak self] in self?.toggle() }))
        lens.installBody(surface: surface, size: rect.size)
        lens.onMinimize = { [weak self] in self?.pause() }
        captureFeedback.$showsSuccess.removeDuplicates().sink { [weak self] _ in
            // @Published sends before mutation. Refresh after the new value is installed.
            Task { @MainActor in self?.refreshToolbar() }
        }.store(in: &modelObservers)
        lens.onBodyArrangement = { [weak self] finished in
            guard let self else { return }
            if finished { if resumeAfterArrangement { resumeAfterArrangement = false; restart() } }
            else { interruptForArrangement() }
        }
        model.$readiness.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.handleStartAction(self.model.startRequest.resolve(self.model.readiness))
            }
        }.store(in: &modelObservers)
        model.onRestart = { [weak self] in self?.restart(reason: "languageSettings") }
        model.onRegionInvalidated = { [weak self] in self?.recording.stop(reason: .sourceInvalidated) }
        model.onRecordingFrame = { [weak self] in self?.recording.offer($0) }
        model.onRecordingObservation = { [weak self] in self?.recording.observe($0) }
        model.onRecordingTranslation = { [weak self] in self?.recording.resolve($0) }
        recording.onStateChange = { [weak self] in
            if let self {
                lens.setRecordingGeometryLocked(recording.isRecording)
                model.setRecordingActive(recording.isRecording || recording.isFinishing)
            }
            self?.updateStatusItem()
            self?.refreshToolbar()
        }
        model.$running.combineLatest(model.$permissionNeeded, model.$hasFrame)
            .removeDuplicates { $0 == $1 }.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem(); self?.refreshToolbar() }
        }.store(in: &modelObservers)
        recording.onError = { [weak self] message in
            guard let self else { return }
            // Finishing a video must not steal focus from OS authentication.
            if systemHandoff.isActive || !NSApp.isActive || terminating {
                onboarding.recoveryNotice = message
                return
            }
            let alert = NSAlert()
            alert.messageText = L10n.text("Video Save Notice")
            alert.informativeText = message
            alert.runModal()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        // Ordinary app activation, including System Settings, is not a permission request.
        // Only openPermissionSettings may suspend the lens for a permission handoff.
        observations.observe(workspace, name: NSWorkspace.willSleepNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        observations.observe(workspace, name: NSWorkspace.didWakeNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.status = L10n.text("Your Mac woke from sleep. Start translation again when ready.") }
        }
        observations.observe(.default, name: NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }
        model.suspend()
        refreshPermissionStatus()
        refreshLanguageCatalog()
        restoreUserInterface()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard lens != nil, !terminating else { return }
        refreshPermissionStatus()
        if systemHandoff.needsReturnGuide { refreshLanguageCatalog() }
        restoreUserInterface()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard lens != nil, !terminating else { return false }
        refreshPermissionStatus()
        if systemHandoff.needsReturnGuide { refreshLanguageCatalog() }
        restoreUserInterface()
        return true
    }
    private func restoreUserInterface() {
        if lens.isMiniaturized, permissionTask == nil, !systemHandoff.needsReturnGuide {
            showLens()
            return
        }
        let destination = LensReturnDestination.resolve(requestPending: permissionTask != nil,
            handoffPending: systemHandoff.needsReturnGuide,
            hasVisibleWindows: NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.canBecomeKey },
            onboardingCompleted: onboarding.completed, permissionGranted: onboarding.permissionGranted)
        switch destination {
        case .none: break
        case .onboarding: showOnboarding()
        case .guide: showPermissionGuide()
        case .lens: showLens()
        }
    }
    private func refreshPermissionStatus() {
        onboarding.refreshPermission(using: model.capture.access)
        model.permissionNeeded = !onboarding.permissionGranted
    }
    private func refreshLanguageCatalog() {
        languageCatalogTask?.cancel()
        model.prepareLanguageCheck()
        languageCatalogTask = Task { await model.refreshLanguages() }
    }
    private func installMenu() {
        menus.install(target: self, actions: .init(
            showAbout: #selector(showAbout),
            showSettings: #selector(showSettings),
            saveCapture: #selector(saveCapture),
            toggleRecording: #selector(toggleRecording),
            openExportDirectory: #selector(openExportDirectory),
            showLens: #selector(showLens),
            showReader: #selector(showReader),
            focusOverflow: #selector(focusOverflow),
            toggle: #selector(toggle),
            toggleLock: #selector(toggleLock),
            showHelp: #selector(showHelp),
            showOnboarding: #selector(showOnboarding),
            showPreparation: #selector(showPreparation)))
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let symbol = recording.isRecording ? "record.circle" : (recording.isFinishing ? "arrow.down.circle" : "viewfinder")
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lens")
        button.image?.isTemplate = true
        button.title = recording.isRecording ? L10n.text(" Recording") : (recording.isFinishing ? L10n.text(" Saving") : "")
        let state = model.permissionNeeded ? L10n.text("Screen Recording Access Needed") : (model.running ? L10n.text("Translating") : L10n.text("Paused"))
        lens?.title = model.permissionNeeded ? L10n.text("Lens — Screen Recording Access Needed") : (model.running ? (model.locked ? L10n.text("Lens — Click-Through") : "Lens") : L10n.text("Lens — Paused"))
        button.toolTip = "Lens — \(recording.isRecording ? L10n.text("Recording") : state)"
        button.setAccessibilityLabel(button.toolTip)
        statusItem?.menu?.items.first?.title = "Lens — \(state)"
    }
    private var toolbarState: LensToolbarState {
        LensToolbarState(running: model.running, permissionNeeded: model.permissionNeeded,
            hasFrame: model.hasFrame, recording: recording.isRecording, finishing: recording.isFinishing,
            choosingDestination: directoryPanel != nil, locked: model.locked,
            captureSucceeded: captureFeedback.showsSuccess)
    }
    private func refreshToolbar() {
        lensToolbar?.update(toolbarState)
    }

    @objc private func showAbout() {
        let info = LensReleaseInfo(info: Bundle.main.infoDictionary ?? [:])
        NSApp.orderFrontStandardAboutPanel(options: info.aboutOptions)
    }

    @objc private func showOnboarding() {
        guard !terminating, permissionTask == nil else { return }
        permissionWindow?.orderOut(nil)
        systemHandoff.acknowledgeReturn()
        onboarding.deferred = false
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 540, height: 460),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.text("Welcome to Lens"); window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed; window.delegate = self
            window.contentView = NSHostingView(rootView: LensOnboardingView(state: onboarding,
                model: model, catalog: model.languages, exports: exports,
                onPermission: { [weak self] in self?.openPermissionSettings() },
                onRefresh: { [weak self] in self?.refreshPermissionStatus(); self?.refreshLanguageCatalog() },
                onPrepare: { [weak self] in self?.showPreparation() },
                onDirectory: { [weak self] in self?.chooseExportDirectory() },
                onFinish: { [weak self] in self?.finishOnboarding() },
                onLater: { [weak self] in self?.deferSetup() }))
            window.center(); onboardingWindow = window
        }
        pause(); lens.orderOut(nil)
        refreshPermissionStatus()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func finishOnboarding() {
        refreshPermissionStatus()
        guard onboarding.permissionGranted else { return }
        guard model.canTranslate else { onboarding.step = .languages; return }
        do { _ = try exports.preparedDirectory() }
        catch { showExportError(error); return }
        guard onboarding.finish(languagesReady: model.canTranslate) else { return }
        onboardingWindow?.orderOut(nil)
        systemHandoff.show(window: lens)
    }

    private func deferSetup() {
        onboarding.deferred = true
        showPermissionGuide()
    }

    private func showPermissionGuide() {
        guard !terminating, permissionTask == nil else { return }
        pause()
        lens.orderOut(nil)
        onboardingWindow?.orderOut(nil)
        systemHandoff.acknowledgeReturn()
        refreshPermissionStatus()
        if permissionWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 390),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Lens"; window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed; window.delegate = self
            window.contentView = NSHostingView(rootView: LensPermissionGuide(state: onboarding,
                model: model, catalog: model.languages, recording: recording,
                onSettings: { [weak self] in self?.openPermissionSettings() },
                onRefresh: { [weak self] in self?.refreshPermissionStatus(); self?.refreshLanguageCatalog() },
                onContinue: { [weak self] in self?.continueFromGuide() },
                onQuit: { NSApp.terminate(nil) }))
            window.center(); permissionWindow = window
        }
        permissionWindow?.deminiaturize(nil)
        permissionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func continueFromGuide() {
        refreshPermissionStatus()
        guard onboarding.permissionGranted else { return }
        if !onboarding.completed { showOnboarding() }
        else { toggle() }
    }

    @objc private func openPermissionSettings() {
        guard permissionTask == nil, !terminating else { return }
        yieldForScreenPermission()
        let stopped = restartTask
        onboarding.requestingPermission = true
        permissionTask = Task { [weak self] in
            await stopped?.value
            guard let self else { return }
            defer { permissionTask = nil; onboarding.requestingPermission = false }
            guard !Task.isCancelled, !terminating else { return }
            // Only this explicit button may ask macOS; never launch, reopen, or refresh.
            _ = model.capture.access.requestFromUserAction()
            refreshPermissionStatus()
            guard !Task.isCancelled, !terminating else { return }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func yieldForScreenPermission() {
        guard lens != nil else { return }
        model.startRequest.cancel()
        systemHandoff.begin(window: lens) { pause() }
        model.status = L10n.text("Lens yielded input to System Settings. Choose Show Lens or Start Translation when finished.")
    }

    @objc private func showHelp() {
        auxiliaryWindows.prepare(.help, delegate: self) { _ in LensHelpView() }
        auxiliaryWindows.show(.help)
    }
    @objc private func showLens() {
        guard permissionTask == nil else { return }
        refreshPermissionStatus()
        if systemHandoff.isActive || !onboarding.permissionGranted {
            onboarding.deferred = false
            showPermissionGuide()
            return
        }
        permissionWindow?.orderOut(nil)
        onboardingWindow?.orderOut(nil)
        systemHandoff.show(window: lens)
        lens.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = LensSettingsWindow(selection: settingsSelection)
            window.contentView = NSHostingView(rootView: LensControls(model: model, languages: model.languages, recording: recording, selection: settingsSelection, exports: exports,
                onToggle: { [weak self] in self?.toggle() }, onLock: { [weak self] in self?.setLocked() },
                onPrepare: { [weak self] in self?.showPreparation() }, onReader: { [weak self] in self?.showReader() },
                onCapture: { [weak self] in self?.saveCapture() },
                onRecord: { [weak self] in self?.toggleRecording() },
                onPermissionSettings: { [weak self] in self?.openPermissionSettings() },
                onCheckPermission: { [weak self] in self?.refreshPermissionStatus() },
                onChooseDirectory: { [weak self] in self?.chooseExportDirectory() },
                onOpenDirectory: { [weak self] in self?.openExportDirectory() }))
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(focusOverflow) {
            return !model.locked && model.running && surface.overlay.layouts.contains(where: \.isTruncated)
        }
        if menuItem.action == #selector(toggle) {
            menuItem.title = model.running ? L10n.text("Pause Translation") : (model.permissionNeeded ? L10n.text("Check Screen Recording Access…") : L10n.text("Start Translation"))
            return true
        }
        if menuItem.action == #selector(toggleLock) { menuItem.state = model.locked ? .on : .off }
        if menuItem.action == #selector(saveCapture) { return toolbarState.canCapture }
        if menuItem.action == #selector(toggleRecording) {
            menuItem.title = recording.isRecording ? L10n.text("Stop Recording and Save") : (recording.isFinishing ? L10n.text("Saving video…") : L10n.text("Start Video Recording"))
            return toolbarState.canToggleRecording
        }
        return true
    }
    @objc private func toggleRecording() { exportCoordinator.toggleRecording() }
    @objc private func saveCapture() { exportCoordinator.saveCapture() }
    @objc private func openExportDirectory() { exportCoordinator.openDirectory() }
    private func chooseExportDirectory() {
        let parent = onboardingWindow?.isVisible == true ? onboardingWindow :
            (settingsWindow?.isVisible == true ? settingsWindow : nil)
        exportCoordinator.chooseDirectory(parent: parent)
    }

    private func showExportError(_ error: Error, title: String = L10n.text("Could Not Save")) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.text("OK"))
        alert.addButton(withTitle: L10n.text("Open Save Settings"))
        if alert.runModal() == .alertSecondButtonReturn {
            settingsSelection.page = .capture
            showSettings()
        }
    }
    @objc private func toggle() {
        if model.startRequest.pending { model.startRequest.cancel(); return }
        if model.running { pause(); return }
        guard permissionTask == nil, !terminating else { return }
        guard model.capture.access.isGranted else {
            onboarding.deferred = false
            showPermissionGuide()
            return
        }
        if case .failed = model.readiness {
            refreshLanguageCatalog()
            _ = model.startRequest.request(.checking)
            return
        }
        handleStartAction(model.startRequest.request(model.readiness))
    }
    private func handleStartAction(_ action: TranslationStartRequest.Action) {
        guard !terminating, permissionTask == nil else { model.startRequest.cancel(); return }
        guard !systemHandoff.needsReturnGuide else { model.startRequest.cancel(); return }
        switch action {
        case .none, .wait: return
        case .retry:
            model.status = L10n.text("Could not check translation languages. Try again.")
            return
        case .guide: showPreparation(); return
        case .start: break
        }
        guard model.capture.access.isGranted else { showPermissionGuide(); return }
        permissionWindow?.orderOut(nil)
        onboardingWindow?.orderOut(nil)
        systemHandoff.show(window: lens)
        lens.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        restart()
    }
    @objc private func toggleLock() { model.locked.toggle(); setLocked() }
    @objc private func focusOverflow() { surface.overlay.focusFirstOverflow() }
    func applicationDidResignActive(_ notification: Notification) { surface.overlay.dismissPopover() }
    func applicationDidHide(_ notification: Notification) {
        surface.overlay.dismissPopover()
        surface.overlay.resetTransitions()
    }
    private func setLocked() {
        lens.setBodyClickThrough(model.locked)
        updateStatusItem()
        refreshToolbar()
    }
    private func pause() {
        resumeAfterArrangement = false
        let previous = restartTask
        previous?.cancel(); model.suspend()
        let finish = recording.stop()
        restartTask = Task {
            await previous?.value
            await model.capture.stop()
            await finish?.value
        }
    }
    private func screenParametersChanged() {
        guard model.running, let lens else { return }
        if let screen = lens.screen ?? NSScreen.main {
            let rect = LensCaptureRegion.screenRect(surface: surface, window: surface.window ?? lens)
            if let layout = CaptureLayout(globalRect: rect, screen: screen), model.capture.activeLayout == layout {
                if recording.isRecording {
                    Logger(subsystem: "dev.local.lens", category: "Recording").notice("Screen notification retained recording: capture layout unchanged")
                }
                return
            }
        }
        restart(reason: "screenParameters")
    }
    private func restart(reason: String = "explicit") {
        guard lens != nil, lens.isVisible, !lens.isMiniaturized else { return }
        if recording.isRecording {
            Logger(subsystem: "dev.local.lens", category: "Recording").notice("Capture restart requested while recording: \(reason, privacy: .public)")
        }
        guard model.capture.access.isGranted else {
            pause()
            model.permissionNeeded = true
            model.status = CaptureError.permissionRequired.localizedDescription
            return
        }
        model.permissionNeeded = false
        let previous = restartTask
        previous?.cancel(); model.invalidate(); model.begin()
        let version = model.regionVersion
        restartTask = Task { [weak self] in
            guard let self else { return }
            do {
                await previous?.value
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(180))
                guard let screen = lens.screen ?? NSScreen.main else { throw CaptureError.displayUnavailable }
                arranging = true
                lens.clampPair(to: screen.visibleFrame)
                arranging = false
                let contentRect = LensCaptureRegion.screenRect(surface: surface, window: surface.window ?? lens)
                try await model.capture.start(globalRect: contentRect, screen: screen, version: version)
                guard model.regionVersion == version else { return }
                model.status = L10n.text("Screen connected · Waiting for text")
            } catch is CancellationError {} catch {
                guard model.regionVersion == version else { return }
                model.suspend()
                await model.capture.stop()
                model.permissionNeeded = !model.capture.access.isGranted
                model.status = L10n.text("Could not start capture. %1$@", String(describing: error.localizedDescription))
            }
        }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        // Keep the floating lens from covering its own settings while they are being edited.
        lens.level = notification.object as? NSWindow === lens && !systemHandoff.isActive ? .floating : .normal
    }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow !== lens { lens.level = systemHandoff.isActive ? .normal : .floating }
    }
    func windowWillMove(_ notification: Notification) {
        guard notification.object as? NSWindow === lens, !arranging, !lens.synchronizingBody,
              !lens.recordingGeometryLocked else { return }
        interruptForArrangement()
    }
    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === lens, !arranging, !lens.synchronizingBody else { return }
        // AppKit can report movement while updating window styles without a new region.
        // Actual OS-driven relocation still invalidates capture and safely saves the video.
        guard !lens.recordingGeometryUnchanged else { return }
        if lens.isVisible && (resumeAfterArrangement || model.running) {
            resumeAfterArrangement = false
            restart(reason: "windowMoved")
        }
    }
    func windowWillStartLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === lens, !lens.recordingGeometryLocked else { return }
        interruptForArrangement()
    }
    func windowWillMiniaturize(_ notification: Notification) {
        guard notification.object as? NSWindow === lens else { return }
        pause()
    }
    func windowDidResize(_ notification: Notification) {
        guard notification.object as? NSWindow === lens else { return }
        lens.synchronizeBody()
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === lens else { return }
        if resumeAfterArrangement { resumeAfterArrangement = false; restart() }
    }
    private func interruptForArrangement() {
        let shouldResume = resumeAfterArrangement || model.running
        pause()
        resumeAfterArrangement = shouldResume
        // A live drag must reveal the destination, even though translation is suspended.
        surface.setTranslationActive(false, arranging: resumeAfterArrangement)
    }
    func windowWillClose(_ notification: Notification) {
        model.startRequest.cancel()
        if notification.object as? NSWindow === onboardingWindow {
            onboardingWindow = nil
            // Closing the setup is an explicit defer, not a capture-start action.
            if !terminating, NSApp.isActive { deferSetup() }
            return
        }
        if notification.object as? NSWindow === permissionWindow {
            permissionWindow = nil
            return
        }
        if auxiliaryWindows.didClose(notification.object as? NSWindow) {
            refreshLanguageCatalog()
            lens.level = systemHandoff.isActive ? .normal : .floating
            return
        }
        if notification.object as? NSWindow === settingsWindow { lens.level = systemHandoff.isActive ? .normal : .floating; return }
        guard notification.object as? NSWindow === lens else { return }
        pause()
    }
    @objc private func showPreparation() {
        model.startRequest.cancel()
        auxiliaryWindows.prepare(.languageGuide, delegate: self) { window in
            SystemLanguageGuideView(model: model, onReady: { [weak window] in window?.performClose(nil) })
        }
        auxiliaryWindows.show(.languageGuide)
    }
    @objc private func showReader() {
        if !auxiliaryWindows.isPresented(.reader) { model.reading.open() }
        auxiliaryWindows.prepare(.reader, delegate: self) { _ in
            TranslationReader(model: model, reading: model.reading,
                onShowLens: { [weak self] in self?.showLens() }, onSettings: { [weak self] in self?.showSettings() })
        }
        auxiliaryWindows.show(.reader)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        exportCoordinator.cancelDirectorySelection()
        permissionTask?.cancel()
        languageCatalogTask?.cancel()
        pause()
        let stopped = restartTask
        Task {
            await stopped?.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        // Keep security handoff notifications alive while a video is finalizing.
        observations.cancel()
        modelObservers.removeAll()
        model.suspend()
    }
}

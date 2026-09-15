import AppKit
import SwiftUI
import Combine

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
    private let recording = LensRecording()
    private let exports = LensExportStore()
    private let captureFeedback = LensCaptureFeedback()
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
    private var preparation: NSWindow?
    private var reader: NSWindow?
    private var helpWindow: NSWindow?
    private var modelObservers = Set<AnyCancellable>()
    private var directoryPanel: NSOpenPanel? { didSet { refreshToolbar() } }
    private var statusItem: NSStatusItem?
    private var restartTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var languageCatalogTask: Task<Void, Never>?
    private var arranging = false
    private var resumeAfterArrangement = false
    private var observers: [NSObjectProtocol] = []

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
        model.onRestart = { [weak self] in self?.restart() }
        model.onRegionInvalidated = { [weak self] in self?.recording.stop() }
        recording.onStateChange = { [weak self] in
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
        recording.onSaved = { [weak self] url in self?.exports.didSave(url) }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let identifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if LensSystemHandoff.requiresHandoff(bundleIdentifier: identifier) {
                    self?.yieldToSystemSettings()
                }
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.status = L10n.text("Your Mac woke from sleep. Start translation again when ready.") }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.model.running == true { self?.restart() } }
        })
        model.suspend()
        refreshPermissionStatus()
        refreshLanguageCatalog()
        if !onboarding.completed { showOnboarding() }
        else { showPermissionGuide() }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard lens != nil, !terminating else { return }
        refreshPermissionStatus()
        refreshLanguageCatalog()
        restoreUserInterface()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard lens != nil, !terminating else { return false }
        refreshPermissionStatus()
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
            onboardingCompleted: onboarding.completed)
        switch destination {
        case .none: break
        case .onboarding: showOnboarding()
        case .guide: showPermissionGuide()
        }
    }
    private func refreshPermissionStatus() {
        onboarding.refreshPermission(using: model.capture.access)
        model.permissionNeeded = !onboarding.permissionGranted
    }
    private func refreshLanguageCatalog() {
        languageCatalogTask?.cancel()
        languageCatalogTask = Task { await model.refreshLanguages() }
    }
    private func installMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            item.submenu = menu; main.addItem(item)
            return menu
        }
        func command(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                     target: AnyObject? = nil, modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            item.keyEquivalentModifierMask = modifiers
            menu.addItem(item)
        }
        let appMenu = submenu("Lens")
        command(appMenu, L10n.text("About Lens"), #selector(showAbout), target: self)
        appMenu.addItem(.separator())
        command(appMenu, L10n.text("Settings…"), #selector(showSettings), ",", target: self)
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: L10n.text("Services"), action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: L10n.text("Services")); appMenu.addItem(services); NSApp.servicesMenu = services.submenu
        appMenu.addItem(.separator())
        command(appMenu, L10n.text("Hide Lens"), #selector(NSApplication.hide(_:)), "h")
        command(appMenu, L10n.text("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option])
        command(appMenu, L10n.text("Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        command(appMenu, L10n.text("Quit Lens"), #selector(NSApplication.terminate(_:)), "q")

        let file = submenu(L10n.text("File"))
        command(file, L10n.text("Save Image"), #selector(saveCapture), "s", target: self, modifiers: [.command, .shift])
        command(file, L10n.text("Start Video Recording"), #selector(toggleRecording), "r", target: self, modifiers: [.command, .shift])
        command(file, L10n.text("Open Save Folder"), #selector(openExportDirectory), target: self)
        file.addItem(.separator())
        command(file, L10n.text("Close"), #selector(NSWindow.performClose(_:)), "w")

        let edit = submenu(L10n.text("Edit"))
        command(edit, L10n.text("Undo"), Selector(("undo:")), "z")
        command(edit, L10n.text("Redo"), Selector(("redo:")), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        command(edit, L10n.text("Cut"), #selector(NSText.cut(_:)), "x")
        command(edit, L10n.text("Copy"), #selector(NSText.copy(_:)), "c")
        command(edit, L10n.text("Paste"), #selector(NSText.paste(_:)), "v")
        command(edit, L10n.text("Select All"), #selector(NSText.selectAll(_:)), "a")

        let view = submenu(L10n.text("View"))
        command(view, L10n.text("Show Lens"), #selector(showLens), "l", target: self)
        command(view, L10n.text("Full Translation"), #selector(showReader), "t", target: self)
        view.addItem(.separator())
        command(view, L10n.text("Start Translation"), #selector(toggle), "r", target: self)
        command(view, L10n.text("Pass Through Clicks and Scrolling"), #selector(toggleLock), "k", target: self)

        let window = submenu(L10n.text("Window"))
        command(window, L10n.text("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        command(window, L10n.text("Zoom"), #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        command(window, L10n.text("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window

        let help = submenu(L10n.text("Help"))
        command(help, L10n.text("Lens Help"), #selector(showHelp), "?", target: self)
        command(help, L10n.text("Getting Started…"), #selector(showOnboarding), target: self)
        command(help, L10n.text("Language Packs…"), #selector(showPreparation), target: self)
        NSApp.helpMenu = help
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusMenu = NSMenu()
        statusMenu.addItem(NSMenuItem(title: "Lens", action: nil, keyEquivalent: ""))
        statusMenu.addItem(.separator())
        command(statusMenu, L10n.text("Show Lens"), #selector(showLens), target: self)
        command(statusMenu, L10n.text("Start Translation"), #selector(toggle), target: self)
        command(statusMenu, L10n.text("Pass Through Clicks and Scrolling"), #selector(toggleLock), target: self)
        statusMenu.addItem(.separator())
        command(statusMenu, L10n.text("Save Image"), #selector(saveCapture), target: self)
        command(statusMenu, L10n.text("Start Video Recording"), #selector(toggleRecording), target: self)
        command(statusMenu, L10n.text("Open Save Folder"), #selector(openExportDirectory), target: self)
        command(statusMenu, L10n.text("Full Translation"), #selector(showReader), target: self)
        statusMenu.addItem(.separator())
        command(statusMenu, L10n.text("Settings…"), #selector(showSettings), target: self)
        command(statusMenu, L10n.text("Quit Lens"), #selector(NSApplication.terminate(_:)))
        statusItem?.menu = statusMenu
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
    private func refreshToolbar() {
        lensToolbar?.update(LensToolbarState(running: model.running, permissionNeeded: model.permissionNeeded,
            hasFrame: model.hasFrame, recording: recording.isRecording, finishing: recording.isFinishing,
            choosingDestination: directoryPanel != nil, locked: model.locked,
            captureSucceeded: captureFeedback.showsSuccess))
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
        else if !model.canTranslate { showPreparation() }
        else { toggle() }
    }

    @objc private func openPermissionSettings() {
        guard permissionTask == nil, !terminating else { return }
        yieldToSystemSettings()
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

    private func yieldToSystemSettings() {
        guard lens != nil else { return }
        systemHandoff.begin(window: lens) { pause() }
        model.status = L10n.text("Lens yielded input to System Settings. Choose Show Lens or Start Translation when finished.")
    }

    @objc private func showHelp() {
        if helpWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 620),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L10n.text("Lens Help"); window.isReleasedWhenClosed = false
            window.contentMinSize = CGSize(width: 460, height: 500)
            window.contentView = NSHostingView(rootView: LensHelpView())
            window.delegate = self; window.tabbingMode = .disallowed; window.center()
            helpWindow = window
        }
        helpWindow?.deminiaturize(nil)
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        if menuItem.action == #selector(toggle) {
            menuItem.title = model.running ? L10n.text("Pause Translation") : (model.permissionNeeded ? L10n.text("Check Screen Recording Access…") : L10n.text("Start Translation"))
            return model.running || model.permissionNeeded || model.canTranslate
        }
        if menuItem.action == #selector(toggleLock) { menuItem.state = model.locked ? .on : .off }
        if menuItem.action == #selector(saveCapture) { return model.hasFrame && directoryPanel == nil }
        if menuItem.action == #selector(toggleRecording) {
            menuItem.title = recording.isRecording ? L10n.text("Stop Recording and Save") : (recording.isFinishing ? L10n.text("Saving video…") : L10n.text("Start Video Recording"))
            return recording.isRecording || (!recording.isFinishing && model.hasFrame && directoryPanel == nil)
        }
        return true
    }
    private func videoFrame() -> CGImage? {
        guard model.hasFrame, let image = surface.canvas.snapshotImage() else { return nil }
        return LensSnapshot.image(background: image, pointSize: surface.bounds.size,
                                  translations: model.translations, maskOpacity: model.opacity)
    }
    @objc private func toggleRecording() {
        if recording.isRecording { recording.stop(); return }
        guard !recording.isFinishing, model.hasFrame else { return }
        guard directoryPanel == nil, let image = videoFrame() else { return }
        do {
            try recording.start(destination: exports.videoDestination(), firstFrame: image,
                                frame: { [weak self] in self?.videoFrame() })
        } catch { showExportError(error) }
    }
    @objc private func saveCapture() {
        captureFeedback.beginAttempt()
        guard directoryPanel == nil else { return }
        guard model.hasFrame, let image = surface.canvas.snapshotImage(),
              let data = LensSnapshot.png(background: image, pointSize: surface.bounds.size,
                  translations: model.translations, maskOpacity: model.opacity) else {
            model.status = L10n.text("No captured screen to save. Start translation and wait for the screen to connect.")
            return
        }
        do {
            let url = try exports.saveImage(data)
            captureFeedback.didSave()
            model.status = L10n.text("Image saved · %1$@", String(describing: url.lastPathComponent))
        } catch { showExportError(error) }
    }

    private func chooseExportDirectory() {
        if let directoryPanel { directoryPanel.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Capture Save Folder")
        panel.message = L10n.text("Images and videos are saved to this folder automatically.")
        panel.prompt = L10n.text("Choose Folder")
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = exports.directory
        directoryPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            directoryPanel = nil
            guard response == .OK, let url = panel.url else { return }
            do { try exports.selectDirectory(url) }
            catch { showExportError(error) }
        }
        if let onboardingWindow, onboardingWindow.isVisible { panel.beginSheetModal(for: onboardingWindow, completionHandler: completion) }
        else if let settingsWindow, settingsWindow.isVisible { panel.beginSheetModal(for: settingsWindow, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    @objc private func openExportDirectory() {
        do { try exports.openDirectory(using: { NSWorkspace.shared.open($0) }) }
        catch { showExportError(error, title: L10n.text("Could Not Open Save Folder")) }
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
        if model.running { pause(); return }
        guard permissionTask == nil, !terminating else { return }
        guard model.capture.access.isGranted else {
            onboarding.deferred = false
            showPermissionGuide()
            return
        }
        guard model.canTranslate else { showPreparation(); return }
        permissionWindow?.orderOut(nil)
        onboardingWindow?.orderOut(nil)
        systemHandoff.show(window: lens)
        lens.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        restart()
    }
    @objc private func toggleLock() { model.locked.toggle(); setLocked() }
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
    private func restart() {
        guard lens != nil, lens.isVisible, !lens.isMiniaturized else { return }
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
        guard notification.object as? NSWindow === lens, !arranging, !lens.synchronizingBody else { return }
        interruptForArrangement()
    }
    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === lens, !arranging, !lens.synchronizingBody else { return }
        if lens.isVisible && (resumeAfterArrangement || model.running) {
            resumeAfterArrangement = false
            restart()
        }
    }
    func windowWillStartLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === lens else { return }
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
        if notification.object as? NSWindow === preparation {
            preparation?.contentView = nil; preparation = nil
            refreshLanguageCatalog()
            lens.level = systemHandoff.isActive ? .normal : .floating
            return
        }
        if notification.object as? NSWindow === settingsWindow { lens.level = systemHandoff.isActive ? .normal : .floating; return }
        guard notification.object as? NSWindow === lens else { return }
        pause()
    }
    @objc private func showPreparation() {
        if let preparation { preparation.deminiaturize(nil); preparation.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.contentMinSize = CGSize(width: 520, height: 560)
        window.title = L10n.text("Language Packs"); window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LanguagePreparationView(model: model,
            onReady: { [weak window] in window?.performClose(nil) }))
        window.delegate = self; window.tabbingMode = .disallowed
        window.center(); window.makeKeyAndOrderFront(nil)
        preparation = window; NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showReader() {
        if reader == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L10n.text("Full Translation"); window.isReleasedWhenClosed = false
            window.contentMinSize = CGSize(width: 440, height: 360)
            window.contentView = NSHostingView(rootView: TranslationReader(model: model,
                onShowLens: { [weak self] in self?.showLens() }, onSettings: { [weak self] in self?.showSettings() }))
            window.delegate = self; window.tabbingMode = .disallowed
            window.center(); reader = window
        }
        reader?.deminiaturize(nil)
        reader?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
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
    func applicationWillTerminate(_ notification: Notification) { model.suspend() }
}

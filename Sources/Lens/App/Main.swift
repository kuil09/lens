import AppKit
import SwiftUI
import UniformTypeIdentifiers
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

@MainActor final class LensPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LensAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let model = LensModel()
    private let recording = LensRecording()
    private let settingsSelection = LensSettingsSelection()
    private let surface = LensSurface(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    private var lens: LensPanel!
    private var lensToolbar: LensToolbar?
    private var settingsWindow: LensSettingsWindow?
    private var preparation: NSWindow?
    private var reader: NSWindow?
    private var helpWindow: NSWindow?
    private var modelObservers = Set<AnyCancellable>()
    private var capturePanel: NSSavePanel? { didSet { refreshToolbar() } }
    private var statusItem: NSStatusItem?
    private var restartTask: Task<Void, Never>?
    private var languageCatalogTask: Task<Void, Never>?
    private var arranging = false
    private var resumeAfterArrangement = false
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let area = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let rect = CGRect(x: area.midX - 400, y: area.midY - 250, width: 800, height: 500)
        lens = LensPanel(contentRect: rect, styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        lens.title = "Lens"; lens.isReleasedWhenClosed = false
        lens.hidesOnDeactivate = false; lens.isFloatingPanel = true; lens.level = .floating
        lens.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        lens.isOpaque = false; lens.backgroundColor = .clear; lens.minSize = CGSize(width: 320, height: 240)
        lens.contentView = surface; lens.delegate = self; model.attach(surface)
        let toolbar = LensToolbar(onTranslate: { [weak self] in self?.toggle() },
                                  onCapture: { [weak self] in self?.saveCapture() },
                                  onRecord: { [weak self] in self?.toggleRecording() })
        lensToolbar = toolbar
        toolbar.attach(to: lens)
        lens.setContentSize(rect.size)
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
        recording.onError = { message in
            let alert = NSAlert()
            alert.messageText = "동영상 저장 확인"
            alert.informativeText = message
            alert.runModal()
        }
        lens.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.status = "잠자기에서 복귀했습니다. 다시 시작을 눌러 주세요." }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.model.running == true { self?.restart() } }
        })
        restart()
        refreshLanguageCatalog()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        refreshLanguageCatalog()
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
        command(appMenu, "Lens에 관하여", #selector(showAbout), target: self)
        appMenu.addItem(.separator())
        command(appMenu, "설정…", #selector(showSettings), ",", target: self)
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "서비스", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "서비스"); appMenu.addItem(services); NSApp.servicesMenu = services.submenu
        appMenu.addItem(.separator())
        command(appMenu, "Lens 가리기", #selector(NSApplication.hide(_:)), "h")
        command(appMenu, "기타 가리기", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option])
        command(appMenu, "모두 보기", #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        command(appMenu, "Lens 종료", #selector(NSApplication.terminate(_:)), "q")

        let file = submenu("파일")
        command(file, "이미지 저장…", #selector(saveCapture), "s", target: self, modifiers: [.command, .shift])
        command(file, "동영상 녹화 시작…", #selector(toggleRecording), "r", target: self, modifiers: [.command, .shift])
        file.addItem(.separator())
        command(file, "닫기", #selector(NSWindow.performClose(_:)), "w")

        let edit = submenu("편집")
        command(edit, "실행 취소", Selector(("undo:")), "z")
        command(edit, "다시 실행", Selector(("redo:")), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        command(edit, "오려두기", #selector(NSText.cut(_:)), "x")
        command(edit, "복사하기", #selector(NSText.copy(_:)), "c")
        command(edit, "붙여넣기", #selector(NSText.paste(_:)), "v")
        command(edit, "모두 선택", #selector(NSText.selectAll(_:)), "a")

        let view = submenu("보기")
        command(view, "렌즈 보기", #selector(showLens), "l", target: self)
        command(view, "번역 전문", #selector(showReader), "t", target: self)
        view.addItem(.separator())
        command(view, "번역 시작", #selector(toggle), "r", target: self)
        command(view, "클릭과 스크롤 통과", #selector(toggleLock), "k", target: self)

        let window = submenu("윈도우")
        command(window, "최소화", #selector(NSWindow.performMiniaturize(_:)), "m")
        command(window, "확대/축소", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        command(window, "모두 앞으로 가져오기", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window

        let help = submenu("도움말")
        command(help, "Lens 도움말", #selector(showHelp), "?", target: self)
        command(help, "언어 팩 관리…", #selector(showPreparation), target: self)
        NSApp.helpMenu = help
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusMenu = NSMenu()
        statusMenu.addItem(NSMenuItem(title: "Lens", action: nil, keyEquivalent: ""))
        statusMenu.addItem(.separator())
        command(statusMenu, "렌즈 보기", #selector(showLens), target: self)
        command(statusMenu, "번역 시작", #selector(toggle), target: self)
        command(statusMenu, "클릭과 스크롤 통과", #selector(toggleLock), target: self)
        statusMenu.addItem(.separator())
        command(statusMenu, "이미지 저장…", #selector(saveCapture), target: self)
        command(statusMenu, "동영상 녹화 시작…", #selector(toggleRecording), target: self)
        command(statusMenu, "번역 전문", #selector(showReader), target: self)
        statusMenu.addItem(.separator())
        command(statusMenu, "설정…", #selector(showSettings), target: self)
        command(statusMenu, "Lens 종료", #selector(NSApplication.terminate(_:)))
        statusItem?.menu = statusMenu
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let symbol = recording.isRecording ? "record.circle" : (recording.isFinishing ? "arrow.down.circle" : "viewfinder")
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lens")
        button.image?.isTemplate = true
        button.title = recording.isRecording ? " 녹화 중" : (recording.isFinishing ? " 저장 중" : "")
        let state = model.permissionNeeded ? "화면 기록 접근 필요" : (model.running ? "번역 중" : "일시정지됨")
        lens?.title = model.permissionNeeded ? "Lens — 화면 기록 접근 필요" : (model.running ? (model.locked ? "Lens — 클릭 통과" : "Lens") : "Lens — 일시정지")
        button.toolTip = "Lens — \(recording.isRecording ? "녹화 중" : state)"
        button.setAccessibilityLabel(button.toolTip)
        statusItem?.menu?.items.first?.title = "Lens — \(state)"
    }
    private func refreshToolbar() {
        lensToolbar?.update(LensToolbarState(running: model.running, permissionNeeded: model.permissionNeeded,
            hasFrame: model.hasFrame, recording: recording.isRecording, finishing: recording.isFinishing,
            choosingDestination: capturePanel != nil, locked: model.locked))
    }

    @objc private func showAbout() {
        let info = LensReleaseInfo(info: Bundle.main.infoDictionary ?? [:])
        NSApp.orderFrontStandardAboutPanel(options: info.aboutOptions)
    }

    @objc private func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showHelp() {
        if helpWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 620),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Lens 도움말"; window.isReleasedWhenClosed = false
            window.contentMinSize = CGSize(width: 460, height: 500)
            window.contentView = NSHostingView(rootView: LensHelpView())
            window.delegate = self; window.tabbingMode = .disallowed; window.center()
            helpWindow = window
        }
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showLens() { lens.orderFrontRegardless() }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = LensSettingsWindow(selection: settingsSelection)
            window.contentView = NSHostingView(rootView: LensControls(model: model, languages: model.languages, recording: recording, selection: settingsSelection,
                onToggle: { [weak self] in self?.toggle() }, onLock: { [weak self] in self?.setLocked() },
                onPrepare: { [weak self] in self?.showPreparation() }, onReader: { [weak self] in self?.showReader() },
                onCapture: { [weak self] in self?.saveCapture() },
                onRecord: { [weak self] in self?.toggleRecording() },
                onPermissionSettings: { [weak self] in self?.openPermissionSettings() }))
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggle) {
            menuItem.title = model.running ? "번역 일시정지" : (model.permissionNeeded ? "화면 기록 접근 확인…" : "번역 시작")
        }
        if menuItem.action == #selector(toggleLock) { menuItem.state = model.locked ? .on : .off }
        if menuItem.action == #selector(saveCapture) { return model.hasFrame && capturePanel == nil }
        if menuItem.action == #selector(toggleRecording) {
            menuItem.title = recording.isRecording ? "녹화 중지 및 저장" : (recording.isFinishing ? "동영상 저장 중…" : "동영상 녹화 시작…")
            return recording.isRecording || (!recording.isFinishing && model.hasFrame && capturePanel == nil)
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
        if let capturePanel { capturePanel.makeKeyAndOrderFront(nil); return }
        let panel = NSSavePanel()
        panel.title = "렌즈 동영상 녹화"
        panel.message = "저장 위치를 선택하면 녹화를 시작합니다. 화면과 번역만 저장하며 소리는 포함하지 않습니다."
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Lens-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")).mp4"
        panel.canCreateDirectories = true; panel.level = .modalPanel
        capturePanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            defer { capturePanel = nil }
            guard response == .OK, let url = panel.url else { return }
            guard let image = videoFrame() else {
                model.status = "녹화할 화면이 없습니다. 번역을 다시 시작한 후 녹화하세요."
                return
            }
            do {
                try recording.start(destination: url, firstFrame: image,
                                    frame: { [weak self] in self?.videoFrame() })
            } catch { recording.onError?(error.localizedDescription) }
        }
    }
    @objc private func saveCapture() {
        if let capturePanel { capturePanel.makeKeyAndOrderFront(nil); return }
        guard model.hasFrame, let image = surface.canvas.snapshotImage(),
              let data = LensSnapshot.png(background: image, pointSize: surface.bounds.size,
                  translations: model.translations, maskOpacity: model.opacity) else {
            model.status = "저장할 화면이 없습니다. 번역을 시작해 화면이 연결된 후 다시 시도하세요."
            return
        }
        let panel = NSSavePanel()
        panel.title = "렌즈 이미지 저장"
        panel.message = "지금 렌즈에 표시된 화면과 번역을 PNG로 저장합니다."
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Lens-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-" )).png"
        panel.canCreateDirectories = true
        panel.level = .modalPanel
        capturePanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            defer { self.capturePanel = nil }
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "이미지를 저장하지 못했습니다."
                alert.runModal()
            }
        }
    }
    @objc private func toggle() {
        if model.running { pause(); return }
        showLens()
        guard model.capture.access.requestFromUserAction() else {
            model.permissionNeeded = true
            model.status = "시스템 설정에서 현재 Lens의 화면 기록 권한을 확인하고 앱을 다시 여세요. 자동 재요청은 하지 않습니다."
            return
        }
        restart()
    }
    @objc private func toggleLock() { model.locked.toggle(); setLocked() }
    private func setLocked() {
        lens.ignoresMouseEvents = model.locked
        updateStatusItem()
        refreshToolbar()
    }
    private func pause() {
        resumeAfterArrangement = false
        restartTask?.cancel(); model.suspend()
        restartTask = Task { await model.capture.stop() }
    }
    private func restart() {
        guard lens != nil, lens.isVisible else { return }
        guard model.capture.access.isGranted else {
            pause()
            model.permissionNeeded = true
            model.status = CaptureError.permissionRequired.localizedDescription
            return
        }
        model.permissionNeeded = false
        restartTask?.cancel(); model.invalidate(); model.begin()
        let version = model.regionVersion
        restartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard let screen = lens.screen ?? NSScreen.main else { throw CaptureError.displayUnavailable }
                arranging = true
                lens.setFrame(LensGeometry.clamped(lens.frame, to: screen.visibleFrame), display: true)
                arranging = false
                let contentRect = LensCaptureRegion.screenRect(surface: surface, window: lens)
                try await model.capture.start(globalRect: contentRect, screen: screen, version: version)
                guard model.regionVersion == version else { return }
                model.status = "화면 연결됨 · 텍스트를 기다리는 중"
            } catch is CancellationError {} catch {
                guard model.regionVersion == version else { return }
                model.running = false
                model.permissionNeeded = !model.capture.access.isGranted
                model.status = "캡처를 시작하지 못했습니다. \(error.localizedDescription)"
            }
        }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        // Keep the floating lens from covering its own settings while they are being edited.
        if notification.object as? NSWindow !== lens { lens.level = .normal }
    }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow !== lens { lens.level = .floating }
    }
    func windowWillMove(_ notification: Notification) {
        guard notification.object as? NSWindow === lens, !arranging else { return }
        interruptForArrangement()
    }
    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === lens, !arranging else { return }
        if lens.isVisible && (resumeAfterArrangement || model.running) {
            resumeAfterArrangement = false
            restart()
        }
    }
    func windowWillStartLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === lens else { return }
        interruptForArrangement()
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === lens else { return }
        if resumeAfterArrangement { resumeAfterArrangement = false; restart() }
    }
    private func interruptForArrangement() {
        resumeAfterArrangement = resumeAfterArrangement || model.running
        restartTask?.cancel(); model.suspend(); surface.canvas.showsCapturedImage = false
        restartTask = Task { await model.capture.stop() }
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === preparation {
            preparation?.contentView = nil; preparation = nil; lens.level = .floating; return
        }
        if notification.object as? NSWindow === settingsWindow { lens.level = .floating; return }
        guard notification.object as? NSWindow === lens else { return }
        pause()
    }
    @objc private func showPreparation() {
        if let preparation { preparation.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.contentMinSize = CGSize(width: 520, height: 560)
        window.title = "언어 팩"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LanguagePreparationView(model: model, catalog: model.languages,
            onReady: { [weak window] in window?.performClose(nil) }))
        window.delegate = self; window.tabbingMode = .disallowed
        window.center(); window.makeKeyAndOrderFront(nil)
        preparation = window; NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showReader() {
        if reader == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "번역 전문"; window.isReleasedWhenClosed = false
            window.contentMinSize = CGSize(width: 440, height: 360)
            window.contentView = NSHostingView(rootView: TranslationReader(model: model,
                onShowLens: { [weak self] in self?.showLens() }, onSettings: { [weak self] in self?.showSettings() }))
            window.delegate = self; window.tabbingMode = .disallowed
            window.center(); reader = window
        }
        reader?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let finish = recording.stop() else { return .terminateNow }
        model.suspend()
        Task {
            await finish.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { model.suspend() }
}

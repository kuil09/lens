import AppKit
import SwiftUI

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
final class LensAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = LensModel()
    private let surface = LensSurface(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    private var lens: LensPanel!
    private var toolbar: NSPanel!
    private var preparation: NSWindow?
    private var reader: NSWindow?
    private var statusItem: NSStatusItem?
    private var restartTask: Task<Void, Never>?
    private var arranging = false
    private var resumeAfterArrangement = false
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let area = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let rect = CGRect(x: area.midX - 400, y: area.midY - 250, width: 800, height: 500)
        lens = LensPanel(contentRect: rect, styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        lens.title = "Lens · 이동 및 크기 조절"; lens.isReleasedWhenClosed = false
        lens.hidesOnDeactivate = false; lens.isFloatingPanel = true; lens.level = .floating
        lens.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        lens.isOpaque = false; lens.backgroundColor = .clear; lens.minSize = CGSize(width: 320, height: 240)
        lens.contentView = surface; lens.delegate = self; model.attach(surface)
        model.onRestart = { [weak self] in self?.restart() }
        toolbar = NSPanel(contentRect: CGRect(x: rect.minX, y: rect.maxY + 36, width: 800, height: 132), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        toolbar.title = "Lens 설정"; toolbar.isReleasedWhenClosed = false
        toolbar.hidesOnDeactivate = false; toolbar.level = .floating
        toolbar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toolbar.contentView = NSHostingView(rootView: LensControls(model: model,
            onToggle: { [weak self] in self?.toggle() }, onLock: { [weak self] in self?.setLocked() },
            onPrepare: { [weak self] in self?.showPreparation() }, onReader: { [weak self] in self?.showReader() }))
        lens.orderFrontRegardless(); positionToolbar(); toolbar.orderFrontRegardless()
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
    }
    private func installMenu() {
        let main = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu(title: "Lens")
        appMenu.addItem(withTitle: "Lens 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let windowItem = NSMenuItem(); let menu = NSMenu(title: "렌즈")
        for (title, action, key) in [("렌즈 보기", #selector(showLens), "l"), ("시작 / 일시정지", #selector(toggle), "r"), ("잠금 전환", #selector(toggleLock), "k"), ("언어 준비", #selector(showPreparation), ","), ("전문 보기", #selector(showReader), "t")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        windowItem.submenu = menu; main.addItem(windowItem); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "◉ Lens"
        let statusMenu = menu.copy() as! NSMenu; statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem?.menu = statusMenu
    }
    @objc private func showLens() { lens.orderFrontRegardless(); toolbar.orderFrontRegardless(); positionToolbar() }
    @objc private func toggle() {
        if model.running { pause(); return }
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
        lens.title = model.locked ? "Lens · 잠금 · 뒤 화면 조작 가능" : "Lens · 이동 및 크기 조절"
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
                arranging = false; positionToolbar()
                let contentRect = lens.contentRect(forFrameRect: lens.frame)
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
    private func positionToolbar() {
        guard toolbar != nil, let screen = lens.screen ?? NSScreen.main else { return }
        var rect = toolbar.frame; rect.origin = CGPoint(x: lens.frame.minX, y: lens.frame.maxY + 8)
        if rect.maxY > screen.visibleFrame.maxY { rect.origin.y = lens.frame.minY - rect.height - 8 }
        toolbar.setFrame(LensGeometry.clamped(rect, to: screen.visibleFrame), display: true)
    }
    func windowWillMove(_ notification: Notification) { if !arranging { interruptForArrangement() } }
    func windowDidMove(_ notification: Notification) {
        guard !arranging else { return }; positionToolbar()
        if lens.isVisible && (resumeAfterArrangement || model.running) {
            resumeAfterArrangement = false
            restart()
        }
    }
    func windowWillStartLiveResize(_ notification: Notification) { interruptForArrangement() }
    func windowDidEndLiveResize(_ notification: Notification) {
        if resumeAfterArrangement { resumeAfterArrangement = false; restart() }
    }
    private func interruptForArrangement() {
        resumeAfterArrangement = resumeAfterArrangement || model.running
        restartTask?.cancel(); model.suspend(); surface.canvas.showsCapturedImage = false
        restartTask = Task { await model.capture.stop() }
    }
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === lens else { return }; pause(); toolbar.orderOut(nil)
    }
    @objc private func showPreparation() {
        if let preparation { preparation.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 540, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Lens · 언어 준비"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LanguagePreparationView(onReady: { [weak self, weak window] in window?.orderOut(nil); self?.restart() }))
        window.level = .floating; window.center(); window.makeKeyAndOrderFront(nil)
        preparation = window; NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showReader() {
        if reader == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Lens · 전문 보기"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: TranslationReader(model: model))
            window.level = .floating; window.center(); reader = window
        }
        reader?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) { model.suspend() }
}

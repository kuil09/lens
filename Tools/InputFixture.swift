// Standalone local-only AppKit fixture; not compiled into Lens or its package.
import AppKit

@MainActor final class InputCanvas: NSView {
    var clicks = 0, drags = 0, scrolls = 0, ticks = 0
    var paused = false, alternate = false
    let status = NSTextField(labelWithString: "Clicks 0 · Drags 0 · Scrolls 0")
    let clock = NSTextField(labelWithString: "Clock 0")
    let critical = NSTextField(labelWithString: "Do not delete the remaining 12 files.")
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor.white.cgColor
        func label(_ text: String, _ rect: CGRect) {
            let view = NSTextField(wrappingLabelWithString: text)
            view.font = .systemFont(ofSize: 23); view.textColor = .black; view.frame = rect
            addSubview(view)
        }
        label("This paragraph must stay translated while the clock beside it keeps changing. Never delete the remaining files without permission.", CGRect(x: 80, y: 430, width: 470, height: 130))
        label("남아 있는 파일을 절대로 삭제하지 마세요.\n残っているファイルを削除しないでください。", CGRect(x: 80, y: 310, width: 600, height: 85))
        critical.font = .systemFont(ofSize: 22); critical.textColor = .black
        critical.frame = CGRect(x: 80, y: 270, width: 700, height: 35); addSubview(critical)
        status.frame = CGRect(x: 80, y: 130, width: 730, height: 30); status.textColor = .black; addSubview(status)
        clock.frame = CGRect(x: 620, y: 490, width: 300, height: 70); clock.textColor = .black; addSubview(clock)
        let field = NSTextField(string: "Keyboard focus stays here")
        field.frame = CGRect(x: 80, y: 210, width: 600, height: 32)
        field.setAccessibilityLabel("Fixture typing field"); addSubview(field)
        for (index, title, action) in [(0, "Count click", #selector(count)), (1, "Change number", #selector(change)), (2, "Pause animation", #selector(pause))] {
            let button = NSButton(title: title, target: self, action: action)
            button.frame = CGRect(x: 80 + index * 210, y: 170, width: 190, height: 32); addSubview(button)
        }
        label("Drag or scroll the blank area below. Header clicks must not increment these counters.", CGRect(x: 80, y: 55, width: 800, height: 60))
    }
    required init?(coder: NSCoder) { fatalError() }
    func update() { status.stringValue = "Clicks \(clicks) · Drags \(drags) · Scrolls \(scrolls)" }
    @objc func count() { clicks += 1; update() }
    @objc func change() { alternate.toggle(); critical.stringValue = alternate ? "Delete the remaining 13 files." : "Do not delete the remaining 12 files." }
    @objc func pause() { paused.toggle() }
    override func mouseDown(with event: NSEvent) { clicks += 1; update() }
    override func mouseDragged(with event: NSEvent) { drags += 1; update() }
    override func scrollWheel(with event: NSEvent) { scrolls += 1; update() }
}

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let area = NSScreen.main!.visibleFrame
        window = NSWindow(contentRect: CGRect(x: area.midX - 500, y: area.midY - 350, width: 1000, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Lens Input Fixture"
        let view = InputCanvas(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.contentView = view; window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard !view.paused else { return }
                view.ticks += 1
                view.clock.stringValue = "Clock \(view.ticks)\nThe current state is \(view.ticks.isMultiple(of: 2) ? "A" : "B")."
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct InputFixtureMain {
    @MainActor static func main() {
        let app = NSApplication.shared, delegate = FixtureDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}

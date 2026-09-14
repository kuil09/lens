import AppKit

struct LensToolbarState: Equatable {
    var running = false
    var permissionNeeded = false
    var hasFrame = false
    var recording = false
    var finishing = false
    var choosingDestination = false
    var locked = false
}

/// Window chrome, deliberately outside the capture/render surface.
@MainActor final class LensToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "LensActions")
    private(set) var state = LensToolbarState()
    private(set) var items: [String: NSToolbarItem] = [:]
    private let onTranslate: () -> Void
    private let onCapture: () -> Void
    private let onRecord: () -> Void

    init(onTranslate: @escaping () -> Void, onCapture: @escaping () -> Void, onRecord: @escaping () -> Void) {
        self.onTranslate = onTranslate; self.onCapture = onCapture; self.onRecord = onRecord
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
    }

    func attach(to window: NSWindow) {
        window.toolbarStyle = .expanded
        window.toolbar = toolbar
        update(state)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("translate"), .init("capture"), .init("record")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard ["translate", "capture", "record"].contains(identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self; item.action = #selector(performAction(_:))
        item.autovalidates = false
        items[identifier.rawValue] = item
        update(state)
        return item
    }
    func update(_ state: LensToolbarState) {
        self.state = state
        configure("translate", label: state.running ? "번역 일시정지" : "번역 시작", symbol: state.running ? "pause.fill" : "character.bubble", enabled: !state.locked,
                  help: state.permissionNeeded ? "화면 기록 접근을 확인하고 번역을 시작합니다. ⌘R" : "번역 시작 / 일시정지 · ⌘R")
        configure("capture", label: "캡처", symbol: "camera", enabled: state.hasFrame && !state.choosingDestination && !state.locked,
                  help: state.hasFrame ? "화면과 번역을 PNG로 저장합니다. ⇧⌘S" : "화면이 연결되면 이미지를 저장할 수 있습니다.")
        configure("record", label: state.recording ? "녹화 중지" : (state.finishing ? "저장 중…" : "녹화 시작"),
                  symbol: state.recording ? "stop.circle.fill" : (state.finishing ? "arrow.down.circle" : "record.circle"),
                  enabled: !state.locked && (state.recording || (!state.finishing && state.hasFrame && !state.choosingDestination)),
                  help: state.recording ? "녹화를 마치고 MP4로 저장합니다. ⇧⌘R" : "화면과 번역을 무음 동영상으로 녹화합니다. ⇧⌘R")
    }
    private func configure(_ key: String, label: String, symbol: String, enabled: Bool, help: String) {
        guard let item = items[key] else { return }
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isEnabled = enabled
        item.toolTip = state.locked ? "클릭 통과 중입니다. 메뉴 막대에서 조작하거나 클릭 통과를 끄세요." : help
    }
    @objc private func performAction(_ item: NSToolbarItem) {
        guard item.isEnabled else { return }
        switch item.itemIdentifier.rawValue {
        case "translate": onTranslate()
        case "capture": onCapture()
        case "record": onRecord()
        default: break
        }
    }
}

@MainActor enum LensCaptureRegion {
    static func screenRect(surface: NSView, window: NSWindow) -> CGRect {
        surface.layoutSubtreeIfNeeded()
        return window.convertToScreen(surface.convert(surface.bounds, to: nil))
    }
}

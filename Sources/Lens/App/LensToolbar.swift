import AppKit

struct LensToolbarState: Equatable {
    var running = false
    var permissionNeeded = false
    var hasFrame = false
    var recording = false
    var finishing = false
    var choosingDestination = false
    var locked = false
    var captureSucceeded = false

    // Menus and toolbar share eligibility; recording stop must always remain available.
    var canCapture: Bool { hasFrame && !choosingDestination }
    var canToggleRecording: Bool { recording || (!finishing && canCapture) }
}

/// Window chrome, deliberately outside the capture/render surface.
@MainActor final class LensToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "LensActions")
    private(set) var state = LensToolbarState()
    private(set) var items: [String: NSToolbarItem] = [:]
    private let onCapture: () -> Void
    private let onRecord: () -> Void
    private let onReader: () -> Void
    private let onSettings: () -> Void
    private let onLock: () -> Void
    private let onOpenFolder: () -> Void

    init(onCapture: @escaping () -> Void, onRecord: @escaping () -> Void,
         onReader: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}, onLock: @escaping () -> Void = {},
         onOpenFolder: @escaping () -> Void = {}) {
        self.onCapture = onCapture; self.onRecord = onRecord
        self.onReader = onReader; self.onSettings = onSettings
        self.onLock = onLock
        self.onOpenFolder = onOpenFolder
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    func attach(to window: NSWindow) {
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = toolbar
        update(state)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("capture"), .init("folder"), .init("record"), .flexibleSpace, .init("lock"), .init("reader"), .init("settings")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard ["capture", "folder", "record", "lock", "reader", "settings"].contains(identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self; item.action = #selector(performAction(_:))
        item.autovalidates = false
        item.isBordered = true
        switch identifier.rawValue {
        case "record", "lock": item.visibilityPriority = .high
        case "folder": item.visibilityPriority = .low
        default: item.visibilityPriority = .standard
        }
        items[identifier.rawValue] = item
        update(state)
        return item
    }
    func update(_ state: LensToolbarState) {
        self.state = state
        configure("capture", label: L10n.text(state.captureSucceeded ? "Image Saved" : "Capture"),
                  symbol: state.captureSucceeded ? "checkmark" : "camera", enabled: state.canCapture,
                  help: state.captureSucceeded ? L10n.text("Image Saved") : (state.hasFrame ? L10n.text("Save a PNG directly to your chosen folder. ⇧⌘S") : L10n.text("Connect the screen to save an image.")))
        configure("folder", label: L10n.text("Open Save Folder"), symbol: "folder", enabled: true,
                  help: L10n.text("Open Save Folder"))
        configure("record", label: state.recording ? L10n.text("Stop Recording") : (state.finishing ? L10n.text("Saving…") : L10n.text("Start Recording")),
                  symbol: state.recording ? "stop.circle.fill" : (state.finishing ? "arrow.down.circle" : "record.circle"),
                  enabled: state.canToggleRecording,
                  help: state.recording ? L10n.text("Stop and save an MP4 to your chosen folder. ⇧⌘R") :
                    (state.finishing ? L10n.text("Saving video…") :
                        (!state.hasFrame ? L10n.text("Connect the screen to record a video.") : L10n.text("Start recording now. Silent video is saved to your chosen folder. ⇧⌘R"))))
        configure("reader", label: L10n.text("Full Translation"), symbol: "text.alignleft", enabled: true,
                  help: L10n.text("Read and copy full translations. ⌘T"))
        configure("settings", label: L10n.text("Settings"), symbol: "gearshape", enabled: true,
                  help: L10n.text("Set languages and appearance in a separate window. ⌘,"))
        items["record"]?.style = state.recording ? .prominent : .plain
        items["record"]?.backgroundTintColor = state.recording ? .systemRed : nil
        configure("lock", label: state.locked ? L10n.text("Turn Off Click-Through") : L10n.text("Pass Through Clicks and Scrolling"), symbol: state.locked ? "cursorarrow.rays" : "cursorarrow", enabled: true,
                  help: L10n.text("Pass Through Clicks and Scrolling"))
        items["lock"]?.style = state.locked ? .prominent : .plain
    }
    private func configure(_ key: String, label: String, symbol: String, enabled: Bool, help: String) {
        guard let item = items[key] else { return }
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isEnabled = enabled
        item.toolTip = help
    }
    @objc private func performAction(_ item: NSToolbarItem) {
        guard item.isEnabled else { return }
        switch item.itemIdentifier.rawValue {
        case "capture": onCapture()
        case "folder": onOpenFolder()
        case "record": onRecord()
        case "reader": onReader()
        case "settings": onSettings()
        case "lock": onLock()
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

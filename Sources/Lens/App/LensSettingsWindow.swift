import AppKit
import Combine

@MainActor
final class LensSettingsWindow: NSWindow, NSToolbarDelegate {
    let selection: LensSettingsSelection
    private var selectionObserver: AnyCancellable?
    init(autosaveName: String = "LensSettingsWindow", selection: LensSettingsSelection = LensSettingsSelection()) {
        self.selection = selection
        super.init(contentRect: CGRect(x: 0, y: 0, width: 580, height: 600),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "번역"
        isReleasedWhenClosed = false
        minSize = CGSize(width: 540, height: 550)
        tabbingMode = .disallowed
        collectionBehavior = [.fullScreenNone]
        toolbarStyle = .preference
        let toolbar = NSToolbar(identifier: "LensSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        self.toolbar = toolbar
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(selection.page.rawValue)
        selectionObserver = selection.$page.sink { [weak self] page in
            self?.title = page.title
            self?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(page.rawValue)
        }
        center()
        if !autosaveName.isEmpty {
            setFrameAutosaveName(autosaveName)
            setFrameUsingName(autosaveName)
        }
        // Preserve the saved position, not the old all-in-one window's size.
        let top = frame.maxY
        setContentSize(CGSize(width: 580, height: 600))
        setFrameOrigin(CGPoint(x: frame.minX, y: top - frame.height))
        if let screen = screen ?? NSScreen.main {
            setFrame(LensGeometry.clamped(frame, to: screen.visibleFrame), display: false)
        }
    }

    func select(_ page: LensSettingsPage) {
        selection.page = page
        title = page.title
        toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(page.rawValue)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        LensSettingsPage.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let page = LensSettingsPage(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = page.title
        item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
        item.target = self; item.action = #selector(selectPage(_:))
        return item
    }
    @objc private func selectPage(_ sender: NSToolbarItem) {
        if let page = LensSettingsPage(rawValue: sender.itemIdentifier.rawValue) { select(page) }
    }
}

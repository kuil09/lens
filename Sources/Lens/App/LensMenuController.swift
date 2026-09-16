import AppKit

/// Owns menu installation and the menu-bar item, without owning application state.
@MainActor final class LensMenuController {
    struct Actions {
        let showAbout: Selector
        let showSettings: Selector
        let saveCapture: Selector
        let toggleRecording: Selector
        let openExportDirectory: Selector
        let showLens: Selector
        let showReader: Selector
        let focusOverflow: Selector
        let toggle: Selector
        let toggleLock: Selector
        let showHelp: Selector
        let showOnboarding: Selector
        let showPreparation: Selector
    }
    private(set) var statusItem: NSStatusItem?
    func install(target: AnyObject, actions: Actions) {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
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
        command(appMenu, L10n.text("About Lens"), actions.showAbout, target: target)
        appMenu.addItem(.separator())
        command(appMenu, L10n.text("Settings…"), actions.showSettings, ",", target: target)
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
        command(file, L10n.text("Save Image"), actions.saveCapture, "s", target: target, modifiers: [.command, .shift])
        command(file, L10n.text("Start Video Recording"), actions.toggleRecording, "r", target: target, modifiers: [.command, .shift])
        command(file, L10n.text("Open Save Folder"), actions.openExportDirectory, target: target)
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
        command(view, L10n.text("Show Lens"), actions.showLens, "l", target: target)
        command(view, L10n.text("Full Translation"), actions.showReader, "t", target: target)
        command(view, L10n.text("Read Truncated Translation"), actions.focusOverflow, "t", target: target, modifiers: [.command, .shift])
        view.addItem(.separator())
        command(view, L10n.text("Start Translation"), actions.toggle, "r", target: target)
        command(view, L10n.text("Pass Through Clicks and Scrolling"), actions.toggleLock, "k", target: target)

        let window = submenu(L10n.text("Window"))
        command(window, L10n.text("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        command(window, L10n.text("Zoom"), #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        command(window, L10n.text("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window

        let help = submenu(L10n.text("Help"))
        command(help, L10n.text("Lens Help"), actions.showHelp, "?", target: target)
        command(help, L10n.text("Getting Started…"), actions.showOnboarding, target: target)
        command(help, L10n.text("System Language Download…"), actions.showPreparation, target: target)
        NSApp.helpMenu = help
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusMenu = NSMenu()
        statusMenu.addItem(NSMenuItem(title: "Lens", action: nil, keyEquivalent: ""))
        statusMenu.addItem(.separator())
        command(statusMenu, L10n.text("Show Lens"), actions.showLens, target: target)
        command(statusMenu, L10n.text("Start Translation"), actions.toggle, target: target)
        command(statusMenu, L10n.text("Pass Through Clicks and Scrolling"), actions.toggleLock, target: target)
        statusMenu.addItem(.separator())
        command(statusMenu, L10n.text("Save Image"), actions.saveCapture, target: target)
        command(statusMenu, L10n.text("Start Video Recording"), actions.toggleRecording, target: target)
        command(statusMenu, L10n.text("Open Save Folder"), actions.openExportDirectory, target: target)
        command(statusMenu, L10n.text("Full Translation"), actions.showReader, target: target)
        statusMenu.addItem(.separator())
        command(statusMenu, L10n.text("Settings…"), actions.showSettings, target: target)
        command(statusMenu, L10n.text("Quit Lens"), #selector(NSApplication.terminate(_:)))
        statusItem?.menu = statusMenu
    }

    isolated deinit {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

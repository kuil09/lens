import AppKit
import SwiftUI

/// Owns reusable reading/help windows and the disposable language guide.
/// Permission and onboarding windows remain in the application's lifecycle flow.
@MainActor
final class LensAuxiliaryWindows {
    enum Kind: CaseIterable {
        case help, reader, languageGuide

        var title: String {
            switch self {
            case .help: "Lens Help"
            case .reader: "Full Translation"
            case .languageGuide: "System Language Download"
            }
        }
        var size: CGSize {
            switch self {
            case .help: CGSize(width: 520, height: 620)
            case .reader: CGSize(width: 600, height: 620)
            case .languageGuide: CGSize(width: 600, height: 520)
            }
        }
        var minimumSize: CGSize {
            switch self {
            case .help: CGSize(width: 460, height: 500)
            case .reader: CGSize(width: 440, height: 360)
            case .languageGuide: CGSize(width: 520, height: 480)
            }
        }
    }

    private var windows: [Kind: NSWindow] = [:]

    func window(for kind: Kind) -> NSWindow? { windows[kind] }

    func isPresented(_ kind: Kind) -> Bool {
        guard let window = windows[kind] else { return false }
        return window.isVisible || window.isMiniaturized
    }

    @discardableResult
    func prepare<Content: View>(_ kind: Kind, delegate: NSWindowDelegate?,
                               content: (NSWindow) -> Content) -> NSWindow {
        if let window = windows[kind] { return window }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: kind.size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = L10n.text(kind.title)
        window.isReleasedWhenClosed = false
        window.contentMinSize = kind.minimumSize
        window.tabbingMode = .disallowed
        window.delegate = delegate
        window.contentView = NSHostingView(rootView: content(window))
        window.center()
        windows[kind] = window
        return window
    }

    func show(_ kind: Kind) {
        guard let window = windows[kind] else { return }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the guide releases its model subscriptions. Reader/help retain state.
    @discardableResult
    func didClose(_ window: NSWindow?) -> Bool {
        guard let window, window === windows[.languageGuide] else { return false }
        window.contentView = nil
        windows[.languageGuide] = nil
        return true
    }
}

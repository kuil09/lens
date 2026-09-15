import AppKit

/// Relinquish the overlay before OS-owned settings/authentication UI takes focus.
/// Never inspect passwords, secure input state, or other applications' key events.
@MainActor final class LensSystemHandoff {
    private(set) var isActive = false
    private(set) var needsReturnGuide = false

    static func requiresHandoff(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.apple.systempreferences"
    }

    func begin(window: LensPanel, pause: () -> Void) {
        needsReturnGuide = true
        guard !isActive else { return }
        isActive = true
        window.interactionSuspended = true
        pause()
        window.makeFirstResponder(nil)
        // orderOut asks AppKit to relinquish key status. Do not call resignKey directly.
        window.orderOut(nil)
        window.level = .normal
    }

    // A normal guide can return without restoring the floating overlay.
    func acknowledgeReturn() { needsReturnGuide = false }

    /// Restoration is an explicit Lens action, never a focus-change side effect.
    func show(window: LensPanel) {
        isActive = false
        needsReturnGuide = false
        window.interactionSuspended = false
        window.level = .floating
        window.orderFrontRegardless()
    }
}

enum LensReturnDestination: Equatable {
    case none, onboarding, guide, lens

    static func resolve(requestPending: Bool, handoffPending: Bool,
                        hasVisibleWindows: Bool, onboardingCompleted: Bool,
                        permissionGranted: Bool = true) -> Self {
        guard !requestPending else { return .none }
        if handoffPending { return .guide }
        guard !hasVisibleWindows else { return .none }
        if !onboardingCompleted { return .onboarding }
        return permissionGranted ? .lens : .guide
    }
}

enum TranslationReadiness: Equatable {
    case checking, ready, missing, failed(String)
}

/// A single explicit intent, never an automatic start caused by app activation.
struct TranslationStartRequest: Equatable {
    enum Action: Equatable { case wait, start, guide, retry, none }
    private(set) var pending = false

    mutating func request(_ readiness: TranslationReadiness) -> Action {
        pending = true
        return resolve(readiness)
    }
    mutating func cancel() { pending = false }
    mutating func resolve(_ readiness: TranslationReadiness) -> Action {
        guard pending else { return .none }
        if readiness == .checking { return .wait }
        pending = false
        switch readiness {
        case .ready: return .start
        case .missing: return .guide
        case .failed: return .retry
        case .checking: return .wait
        }
    }
}

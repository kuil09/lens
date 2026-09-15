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
    case none, onboarding, guide

    static func resolve(requestPending: Bool, handoffPending: Bool,
                        hasVisibleWindows: Bool, onboardingCompleted: Bool) -> Self {
        guard !requestPending else { return .none }
        if handoffPending { return .guide }
        guard !hasVisibleWindows else { return .none }
        return onboardingCompleted ? .guide : .onboarding
    }
}

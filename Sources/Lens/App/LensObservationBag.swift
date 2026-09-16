import Foundation

/// Notification tokens must be removed from the center that issued them.
@MainActor final class LensObservationBag {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    func observe(_ center: NotificationCenter, name: Notification.Name,
                 using handler: @escaping @Sendable (Notification) -> Void) {
        tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: handler)))
    }
    func cancel() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }
    isolated deinit { for (center, token) in tokens { center.removeObserver(token) } }
}

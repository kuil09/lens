import Combine
import Foundation

/// Transient image-save feedback, independent of recording and export errors.
@MainActor public final class LensCaptureFeedback: ObservableObject {
    public typealias Scheduler = @MainActor (Duration, @escaping @MainActor @Sendable () -> Void) -> AnyCancellable

    @Published public private(set) var showsSuccess = false
    private let scheduler: Scheduler
    private var expiration: AnyCancellable?
    private var generation = UUID()

    public init(scheduler: Scheduler? = nil) {
        self.scheduler = scheduler ?? Self.schedule
    }

    /// Call before capture guards or fallible work so a failed attempt stays neutral.
    public func beginAttempt() {
        invalidateExpiration()
        showsSuccess = false
    }

    /// Call only after the image has been successfully saved.
    public func didSave() {
        invalidateExpiration()
        let generation = generation
        showsSuccess = true
        expiration = scheduler(.seconds(1.5)) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.beginAttempt()
        }
    }

    private func invalidateExpiration() {
        // Invalidate before cancellation, including schedulers that deliver stale callbacks.
        generation = UUID()
        expiration?.cancel()
        expiration = nil
    }

    private static func schedule(after delay: Duration, action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        let task = Task { @MainActor in
            do { try await Task.sleep(for: delay) }
            catch { return }
            action()
        }
        return AnyCancellable { task.cancel() }
    }
}

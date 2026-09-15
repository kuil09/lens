import Combine
import Testing
@testable import Lens

@MainActor private final class CaptureFeedbackClock {
    final class Entry {
        let deadline: Duration
        let action: @MainActor @Sendable () -> Void
        var cancelled = false
        var fired = false

        init(deadline: Duration, action: @escaping @MainActor @Sendable () -> Void) {
            self.deadline = deadline
            self.action = action
        }
    }

    var now: Duration = .zero
    var entries: [Entry] = []

    func schedule(after delay: Duration, action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        let entry = Entry(deadline: now + delay, action: action)
        entries.append(entry)
        return AnyCancellable { entry.cancelled = true }
    }

    func advance(by duration: Duration) {
        now += duration
        for entry in entries where !entry.cancelled && !entry.fired && entry.deadline <= now {
            entry.fired = true
            entry.action()
        }
    }

    func fireEvenIfCancelled(_ index: Int) {
        entries[index].action()
    }
}

@Test @MainActor func captureFeedbackExpiresAfterOneAndAHalfSeconds() {
    let clock = CaptureFeedbackClock()
    let feedback = LensCaptureFeedback(scheduler: clock.schedule)
    #expect(!feedback.showsSuccess)
    feedback.beginAttempt()
    feedback.didSave()
    #expect(feedback.showsSuccess)
    #expect(clock.entries[0].deadline == .seconds(1.5))
    clock.advance(by: .milliseconds(1499))
    #expect(feedback.showsSuccess)
    clock.advance(by: .milliseconds(1))
    #expect(!feedback.showsSuccess)
}

@Test @MainActor func captureFeedbackRepeatedSuccessIgnoresCancelledTimer() {
    let clock = CaptureFeedbackClock()
    let feedback = LensCaptureFeedback(scheduler: clock.schedule)
    feedback.didSave()
    clock.advance(by: .seconds(1))
    feedback.didSave()
    #expect(clock.entries[0].cancelled)
    clock.advance(by: .milliseconds(500))
    clock.fireEvenIfCancelled(0)
    #expect(feedback.showsSuccess)
    clock.advance(by: .milliseconds(999))
    #expect(feedback.showsSuccess)
    clock.advance(by: .milliseconds(1))
    #expect(!feedback.showsSuccess)
}

@Test @MainActor func captureFeedbackNewAttemptClearsSuccessAndInvalidatesTimer() {
    let clock = CaptureFeedbackClock()
    let feedback = LensCaptureFeedback(scheduler: clock.schedule)
    feedback.didSave()
    feedback.beginAttempt()
    #expect(!feedback.showsSuccess)
    #expect(clock.entries[0].cancelled)
    clock.fireEvenIfCancelled(0)
    #expect(!feedback.showsSuccess)
    feedback.didSave()
    clock.fireEvenIfCancelled(0)
    #expect(feedback.showsSuccess)
    clock.advance(by: .seconds(1.5))
    #expect(!feedback.showsSuccess)
}

@Test @MainActor func captureFeedbackFailureWithoutDidSaveStaysNeutral() {
    let clock = CaptureFeedbackClock()
    let feedback = LensCaptureFeedback(scheduler: clock.schedule)
    // An early return or save error never calls didSave().
    feedback.beginAttempt()
    clock.advance(by: .seconds(10))
    #expect(!feedback.showsSuccess)
    #expect(clock.entries.isEmpty)
    feedback.didSave()
    feedback.beginAttempt()
    clock.fireEvenIfCancelled(0)
    clock.advance(by: .seconds(10))
    #expect(!feedback.showsSuccess)
    #expect(clock.entries.count == 1)
}

@Test @MainActor func captureFeedbackPublishesSuccessAndExpiryForToolbarObservers() {
    let clock = CaptureFeedbackClock()
    let feedback = LensCaptureFeedback(scheduler: clock.schedule)
    var values: [Bool] = []
    let observer = feedback.$showsSuccess.sink { values.append($0) }
    feedback.didSave()
    clock.advance(by: .seconds(1.5))
    #expect(values == [false, true, false])
    withExtendedLifetime(observer) {}
}

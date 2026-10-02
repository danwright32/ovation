import Foundation

/// ovation#651. Waits, up to a named deadline, for something a test released to
/// actually be gone.
///
/// WHY A WAIT AT ALL, measured rather than guessed. Under load a released
/// container's store stays open after the case that opened it has returned, and
/// then closes on its own, off the main thread, with nothing on the main run loop
/// needed: 1146ms for a SwiftDataBehaviourTests probe and 2079ms for "a real
/// version 7 store opens under version 8", each with every core kept busy. A
/// third case read the same store straight after a version 2 fixture was written
/// and SQLite answered "database is locked". Each of the three looked like a
/// survivor to a check that looked once, and each passed on a rerun.
///
/// IT WAITS FOR RELEASE, IT NEVER EXCUSES A SURVIVOR. A container still alive at
/// the deadline is the #632 crash this guards against, so `stillHeld` is a
/// failure for every caller, and it says how long it was given (L440).
///
/// THE CLOCK AND THE SLEEP ARE SEAMS from the day this was written (L524), so
/// `ReleaseWaitTests` measures the deadline arithmetic without waiting for real.
struct ReleaseWait {
    enum Outcome: Equatable {
        case released(after: Duration)
        case stillHeld(after: Duration)
    }

    /// How long a store is given to close. About five times the worst late close
    /// measured on a 12 core Mac with every core busy, because CI's runners have
    /// three. Only a store that never closes ever waits the whole of it.
    static let storeReleaseDeadline: Duration = .seconds(10)

    let deadline: Duration
    let interval: Duration
    let elapsed: () -> Duration
    let sleep: (Duration) -> Void
    /// The pause an ASYNC caller uses, which suspends rather than blocks (L241):
    /// a blocking sleep inside an async case parks one of the cooperative pool's
    /// few threads, three on CI, and stalls every async case beside it.
    let suspend: (Duration) async -> Void

    init(deadline: Duration, interval: Duration = .milliseconds(10),
         elapsed: (() -> Duration)? = nil, sleep: ((Duration) -> Void)? = nil,
         suspend: ((Duration) async -> Void)? = nil) {
        self.deadline = deadline
        self.interval = interval
        let clock = ContinuousClock()
        let origin = clock.now
        self.elapsed = elapsed ?? { origin.duration(to: clock.now) }
        let blocking: (Duration) -> Void = { duration in
            let (seconds, attoseconds) = duration.components
            usleep(useconds_t(seconds * 1_000_000 + attoseconds / 1_000_000_000_000))
        }
        self.sleep = sleep ?? blocking
        // A CANCELLED CASE CANNOT SUSPEND: Task.sleep throws at once, and swallowing
        // that would return from every pause immediately and spin for the whole
        // deadline, scanning every open file each pass. So a pause the task cannot
        // suspend for is taken by blocking instead, which only a cancelled case pays.
        self.suspend = suspend ?? { duration in
            do { try await Task.sleep(for: duration) } catch { blocking(duration) }
        }
    }

    /// Looks at `released` now and then every `interval`, and answers as soon as
    /// it is true, or with `stillHeld` once `deadline` has passed.
    func until(_ released: () -> Bool) -> Outcome {
        until(looking: { () }, released: { released() }).outcome
    }

    /// The same wait, handing back what its LAST look saw, so a caller naming what
    /// was held reports the reading the verdict was made on, never a second one
    /// taken after the wait gave up, which can list other things or nothing (L11).
    func until<Seen>(looking look: () -> Seen, released: (Seen) -> Bool) -> (outcome: Outcome, seen: Seen) {
        let start = elapsed()
        while true {
            let waited = elapsed() - start
            let seen = look()
            if released(seen) { return (.released(after: waited), seen) }
            if waited >= deadline { return (.stillHeld(after: waited), seen) }
            sleep(min(interval, deadline - waited))
        }
    }

    /// The same wait for an async caller, pausing by SUSPENDING between looks,
    /// so it holds no thread while a store finishes closing (L241).
    func suspendingUntil<Seen>(looking look: () -> Seen,
                               released: (Seen) -> Bool) async -> (outcome: Outcome, seen: Seen) {
        let start = elapsed()
        while true {
            let waited = elapsed() - start
            let seen = look()
            if released(seen) { return (.released(after: waited), seen) }
            if waited >= deadline { return (.stillHeld(after: waited), seen) }
            await suspend(min(interval, deadline - waited))
        }
    }
}

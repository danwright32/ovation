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

    init(deadline: Duration, interval: Duration = .milliseconds(10),
         elapsed: (() -> Duration)? = nil, sleep: ((Duration) -> Void)? = nil) {
        self.deadline = deadline
        self.interval = interval
        let clock = ContinuousClock()
        let origin = clock.now
        self.elapsed = elapsed ?? { origin.duration(to: clock.now) }
        self.sleep = sleep ?? { duration in
            let (seconds, attoseconds) = duration.components
            usleep(useconds_t(seconds * 1_000_000 + attoseconds / 1_000_000_000_000))
        }
    }

    /// Looks at `released` now and then every `interval`, and answers as soon as
    /// it is true, or with `stillHeld` once `deadline` has passed.
    func until(_ released: () -> Bool) -> Outcome {
        let start = elapsed()
        while true {
            let waited = elapsed() - start
            if released() { return .released(after: waited) }
            if waited >= deadline { return .stillHeld(after: waited) }
            sleep(min(interval, deadline - waited))
        }
    }
}

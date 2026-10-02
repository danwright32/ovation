import Foundation
import SwiftData
import Testing

/// ovation#651. The bounded wait both store checks use, measured on a clock the
/// test owns, so no case here waits for real (L524, L290).
struct ReleaseWaitTests {

    /// A clock that only moves when the wait sleeps, and records every sleep.
    final class FakeClock: @unchecked Sendable {
        var elapsed: Duration = .zero
        var sleeps: [Duration] = []
        func wait(deadline: Duration, interval: Duration = .milliseconds(10)) -> ReleaseWait {
            ReleaseWait(deadline: deadline, interval: interval,
                        elapsed: { [unowned self] in self.elapsed },
                        sleep: { [unowned self] in self.sleeps.append($0); self.elapsed += $0 })
        }
    }

    @Test("something already released is answered at once, without sleeping")
    func alreadyReleased() {
        let clock = FakeClock()
        #expect(clock.wait(deadline: .seconds(5)).until { true } == .released(after: .zero))
        #expect(clock.sleeps.isEmpty)
    }

    @Test("something released late, inside the deadline, is released, and says after how long")
    func releasedLate() {
        let clock = FakeClock()
        let outcome = clock.wait(deadline: .seconds(5)).until { clock.elapsed >= .milliseconds(1_150) }
        #expect(outcome == .released(after: .milliseconds(1_150)))
    }

    @Test("something still held at the deadline is refused, and says how long it was given")
    func stillHeldAtTheDeadline() {
        let clock = FakeClock()
        let outcome = clock.wait(deadline: .milliseconds(200)).until { false }
        #expect(outcome == .stillHeld(after: .milliseconds(200)))
        #expect(clock.sleeps.count == 20, "it looked again every interval, not once at the end")
    }

    /// WHAT IS REPORTED IS WHAT THE WAIT LAST SAW (L11). Both store checks name
    /// what was held, and a second reading after the wait gave up can differ from
    /// the one the verdict was made on. Each look here sees a later number, so
    /// the answer must be the number of the wait's own final look.
    @Test("a wait that looks hands back what its last look saw")
    func handsBackItsLastLook() {
        let clock = FakeClock()
        var looks = 0
        let (outcome, seen) = clock.wait(deadline: .milliseconds(20)).until(looking: {
            looks += 1
            return looks
        }, released: { _ in false })
        #expect(outcome == .stillHeld(after: .milliseconds(20)))
        #expect(looks == 3, "it looked at 0, 10 and 20 milliseconds")
        #expect(seen == 3, "the answer is the third look's, the last one the verdict was made on")
    }

    @Test("the last sleep stops at the deadline rather than overshooting it")
    func theLastSleepIsTrimmed() {
        let clock = FakeClock()
        _ = clock.wait(deadline: .milliseconds(25), interval: .milliseconds(10)).until { false }
        #expect(clock.sleeps == [.milliseconds(10), .milliseconds(10), .milliseconds(5)])
    }

    @Test("the deadline both checks use by default is a named constant, not inlined")
    func theDefaultIsNamed() {
        #expect(ReleaseWait.storeReleaseDeadline == .seconds(10))
    }

    // MARK: the two checks wait for a late release instead of failing on it

    /// THE FLAKE ITSELF, made certain. Measured 2026-10-01 under load: a case's
    /// store files stayed open 1146ms after the case returned, then closed on
    /// their own, off the main thread. Here a descriptor inside the directory is
    /// closed 300ms after the body returns, which is the same shape on demand.
    @Test("a store that closes a moment after the case returns is not charged to it")
    func aLateCloseIsNotAFailure() throws {
        var seen: URL?
        try ScratchStore.with("late-close") { url in
            seen = url
            let descriptor = open(url.path, O_CREAT | O_RDWR, 0o600)
            try #require(descriptor >= 0)
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(300)) {
                close(descriptor)
            }
        }
        let directory = try #require(seen).deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: directory.path), "and it was deleted once closed")
    }

    @Test("an earlier version's container released a moment late is not refused")
    @MainActor
    func aLateReleaseIsNotRefused() throws {
        try ScratchStore.with("late-release") { url in
            try EarlierVersionStore.open(OvationSchemaV1.self, at: url) { container in
                // Something outside the call holds the container briefly, as
                // SwiftData does under load, and lets go off the main thread.
                let holder = Holder(container)
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(300)) {
                    holder.release()
                }
            }
        }
    }

    /// THE THIRD FORM, measured 2026-10-01: `StoreCheckpoint.run` straight after a
    /// version 2 fixture was written answered "database is locked", because the
    /// released container's connection had not finished closing. So the call
    /// returns only once the store's own files are closed. Here the store's log
    /// file is held 300ms past the body, the same shape on demand.
    @Test("an earlier version's store is closed by the time the call returns")
    @MainActor
    func theStoreIsClosedWhenTheCallReturns() throws {
        try ScratchStore.with("late-store") { url in
            try EarlierVersionStore.open(OvationSchemaV1.self, at: url) { _ in
                let descriptor = open(url.path + "-wal", O_CREAT | O_RDWR, 0o600)
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(300)) {
                    close(descriptor)
                }
            }
            #expect(ScratchStore.descriptors(on: url) == [])
        }
    }

    final class Holder: @unchecked Sendable {
        private var held: ModelContainer?
        private let lock = NSLock()
        init(_ held: ModelContainer) { self.held = held }
        func release() { lock.lock(); held = nil; lock.unlock() }
    }
}

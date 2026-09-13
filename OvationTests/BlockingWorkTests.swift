import Foundation
import Testing

/// ovation#246. The one place blocking work is run from.
///
/// PORTED FROM DOWNBEAT rather than reinvented (L195), so these cases are about
/// what OVATION needs from it rather than a copy of the source's: the launch
/// copies and hashes everything Ovation holds onto a folder that may sync to a
/// NAS, which blocks, can be slow for entirely ordinary reasons, and must not
/// take the window down with it.
///
/// THE DEADLINE IS DRIVEN, NEVER WAITED FOR. `sleeping` is injected for exactly
/// this: a test that paid a real five second deadline would be the slowest in
/// the suite and would assert about how busy the machine is (L290, L524).
struct BlockingWorkTests {

    @Test("work that answers comes back with its answer")
    func answeredComesBack() async {
        let outcome = await BlockingWork.run { 41 + 1 }

        #expect(outcome == .answered(42))
    }

    /// A FAILURE IS ITS OWN OUTCOME, never an empty answer. A caller handed
    /// nothing cannot tell a refusal from a result, and in this app the caller is
    /// deciding whether a backup happened (L10, L11).
    @Test("work that throws comes back as failed, carrying what it said")
    func failedCarriesTheReason() async {
        let outcome = await BlockingWork.run { () -> Int in
            throw BackupError.couldNotWrite("/Volumes/Backups is not mounted")
        }

        guard case .failed(let detail) = outcome else {
            Issue.record("a throw did not come back as failed, got \(outcome)")
            return
        }
        #expect(detail.contains("not mounted"))
    }

    /// AND GIVING UP IS A THIRD THING, not a failure. The work may still be
    /// running: a blocking file copy reads no cancellation flag, so the deadline
    /// ABANDONS the wait rather than stopping the work, and saying "it failed"
    /// would claim something nobody measured (L11).
    @Test("work that outlasts its deadline comes back as gave up, not as failed")
    func gaveUpIsNotFailed() async {
        let started = Gate()
        let outcome = await BlockingWork.run(
            deadline: .seconds(5),
            // The deadline is driven rather than waited for: this returns at once,
            // so the timer wins the race deterministically.
            sleeping: { _ in },
            { () -> Bool in started.waitForever(); return true })

        guard case .gaveUp(let after) = outcome else {
            Issue.record("work that outlasted its deadline did not give up, got \(outcome)")
            started.release()
            return
        }
        #expect(after == .seconds(5))
        started.release()
    }

    /// FIRST ANSWER WINS, ONCE. The work and the deadline race, and resuming a
    /// continuation twice is a crash rather than a wasted call, so this is the
    /// difference between "usually right" and right.
    @Test("work that answers before the deadline is not overtaken by it")
    func theAnswerBeatsASleepingDeadline() async {
        let outcome = await BlockingWork.run(
            deadline: .seconds(5),
            // A deadline that never arrives, so the work must be what answers.
            sleeping: { _ in try await Task.sleep(for: .seconds(60)) },
            { "done" })

        #expect(outcome == .answered("done"))
    }

    /// IT RUNS OFF THE CALLING THREAD, which is the whole reason it exists: the
    /// launch runs on the main actor and the copying must not.
    @Test("the work does not run on the main thread")
    @MainActor
    func theWorkLeavesTheMainThread() async {
        let outcome = await BlockingWork.run { Thread.isMainThread }

        #expect(outcome == .answered(false))
    }

    /// A gate a test can hold open and then release, so a case about the deadline
    /// does not leave a thread parked for the rest of the run.
    private final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func waitForever() { semaphore.wait() }
        func release() { semaphore.signal() }
    }
}

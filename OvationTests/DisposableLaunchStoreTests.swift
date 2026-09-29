import Foundation
import SwiftData
import Testing

/// ovation#604. What a disposable launch opens in place of Dan's store.
///
/// THE REAL LAUNCH IS THE CASE THAT MATTERS MOST. A store in memory handed to a
/// launch that is not disposable would have Dan working in a database that
/// vanishes when he quits, so the refusal is asserted first and against the one
/// predicate every other refusal reads (L261).
@MainActor
struct DisposableLaunchStoreTests {

    private struct Unopenable: Error, LocalizedError {
        var errorDescription: String? { "the schema would not load" }
    }

    @Test("a launch that is not disposable is given nothing, and nothing is opened")
    func aRealLaunchIsGivenNothing() {
        var asked = false
        let opening = DisposableLaunchStore.open(isDisposableLaunch: false) {
            asked = true
            return try OvationSchema.container(inMemory: true)
        }
        #expect(opening == nil)
        #expect(!asked, "nothing is opened for a real launch, not even to be thrown away")
    }

    @Test("a disposable launch opens a store in memory and says it opened")
    func aDisposableLaunchOpensAStoreInMemory() throws {
        let opening = try #require(DisposableLaunchStore.open(isDisposableLaunch: true))
        #expect(opening.outcome == .opened)
        let container = try #require(opening.container)
        let inMemory = container.configurations.allSatisfy { $0.isStoredInMemoryOnly }
        #expect(inMemory, "the store a test host opens is never a file")
    }

    @Test("a store that will not open is a refusal saying why, never a launch left starting")
    func aStoreThatWillNotOpenIsARefusal() throws {
        let opening = try #require(DisposableLaunchStore.open(isDisposableLaunch: true) {
            throw Unopenable()
        })
        #expect(opening.container == nil)
        guard case .refused(_, let detail) = opening.outcome else {
            Issue.record("a failed open reported \(opening.outcome)")
            return
        }
        #expect(detail.contains("the schema would not load"))
    }

    @Test("the default reads this process, which is a test, so it opens")
    func theDefaultReadsThisProcess() throws {
        let opening = try #require(DisposableLaunchStore.open())
        #expect(opening.outcome == .opened)
    }

    // MARK: the gate

    @Test("a real launch is answered at once, without waiting for an ask that never comes", .timeLimit(.minutes(1)))
    func aRealLaunchNeverWaits() async {
        let waited = await DisposableLaunchStore.openWhenAsked(
            isDisposableLaunch: false, gate: DisposableLaunchStore.Gate())
        #expect(waited.isNotADisposableLaunch)
        // A REAL LAUNCH IS NEVER TOLD TO RUN AGAIN by this: its once only rule is
        // what stops two containers over Dan's one store file (ovation#84).
        #expect(!waited.launchIsStillToRun)
    }

    @Test("an ask made before the launch waits is kept, so the launch still opens", .timeLimit(.minutes(1)))
    func anEarlyAskIsKept() async {
        let gate = DisposableLaunchStore.Gate()
        gate.ask()
        let waited = await DisposableLaunchStore.openWhenAsked(isDisposableLaunch: true, gate: gate)
        #expect(waited.opening?.outcome == .opened)
        #expect(!waited.launchIsStillToRun)
    }

    /// Waits until the gate holds `count` parked waiters, on the condition rather
    /// than a number of turns (L290), and under a deadline so a waiter that never
    /// parks fails here by name rather than hanging (L110). A launch that had not
    /// yet reached the gate would otherwise look exactly like one parked on it.
    private static func waitUntilParked(_ gate: DisposableLaunchStore.Gate, count: Int = 1)
        async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while gate.parked < count && clock.now < deadline { await Task.yield() }
        try #require(gate.parked == count,
                     "the launch never parked on the gate: \(gate.parked) parked, wanted \(count)")
    }

    @Test("a disposable launch waits on Starting until it is asked, then opens", .timeLimit(.minutes(1)))
    func aDisposableLaunchWaitsForTheAsk() async throws {
        let gate = DisposableLaunchStore.Gate()
        var finished = false
        let launch = Task { @MainActor in
            let opening = await DisposableLaunchStore.openWhenAsked(isDisposableLaunch: true,
                                                                     gate: gate)
            finished = true
            return opening
        }
        try await Self.waitUntilParked(gate)
        #expect(!finished, "the launch opened before anything asked")
        gate.ask()
        let waited = await launch.value
        #expect(waited.opening?.outcome == .opened)
        #expect(gate.parked == 0)
    }

    @Test("a launch cancelled while PARKED is let go, opens nothing, and leaves the gate usable", .timeLimit(.minutes(1)))
    func aCancelledWaitIsLetGo() async throws {
        let gate = DisposableLaunchStore.Gate()
        let launch = Task { @MainActor in
            await DisposableLaunchStore.openWhenAsked(isDisposableLaunch: true, gate: gate)
        }
        // PARKED FIRST, so the cancel below is the one the handler releases, never
        // the check a task that begins already cancelled takes before parking.
        try await Self.waitUntilParked(gate)
        launch.cancel()
        let waited = await launch.value
        #expect(waited.opening == nil, "a cancelled launch opened a store for a window that has gone")
        // AND IT IS STILL TO RUN. The launch sets its once only flag before it
        // waits, so a wait let go without saying so would leave the next .task
        // returning at once and the window on Starting for good.
        #expect(waited.launchIsStillToRun)
        #expect(!waited.isNotADisposableLaunch)
        #expect(!gate.hasBeenAsked, "letting a cancelled wait go is not an ask")
        #expect(gate.parked == 0, "the released continuation is not left parked")
    }

    @Test("a launch that begins already cancelled is let go, and leaves nothing parked", .timeLimit(.minutes(1)))
    func aLaunchCancelledBeforeItParksIsLetGo() async {
        let gate = DisposableLaunchStore.Gate()
        let launch = Task { @MainActor in
            await DisposableLaunchStore.openWhenAsked(isDisposableLaunch: true, gate: gate)
        }
        // Cancelled in the same turn it was made, so it has not run a line yet.
        launch.cancel()
        let waited = await launch.value
        #expect(waited.launchIsStillToRun)
        #expect(gate.parked == 0)
    }

    @Test("an ask and a cancel arriving together are an ask: the store opens and the launch is done", .timeLimit(.minutes(1)))
    func anAskThatReleasedTheWaitIsNotUndoneByACancel() async throws {
        let gate = DisposableLaunchStore.Gate()
        let launch = Task { @MainActor in
            await DisposableLaunchStore.openWhenAsked(isDisposableLaunch: true, gate: gate)
        }
        try await Self.waitUntilParked(gate)
        // BOTH IN ONE TURN. The ask resumes the parked wait, and the cancel then
        // lands on a task already released. Called let go, this would consume the
        // ask and leave the next launch nothing to wait for and nothing opened.
        gate.ask()
        launch.cancel()
        let waited = await launch.value
        #expect(waited.opening?.outcome == .opened,
                "the ask released the wait, so the cancel after it must not undo it")
        #expect(!waited.launchIsStillToRun)
    }
}

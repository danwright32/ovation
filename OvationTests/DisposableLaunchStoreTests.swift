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
        let opening = await DisposableLaunchStore.openWhenAsked(
            isDisposableLaunch: false, gate: DisposableLaunchStore.Gate())
        #expect(opening == nil)
    }

    @Test("an ask made before the launch waits is kept, so the launch still opens", .timeLimit(.minutes(1)))
    func anEarlyAskIsKept() async {
        let gate = DisposableLaunchStore.Gate()
        gate.ask()
        let opening = await DisposableLaunchStore.openWhenAsked(isDisposableLaunch: true, gate: gate)
        #expect(opening?.outcome == .opened)
    }

    @Test("a disposable launch waits on Starting until it is asked, then opens", .timeLimit(.minutes(1)))
    func aDisposableLaunchWaitsForTheAsk() async {
        let gate = DisposableLaunchStore.Gate()
        var finished = false
        let launch = Task { @MainActor in
            let opening = await DisposableLaunchStore.openWhenAsked(isDisposableLaunch: true,
                                                                     gate: gate)
            finished = true
            return opening
        }
        // Several turns of the main actor, which is where the launch waits.
        for _ in 0..<20 { await Task.yield() }
        #expect(!finished, "the launch opened before anything asked")
        gate.ask()
        let opening = await launch.value
        #expect(opening?.outcome == .opened)
    }

    @Test("a launch cancelled while it waits is let go, opens nothing, and leaves the gate usable", .timeLimit(.minutes(1)))
    func aCancelledWaitIsLetGo() async {
        let gate = DisposableLaunchStore.Gate()
        let launch = Task { @MainActor in
            await DisposableLaunchStore.openWhenAsked(isDisposableLaunch: true, gate: gate)
        }
        for _ in 0..<20 { await Task.yield() }
        launch.cancel()
        let opening = await launch.value
        #expect(opening == nil, "a cancelled launch opened a store for a window that has gone")
        #expect(!gate.hasBeenAsked, "letting a cancelled wait go is not an ask")
    }
}

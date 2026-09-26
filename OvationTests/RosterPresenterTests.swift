import Foundation
import SwiftData
import Testing

/// ovation#40, PRD 5a. The pass as something Dan ACTS on, rather than the
/// reading `RosterPass` takes.
///
/// THE STARTING FIGURE IS THE WHOLE POINT AND IT MUST NOT MOVE. PRD 5a says the
/// screen says the number it began with so the pass reads as a one time job, and
/// that a figure counting down as you answer IS the nag it was written against.
/// So these assert both halves at once, on the same presenter: what is LEFT
/// falls and what it STARTED WITH does not.
///
/// SINCE ovation#481 THE WRITE IS `ClientTaxStatusWriter`'s, the one writer the
/// invoice screen already used, so the cases below either hand the presenter a
/// double for that write or, in the last section, the real writer over a real
/// store read back through a different context.
@MainActor
struct RosterPresenterTests {

    private static func client(_ name: String, tax: TaxStatus = .neverRecorded) -> Client {
        let c = Client(name: name, taxStatus: tax)
        c.email = "\(name.lowercased())@example.example"
        return c
    }

    /// A write that records what it was asked and does nothing else.
    private static func accepting(_ heard: RosterWriteHeard) -> RosterPresenter.TaxStatusWrite {
        { client, status in heard.calls.append((client.name, status)) }
    }

    private static func failing() -> RosterPresenter.TaxStatusWrite {
        { _, _ in throw RosterPresenterTestError.diskFull }
    }

    @Test("answering one client takes it out of what is left and leaves the starting figure alone")
    func answeringMovesRemainingAndNotStartedWith() async {
        let clients = [Self.client("A"), Self.client("B"), Self.client("C")]
        let heard = RosterWriteHeard()
        let presenter = RosterPresenter(clients: clients, write: Self.accepting(heard))

        #expect(presenter.startedWith == 3)
        #expect(presenter.remaining == 3)

        await presenter.answer(clients[0], as: .exempt)

        #expect(presenter.startedWith == 3)
        #expect(presenter.remaining == 2)
        #expect(presenter.status(of: clients[0]) == .exempt)
        #expect(heard.calls.map(\.1) == [.exempt])
    }

    @Test("the pass is settled once every client has been answered")
    func settledWhenAllAnswered() async {
        let clients = [Self.client("A"), Self.client("B")]
        let presenter = RosterPresenter(clients: clients, write: Self.accepting(RosterWriteHeard()))

        await presenter.answer(clients[0], as: .exempt)
        #expect(!presenter.isSettled)

        await presenter.answer(clients[1], as: .notExempt)
        #expect(presenter.isSettled)
        #expect(presenter.remaining == 0)
        #expect(presenter.startedWith == 2)
    }

    /// THE SCREEN NEVER WRITES TO THE OBJECT IT HOLDS (L443, PRD 51l). The object
    /// came from the roster's own context, and a change made to it would leave
    /// that context dirty and able to put its older values back over the
    /// writer's. So the answer is carried by the presenter, and the object is
    /// exactly as it was read.
    @Test("answering does not change the client object the roster holds")
    func answeringLeavesTheHeldObjectAlone() async {
        let clients = [Self.client("A")]
        let presenter = RosterPresenter(clients: clients, write: Self.accepting(RosterWriteHeard()))

        await presenter.answer(clients[0], as: .exempt)

        #expect(clients[0].taxStatus == .neverRecorded)
        #expect(presenter.status(of: clients[0]) == .exempt)
    }

    // MARK: the failure path, which is the half a happy path test cannot see

    /// L415. A screen that shows a change BEFORE the write lands owes a failure
    /// path that puts it back AND says so, or a failed write looks exactly like
    /// a slow one. Here the change is visible the instant a chip is pressed, so
    /// a write that throws must leave the client as it was and leave a sentence
    /// behind, rather than a row that has quietly gone from the list while the
    /// store still refuses to invoice it.
    @Test("a write that fails puts the client back and says what went wrong")
    func aFailedWriteRevertsAndSpeaks() async {
        let clients = [Self.client("A")]
        let presenter = RosterPresenter(clients: clients, write: Self.failing())

        await presenter.answer(clients[0], as: .exempt)

        #expect(presenter.status(of: clients[0]) == .neverRecorded)
        #expect(presenter.remaining == 1)
        #expect(presenter.startedWith == 1)
        #expect(presenter.lastFailure != nil)
    }

    /// The row leaves the moment the chip is pressed, BEFORE the write returns,
    /// which is what makes the change optimistic rather than slow.
    @Test("the answer shows before the write has returned")
    func theAnswerShowsBeforeTheWriteReturns() async {
        let clients = [Self.client("A")]
        let gate = RosterWriteGate()
        let presenter = RosterPresenter(clients: clients, write: { _, status in
            try await gate.wait(recording: status)
        })

        let pressed = Task { await presenter.answer(clients[0], as: .exempt) }
        await gate.untilWaiting(1)

        #expect(presenter.remaining == 0, "the row waited for the write")

        gate.release(1, with: nil)
        await pressed.value
        #expect(presenter.remaining == 0)
    }

    /// REVERSED 2026-09-11, and the test that defended the old answer is gone
    /// rather than adjusted (L252). This sentence used to carry the client's id
    /// and deliberately not its name, applying docs/PRIVACY-FLOOR.md to it. That
    /// was a misreading: the floor keeps real names out of a PUBLIC repository
    /// and out of terminal output, and it says in terms that Dan reads them on
    /// his own screen. This is his own screen.
    @Test("the failure sentence names the client, because this is Dan's own screen")
    func theFailureNamesTheClient() async {
        let clients = [Self.client("Ashgrove Chamber Players")]
        let presenter = RosterPresenter(clients: clients, write: Self.failing())

        await presenter.answer(clients[0], as: .exempt)

        let said = presenter.lastFailure ?? ""
        #expect(said.contains("Ashgrove Chamber Players"))
        // And no identifier, which says nothing to the person reading it.
        #expect(!said.contains(clients[0].id.uuidString))
    }

    /// L415 again, from the other side: the sentence has to say the change was
    /// UNDONE, or a person reads "could not be saved" and cannot tell whether
    /// the screen in front of them is showing the old value or the new one.
    @Test("the failure sentence says the value was put back")
    func theFailureSaysItWasPutBack() async {
        let clients = [Self.client("Ashgrove Chamber Players")]
        let presenter = RosterPresenter(clients: clients, write: Self.failing())

        await presenter.answer(clients[0], as: .exempt)

        #expect(presenter.lastFailure?.contains("put back") == true)
    }

    /// A REFUSAL IS SAID IN THE WRITER'S OWN WORDS, which are the ones the invoice
    /// screen shows, rather than as a programmer's error quoted at Dan. It still
    /// names the client and still says the value was put back.
    @Test("a refusal from the writer is said in its own sentence, naming the client")
    func aRefusalIsSaidInItsOwnSentence() async {
        let clients = [Self.client("Ashgrove Chamber Players")]
        let presenter = RosterPresenter(clients: clients, write: { _, _ in
            throw ClientTaxStatusRefusal.noSuchClient
        })

        await presenter.answer(clients[0], as: .exempt)

        let said = presenter.lastFailure ?? ""
        #expect(said.contains(ClientTaxStatusRefusal.noSuchClient.sentence))
        #expect(said.contains("Ashgrove Chamber Players"))
        #expect(said.contains("put back"))
        #expect(!said.contains("noSuchClient"), "the enum case reached the screen")
    }

    /// A second attempt that SUCCEEDS must clear what the first one left behind,
    /// or a sentence about a write that has since landed sits on the screen
    /// contradicting it.
    @Test("a later success clears the earlier failure")
    func aLaterSuccessClearsTheFailure() async {
        let clients = [Self.client("A")]
        var shouldFail = true
        let presenter = RosterPresenter(clients: clients, write: { _, _ in
            if shouldFail { throw RosterPresenterTestError.diskFull }
        })

        await presenter.answer(clients[0], as: .exempt)
        #expect(presenter.lastFailure != nil)

        shouldFail = false
        await presenter.answer(clients[0], as: .exempt)
        #expect(presenter.lastFailure == nil)
        #expect(presenter.remaining == 0)
    }

    /// THE SENTENCE EXPLAINS WHY ONE ROW CAME BACK, so it goes when THAT client is
    /// saved, not when some other client is. Before ovation#481 any success
    /// cleared it, which took the only explanation off the screen while the row
    /// it explained was still sitting in the list.
    @Test("another client's success leaves the failure about the first one on screen")
    func anotherClientsSuccessKeepsTheFailure() async {
        let clients = [Self.client("Aldgate Players"), Self.client("Bexley Choir")]
        let presenter = RosterPresenter(clients: clients, write: { client, _ in
            if client.name == "Aldgate Players" { throw RosterPresenterTestError.diskFull }
        })

        await presenter.answer(clients[0], as: .exempt)
        await presenter.answer(clients[1], as: .exempt)

        #expect(presenter.lastFailure?.contains("Aldgate Players") == true)
        #expect(presenter.status(of: clients[0]) == .neverRecorded)
        #expect(presenter.status(of: clients[1]) == .exempt)
    }

    // MARK: two presses on one client, once the write is asynchronous

    /// WRITES LAND IN THE ORDER THEY WERE PRESSED. Each answer builds a fresh
    /// actor, and two actors are not ordered with each other, so without the
    /// presenter queueing them the earlier press could land last and the store
    /// would hold the answer Dan changed his mind about.
    @Test("a second press waits for the first write rather than racing it")
    func writesAreQueuedInPressOrder() async {
        let clients = [Self.client("A")]
        let gate = RosterWriteGate()
        let presenter = RosterPresenter(clients: clients, write: { _, status in
            try await gate.wait(recording: status)
        })

        let first = Task { await presenter.answer(clients[0], as: .exempt) }
        await gate.untilWaiting(1)
        let second = Task { await presenter.answer(clients[0], as: .notExempt) }
        for _ in 0..<50 { await Task.yield() }

        #expect(gate.started == [.exempt], "the second write started before the first ended")
        #expect(presenter.status(of: clients[0]) == .notExempt, "the second press did not show")

        gate.release(1, with: nil)
        await gate.untilWaiting(2)
        gate.release(2, with: nil)
        await first.value
        await second.value

        #expect(gate.started == [.exempt, .notExempt])
        #expect(presenter.status(of: clients[0]) == .notExempt)
    }

    /// A FAILED FIRST WRITE MUST NOT ROLL BACK OVER A SECOND ANSWER. The second
    /// press is what Dan now means, and its own write decides what is shown.
    @Test("an earlier failure does not undo a later answer that landed")
    func anEarlierFailureDoesNotUndoALaterAnswer() async {
        let clients = [Self.client("A")]
        let gate = RosterWriteGate()
        let presenter = RosterPresenter(clients: clients, write: { _, status in
            try await gate.wait(recording: status)
        })

        let first = Task { await presenter.answer(clients[0], as: .exempt) }
        await gate.untilWaiting(1)
        let second = Task { await presenter.answer(clients[0], as: .notExempt) }
        for _ in 0..<50 { await Task.yield() }

        gate.release(1, with: RosterPresenterTestError.diskFull)
        await gate.untilWaiting(2)
        #expect(presenter.status(of: clients[0]) == .notExempt,
                "the first failure put the client back over the second answer")
        gate.release(2, with: nil)
        await first.value
        await second.value

        #expect(presenter.status(of: clients[0]) == .notExempt)
        #expect(presenter.lastFailure == nil)
    }

    /// A LATER FAILURE PUTS BACK WHAT THE STORE HOLDS, which is the earlier answer
    /// that landed, not the status the pass was opened with.
    @Test("a later failure puts back the earlier answer that landed")
    func aLaterFailureRestoresTheEarlierAnswer() async {
        let clients = [Self.client("A")]
        var failNext = false
        let presenter = RosterPresenter(clients: clients, write: { _, _ in
            if failNext { throw RosterPresenterTestError.diskFull }
        })

        await presenter.answer(clients[0], as: .exempt)
        failNext = true
        await presenter.answer(clients[0], as: .notExempt)

        #expect(presenter.status(of: clients[0]) == .exempt)
        #expect(presenter.lastFailure?.contains("put back") == true)
    }

    // MARK: the real writer, over a real store

    private static func store(_ names: [String]) throws -> ModelContainer {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        for name in names { context.insert(Self.client(name)) }
        try context.save()
        return container
    }

    /// ONE WRITER (ovation#481). The roster records the answer through
    /// `ClientTaxStatusWriter`, the same code the invoice screen uses, so the
    /// answer is read back from a context that is neither the roster's nor the
    /// writer's, and the roster's own context is left with nothing unsaved.
    @Test("the roster's answer lands in the store through the one writer")
    func theAnswerLandsThroughTheWriter() async throws {
        let container = try Self.store(["A", "B"])
        let rosterContext = ModelContext(container)
        let clients = try rosterContext.fetch(FetchDescriptor<Client>())
            .sorted { $0.name < $1.name }
        let presenter = RosterPresenter(clients: clients,
                                        write: RosterPresenter.writer(over: container))

        await presenter.answer(clients[0], as: .exempt)

        #expect(presenter.lastFailure == nil)
        let stored = try ModelContext(container).fetch(FetchDescriptor<Client>())
        #expect(stored.first { $0.name == "A" }?.taxStatus == .exempt)
        #expect(stored.first { $0.name == "B" }?.taxStatus == .neverRecorded)
        #expect(!rosterContext.hasChanges, "the roster's own context was written to")
    }

    /// THE RULE THE WRITER HOLDS NOW HOLDS ON THE ROSTER TOO (L281). Before
    /// ovation#481 the roster wrote the field itself and could record the absence
    /// of an answer, correct only because its own screen does not offer it.
    @Test("the roster cannot record never recorded, because the writer refuses it")
    func theRosterPathRefusesNeverRecorded() async throws {
        let container = try Self.store(["A"])
        let clients = try ModelContext(container).fetch(FetchDescriptor<Client>())
        let presenter = RosterPresenter(clients: clients,
                                        write: RosterPresenter.writer(over: container))

        await presenter.answer(clients[0], as: .exempt)
        await presenter.answer(clients[0], as: .neverRecorded)

        #expect(presenter.lastFailure?.contains(ClientTaxStatusRefusal.notAnAnswer.sentence) == true)
        #expect(presenter.status(of: clients[0]) == .exempt)
        let stored = try ModelContext(container).fetch(FetchDescriptor<Client>())
        #expect(stored.first?.taxStatus == .exempt)
    }
}

enum RosterPresenterTestError: Error {
    case diskFull
}

/// What a double write was asked to do, carried out of its closure.
@MainActor
final class RosterWriteHeard {
    var calls: [(String, TaxStatus)] = []
}

/// A write that is held until the test lets it go, so a case can press twice
/// while the first write is still in flight. The waits are on the main actor,
/// like every write the presenter makes, and each is numbered in arrival order.
@MainActor
final class RosterWriteGate {
    private(set) var started: [TaxStatus] = []
    private var held: [Int: CheckedContinuation<Void, any Error>] = [:]

    func wait(recording status: TaxStatus) async throws {
        started.append(status)
        let number = started.count
        try await withCheckedThrowingContinuation { held[number] = $0 }
    }

    /// Waits until the nth write is being held. Bounded, so a write that never
    /// arrives fails the case rather than hanging the suite (L110).
    func untilWaiting(_ number: Int) async {
        for _ in 0..<10_000 where held[number] == nil { await Task.yield() }
        #expect(held[number] != nil, "write \(number) never arrived")
    }

    func release(_ number: Int, with error: (any Error)?) {
        guard let continuation = held.removeValue(forKey: number) else { return }
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}

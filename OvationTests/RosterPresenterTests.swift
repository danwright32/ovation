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
@MainActor
struct RosterPresenterTests {

    private static func client(_ name: String, tax: TaxStatus = .neverRecorded) -> Client {
        let c = Client(name: name, taxStatus: tax)
        c.email = "\(name.lowercased())@example.example"
        return c
    }

    @Test("answering one client takes it out of what is left and leaves the starting figure alone")
    func answeringMovesRemainingAndNotStartedWith() throws {
        let clients = [Self.client("A"), Self.client("B"), Self.client("C")]
        let presenter = RosterPresenter(clients: clients, save: {})

        #expect(presenter.startedWith == 3)
        #expect(presenter.remaining == 3)

        try presenter.answer(clients[0], as: .exempt)

        #expect(presenter.startedWith == 3)
        #expect(presenter.remaining == 2)
        #expect(clients[0].taxStatus == .exempt)
    }

    @Test("the pass is settled once every client has been answered")
    func settledWhenAllAnswered() throws {
        let clients = [Self.client("A"), Self.client("B")]
        let presenter = RosterPresenter(clients: clients, save: {})

        try presenter.answer(clients[0], as: .exempt)
        #expect(!presenter.isSettled)

        try presenter.answer(clients[1], as: .notExempt)
        #expect(presenter.isSettled)
        #expect(presenter.remaining == 0)
        #expect(presenter.startedWith == 2)
    }

    // MARK: the failure path, which is the half a happy path test cannot see

    /// L415. A screen that shows a change BEFORE the write lands owes a failure
    /// path that puts it back AND says so, or a failed write looks exactly like
    /// a slow one. Here the change is visible the instant a chip is pressed, so
    /// a save that throws must leave the client as it was and leave a sentence
    /// behind, rather than a row that has quietly gone from the list while the
    /// store still refuses to invoice it.
    @Test("a save that fails puts the client back and says what went wrong")
    func aFailedSaveRevertsAndSpeaks() {
        let clients = [Self.client("A")]
        let presenter = RosterPresenter(clients: clients, save: {
            throw RosterPresenterTestError.diskFull
        })

        #expect(throws: RosterPresenterTestError.self) {
            try presenter.answer(clients[0], as: .exempt)
        }

        #expect(clients[0].taxStatus == .neverRecorded)
        #expect(presenter.remaining == 1)
        #expect(presenter.startedWith == 1)
        #expect(presenter.lastFailure != nil)
    }

    /// REVERSED 2026-09-11, and the test that defended the old answer is gone
    /// rather than adjusted (L252). This sentence used to carry the client's id
    /// and deliberately not its name, applying docs/PRIVACY-FLOOR.md to it. That
    /// was a misreading: the floor keeps real names out of a PUBLIC repository
    /// and out of terminal output, and it says in terms that Dan reads them on
    /// his own screen. This is his own screen. So the one sentence that appears
    /// at the worst moment named nobody he recognises and quoted a programmer's
    /// error at him.
    @Test("the failure sentence names the client, because this is Dan's own screen")
    func theFailureNamesTheClient() {
        let clients = [Self.client("Ashgrove Chamber Players")]
        let presenter = RosterPresenter(clients: clients, save: {
            throw RosterPresenterTestError.diskFull
        })

        try? presenter.answer(clients[0], as: .exempt)

        let said = presenter.lastFailure ?? ""
        #expect(said.contains("Ashgrove Chamber Players"))
        // And no identifier, which says nothing to the person reading it.
        #expect(!said.contains(clients[0].id.uuidString))
    }

    /// L415 again, from the other side: the sentence has to say the change was
    /// UNDONE, or a person reads "could not be saved" and cannot tell whether
    /// the screen in front of them is showing the old value or the new one.
    @Test("the failure sentence says the value was put back")
    func theFailureSaysItWasPutBack() {
        let clients = [Self.client("Ashgrove Chamber Players")]
        let presenter = RosterPresenter(clients: clients, save: {
            throw RosterPresenterTestError.diskFull
        })

        try? presenter.answer(clients[0], as: .exempt)

        #expect(presenter.lastFailure?.contains("put back") == true)
    }

    /// A second attempt that SUCCEEDS must clear what the first one left behind,
    /// or a sentence about a write that has since landed sits on the screen
    /// contradicting it.
    @Test("a later success clears the earlier failure")
    func aLaterSuccessClearsTheFailure() throws {
        let clients = [Self.client("A")]
        var shouldFail = true
        let presenter = RosterPresenter(clients: clients, save: {
            if shouldFail { throw RosterPresenterTestError.diskFull }
        })

        try? presenter.answer(clients[0], as: .exempt)
        #expect(presenter.lastFailure != nil)

        shouldFail = false
        try presenter.answer(clients[0], as: .exempt)
        #expect(presenter.lastFailure == nil)
        #expect(presenter.remaining == 0)
    }
}

enum RosterPresenterTestError: Error {
    case diskFull
}


import Foundation
import SwiftData
import Testing

/// ovation#40. The step between an opened store and the two presenters the
/// window needs, kept out of `OvationApp` on purpose.
///
/// WHY IT IS NOT IN THE ENTRY POINT. `OvationApp.swift` is the one file the pure
/// suite cannot compile, because it carries `@main`, so anything decided there
/// is decided where no test can reach it. What is left in the app is the call.
///
/// A FETCH THAT FAILS IS NOT AN EMPTY ROSTER (L215). A reader that answers with
/// an empty collection when its accessor threw is indistinguishable from a
/// correct read of an empty store, and here the two mean opposite things: an
/// empty store is a healthy new install, and a failed read is a store Ovation
/// cannot see its own clients in. So the failure raises a problem and returns
/// nothing, and it is asserted in both directions.
@MainActor
struct RosterLaunchTests {

    private static func needing(_ count: Int) -> [Client] {
        (0..<count).map { i in
            let c = Client(name: "Client \(i)", taxStatus: .neverRecorded)
            c.email = "c\(i)@example.example"
            return c
        }
    }

    private static func store() -> ProblemsStore {
        ProblemsStore(journal: InMemoryProblemsJournal())
    }

    @Test("it reads the roster and captures what the pass started with")
    func itCapturesWhatThePassStartedWith() throws {
        let problems = Self.store()
        let made = RosterLaunch.presenters(
            fetchClients: { Self.needing(3) }, write: { _, _ in }, problems: problems, now: Date())

        let pair = try #require(made)
        #expect(pair.roster.startedWith == 3)
        #expect(problems.open.isEmpty)
    }

    /// Where the pass has work, that is where Dan lands.
    @Test("the shell starts on the roster when something blocks a send")
    func theShellStartsOnTheRosterWhenSomethingBlocks() throws {
        // Made OUTSIDE `#require`, whose expansion wants a Sendable closure and
        // the write is main actor isolated rather than Sendable.
        let made = RosterLaunch.presenters(
            fetchClients: { Self.needing(3) }, write: { _, _ in }, problems: Self.store(), now: Date())
        let pair = try #require(made)

        #expect(pair.shell.selected == .roster)
        #expect(pair.shell.destinations.contains(.roster))
    }

    /// And where it has none it must NOT start there, or standing on it is what
    /// keeps it in the rail for ever and the rule that it leaves when empty can
    /// never fire (PRD 5a).
    @Test("the shell does not start on the roster when nothing blocks")
    func theShellDoesNotStartOnAnEmptyRoster() throws {
        let made = RosterLaunch.presenters(
            fetchClients: { [] }, write: { _, _ in }, problems: Self.store(), now: Date())
        let pair = try #require(made)

        #expect(pair.shell.selected != .roster)
        #expect(!pair.shell.destinations.contains(.roster))
    }

    // MARK: the failure path

    @Test("a fetch that fails raises a problem and hands back nothing")
    func aFailedFetchIsNotAnEmptyRoster() {
        let problems = Self.store()

        let made = RosterLaunch.presenters(
            fetchClients: { throw RosterLaunchTestError.storeUnreadable },
            write: { _, _ in }, problems: problems, now: Date())

        #expect(made == nil)
        #expect(problems.open.count == 1)
    }

    /// The other direction, or the assertion above is satisfied by something
    /// that raises a problem every time (L98, L159).
    @Test("and a store that really is empty raises nothing")
    func anEmptyStoreIsNotAProblem() {
        let problems = Self.store()

        _ = RosterLaunch.presenters(
            fetchClients: { [] }, write: { _, _ in }, problems: problems, now: Date())

        #expect(problems.open.isEmpty)
    }

    @Test("the problem it raises says what Ovation cannot do, not only what broke")
    func theProblemSaysWhatItMeans() {
        let problems = Self.store()

        _ = RosterLaunch.presenters(
            fetchClients: { throw RosterLaunchTestError.storeUnreadable },
            write: { _, _ in }, problems: problems, now: Date())

        let said = problems.open.first?.sentence ?? ""
        #expect(said.contains("client"))
        #expect(!said.isEmpty)
    }
}

enum RosterLaunchTestError: Error {
    case storeUnreadable
}

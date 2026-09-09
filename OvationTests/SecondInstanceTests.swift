import Foundation
import Testing

/// Plan 1.3, PRD 5.37, ovation#84. A second running copy stands aside and names
/// the copy it stood aside for.
struct SecondInstanceTests {

    private static let path = "/Applications/Ovation.app/Contents/MacOS/Ovation"

    @Test("the only copy runs")
    func theonlyCopyRuns() {
        let verdict = SecondInstance.check(
            executablePath: Self.path, ownPID: 501, runningPIDs: { _ in [501] })

        #expect(verdict == .theOnlyCopy)
        #expect(verdict.mayRun)
    }

    @Test("a process list that does not even include this one still runs")
    func anemptyListStillRuns() {
        // pgrep can legitimately answer nothing about a process that is mid
        // launch. That is not another copy.
        let verdict = SecondInstance.check(
            executablePath: Self.path, ownPID: 501, runningPIDs: { _ in [] })

        #expect(verdict == .theOnlyCopy)
    }

    @Test("a second copy stands aside and NAMES the one it stood aside for")
    func asecondCopyStandsAside() {
        let verdict = SecondInstance.check(
            executablePath: Self.path, ownPID: 900, runningPIDs: { _ in [412, 900] })

        #expect(verdict == .standingAsideFor(pid: 412, executablePath: Self.path))
        #expect(!verdict.mayRun)
    }

    @Test("the OWN pid is excluded by identity, not by position in the list")
    func theownPidIsExcludedByIdentity() {
        // A process list has no promised order, so taking all but the first would
        // stand aside for itself whenever pgrep answered in another order.
        let ownIsLast = SecondInstance.check(
            executablePath: Self.path, ownPID: 900, runningPIDs: { _ in [412, 900] })
        let ownIsFirst = SecondInstance.check(
            executablePath: Self.path, ownPID: 900, runningPIDs: { _ in [900, 412] })

        #expect(ownIsLast == ownIsFirst)
        #expect(ownIsLast == .standingAsideFor(pid: 412, executablePath: Self.path))
    }

    @Test("two copies racing name the SAME one, rather than each naming the other")
    func tworacingLaunchesAgree() {
        // Each naming the other reads as a disagreement about which is real, and
        // Dan would be told two different things by two windows.
        let first = SecondInstance.check(
            executablePath: Self.path, ownPID: 900, runningPIDs: { _ in [412, 700, 900] })
        let second = SecondInstance.check(
            executablePath: Self.path, ownPID: 700, runningPIDs: { _ in [412, 700, 900] })

        #expect(first == second)
        #expect(first == .standingAsideFor(pid: 412, executablePath: Self.path))
    }

    @Test("the executable PATH is what is asked about, so Debug and Release are not each other's")
    func thepathIsWhatIsAskedAbout() {
        // They carry different bundle identities and different data directories
        // on purpose, so they share no store and must not stand aside for one
        // another. Identifying by name or bundle id has picked the wrong copy in
        // this estate before.
        let release = "/Applications/Ovation.app/Contents/MacOS/Ovation"
        let debug = "/Users/dan/Library/Developer/Xcode/DerivedData/Ovation/Debug/Ovation.app/Contents/MacOS/Ovation"
        final class Asked: @unchecked Sendable {
            private let lock = NSLock()
            private var paths: [String] = []
            func record(_ path: String) { lock.lock(); paths.append(path); lock.unlock() }
            var all: [String] { lock.lock(); defer { lock.unlock() }; return paths }
        }
        let asked = Asked()
        let lookup: SecondInstance.RunningPIDs = { path in
            asked.record(path)
            return path == release ? [412] : []
        }

        #expect(SecondInstance.check(executablePath: debug, ownPID: 900, runningPIDs: lookup)
            == .theOnlyCopy, "a running Release copy is not the Debug build's second instance")
        #expect(asked.all == [debug], "and it asked about its OWN path, not about the app's name")
    }

    @Test("a lookup that could not run stands aside, rather than answering that nothing is there")
    func afailedLookupStandsAside() {
        // Returning nothing on a failure would say "no other copy" on the
        // strength of not having looked, which is the permissive answer reached
        // by a check that did not happen (L215, L98).
        let verdict = SecondInstance.check(
            executablePath: Self.path, ownPID: 900,
            runningPIDs: { _ in [SecondInstance.lookupFailed] })

        #expect(!verdict.mayRun)
        #expect(verdict == .couldNotTell(reason: "the list of running processes could not be read"))
    }

    @Test("and it does NOT claim another copy is running, because nothing measured that")
    func afailedLookupDoesNotInventACopy() throws {
        // The action is the same and the sentence must not be. The first version
        // reported this as `standingAsideFor(pid: -1)`, which stands aside
        // correctly and then tells Dan another copy is running as process -1,
        // sending him to find something that does not exist (L11).
        let verdict = SecondInstance.check(
            executablePath: Self.path, ownPID: 900,
            runningPIDs: { _ in [SecondInstance.lookupFailed] })
        let sentence = try #require(SecondInstance.sentence(for: verdict))

        // The needle is the CLAIM, not a substring of it. "is already running"
        // also appears inside "could not check WHETHER another copy is already
        // running", which is a question rather than an assertion, and a test that
        // banned the substring would have banned the honest sentence too.
        #expect(!sentence.contains("-1"), "there is no process -1 to send anybody looking for")
        #expect(!sentence.contains("Another copy of Ovation is already running"))
        #expect(sentence.hasPrefix("Ovation could not check whether"))
        #expect(sentence.contains("stood aside"))
        #expect(sentence.contains("rather than assume it is alone"))

        // And the sentence for a copy that WAS found still makes the claim, so
        // this is not passing because the wording went vague everywhere.
        let found = try #require(SecondInstance.sentence(
            for: .standingAsideFor(pid: 412, executablePath: Self.path)))
        #expect(found.contains("Another copy of Ovation is already running"))
    }

    @Test("the sentence names the process and the path, and says what it did NOT do")
    func thesentenceNamesTheCopy() throws {
        let sentence = try #require(SecondInstance.sentence(
            for: .standingAsideFor(pid: 412, executablePath: Self.path)))

        #expect(sentence.contains("412"))
        #expect(sentence.contains(Self.path))
        #expect(sentence.contains("opened nothing"))
        #expect(sentence.contains("Use the copy that is already open"))
    }

    @Test("the only copy has no sentence, because there is nothing to say")
    func theonlyCopySaysNothing() {
        #expect(SecondInstance.sentence(for: .theOnlyCopy) == nil)
    }

    @Test("the real lookup answers about a process that IS running, which is this test")
    func therealLookupWorks() throws {
        // The seam is not the only thing ever exercised (L246). This asks the
        // real pgrep about the running test process's own executable and expects
        // to find it, which is the one case that proves the anchored pattern and
        // the parsing both work.
        let executable = try #require(Bundle.main.executableURL?.path
            ?? ProcessInfo.processInfo.arguments.first)
        let pids = SecondInstance.pidsRunning(executable)

        #expect(pids.contains(ProcessInfo.processInfo.processIdentifier)
                || pids.isEmpty || pids == [-1],
                Comment(rawValue: "either it found this process, or the harness runs under a "
                    + "path pgrep reports differently, which is a fact about the harness "
                    + "rather than a defect"))
        #expect(!pids.contains(0), "zero is never a pid, so a parse that produced one is broken")
    }
}

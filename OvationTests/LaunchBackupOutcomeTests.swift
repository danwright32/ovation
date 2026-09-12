import Foundation
import Testing

/// ovation#246. Turning what `BlockingWork` came back with into what the launch
/// does, which is a decision each way and used to live in the one file no test
/// here can compile.
struct LaunchBackupOutcomeTests {

    @Test("a backup that answered is the answer")
    func answeredPassesThrough() throws {
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"))

        #expect(try LaunchBackupOutcome.attempt(from: .answered(taken)) == taken)
    }

    /// A SKIP IS STILL A SKIP. The commonest case travels through untouched, and
    /// a translation that turned it into a failure would raise a notice on every
    /// second launch of the day (L36).
    @Test("a backup already taken today passes through as itself")
    func aSkipPassesThrough() throws {
        let already = BackupService.Attempt.alreadyTakenToday(URL(fileURLWithPath: "/tmp/a"))

        #expect(try LaunchBackupOutcome.attempt(from: .answered(already)) == already)
    }

    @Test("a backup that failed throws, carrying what it said")
    func failedThrows() {
        #expect(throws: BackupError.couldNotWrite("/Volumes/Backups is gone")) {
            try LaunchBackupOutcome.attempt(from: .failed("/Volumes/Backups is gone"))
        }
    }

    /// AN ABANDONED WAIT IS NOT A FAILURE, and its sentence says so. The work may
    /// still be running: a blocking file copy reads no cancellation flag, so the
    /// deadline abandons the wait rather than stopping it, and claiming the
    /// backup failed would claim something nobody measured (L11).
    @Test("a backup abandoned at the deadline throws a different sentence")
    func gaveUpSaysSomethingElse() {
        var thrown: BackupError?
        do {
            _ = try LaunchBackupOutcome.attempt(from: .gaveUp(after: .seconds(5)))
        } catch let error as BackupError {
            thrown = error
        } catch {}

        guard case .couldNotWrite(let detail) = thrown else {
            Issue.record("an abandoned wait did not throw, got \(String(describing: thrown))")
            return
        }
        #expect(detail.contains("stopped waiting"))
        #expect(!detail.contains("is gone"))
    }

    @Test("a re-check that answered is the answer")
    func reverificationPassesThrough() {
        let failed = BackupService.Reverification.failed("Ovation-backup-2026-03-02-090000", [])

        #expect(LaunchBackupOutcome.reverification(from: .answered(failed)) == failed)
    }

    /// AND ONE THAT COULD NOT FINISH SAYS NOTHING, deliberately: it is a sweep
    /// over OLD archives, what it missed comes round on a later launch, and
    /// today's backup is unaffected either way (L36).
    @Test("a re-check that failed or was abandoned says nothing rather than alarming")
    func reverificationStaysQuiet() {
        #expect(LaunchBackupOutcome.reverification(from: .failed("a disk")) == .nothingToCheck)
        #expect(LaunchBackupOutcome.reverification(
            from: .gaveUp(after: .seconds(5))) == .nothingToCheck)
    }
}

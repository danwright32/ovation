// ovation#246. WHAT THE LAUNCH DOES WITH WHAT `BlockingWork` CAME BACK WITH.
//
// The backup and the re-check run off the main actor now, through a helper that
// answers one of three ways: it answered, it failed, or it was abandoned at the
// deadline. Turning those into what the launch sequence expects is a DECISION
// each way, and it lived in `OvationApp`, which is the one file no test here can
// compile (ovation#88). It lives here so both translations can be driven.
//
// THE THREE STAY THREE. Flattening "it was abandoned" into "it failed" would
// claim something nobody measured: the work may still be running, because a
// blocking file copy reads no cancellation flag and the deadline abandons the
// wait rather than stopping it (L11).
import Foundation

enum LaunchBackupOutcome {

    /// What the sequence's backup step should do with the answer.
    ///
    /// A FAILURE AND AN ABANDONED WAIT BOTH THROW, and they throw DIFFERENT
    /// sentences, because the remedies differ: one is a folder that refused, the
    /// other is a folder that is slow enough to be a problem of its own.
    static func attempt(
        from outcome: BlockingWorkOutcome<BackupService.Attempt>
    ) throws -> BackupService.Attempt {
        switch outcome {
        case .answered(let attempt):
            return attempt
        case .failed(let detail):
            throw BackupError.couldNotWrite(detail)
        case .gaveUp(let after):
            throw BackupError.couldNotWrite(
                "the backup was still running after \(after), so Ovation stopped "
                    + "waiting for it and opened")
        }
    }

    /// What the sequence's re-check step should do with the answer.
    ///
    /// A RE-CHECK THAT COULD NOT FINISH SAYS NOTHING, and that is right for this
    /// one rather than a swallowed failure: it is a sweep over OLD archives, the
    /// ones it did not reach come round on later launches, and a notice about it
    /// carries nothing Dan can act on (L36). Today's backup is unaffected either
    /// way, which is the fact that makes silence honest here and would make it
    /// dishonest for the backup above.
    static func reverification(
        from outcome: BlockingWorkOutcome<BackupService.Reverification>
    ) -> BackupService.Reverification {
        if case .answered(let checked) = outcome { return checked }
        return .nothingToCheck
    }
}

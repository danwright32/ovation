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

    // MARK: how long the launch waits (ovation#507)

    /// The least any launch waits: `BlockingWork`'s own deadline, which is what
    /// every launch waited before the deadline was sized, and is still far above
    /// today's data folder (19 files, 372KB, measured 2026-09-26).
    static let deadlineFloor: Duration = BlockingWork.defaultDeadline

    /// What each file adds. MEASURED: 4,000 documents of 40KB were backed up and
    /// verified in 3.07s on this Mac (BackupCostTests, 2026-09-08), about 0.75ms a
    /// document. Ten milliseconds is thirteen times that.
    static let allowancePerFile: Duration = .milliseconds(10)

    /// What each byte adds, as a rate the backup is allowed to be as slow as.
    /// MEASURED: 1,000 files of 300KB (300MB) were copied, hashed and read again in
    /// 0.75s on this Mac's own disk, about 400MB a second, 2026-09-26. Twenty
    /// megabytes a second is twenty times slower, which leaves room for a folder
    /// Dan might later choose on an external drive or a network share, where the
    /// copy is a real copy rather than the disk's own clone.
    static let allowedBytesPerSecond = 20_000_000

    /// How long a launch waits for a backup of this size before it stops waiting.
    ///
    /// SIZED FOR THE WORK, NOT FOR A KEYCHAIN READ. The five seconds this used to
    /// inherit were chosen for reads that cost microseconds, and past them a launch
    /// that would upgrade the store REFUSES to open (ovation#505), so a deadline
    /// the data outgrows turns a working backup into a refusal nobody can explain.
    /// A number fixed today would be outgrown by the receipts silently (L354), so it
    /// grows with what is copied, from a floor that is the old deadline.
    static func deadline(for size: BackupSize) -> Duration {
        deadlineFloor
            + allowancePerFile * size.files
            + .nanoseconds(size.bytes * (1_000_000_000 / allowedBytesPerSecond))
    }

    /// Runs the launch's backup off the main actor, for as long as its size calls
    /// for, and hands back what it did or THE ERROR IT THREW, unchanged
    /// (ovation#505, ovation#507).
    ///
    /// `measuring` is REQUIRED, with no default: a caller that forgot it would get
    /// the floor for every size, which is the defect this exists to end (L168).
    ///
    /// A SIZE THAT CANNOT BE READ LEAVES THE FLOOR. Whatever stopped the walk will
    /// stop the backup too, and the backup is what says so, in its own words; the
    /// walk failing is not a reason to skip the attempt (L93). The walk itself runs
    /// under the floor, because it reads no file contents.
    ///
    /// `BlockingWork` can only carry a failure as text, because it serves work of
    /// every kind. So a `BackupError` thrown inside it came out as a string, and
    /// `attempt(from:)` then called every string a write failure: "no folder
    /// chosen" reached the launch as a backup that "could not be written to
    /// noFolderChosen", under a kind nothing resolves, and a backup that did not
    /// verify read the same as a full disk (L11, L199).
    ///
    /// SO A BACKUP ERROR IS CAUGHT INSIDE THE WORK AND RETURNED AS A VALUE, and
    /// only something that is not a backup error at all travels as text. The
    /// launch can then say which of them happened, and it has to, because on a
    /// launch that would upgrade the store each one is the reason it refused.
    ///
    /// `sleeping` is injected so a test can read the deadline each wait was given
    /// without paying it.
    static func run(
        measuring: @escaping @Sendable () throws -> BackupSize,
        sleeping: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        _ work: @escaping @Sendable () throws -> BackupService.Attempt
    ) async throws -> BackupService.Attempt {
        let deadline = await measuredDeadline(measuring, sleeping: sleeping)
        let outcome = await BlockingWork.run(deadline: deadline, sleeping: sleeping) {
            () throws -> Result<BackupService.Attempt, BackupError> in
            do {
                return .success(try work())
            } catch let refusal as BackupError {
                return .failure(refusal)
            }
        }
        switch outcome {
        case .answered(.success(let attempt)):
            return attempt
        case .answered(.failure(let refusal)):
            throw refusal
        case .failed(let detail):
            return try attempt(from: .failed(detail))
        case .gaveUp(let after):
            return try attempt(from: .gaveUp(after: after))
        }
    }

    /// Re-checks one older archive, for as long as the data folder's size calls
    /// for, and hands back what it found (ovation#507).
    ///
    /// SIZED LIKE THE BACKUP, because it is the same work: it reads and hashes
    /// every file in one archive, and an archive holds what the data folder held
    /// on its day, so the folder's size today is the measure that grows the way
    /// the archives do. It gives up
    /// silently by design (see `reverification(from:)`), which is exactly why a
    /// floor the archives had outgrown would be invisible: every launch would stop
    /// waiting, say nothing, and no old archive would ever be checked again.
    static func reverify(
        measuring: @escaping @Sendable () throws -> BackupSize,
        sleeping: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        _ work: @escaping @Sendable () throws -> BackupService.Reverification
    ) async -> BackupService.Reverification {
        let deadline = await measuredDeadline(measuring, sleeping: sleeping)
        return reverification(
            from: await BlockingWork.run(deadline: deadline, sleeping: sleeping, work))
    }

    /// The deadline the measured size calls for, or the floor when the size could
    /// not be read. The walk runs under the floor, because it reads no contents.
    private static func measuredDeadline(
        _ measuring: @escaping @Sendable () throws -> BackupSize,
        sleeping: @escaping @Sendable (Duration) async throws -> Void
    ) async -> Duration {
        let measured = await BlockingWork.run(deadline: deadlineFloor, sleeping: sleeping, measuring)
        if case .answered(let size) = measured { return deadline(for: size) }
        return deadlineFloor
    }

    /// What the sequence's backup step should do with the answer.
    ///
    /// A FAILURE AND AN ABANDONED WAIT BOTH THROW, and they throw DIFFERENT
    /// errors, because the remedies differ: one is a folder that refused, the
    /// other is a folder that is slow enough to be a problem of its own. The
    /// abandoned wait was a write failure carrying a sentence until ovation#507,
    /// which filed a slow folder under the notice for a broken one.
    static func attempt(
        from outcome: BlockingWorkOutcome<BackupService.Attempt>
    ) throws -> BackupService.Attempt {
        switch outcome {
        case .answered(let attempt):
            return attempt
        case .failed(let detail):
            throw BackupError.couldNotWrite(detail)
        case .gaveUp(let after):
            throw BackupError.stillRunning(after: after)
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

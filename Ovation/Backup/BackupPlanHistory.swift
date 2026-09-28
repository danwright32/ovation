// ovation#610. EVERY PLAN AN ARCHIVE COULD HAVE BEEN WRITTEN UNDER, so each
// archive is judged by its own plan rather than by today's.
//
// WHY IT EXISTS. PR #573 added `launch-backups.jsonl` to `BackupPlan.members`,
// and the verifier checked every member of the CURRENT plan against each
// archive's manifest. Every archive written before it then failed with a member
// missing, although every file in it was exactly as written, and the restore,
// which runs the same check, refused all four of Dan's older archives. The
// rule changed; the archives did not.
//
// A VERSION IS IMMUTABLE ONCE ARCHIVES EXIST UNDER IT (L1010). Changing
// `BackupPlan.members` is therefore a new version: the list as it stood is copied
// into `earlierRevisions` below, unchanged, `version` goes up by one, `versionDay`
// becomes the day the change merges, and a manifest of the new plan is committed
// under OvationTests/Fixtures/backup-manifests. BackupPlanHistoryTests fails until
// all of that is done, because it takes a backup today and compares it with the
// newest committed manifest.
//
// THE REVISIONS BELOW ARE COPIED FROM THE PLAN'S OWN HISTORY IN GIT, one per
// commit that changed the list: 108cb40, 2c5ced0, 4058a4c, 7a5fd20, bdfcf74 and
// 69ca8b7. Only what the verifier reads is carried, each member's path, kind and
// expectation; what a restore does is today's plan's business, and restore asks
// today's plan (`BackupPlan.restorePolicy(of:)`).
import Foundation

/// One version of what a backup contains.
struct BackupPlanRevision: Sendable {
    let version: Int
    /// The day this version reached main, as a day key. An archive cannot have
    /// been written under a plan that did not exist yet, so this bounds which
    /// plans can explain a manifest. It cannot pick one on its own, because the
    /// build Dan has installed lags main: his 2026-09-27 archive was written a
    /// day after #573 merged, by a build from before it.
    let day: String
    let members: [BackupMember]

    func requires(_ path: String) -> Bool {
        members.contains { $0.path == path && $0.expectation == .required }
    }

    /// Whether this plan's build could have written exactly these member records.
    ///
    /// Every build records every member it knows, in a word its expectation
    /// allows, and `takeBackup` refuses rather than write a manifest short of one.
    /// So the set of paths a manifest records is the set its build's plan
    /// declared, and a member it does not mention at all is one that build did
    /// not know.
    func couldHaveWritten(_ records: [BackupManifest.MemberRecord]) -> Bool {
        guard records.count == members.count,
              Set(records.map(\.path)) == Set(members.map(\.path)) else { return false }
        return records.allSatisfy { record in
            members.first { $0.path == record.path }?.allowedStatuses.contains(record.status)
                ?? false
        }
    }
}

extension BackupMember {
    /// What a manifest may record for this member under the plan declaring it.
    var allowedStatuses: Set<BackupManifest.MemberStatus> {
        switch expectation {
        case .required:
            return [.copied]
        case .presentSometimes:
            // Either is correct, but it must say WHICH. A member missing from the
            // manifest altogether is not the same as one recorded as absent, and
            // only the second is evidence anybody looked.
            return [.copied, .legitimatelyAbsent]
        case .notYetBuilt:
            return [.copied, .notYetBuilt]
        }
    }
}

extension BackupPlan {
    /// The version of `members`, recorded in every manifest written from
    /// ovation#610 on. See this file's header before changing either.
    static let version = 7
    /// The day version 7 reached main: #573, which added the launch backup record.
    static let versionDay = "2026-09-26"

    static var current: BackupPlanRevision {
        BackupPlanRevision(version: version, day: versionDay, members: members)
    }

    /// Every version, oldest first, today's last.
    static var revisions: [BackupPlanRevision] { earlierRevisions + [current] }

    /// The plan a manifest was written under.
    ///
    /// A MANIFEST THAT NAMES ITS VERSION IS HELD TO IT, and one naming a version
    /// this build does not know, written by a newer Ovation, is held to today's
    /// plan, which is what every archive was held to before.
    ///
    /// ONE THAT NAMES NONE was written before ovation#610, and its plan is the
    /// newest one that already existed on the day it was written AND could have
    /// written exactly the members it records. The day alone would be wrong for
    /// an archive written by a build older than main; the members alone could
    /// match a plan from after the archive was written. When no plan explains it,
    /// the manifest has been changed by something other than Ovation, and it is
    /// held to today's plan, strictly, rather than excused.
    static func revision(thatWrote manifest: BackupManifest) -> BackupPlanRevision {
        if let named = manifest.planVersion {
            return revisions.first { $0.version == named } ?? current
        }
        let day = BusinessCalendar.dayKey(for: manifest.createdAt)
        return revisions
            .filter { $0.day <= day }
            .last { $0.couldHaveWritten(manifest.members) }
            ?? current
    }

    private static let checkpointed = "absent once the store is checkpointed"
    private static let noExportYet = "absent until the first export has been run"
    private static let noProblemYet = "absent until the first problem has been recorded"
    private static let noBookingYet = "absent until Downbeat has queued its first booking"

    /// Versions 1 to 6, frozen. Never edited: an archive written under one of
    /// them is judged by it for as long as the archive is kept.
    static let earlierRevisions: [BackupPlanRevision] = [
        // 108cb40, the first plan.
        .init(version: 1, day: "2026-09-06", members: [
            .init(path: "problems.jsonl", kind: .file, expectation: .required),
            .init(path: "documents", kind: .directory, expectation: .required),
            .init(path: "custody", kind: .directory, expectation: .required),
            .init(path: "Ovation.store", kind: .file, expectation: .notYetBuilt(issue: "ovation#60")),
            .init(path: "Ovation.store-wal", kind: .file, expectation: .notYetBuilt(issue: "ovation#60")),
            .init(path: "Ovation.store-shm", kind: .file, expectation: .notYetBuilt(issue: "ovation#60")),
            .init(path: "consumed-bookings.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#31")),
            .init(path: "consumed-messages.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#79")),
            .init(path: "referral-ledger.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#38")),
            .init(path: "export-runs.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#64")),
        ]),
        // 2c5ced0 (ovation#88): the database required, its log and shared memory
        // file present sometimes.
        .init(version: 2, day: "2026-09-07", members: [
            .init(path: "problems.jsonl", kind: .file, expectation: .required),
            .init(path: "documents", kind: .directory, expectation: .required),
            .init(path: "custody", kind: .directory, expectation: .required),
            .init(path: "Ovation.store", kind: .file, expectation: .required),
            .init(path: "Ovation.store-wal", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "Ovation.store-shm", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "consumed-bookings.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#31")),
            .init(path: "consumed-messages.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#79")),
            .init(path: "referral-ledger.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#38")),
            .init(path: "export-runs.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#64")),
        ]),
        // 4058a4c (ovation#116): the version marker required; the referral
        // ledger gone, since it lives inside the store.
        .init(version: 3, day: "2026-09-08", members: [
            .init(path: "problems.jsonl", kind: .file, expectation: .required),
            .init(path: "documents", kind: .directory, expectation: .required),
            .init(path: "custody", kind: .directory, expectation: .required),
            .init(path: "Ovation.store", kind: .file, expectation: .required),
            .init(path: "Ovation.store.version", kind: .file, expectation: .required),
            .init(path: "Ovation.store-wal", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "Ovation.store-shm", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "consumed-bookings.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#31")),
            .init(path: "consumed-messages.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#79")),
            .init(path: "export-runs.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#64")),
        ]),
        // 7a5fd20 (ovation#64): the export run record built, so present sometimes.
        .init(version: 4, day: "2026-09-09", members: [
            .init(path: "problems.jsonl", kind: .file, expectation: .required),
            .init(path: "documents", kind: .directory, expectation: .required),
            .init(path: "custody", kind: .directory, expectation: .required),
            .init(path: "Ovation.store", kind: .file, expectation: .required),
            .init(path: "Ovation.store.version", kind: .file, expectation: .required),
            .init(path: "export-runs.jsonl", kind: .file, expectation: .presentSometimes(reason: noExportYet)),
            .init(path: "Ovation.store-wal", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "Ovation.store-shm", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "consumed-bookings.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#31")),
            .init(path: "consumed-messages.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#79")),
        ]),
        // bdfcf74 (ovation#222): the problems journal present sometimes.
        .init(version: 5, day: "2026-09-11", members: [
            .init(path: "problems.jsonl", kind: .file, expectation: .presentSometimes(reason: noProblemYet)),
            .init(path: "documents", kind: .directory, expectation: .required),
            .init(path: "custody", kind: .directory, expectation: .required),
            .init(path: "Ovation.store", kind: .file, expectation: .required),
            .init(path: "Ovation.store.version", kind: .file, expectation: .required),
            .init(path: "export-runs.jsonl", kind: .file, expectation: .presentSometimes(reason: noExportYet)),
            .init(path: "Ovation.store-wal", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "Ovation.store-shm", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "consumed-bookings.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#31")),
            .init(path: "consumed-messages.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#79")),
        ]),
        // 69ca8b7 (ovation#253): the booking queue and Downbeat's record of it.
        // Every archive Dan has from before #573 was written under this one.
        .init(version: 6, day: "2026-09-13", members: [
            .init(path: "problems.jsonl", kind: .file, expectation: .presentSometimes(reason: noProblemYet)),
            .init(path: "documents", kind: .directory, expectation: .required),
            .init(path: "custody", kind: .directory, expectation: .required),
            .init(path: "Ovation.store", kind: .file, expectation: .required),
            .init(path: "Ovation.store.version", kind: .file, expectation: .required),
            .init(path: "export-runs.jsonl", kind: .file, expectation: .presentSometimes(reason: noExportYet)),
            .init(path: "Ovation.store-wal", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "Ovation.store-shm", kind: .file, expectation: .presentSometimes(reason: checkpointed)),
            .init(path: "consumed-bookings.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#31")),
            .init(path: "consumed-messages.jsonl", kind: .file, expectation: .notYetBuilt(issue: "ovation#79")),
            .init(path: "booking-queue", kind: .directory, expectation: .presentSometimes(reason: noBookingYet)),
            .init(path: "downbeat-queued-bookings.json", kind: .file,
                  expectation: .presentSometimes(reason: noBookingYet)),
        ]),
    ]
}

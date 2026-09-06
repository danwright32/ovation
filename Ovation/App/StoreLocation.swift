// Ported-From: danwright32/overture mac/Overture/App/StoreLocation.swift @ ec86b9d375f6851dbf8431320e85eac1c9ff1f88
//
// Port discipline: docs/PORT-DISCIPLINE.md. Plan 1.1, ovation#51. Every constant
// below was re-checked against what OVATION needs rather than inherited, and
// everything that differs from the source is called out where it sits.
//
// Where Ovation's on-disk state lives.
//
// Release (the resident /Applications copy): an `Ovation` folder under
// Application Support. Debug (a development run from Xcode): an isolated
// `Ovation-Debug` folder, and the bundle identity carries a `.debug` suffix
// (project.yml). macOS keys the data directory, the TCC grants and the Gmail
// login to the BUNDLE IDENTIFIER, so that suffix is not cosmetic: it is the
// entire isolation mechanism. Together these guarantee a dev run can never share
// a store, a write ahead log, a Gmail login or a backup folder with the resident
// copy.
//
// THE FILENAME IS `Ovation.store`, NOT SwiftData's `default.store`, and it is
// stated here because an agent porting "the Downbeat pattern" literally would
// undo it. Downbeat uses SwiftData's default filename inside a dedicated folder
// (AppStoreConfiguration.swift). Overture uses `Overture.store` and records why:
// twice it cost Dan his live store at `Application Support/default.store`, once
// when Downbeat opened it (2026-07-08) and once when /usr/libexec/icloudmailagent
// ran a Core Data lightweight migration onto it, replacing every Overture table
// with its own (2026-07-23). Claiming an Ovation-only FOLDER makes the collision
// impossible; claiming an Ovation-only FILENAME means that even if something did
// write into that folder, it would arrive as `default.store` and miss Dan's data
// entirely. Ovation follows Overture.
//
// WHAT IS NOT PORTED, recorded so a port that never happened is visible rather
// than absent from a list nobody maintains:
//
//   `legacyStoreFilename` and `legacyStoreURL`. They exist so StoreRelocation can
//   perform a one-time move of data written by an earlier version. Ovation has
//   never written a store anywhere, so there is nothing to move, and carrying
//   them would put `default.store` back in the list of paths Ovation opens: the
//   exact filename both data losses are about.
//
//   `lockURL`. The source's single-writer lockfile. Plan 1.3 refuses a second
//   running copy by PID resolved from the executable path, and NAMES the copy it
//   stood aside for, which a lockfile cannot do. A lockfile also differs from the
//   PID route in what happens when its holder DIES (L409), so the two are not
//   interchangeable and only one is being built.
//
//   `revealStoreInFinder`. Wanted, but it belongs with the surface that offers
//   it: plan 1.13's launch presenter is where a store refusal becomes actionable.
//   Ported with that issue, not ahead of it.
//
//   `handoffDirectory`, `writableHandoffDirectory` and `isLiveHandoffDirectory`.
//   Overture's handoff folder is a published contract it WRITES; Ovation's
//   equivalent is the queue it READS and drains by deleting. See the queue
//   comment below for the two behaviours that differ as a result.
//
// The Debug/Release decision is factored into pure functions so both branches are
// testable from the (always-Debug) test bundle; the live build wires `#if DEBUG`
// to it.
import Foundation

enum StoreLocation {
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// Ovation's own store filename, deliberately NOT SwiftData's
    /// `default.store`. See above.
    static let storeFilename = "Ovation.store"

    static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Pure and testable: given the Application Support root and whether this is a
    /// Debug build, the directory this build keeps its own state in. Each build
    /// claims a folder of its own, and neither is the shared root.
    ///
    /// UNLIKE THE SOURCE, this creates nothing. Overture's live accessor creates
    /// its folder on first use. Ovation's does not: creation belongs to the store
    /// launch sequence (plan 1.2), which identifies the file, checkpoints and
    /// backs up BEFORE anything opens it for writing. A resolver that creates
    /// means merely displaying a path creates the directory, and a directory that
    /// exists is evidence to whatever reads it next.
    nonisolated static func dataDirectory(appSupport: URL, isDebugBuild: Bool) -> URL {
        appSupport.appendingPathComponent(isDebugBuild ? "Ovation-Debug" : "Ovation",
                                          isDirectory: true)
    }

    nonisolated static func storeURL(appSupport: URL, isDebugBuild: Bool) -> URL {
        dataDirectory(appSupport: appSupport, isDebugBuild: isDebugBuild)
            .appendingPathComponent(storeFilename)
    }

    /// The directory Downbeat writes booking handoff records into, and Ovation
    /// drains (plan 6, ovation#32).
    ///
    /// THE SPLIT HERE IS NOT THE STORE'S SPLIT, and that is the wiring detail
    /// that bites otherwise. Downbeat's `bookingHandoffQueueURL` writes
    /// `Application Support/Ovation/booking-queue`, and its Debug build writes
    /// `Application Support/Ovation/booking-queue.debug`: a SIBLING INSIDE THE
    /// RELEASE FOLDER, not inside `Ovation-Debug`. So a Debug Ovation keeps its
    /// store in `Ovation-Debug` while reading its queue from `Ovation`. Anyone
    /// who tidies either resolver to match the other points a Debug run at a
    /// directory nothing writes, and an empty queue is indistinguishable from a
    /// drained one (L98). `StoreLocationTests` fails if either moves.
    ///
    /// This is a cross-repository contract, so the producer is named: Downbeat's
    /// `AppStoreConfiguration.bookingHandoffQueueURL`.
    nonisolated static func bookingQueueDirectory(appSupport: URL, isDebugBuild: Bool) -> URL {
        appSupport
            .appendingPathComponent("Ovation", isDirectory: true)
            .appendingPathComponent(isDebugBuild ? "booking-queue.debug" : "booking-queue",
                                    isDirectory: true)
    }

    // MARK: the live paths, and the refusal that is structural rather than conventional

    /// This build's real store path, or nil when the launch may not touch
    /// anything real (plan 1.9).
    ///
    /// The refusal lives HERE, where the path is resolved, rather than at each
    /// call site, so a reader or writer added later arrives protected instead of
    /// needing to be remembered (L196). The defaults read this process, so a
    /// caller that passes nothing is refused.
    ///
    /// REFUSED, NOT REDIRECTED, which is where Ovation parts company with the
    /// source. Overture redirects a test's handoff writes to a temp folder, on
    /// the grounds that a test exercising a real write path should still exercise
    /// it. Ovation's equivalent path is one it DELETES from: a redirect to an
    /// empty temp folder would let a drain test pass over nothing at all, and a
    /// test write into the real store or queue is unrecoverable. A test that
    /// needs a store hands the pure resolver above a directory it owns.
    nonisolated static func liveStoreURL(
        appSupport: URL = StoreLocation.appSupport,
        isDebugBuild: Bool = StoreLocation.isDebugBuild,
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch()
    ) -> URL? {
        guard !isDisposableLaunch else { return nil }
        return storeURL(appSupport: appSupport, isDebugBuild: isDebugBuild)
    }

    /// This build's real queue directory, or nil when the launch may not touch
    /// anything real. Same reasoning as `liveStoreURL`, and the cost of a wrong
    /// answer is higher: draining acknowledges by DELETING, so a test that
    /// reached the real queue would destroy a handoff permanently and the
    /// absence would read as "already consumed" (L258).
    nonisolated static func liveBookingQueueDirectory(
        appSupport: URL = StoreLocation.appSupport,
        isDebugBuild: Bool = StoreLocation.isDebugBuild,
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch()
    ) -> URL? {
        guard !isDisposableLaunch else { return nil }
        return bookingQueueDirectory(appSupport: appSupport, isDebugBuild: isDebugBuild)
    }
}

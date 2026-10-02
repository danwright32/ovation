import Foundation
import SwiftData

/// ovation#632. The one way a test opens a store as an EARLIER version of Ovation's
/// schema wrote it, because opening one the obvious way crashes the test process.
///
/// WHAT CRASHED, from the three CI runs on 2026-09-29. The test process died with
/// `NSUnknownKeyException: the entity Invoice is not key value coding-compliant for
/// the key "noteToClient"`, thrown from a SwiftData timer on the MAIN run loop,
/// while a migration case was building its version 1 fixture on another thread.
///
/// WHY, measured the same day on macOS 26 in a standalone program and repeated at
/// will. SwiftData collides versions by ENTITY NAME, the fact
/// `OvationSchemaV1Shape.swift` records for relationships. While containers of two
/// versions are alive in one process, a write through the one opened FIRST encodes
/// with the other version's keys and throws. Every earlier version's `Invoice` is
/// called `Invoice`, so a current version context that any earlier suite left
/// alive, written by a SwiftData main thread timer while a version 1 fixture is
/// open, dies on `noteToClient`, the one field a later version DROPPED. The other
/// versions only ever ADDED fields, so the same collision against them encodes
/// keys the entity has and passes silently, which is why every crash named that
/// key. Releasing the earlier VERSION's container ends the collision.
///
/// WHY CURRENT CONTAINERS OUTLIVE THEIR TESTS AT ALL, also measured: reading both
/// sides of one link in one context (an invoice's client, then that client's
/// invoices) keeps both models, their context and the container alive for the
/// rest of the process. Any suite can do that, so this cannot assume the process
/// holds no earlier opened container; it has to make the window safe anyway.
///
/// IT IS NOT THE MIGRATION. The app opens only the current version, and a store
/// migrated through `OvationMigrationPlan` in the same process as a live current
/// container leaves that container writing correctly, measured beside the above.
/// Only a test builds an earlier version's container of its own.
///
/// SO THE WINDOW IS CLOSED RATHER THAN NARROWED. The container is opened, used and
/// released inside one synchronous job on the MAIN actor, where no main run loop
/// timer can fire, and a container that outlives the call is refused by name
/// rather than trusted to be gone, because a survivor reopens the window for
/// whatever runs next. `EarlierVersionStoreTests` measures each of those, and
/// refuses a test that builds an earlier version any other way.
enum EarlierVersionStore {
    /// The earlier version's container was still alive after the call, so the
    /// collision would outlast the fixture that caused it.
    struct StillOpen: Error, CustomStringConvertible {
        let version: Schema.Version
        /// How long it was waited for before being refused (ovation#651).
        let waited: Duration
        /// WHICH OF THE TWO WAS HELD, read at the deadline (L11): a container
        /// still alive and store files still open are different faults, so the
        /// refusal names the one it measured rather than covering both.
        let containerAlive: Bool
        let openFiles: [String]
        var description: String {
            let held = containerAlive
                ? "container was still alive"
                : "store still had \(openFiles.count) file(s) open (\(openFiles.joined(separator: ", ")))"
            return "the version \(version) \(held) \(waited) after the call that opened it, "
                + "so every earlier opened container of another version stays unsafe to write"
        }
    }

    /// Opens the store at `url` as `version` alone, with no plan, and hands the
    /// container to `body`. `body` must not keep it.
    @MainActor
    static func open<Result>(_ version: any VersionedSchema.Type, at url: URL,
                             release: ReleaseWait = ReleaseWait(deadline: ReleaseWait.storeReleaseDeadline),
                             _ body: (ModelContainer) throws -> Result) throws -> Result {
        weak var survivor: ModelContainer?
        let result = try autoreleasepool {
            let schema = Schema(versionedSchema: version)
            let container = try ModelContainer(
                for: schema, migrationPlan: nil,
                configurations: ModelConfiguration(schema: schema, url: url))
            survivor = container
            return try body(container)
        }
        let gone = release.until { survivor == nil && ScratchStore.descriptors(on: url).isEmpty }
        if case .stillHeld(let waited) = gone {
            throw StillOpen(version: version.versionIdentifier, waited: waited,
                            containerAlive: survivor != nil,
                            openFiles: ScratchStore.descriptors(on: url))
        }
        return result
    }

    /// Writes the store at `url` as `version` wrote it: `fill` inserts the rows,
    /// and they are saved before the container is released.
    ///
    /// AUTOSAVE IS OFF because a context made on the main thread autosaves by
    /// default, and a pending autosave would put this earlier version's work back
    /// on the main run loop after the call returned.
    @MainActor
    static func write(_ version: any VersionedSchema.Type, at url: URL,
                      _ fill: (ModelContext) throws -> Void) throws {
        try open(version, at: url) { container in
            let context = ModelContext(container)
            context.autosaveEnabled = false
            try fill(context)
            try context.save()
        }
    }
}

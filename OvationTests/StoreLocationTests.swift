import Foundation
import Testing
@testable import Ovation

/// Plan 1.1. Where Ovation's on-disk state lives, and the isolation that keeps a
/// development run away from the resident copy's data.
///
/// Every path assertion runs against an INJECTED Application Support root, so the
/// suite reads and writes nothing under the real one. The live accessors, which
/// resolve the real root, are asserted only to REFUSE.
struct StoreLocationTests {
    private let root = URL(fileURLWithPath: "/tmp/ovation-store-location-fixture", isDirectory: true)

    // MARK: the filename

    @Test("the store is Ovation.store, never SwiftData's default.store")
    func theStoreCarriesOvationsOwnFilename() {
        // Two data losses on this Mac happened at Application Support/default.store,
        // recorded in Overture's StoreLocation.swift: Downbeat opened it on
        // 2026-07-08, and on 2026-07-23 /usr/libexec/icloudmailagent migrated its
        // own schema over Overture's tables. A greenfield SwiftData app that passes
        // no explicit url lands on exactly that file. Ovation would be the third.
        #expect(StoreLocation.storeFilename == "Ovation.store")
        #expect(StoreLocation.storeFilename != "default.store")
    }

    // MARK: the two directories

    @Test("release keeps its state in an Ovation folder, never the shared Application Support root")
    func releaseClaimsItsOwnFolder() {
        let directory = StoreLocation.dataDirectory(appSupport: root, isDebugBuild: false)
        #expect(directory.path == "/tmp/ovation-store-location-fixture/Ovation")
        #expect(directory.path != root.path)
    }

    @Test("debug keeps its state in a separate Ovation-Debug folder")
    func debugClaimsADifferentFolder() {
        let debug = StoreLocation.dataDirectory(appSupport: root, isDebugBuild: true)
        let release = StoreLocation.dataDirectory(appSupport: root, isDebugBuild: false)
        #expect(debug.path == "/tmp/ovation-store-location-fixture/Ovation-Debug")
        #expect(debug.path != release.path)
    }

    @Test("each build's store hangs off its own folder")
    func theStoreHangsOffTheDataDirectory() {
        #expect(StoreLocation.storeURL(appSupport: root, isDebugBuild: false).path
                == "/tmp/ovation-store-location-fixture/Ovation/Ovation.store")
        #expect(StoreLocation.storeURL(appSupport: root, isDebugBuild: true).path
                == "/tmp/ovation-store-location-fixture/Ovation-Debug/Ovation.store")
    }

    // MARK: the queue, whose split is NOT the store's split

    @Test("the release queue is the directory Downbeat actually writes")
    func theReleaseQueueMatchesTheProducer() {
        // Downbeat's AppStoreConfiguration.bookingHandoffQueueURL writes
        // Application Support/Ovation/booking-queue. This is a cross repository
        // contract, so the value is asserted rather than left to the reader.
        #expect(StoreLocation.bookingQueueDirectory(appSupport: root, isDebugBuild: false).path
                == "/tmp/ovation-store-location-fixture/Ovation/booking-queue")
    }

    @Test("the debug queue is a sibling INSIDE Ovation, not inside Ovation-Debug")
    func theDebugQueueDoesNotFollowTheStoresSplit() {
        // The wiring detail that bites otherwise. Downbeat's Debug build writes to
        // Application Support/Ovation/booking-queue.debug, a sibling of the real
        // queue inside the RELEASE folder. Ovation's Debug store lives in
        // Ovation-Debug while its Debug queue source lives in Ovation. Anyone who
        // "tidies" either resolver to match the other silently points a Debug run
        // at a directory nothing writes, and an empty queue reads as a drained one
        // (L98).
        let queue = StoreLocation.bookingQueueDirectory(appSupport: root, isDebugBuild: true)
        let store = StoreLocation.storeURL(appSupport: root, isDebugBuild: true)

        #expect(queue.path == "/tmp/ovation-store-location-fixture/Ovation/booking-queue.debug")
        #expect(!queue.path.contains("Ovation-Debug"))
        #expect(store.path.contains("Ovation-Debug"))
        #expect(queue.deletingLastPathComponent().path != store.deletingLastPathComponent().path)
    }

    @Test("the two queues are different directories")
    func theQueuesAreSeparate() {
        #expect(StoreLocation.bookingQueueDirectory(appSupport: root, isDebugBuild: true).path
                != StoreLocation.bookingQueueDirectory(appSupport: root, isDebugBuild: false).path)
    }

    // MARK: the refusal

    @Test("a disposable launch gets no store path at all")
    func theLiveStoreIsRefusedUnderTests() {
        #expect(StoreLocation.liveStoreURL(appSupport: root,
                                           isDebugBuild: false,
                                           isDisposableLaunch: true) == nil)
    }

    @Test("a real launch gets the real store path, in the same fixture as the refusal")
    func theLiveStoreResolvesWhenTheLaunchIsReal() {
        // Without this, the refusal above is satisfied by a resolver that answers
        // nil to everything, and nothing would ever notice the app had no store
        // (L159).
        #expect(StoreLocation.liveStoreURL(appSupport: root,
                                           isDebugBuild: false,
                                           isDisposableLaunch: false)?.path
                == "/tmp/ovation-store-location-fixture/Ovation/Ovation.store")
    }

    @Test("a disposable launch gets no queue directory, and a real one does")
    func theLiveQueueIsRefusedUnderTests() {
        #expect(StoreLocation.liveBookingQueueDirectory(appSupport: root,
                                                        isDebugBuild: false,
                                                        isDisposableLaunch: true) == nil)
        #expect(StoreLocation.liveBookingQueueDirectory(appSupport: root,
                                                        isDebugBuild: false,
                                                        isDisposableLaunch: false)?.path
                == "/tmp/ovation-store-location-fixture/Ovation/booking-queue")
    }

    @Test("a caller that passes nothing is refused, because the defaults read this process")
    func theDefaultsRefuseThisSuite() {
        // The structural half of plan 1.9. A test that constructs no arguments,
        // and there will be many, must not be handed Dan's real store or the real
        // queue it would then delete from. The refusal lives in the resolver, so
        // it cannot be forgotten at a call site.
        #expect(StoreLocation.liveStoreURL() == nil)
        #expect(StoreLocation.liveBookingQueueDirectory() == nil)
    }

    // MARK: no side effects

    @Test("resolving a path creates nothing on disk")
    func resolvingDoesNotCreateDirectories() throws {
        // Overture's live dataDirectory creates its folder on first use. Ovation's
        // does not, deliberately: creation belongs to the store launch sequence
        // (plan 1.2), which identifies, checkpoints and backs up BEFORE anything
        // opens the store. A resolver that creates means merely displaying the
        // path creates it, and a directory that exists is evidence to whatever
        // reads it next.
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ovation-no-side-effects-\(UUID().uuidString)", isDirectory: true)

        _ = StoreLocation.dataDirectory(appSupport: scratch, isDebugBuild: false)
        _ = StoreLocation.storeURL(appSupport: scratch, isDebugBuild: true)
        _ = StoreLocation.bookingQueueDirectory(appSupport: scratch, isDebugBuild: false)
        _ = StoreLocation.liveStoreURL(appSupport: scratch,
                                       isDebugBuild: false,
                                       isDisposableLaunch: false)

        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }
}

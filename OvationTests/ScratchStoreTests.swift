import Foundation
import SwiftData
import Testing

/// ovation#632. What `ScratchStore` promises, each seen to hold.
struct ScratchStoreTests {

    @Model
    final class Scrap {
        var note: String = ""
        init(note: String) { self.note = note }
    }

    /// The deliberate leaks below are never released, so they are given a short
    /// deadline rather than the default, which is sized for real late releases.
    static var shortWait: ReleaseWait { ReleaseWait(deadline: .milliseconds(200)) }

    private static func write(_ url: URL) throws -> ModelContainer {
        let schema = Schema([Scrap.self])
        let container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        context.insert(Scrap(note: "a row"))
        try context.save()
        return container
    }

    @Test("a store released inside the call is deleted with nothing recorded")
    func areleasedStoreIsDeleted() throws {
        var seen: URL?
        try ScratchStore.with("scratch-released") { url in
            seen = url
            _ = try Self.write(url)
        }
        let directory = try #require(seen).deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// THE CASE THE REVIEW ASKED FOR. A sibling's store held open for the whole
    /// call, as a sibling running at the same moment would hold it, must not be
    /// charged to this call. Before the check was scoped to its own directory, a
    /// scan of every store in the process would have failed here.
    @Test("a sibling's store held open across the call is not charged to it")
    func asiblingsStoreIsNotSeen() throws {
        let sibling = URL.temporaryDirectory
            .appending(path: "ovation-scratch-sibling-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        let held = try Self.write(sibling.appending(path: "Ovation.store"))
        #expect(!ScratchStore.descriptors(inside: sibling).isEmpty,
                "the sibling really is open, so its absence below means something")

        try ScratchStore.with("scratch-beside-a-sibling") { url in
            _ = try Self.write(url)
        }
        withExtendedLifetime(held) {}
    }

    @Test("a store still open when the call returns is recorded against it")
    func aleakedStoreIsRecorded() throws {
        var kept: ModelContainer?
        var seen: URL?
        try withKnownIssue("the case kept its container, so the store is still open") {
            try ScratchStore.with("scratch-leaked", release: Self.shortWait) { url in
                seen = url
                kept = try Self.write(url)
            }
        } matching: { issue in
            String(describing: issue).contains("still open after the case released it")
        }
        #expect(kept != nil, "the fixture really did keep it, so the issue is about that")
        let directory = try #require(seen).deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: directory.path),
                "and the directory was left, not deleted from under the open store")
        kept = nil
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("an awaiting case gets the same check")
    func theAsyncFormChecksToo() async throws {
        var kept: ModelContainer?
        var seen: URL?
        try await withKnownIssue("the case kept its container") {
            try await ScratchStore.with("scratch-leaked-async", release: Self.shortWait) { url in
                await Task.yield()
                seen = url
                kept = try Self.write(url)
            }
        } matching: { issue in
            String(describing: issue).contains("still open after the case released it")
        }
        kept = nil
        if let seen { try? FileManager.default.removeItem(at: seen.deletingLastPathComponent()) }
    }

    /// AN ASYNC CASE NEVER BLOCKS A THREAD WHILE IT WAITS (L241). The async
    /// overload is used by 16 cases, the migration ones among them, which saw
    /// stores close 2s late under load; a blocking sleep there parks one of the
    /// cooperative pool's few threads (three on CI) and stalls every other async
    /// case beside it. Here a real file is left open by the body and closed by
    /// the wait's first suspension, so the wait has to pause once, and the
    /// blocking sleep records itself if it is ever reached.
    @Test("an async case waits for a late close by suspending, never by blocking a thread")
    func anAsyncWaitSuspends() async throws {
        let clock = ReleaseWaitTests.FakeClock()
        var blocked = 0
        var suspended = 0
        var held: FileHandle?
        let wait = ReleaseWait(
            deadline: .seconds(5), interval: .milliseconds(10),
            elapsed: { clock.elapsed },
            sleep: { blocked += 1; clock.elapsed += $0 },
            suspend: { suspended += 1; try? held?.close(); held = nil; clock.elapsed += $0 })
        try await ScratchStore.with("async-wait", release: wait) { url in
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            held = try FileHandle(forReadingFrom: url)
            await Task.yield()
        }
        #expect(blocked == 0, "the async case blocked a thread to wait")
        #expect(suspended == 1, "it paused once, and the close it was waiting for happened")
    }
}

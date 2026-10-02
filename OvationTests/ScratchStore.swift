import Foundation
import Testing

/// ovation#632. A store file in a directory of its own, for one case, deleted only
/// once nothing holds it open.
///
/// WHY THE DIRECTORY IS OWNED HERE RATHER THAN BY A `defer`. A case that removes
/// its directory in a `defer` removes it while its own container is still in
/// scope, and SQLite reports that as "vnode unlinked while in use". It did so on
/// every run for fourteen cases in two suites. So the case's work runs inside
/// `body`, whose containers are gone when it returns, and only then is the
/// directory checked and deleted.
///
/// WHY THE CHECK LOOKS ONLY INSIDE ITS OWN DIRECTORY. Swift Testing may run
/// sibling cases at the same time, and a sibling tearing down its own store is not
/// this case's fault. Every directory here carries a fresh UUID, so a descriptor
/// inside it can only belong to what `body` opened. `ScratchStoreTests` holds a
/// sibling's store open across a call and shows the call does not see it.
enum ScratchStore {
    /// Runs `body` with a store URL `file` inside a new directory, then records an
    /// issue if anything still holds a file in that directory, then deletes it.
    static func with<Result>(_ label: String, file: String = "Ovation.store",
                             release: ReleaseWait = ReleaseWait(deadline: ReleaseWait.storeReleaseDeadline),
                             _ body: (URL) throws -> Result) throws -> Result {
        let directory = try make(label)
        defer { finish(directory, release) }
        return try body(directory.appending(path: file))
    }

    /// The same, for a case whose work awaits. It waits for the release by
    /// SUSPENDING, never by blocking a thread of the cooperative pool (L241), so
    /// the finish runs on both exits by hand, since a `defer` cannot await.
    static func with<Result>(_ label: String, file: String = "Ovation.store",
                             release: ReleaseWait = ReleaseWait(deadline: ReleaseWait.storeReleaseDeadline),
                             _ body: (URL) async throws -> Result) async throws -> Result {
        let directory = try make(label)
        let result: Result
        do {
            result = try await body(directory.appending(path: file))
        } catch {
            await finishSuspending(directory, release)
            throw error
        }
        await finishSuspending(directory, release)
        return result
    }

    /// Every descriptor this process holds on a file inside `directory`.
    static func descriptors(inside directory: URL) -> [String] {
        let prefix = directory.standardizedFileURL.path + "/"
        var held: [String] = []
        for descriptor in 0..<Int32(getdtablesize()) {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &path) == 0 else { continue }
            let text = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                              as: UTF8.self)
            // The kernel answers with the resolved path, /private/var rather than
            // /var, so both spellings of the directory are compared.
            if text.hasPrefix(prefix) || text.hasPrefix("/private" + prefix) { held.append(text) }
        }
        return held
    }

    /// Every descriptor this process holds on the store at `store` itself, its
    /// write ahead log or its shared memory file, and on nothing else beside it.
    static func descriptors(on store: URL) -> [String] {
        let name = store.lastPathComponent
        return descriptors(inside: store.deletingLastPathComponent()).filter {
            let file = ($0 as NSString).lastPathComponent
            return file == name || file == name + "-wal" || file == name + "-shm"
        }
    }

    private static func make(_ label: String) throws -> URL {
        let directory = URL.temporaryDirectory
            .appending(path: "ovation-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A directory still held is recorded and LEFT, because deleting it would be
    /// the very fault being reported, and SQLite would say so all over again.
    /// The files named are the ones the wait's last look saw, never a second
    /// reading taken after it gave up, which could list others or none (L11).
    private static func finish(_ directory: URL, _ release: ReleaseWait) {
        let (gone, held) = release.until(looking: { descriptors(inside: directory) }, released: { $0.isEmpty })
        settle(directory, gone, held)
    }

    /// The async case's finish, the same wait made by suspending (L241).
    private static func finishSuspending(_ directory: URL, _ release: ReleaseWait) async {
        let (gone, held) = await release.suspendingUntil(looking: { descriptors(inside: directory) },
                                                          released: { $0.isEmpty })
        settle(directory, gone, held)
    }

    /// One verdict for both: record and leave a directory still held, delete one
    /// that was released.
    private static func settle(_ directory: URL, _ gone: ReleaseWait.Outcome, _ held: [String]) {
        if case .stillHeld(let waited) = gone {
            Issue.record("the store is still open after the case released it, and was still open \(waited) later, so \(directory.path) is left in place: \(held)")
            return
        }
        try? FileManager.default.removeItem(at: directory)
    }
}

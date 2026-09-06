import CryptoKit
import Foundation
import Testing
@testable import Ovation

/// Plan 1.7, ovation#56. Receipts and invoice PDFs are files on disk addressed by
/// their content hash, never blobs inside the database.
struct DocumentStoreTests {

    // MARK: writing

    @Test("storing bytes puts them on disk and hands back what identifies them")
    func storingWritesTheFile() throws {
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let bytes = Data("a receipt".utf8)

        let reference = try store.store(bytes, extension: "pdf")

        #expect(reference.sha256 == sha256(of: bytes))
        #expect(reference.byteCount == bytes.count)
        #expect(reference.relativePath.hasSuffix(".pdf"))
        let url = try #require(store.url(for: reference))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("the same bytes stored twice are one file, not two")
    func contentAddressingDeduplicates() throws {
        // A re-import, a resend, or the same receipt arriving twice must not
        // leave two copies for the backup to carry and the audit to disagree
        // about. The path IS the hash, so identical bytes cannot land anywhere
        // else.
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let bytes = Data("a receipt".utf8)

        let first = try store.store(bytes, extension: "pdf")
        let second = try store.store(bytes, extension: "pdf")

        #expect(first == second)
        #expect(store.allFiles().count == 1)
    }

    @Test("different bytes land somewhere different, even under the same extension")
    func differentContentIsADifferentDocument() throws {
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)

        let first = try store.store(Data("version one".utf8), extension: "pdf")
        let second = try store.store(Data("version two".utf8), extension: "pdf")

        #expect(first.relativePath != second.relativePath)
        #expect(store.allFiles().count == 2)
    }

    // MARK: verifying, one outcome per way it can be wrong

    @Test("a document that is there and unchanged verifies")
    func aGoodDocumentVerifies() throws {
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let reference = try store.store(Data("a receipt".utf8), extension: "pdf")

        #expect(store.verify(reference) == .verified)
    }

    @Test("a document whose file is gone is ABSENT, which is not the same as failing to read it")
    func anAbsentDocumentSaysSo() throws {
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let reference = try store.store(Data("a receipt".utf8), extension: "pdf")
        try FileManager.default.removeItem(at: #require(store.url(for: reference)))

        #expect(store.verify(reference) == .absent)
    }

    @Test("a document that cannot be read is UNREADABLE, which is not the same as being gone")
    func anUnreadableDocumentSaysSo() throws {
        // Permissions, or a bad disk. The remedy is different from a file that
        // was moved, so the verdict is different (L11).
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let reference = try store.store(Data("a receipt".utf8), extension: "pdf")
        let url = try #require(store.url(for: reference))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        #expect(store.verify(reference) == .unreadable)
    }

    @Test("a document whose bytes changed is a MISMATCH, even when the length is identical")
    func changedBytesAreAMismatch() throws {
        // THE REPLACEMENT IS THE SAME LENGTH ON PURPOSE. The first version of
        // this test swapped in longer text, and planting "verify by byte count
        // instead of hash" left it green: the test could not tell the check it
        // was written for from a check that reads nothing. The hash is the point,
        // not decoration.
        let original = Data("a receipt".utf8)
        let tampered = Data("b receipt".utf8)
        #expect(original.count == tampered.count)

        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let reference = try store.store(original, extension: "pdf")
        try tampered.write(to: #require(store.url(for: reference)))

        #expect(store.verify(reference) == .mismatch)
    }

    @Test("a reference that records NO hash is its own outcome, never a pass")
    func aReferenceWithNoHashIsRefused() throws {
        // The fourth outcome scripts/check-custody-files.sh surfaced when it was
        // built: a record naming a file but storing no hash for it cannot be
        // absent, unreadable or mismatched, and treating it as verified means the
        // file it names is the one nobody is checking.
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let real = try store.store(Data("a receipt".utf8), extension: "pdf")
        let hashless = DocumentReference(relativePath: real.relativePath, sha256: "",
                                         byteCount: real.byteCount)

        #expect(store.verify(hashless) == .noHashRecorded)
    }

    @Test("a stored path that climbs out of the documents folder is refused, never followed")
    func anEscapingPathIsRefused() throws {
        // A path read back from the store is input, not a fact (L50). These are
        // refused as their own verdict, because the record is wrong rather than
        // the file being missing.
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)

        for path in ["../outside.pdf", "ab/../../outside.pdf", "/etc/hosts", ""] {
            let reference = DocumentReference(relativePath: path, sha256: "abc", byteCount: 1)
            #expect(store.url(for: reference) == nil)
            #expect(store.verify(reference) == .pathRefused)
        }
    }

    @Test("and an ordinary path is resolved, in the same fixture as the refusals")
    func anOrdinaryPathResolves() throws {
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let reference = try store.store(Data("a receipt".utf8), extension: "pdf")

        let url = try #require(store.url(for: reference))
        #expect(url.path.hasPrefix(scratch.root.path))
    }

    // MARK: what the backup has to be able to walk

    @Test("a file on disk that no record names is reported, so a backup can tell")
    func orphansAreFindable() throws {
        // ovation#57 enumerates every REFERENCED document. The other direction
        // matters too: bytes nothing points at are either a lost reference or
        // rubbish, and both are worth knowing rather than being carried silently
        // in every backup forever.
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let kept = try store.store(Data("a receipt".utf8), extension: "pdf")
        let orphaned = try store.store(Data("nobody points at this".utf8), extension: "pdf")

        let unreferenced = store.unreferencedFiles(given: [kept])

        #expect(unreferenced == [orphaned.relativePath])
    }

    @Test("with every file referenced, nothing is reported as an orphan")
    func noOrphansWhenEverythingIsReferenced() throws {
        let scratch = try Scratch()
        let store = DocumentStore(root: scratch.root)
        let one = try store.store(Data("one".utf8), extension: "pdf")
        let two = try store.store(Data("two".utf8), extension: "pdf")

        #expect(store.unreferencedFiles(given: [one, two]).isEmpty)
    }

    // MARK: where it lives

    @Test("documents sit under the data directory, and a disposable launch gets no path at all")
    func theLiveRootIsRefusedUnderTests() {
        let appSupport = URL(fileURLWithPath: "/tmp/ovation-documents-fixture", isDirectory: true)

        #expect(DocumentStore.liveRoot(appSupport: appSupport, isDebugBuild: false,
                                       isDisposableLaunch: false)?.path
                == "/tmp/ovation-documents-fixture/Ovation/documents")
        #expect(DocumentStore.liveRoot(appSupport: appSupport, isDebugBuild: false,
                                       isDisposableLaunch: true) == nil)
        #expect(DocumentStore.liveRoot() == nil)
    }

    // MARK: fixtures

    private func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class Scratch {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ovation-documents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

// Plan 1.7, ovation#56. Receipts and invoice PDFs are FILES, addressed by their
// content hash, never blobs inside the database.
//
// WHY NOT `@Attribute(.externalStorage)`, and the reason is not performance.
// PRD 42b measured it: the convenient option writes the bytes into a HIDDEN
// folder beside the database rather than inside it, and a backup that copies
// only the database then verifies success by checking it opens and holds the
// right tables. Cloning that gives seven years of backups containing zero
// receipts and zero PDFs, with every verification passing, which is a check
// reporting success having found nothing to check (L98).
//
// THE PATH IS THE HASH. Identical bytes cannot land anywhere else, so a
// re-import, a resend or the same receipt arriving twice is one file rather than
// two copies for the backup to carry and the audit to disagree about. An edited
// invoice is different bytes and therefore a different document, which is what
// plan 5.11 needs when it keeps the PDF of every version sent.
//
// THE COST, STATED. A person browsing the folder in Finder sees hashes rather
// than "invoice-1123.pdf". Documents are reached through the record that names
// them, not by reading the directory, and the alternative (a readable name plus
// a hash) reintroduces two copies of the same bytes under two names and a
// collision rule for the second receipt called "receipt.pdf".
//
// EVERY OUTCOME IS ITS OWN VERDICT, following the precedent already working in
// this repository: `scripts/check-custody-files.sh` verifies the custody files
// exactly this way, and building it surfaced the fourth one, a record naming a
// file but storing no hash for it (L11).
import CryptoKit
import Foundation

/// Where a document is and what it must contain. One value, because a path and
/// the hash that proves it are one fact and a call site holding them separately
/// can pair them wrongly (L544).
struct DocumentReference: Equatable, Hashable, Codable, Sendable {
    /// Relative to the documents root, so moving the folder does not invalidate
    /// every record (L8).
    let relativePath: String
    let sha256: String
    let byteCount: Int
}

/// What verifying a document found. Five outcomes, kept apart because they need
/// different actions and none may be reported as another.
enum DocumentVerdict: Equatable, Sendable {
    /// It is there and its bytes are what was recorded.
    case verified
    /// The file the record names is not on disk: moved, or never written.
    case absent
    /// It is there and cannot be read: permissions, or a bad disk.
    case unreadable
    /// It reads, and its contents are NOT what was recorded.
    case mismatch
    /// The record names a file and stores no hash for it. It cannot be absent,
    /// unreadable or mismatched, and treating it as verified means the file it
    /// names is the one nobody is checking.
    case noHashRecorded
    /// The stored path does not name a place inside the documents folder. The
    /// RECORD is wrong, which is a different fact from the file being missing.
    case pathRefused
}

struct DocumentStore {
    let root: URL
    private let fileManager: FileManager

    init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    /// Where a real launch keeps them, or nil when this launch may not touch
    /// anything real. Same refusal, in the same place, as every other path
    /// (ovation#51, plan 1.9).
    static func liveRoot(
        appSupport: URL = StoreLocation.appSupport,
        isDebugBuild: Bool = StoreLocation.isDebugBuild,
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch()
    ) -> URL? {
        guard !isDisposableLaunch else { return nil }
        return StoreLocation.dataDirectory(appSupport: appSupport, isDebugBuild: isDebugBuild)
            .appendingPathComponent("documents", isDirectory: true)
    }

    // MARK: writing

    /// Write these bytes and hand back what identifies them.
    ///
    /// Idempotent by construction: the path is derived from the content, so
    /// storing the same bytes again finds them already there. It does NOT
    /// overwrite in that case, because the bytes are by definition identical and
    /// rewriting a file somebody may be reading buys nothing (L5).
    func store(_ data: Data, extension fileExtension: String) throws -> DocumentReference {
        let digest = Self.hash(of: data)
        let reference = DocumentReference(relativePath: Self.path(for: digest,
                                                                 extension: fileExtension),
                                          sha256: digest,
                                          byteCount: data.count)

        guard let url = url(for: reference) else {
            throw DocumentStoreError.pathRefused(reference.relativePath)
        }

        if fileManager.fileExists(atPath: url.path) { return reference }

        let directory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Atomic: a half written document must never be readable as a whole
            // one, because its hash would simply not match and the record would
            // read as corrupt rather than as interrupted (L5).
            try data.write(to: url, options: .atomic)
        } catch {
            throw DocumentStoreError.couldNotWrite(reference.relativePath,
                                                   error.localizedDescription)
        }
        return reference
    }

    // MARK: reading

    /// The absolute location of a reference, or nil when the stored path does not
    /// name a place inside the documents folder.
    ///
    /// A path read back from the store is INPUT (L50). An absolute path, an empty
    /// one, or one climbing out with `..` is refused rather than resolved, so a
    /// wrong or hostile record cannot reach a file elsewhere on the disk.
    func url(for reference: DocumentReference) -> URL? {
        let path = reference.relativePath
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }

        let resolved = root.appendingPathComponent(path).standardizedFileURL
        let base = root.standardizedFileURL
        guard resolved.path.hasPrefix(base.path + "/") else { return nil }
        return resolved
    }

    /// Check a document against what was recorded, at READ time rather than only
    /// when it was written.
    func verify(_ reference: DocumentReference) -> DocumentVerdict {
        guard let url = url(for: reference) else { return .pathRefused }
        guard !reference.sha256.isEmpty else { return .noHashRecorded }
        guard fileManager.fileExists(atPath: url.path) else { return .absent }

        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        return Self.hash(of: data) == reference.sha256 ? .verified : .mismatch
    }

    // MARK: what the backup has to be able to walk

    /// Every file under the documents root, as relative paths, sorted.
    ///
    /// IT THROWS RATHER THAN ANSWERING EMPTY when it cannot look. A missing or
    /// unwalkable documents folder and a folder holding no documents are
    /// different facts, and returning an empty list for both makes the first
    /// indistinguishable from the second (L215). It matters most at the one call
    /// site that has consequences: `unreferencedFiles` would report no orphans,
    /// and ovation#57's backup would carry that as a clean bill of health.
    func allFiles() throws -> [String] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DocumentStoreError.rootUnavailable(root.path)
        }
        guard let walker = fileManager.enumerator(at: root,
                                                  includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles]) else {
            throw DocumentStoreError.rootUnavailable(root.path)
        }
        var found: [String] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            let base = root.standardizedFileURL.path + "/"
            guard path.hasPrefix(base) else { continue }
            found.append(String(path.dropFirst(base.count)))
        }
        return found.sorted()
    }

    /// Files on disk that none of these references names.
    ///
    /// ovation#57 enumerates every REFERENCED document. This is the other
    /// direction: bytes nothing points at are either a lost reference or rubbish,
    /// and both are worth knowing rather than being carried silently in every
    /// backup forever.
    func unreferencedFiles(given references: [DocumentReference]) throws -> [String] {
        let referenced = Set(references.map(\.relativePath))
        return try allFiles().filter { !referenced.contains($0) }
    }

    // MARK: the addressing rule, in one place

    static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Sharded by the first two characters of the hash, so a folder holding seven
    /// years of receipts is not one directory with thousands of entries in it.
    static func path(for digest: String, extension fileExtension: String) -> String {
        let shard = String(digest.prefix(2))
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        return "\(shard)/\(digest)\(suffix)"
    }
}

enum DocumentStoreError: Error, Equatable {
    /// The documents folder is not there, or is not a folder. Never reported as
    /// "no documents".
    case rootUnavailable(String)
    case pathRefused(String)
    case couldNotWrite(String, String)
}

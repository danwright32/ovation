// ovation#64. One line per thing that happened, appended, never rewritten.
//
// WHY IT EXISTS AS ITS OWN TYPE. `FileProblemsJournal` (ovation#59) had all of
// this inside it, and the export run record (ovation#64) needs exactly the same
// behaviour for the same reason. A second copy would be two implementations of
// the fresh line repair below, and the one that drifted would be the one nobody
// was looking at (L613, L370). So the mechanics live here and each caller keeps
// its own record type, its own error vocabulary and its own decisions about what
// a damaged line means.
//
// APPEND ONLY IS THE POINT. A file holding the CURRENT state is a read, modify,
// write cycle, and one whose read answers empty when it fails erases the whole
// record at the exact moment it is worth having (L105).
//
// THE FRESH LINE REPAIR IS A FIX, NOT TIDINESS. A crash part way through an
// append leaves a fragment with no newline after it, and writing straight onto
// that FUSES the fragment and the next record into one line, so the corruption
// costs a good record as well as the lost one. Found in ovation#59 by the test
// that stages exactly that, which expected to lose one line and lost two.
import Foundation

enum AppendOnlyLineFileError: Error, Equatable {
    case couldNotWrite(String)
    case couldNotRead(String)
}

struct AppendOnlyLineFile {
    let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    var exists: Bool { fileManager.fileExists(atPath: url.path) }

    /// Appends one line, making the directory if it is not there.
    ///
    /// The line must not contain a newline of its own: it is one record, and a
    /// caller that puts a newline in it has written two records that nothing can
    /// tell apart afterwards. JSON encoders do not, which is why every caller
    /// here encodes first.
    func append(_ line: String) throws {
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw AppendOnlyLineFileError.couldNotWrite(
                    "the directory \(directory.path) could not be made: "
                        + "\(error.localizedDescription)")
            }
        }

        guard let data = (line + "\n").data(using: .utf8) else {
            throw AppendOnlyLineFileError.couldNotWrite("the record did not encode as bytes")
        }

        guard fileManager.fileExists(atPath: url.path) else {
            do {
                try data.write(to: url, options: .atomic)
                return
            } catch {
                throw AppendOnlyLineFileError.couldNotWrite(
                    "\(url.path): \(error.localizedDescription)")
            }
        }

        do {
            // Opened for UPDATE rather than writing: the fresh line check has to
            // READ the last byte, and a write only handle refuses that.
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if try !endsWithNewline(handle) {
                try handle.write(contentsOf: Data("\n".utf8))
            }
            try handle.write(contentsOf: data)
        } catch {
            throw AppendOnlyLineFileError.couldNotWrite(
                "\(url.path): \(error.localizedDescription)")
        }
    }

    /// Every non empty line, in the order they were written. A file that is not
    /// there is EMPTY rather than an error: nothing has been appended yet, which
    /// is a state rather than a fault. A file that is there and cannot be read
    /// throws, because that is a different fact (L11).
    func lines() throws -> [String] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppendOnlyLineFileError.couldNotRead(
                "\(url.path): \(error.localizedDescription)")
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Whether the file already ends in a newline, so an append starts cleanly.
    /// An empty file counts as ending in one: there is nothing to fuse to.
    private func endsWithNewline(_ handle: FileHandle) throws -> Bool {
        let end = try handle.offset()
        guard end > 0 else { return true }
        try handle.seek(toOffset: end - 1)
        let last = try handle.read(upToCount: 1)
        try handle.seekToEnd()
        return last == Data("\n".utf8)
    }
}

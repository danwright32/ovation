// Plan 1.13, ovation#59. How a problem survives a relaunch.
//
// APPEND ONLY, one record per thing that happened, replayed to rebuild the
// store. A file holding the CURRENT state would be a read, modify, write cycle,
// and one whose read answers empty when it fails erases the whole record at the
// exact moment it is worth having (L105).
//
// It is NOT the SwiftData store. Plan 1.8 enumerates what a backup contains and
// lists the Problems store separately from the store and its write ahead log,
// so it is its own file by design, and it exists before the domain model does.
import Foundation

enum ProblemJournalAction: String, Codable, Sendable {
    case raised
    case acknowledged
    case resolved
}

struct ProblemJournalRecord: Codable, Sendable, Equatable {
    let action: ProblemJournalAction
    let problem: Problem
}

enum ProblemsJournalError: Error, Equatable {
    case couldNotWrite(String)
    case couldNotRead(String)
}

protocol ProblemsJournal: AnyObject {
    /// Whether what is written here outlives the process. False is not a
    /// failure, it is a fact a caller may need to say out loud (L319).
    var isDurable: Bool { get }

    /// How many records the last `load` could not read. A corrupt line loses one
    /// record, never the whole journal, and losing one silently would make the
    /// journal's own damage the thing nobody hears about (L215).
    var skippedOnLastLoad: Int { get }

    func append(_ record: ProblemJournalRecord) throws
    func load() throws -> [ProblemJournalRecord]
}

/// The journal a disposable launch gets, and the one tests use. Writes nowhere.
final class InMemoryProblemsJournal: ProblemsJournal {
    let isDurable = false
    let skippedOnLastLoad = 0
    private(set) var appended: [ProblemJournalRecord] = []

    init() {}

    func append(_ record: ProblemJournalRecord) throws { appended.append(record) }
    func load() throws -> [ProblemJournalRecord] { appended }
}


/// The journal a real launch gets: one JSON object per line, appended.
///
/// APPEND ONLY. A file holding the CURRENT state would be a read, modify, write
/// cycle, and one whose read answers empty when it fails erases the whole record
/// at the exact moment it is worth having (L105).
///
/// A LINE THAT DOES NOT DECODE COSTS THAT LINE, never the file. It is counted in
/// `skippedOnLastLoad` and the store raises a problem about it, because a
/// journal quietly returning fewer records than it holds is the same shape as
/// one returning none (L215).
final class FileProblemsJournal: ProblemsJournal {
    let isDurable = true
    private(set) var skippedOnLastLoad = 0

    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    /// Where a real launch keeps it, or nil when this launch may not touch
    /// anything real. Same refusal, in the same place, as every other path
    /// (ovation#51, plan 1.9).
    static func liveURL(
        appSupport: URL = StoreLocation.appSupport,
        isDebugBuild: Bool = StoreLocation.isDebugBuild,
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch()
    ) -> URL? {
        guard !isDisposableLaunch else { return nil }
        return StoreLocation.dataDirectory(appSupport: appSupport, isDebugBuild: isDebugBuild)
            .appendingPathComponent("problems.jsonl")
    }

    func append(_ record: ProblemJournalRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var line = String(data: try encoder.encode(record), encoding: .utf8) else {
            throw ProblemsJournalError.couldNotWrite("the record did not encode as text")
        }
        line += "\n"

        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw ProblemsJournalError.couldNotWrite(
                    "the directory \(directory.path) could not be made: \(error.localizedDescription)")
            }
        }

        guard let data = line.data(using: .utf8) else {
            throw ProblemsJournalError.couldNotWrite("the record did not encode as bytes")
        }

        if fileManager.fileExists(atPath: url.path) {
            do {
                // Opened for UPDATE rather than writing: the fresh line check
                // below has to READ the last byte, and a write only handle
                // refuses that.
                let handle = try FileHandle(forUpdating: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                // START ON A FRESH LINE, and this is a fix rather than tidiness.
                // A crash part way through an append leaves a fragment with no
                // newline after it, and writing straight onto that FUSES the
                // fragment and the next record into one line, so the corruption
                // costs a good record as well as the lost one. Found by the test
                // that stages exactly that, which expected to lose one line and
                // lost two.
                if try !endsWithNewline(handle) {
                    try handle.write(contentsOf: Data("\n".utf8))
                }
                try handle.write(contentsOf: data)
            } catch {
                throw ProblemsJournalError.couldNotWrite(
                    "\(url.path): \(error.localizedDescription)")
            }
        } else {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ProblemsJournalError.couldNotWrite(
                    "\(url.path): \(error.localizedDescription)")
            }
        }
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

    func load() throws -> [ProblemJournalRecord] {
        skippedOnLastLoad = 0
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ProblemsJournalError.couldNotRead("\(url.path): \(error.localizedDescription)")
        }

        let decoder = JSONDecoder()
        var records: [ProblemJournalRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(ProblemJournalRecord.self, from: data) else {
                skippedOnLastLoad += 1
                continue
            }
            records.append(record)
        }
        return records
    }
}

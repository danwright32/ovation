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

    private let file: AppendOnlyLineFile

    init(url: URL, fileManager: FileManager = .default) {
        self.file = AppendOnlyLineFile(url: url, fileManager: fileManager)
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
        guard let line = String(data: try encoder.encode(record), encoding: .utf8) else {
            throw ProblemsJournalError.couldNotWrite("the record did not encode as text")
        }
        do {
            try file.append(line)
        } catch let error as AppendOnlyLineFileError {
            // The file mechanics are shared (ovation#64); the vocabulary a caller
            // sees is not. Every existing caller catches `ProblemsJournalError`,
            // and a shared error type leaking through here would make the
            // extraction a change to what they can catch (L337).
            switch error {
            case .couldNotWrite(let detail), .couldNotRead(let detail):
                throw ProblemsJournalError.couldNotWrite(detail)
            }
        }
    }

    func load() throws -> [ProblemJournalRecord] {
        skippedOnLastLoad = 0
        let lines: [String]
        do {
            lines = try file.lines()
        } catch let error as AppendOnlyLineFileError {
            switch error {
            case .couldNotRead(let detail), .couldNotWrite(let detail):
                throw ProblemsJournalError.couldNotRead(detail)
            }
        }

        let decoder = JSONDecoder()
        var records: [ProblemJournalRecord] = []
        for line in lines {
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

// ovation#461, PRD 1. Reading the booking handoff queue, and never writing to it.
//
// DOWNBEAT WRITES ONE `<booking-uuid>.json` PER COMMITTED BOOKING into a
// directory its own retention never sweeps. This reads them. It is the shortcut
// ovation#32's drain replaces, and it exists because ovation#42 had nothing to
// send: nothing in Ovation created an invoice outside the Debug sample world.
//
// IT IS READ ONLY, AND THE PROOF IS NOT IN THIS HEADER. The one instrument that
// watches the disk, `scripts/check-live-data-untouched.sh`, deliberately does
// NOT watch `booking-queue`, because Downbeat writes it and a before and after
// comparison would accuse the suite of another application's change. So that
// guard is blind to exactly this directory, and reading this file for the
// absence of a `removeItem` is the count of call sites that mistakes a shared
// helper for safety (L201, L212, L375). `BookingQueueTests` takes a census of a
// throwaway copy, reads it, and asserts the file set, the bytes and every
// modification time are unchanged.
//
// SO THE DIRECTORY IS A PARAMETER, never resolved in here. The live location
// comes from `StoreLocation.bookingQueueDirectory` at the one call site in the
// app, which is also where the Debug and Release split is stated.
//
// AN EMPTY ANSWER IS NOT A GOOD ANSWER. Never created, created and empty, and
// present and read are three different states because they need three different
// actions: the first means Downbeat has never queued anything from this build,
// the second that it has and something already drained it. Reporting a queue
// with nothing in it the same way as one that was read and handled is the
// failure `scripts/check-booking-queue.sh` was written against (L98, L215).
import Foundation

/// What one file in the queue came to.
struct QueuedBooking: Equatable, Sendable {
    /// The file's own name, which is what a refusal or a report must name: a
    /// booking id means nothing to look for on disk.
    let file: String
    let record: HandoffRecord
}

/// A file that is a record and could not be read.
struct UnreadableQueueFile: Equatable, Sendable {
    let file: String
    let refusal: HandoffRefusal
}

/// What reading the whole directory came to.
struct BookingQueueReading: Equatable, Sendable {

    /// Which of the three answers this is. It is kept beside the records rather
    /// than inferred from them being empty, because empty has two causes and
    /// they need opposite actions.
    enum State: Equatable, Sendable {
        /// Downbeat has never queued anything from this build.
        case directoryIsNotThere
        /// It has, and there is nothing waiting now.
        case nothingQueued
        /// There were records. Some may be in `unreadable`.
        case read
    }

    let state: State
    let records: [QueuedBooking]
    let unreadable: [UnreadableQueueFile]
}

enum BookingQueue {

    /// Read every record in the directory, in a declared order.
    ///
    /// ONLY `.json`, because a folder on a Mac collects `.DS_Store` and an icon
    /// file whether anybody wants them or not, and a stray file counted as
    /// unreadable would raise a problem on every run with nothing wrong.
    ///
    /// SORTED BY FILE NAME, because a directory listing carries no order and a
    /// report that named the same files in a different order each run would read
    /// as the queue changing (L343).
    static func read(directory: URL) -> BookingQueueReading {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return BookingQueueReading(state: .directoryIsNotThere, records: [], unreadable: [])
        }

        let names: [String]
        do {
            names = try manager.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
                .sorted()
        } catch {
            // A directory that is there and cannot be listed is not an empty
            // one, and saying "nothing queued" would be a claim this never
            // measured (L11).
            return BookingQueueReading(
                state: .read, records: [],
                unreadable: [UnreadableQueueFile(
                    file: directory.lastPathComponent,
                    refusal: .notReadable(detail: "the directory could not be listed"))])
        }

        guard !names.isEmpty else {
            return BookingQueueReading(state: .nothingQueued, records: [], unreadable: [])
        }

        var records: [QueuedBooking] = []
        var unreadable: [UnreadableQueueFile] = []
        for name in names {
            guard let data = try? Data(contentsOf: directory.appending(path: name)) else {
                unreadable.append(UnreadableQueueFile(
                    file: name, refusal: .notReadable(detail: "the file could not be opened")))
                continue
            }
            switch HandoffRecord.read(data) {
            case .read(let record):
                records.append(QueuedBooking(file: name, record: record))
            case .refused(let refusal):
                // CARRIED, NOT DROPPED, and it does not stop the readable ones
                // beside it. A record Ovation cannot read is a booking that may
                // never be invoiced, which is the one outcome that means a shoot
                // went unbilled (PRD 1).
                unreadable.append(UnreadableQueueFile(file: name, refusal: refusal))
            }
        }
        return BookingQueueReading(state: .read, records: records, unreadable: unreadable)
    }
}

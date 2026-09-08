// ovation#116. The schema version that last opened the store, written beside it
// so a raw read can answer the question before anything opens anything.
//
// WHY A FILE BESIDE THE STORE AND NOT A ROW INSIDE IT. Measured in
// `SchemaMigrationTests`: the store file records Core Data's model version
// HASHES in Z_METADATA and not the semantic version Ovation declares. A hash
// answers "different", never "newer", and the direction is the whole question.
// The version could be a row in the store instead, and that is worse for one
// decisive reason: reading a row means OPENING the store, and opening is the act
// that does the damage.
//
// WHAT THE DAMAGE IS, measured on macOS 26.5 and Swift 6.3.3. An older build
// handed a store written by a newer one does NOT refuse and does NOT merely
// ignore the column it does not know about. It opens the store, migrates it
// BACKWARDS, and the field only the newer build knew about is gone. Reopening
// under the newer version returns nil. The backup was taken before any of it.
//
// IT IS WRITTEN BY WHATEVER ESTABLISHES THE VERSION, which is the launch
// sequence after a successful open, never by a screen that happens to notice
// (L319). A marker written anywhere else is one that can be absent exactly when
// the store was opened by something that did not know to write it.
//
// AN ABSENT MARKER IS ITS OWN ANSWER AND NOT A REFUSAL, and the reason is
// measured rather than assumed. A marker cannot describe a store written before
// the marker existed, which is the population every such detector is blind to
// (L223). Measured 2026-09-08: no `Ovation.store` exists under Application
// Support on either the Debug or the Release path, so that population is EMPTY
// and stays empty, because from here every store gets a marker at its first
// successful open. If a store ever turns up without one, it was opened by a
// build older than this file, and the honest answer about it is "unknown"
// rather than "same version".
import Foundation
import SwiftData

struct StoreVersionMarker: Equatable, Sendable {

    /// What the marker says, or why it says nothing. Three answers, because they
    /// lead to different actions and none may be reported as another (L11).
    enum Reading: Equatable, Sendable {
        /// A marker is there and it parses.
        case version(Schema.Version)
        /// There is no marker at all. See the header: today this means a store
        /// no build carrying this code has ever opened.
        case absent
        /// A marker is there and could not be read. NOT the same as absent: this
        /// one says something is wrong with the file rather than that nobody
        /// wrote it.
        case unreadable(detail: String)
    }

    /// Where the marker sits for a given store. Beside it, sharing its name, so
    /// a copy of the data folder carries both and a restore cannot separate them.
    static func url(besideStoreAt storeURL: URL) -> URL {
        storeURL.appendingPathExtension("version")
    }

    static func read(besideStoreAt storeURL: URL) -> Reading {
        let path = url(besideStoreAt: storeURL)
        guard FileManager.default.fileExists(atPath: path.path) else { return .absent }
        do {
            let text = try String(contentsOf: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = parse(text) else {
                return .unreadable(detail: "the marker does not hold a version")
            }
            return .version(parsed)
        } catch {
            return .unreadable(detail: error.localizedDescription)
        }
    }

    /// Records the version that has just opened the store.
    ///
    /// ATOMIC, because a half written marker is a store that reads as
    /// unreadable rather than as whatever it actually is, and this is written on
    /// every launch.
    static func write(_ version: Schema.Version, besideStoreAt storeURL: URL) throws {
        let text = "\(version.major).\(version.minor).\(version.patch)\n"
        try Data(text.utf8).write(to: url(besideStoreAt: storeURL), options: .atomic)
    }

    /// A version parsed from storage is INPUT, so it goes through one place that
    /// answers a value or nothing, and never feeds a comparison directly (L50).
    /// A partial or malformed marker is refused rather than being read as a zero,
    /// because zero would compare as older than everything and wave every store
    /// through.
    static func parse(_ text: String) -> Schema.Version? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return Schema.Version(numbers[0], numbers[1], numbers[2])
    }
}

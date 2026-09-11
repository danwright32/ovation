// ovation#208. Why a JSON artifact Downbeat wrote could not be read.
//
// ONE SET OF CAUSES, AND THE SENTENCE BELONGS TO THE READER. Ovation now reads
// two things Downbeat writes: a queued booking (`HandoffRecord`, ovation#33) and
// the whole export (`DownbeatExport`). The ways they can fail to be read are the
// same five, because both are versioned JSON from the same producer, but what
// each failure COSTS is not: a queued booking that will not read is a shoot that
// has not been invoiced and a file left in the queue, and an export that will not
// read is a roster that was not refreshed while every client Ovation already
// holds stays exactly as it was.
//
// So the CAUSE is shared here and each reader supplies its own sentence, which is
// the pattern `SecondInstance.sentence(for:)` and
// `YearEndExportCommand.sentence(for:)` already use. Sharing the sentence too
// would put one consequence on two unrelated events; writing the causes twice
// would be two things doing one job, and a shared NAME across a boundary is read
// as shared behaviour whether or not it is (L263, L342).
//
// THE DECODING ERROR MAPPER IS GENUINELY SHARED and lives here with it: turning
// Foundation's error into a cause that names a FIELD is the same work for any
// artifact, and it is the part that has to point at something in the file rather
// than at a type in this app.
import Foundation

/// Why a versioned JSON artifact from Downbeat could not be read. Distinct causes
/// get distinct cases, because the remedies are unrelated: an old version is a
/// Downbeat to upgrade, a missing field is a contract that has changed, and
/// unreadable bytes are a damaged file (L11).
enum DownbeatReadRefusal: Equatable, Sendable {
    /// The bytes are not JSON at all, or there are no bytes. An empty file is
    /// this rather than an empty record: PRD 5.34 refuses a malformed handoff
    /// loudly and never reads one as empty.
    case notReadable(detail: String)
    /// It parsed and says nothing about which version it is. Deliberately not
    /// folded into `versionBelowMinimum` as version zero: that would report "this
    /// is too old" about a file that never said how old it is, and the two need
    /// different work.
    case versionMissing
    case versionBelowMinimum(found: Int, minimum: Int)
    /// A field Ovation cannot proceed without is absent. Named, never defaulted:
    /// a shoot defaulted to no duration would price at nothing and the invoice
    /// would total correctly against its own parts (L67).
    case fieldMissing(String)
    case fieldMalformed(String, detail: String)

    /// Turns Foundation's decoding error into a refusal that NAMES the field, so
    /// the sentence Dan reads points at something in the file rather than at a
    /// type in this app.
    static func refusal(for error: DecodingError,
                        fallback: String = "the record") -> DownbeatReadRefusal {
        switch error {
        case .keyNotFound(let key, let context):
            return .fieldMissing(path(context.codingPath + [key], fallback: fallback))
        case .valueNotFound(_, let context):
            return .fieldMissing(path(context.codingPath, fallback: fallback))
        case .typeMismatch(_, let context):
            return .fieldMalformed(path(context.codingPath, fallback: fallback),
                                   detail: context.debugDescription)
        case .dataCorrupted(let context):
            // A date that is not ISO 8601 arrives here, with the field in the
            // path, so it is a malformed field rather than an unreadable file.
            if context.codingPath.isEmpty {
                return .notReadable(detail: context.debugDescription)
            }
            return .fieldMalformed(path(context.codingPath, fallback: fallback),
                                   detail: context.debugDescription)
        @unknown default:
            return .notReadable(detail: "\(error)")
        }
    }

    /// `booking.startsAt` rather than `CodingKeys(stringValue: "startsAt")`.
    ///
    /// `fallback` is what to call the whole artifact when the error carries no
    /// path at all, because "the record" is wrong for an export and "the export"
    /// is wrong for a queued booking.
    static func path(_ keys: [CodingKey], fallback: String = "the record") -> String {
        let joined = keys.map(\.stringValue).joined(separator: ".")
        return joined.isEmpty ? fallback : joined
    }
}

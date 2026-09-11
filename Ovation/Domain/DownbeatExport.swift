// ovation#208. Downbeat's whole export, as it arrived, and the version floor
// that decides which of them Ovation will read.
//
// WHAT THIS TYPE IS AND IS NOT. It is the WIRE value. Turning its clients into
// rows in Ovation's store is `ClientImport`'s job, kept out of here so that
// reading the file cannot depend on the store being open, and so a refusal names
// the file rather than half a saved roster. That is the same division
// `HandoffRecord` already draws for a queued booking.
//
// IT DECODES THE CLIENTS AND DELIBERATELY NOT THE REST. The export also carries
// `bookings`, `venues` and `blockedDates`, and this build reads none of them:
// ovation#32 drains bookings from the QUEUE rather than from here, and ovation#35
// will add the export's bookings for the backfill. That omission is named here
// because a decoder which declares only the fields it needs today otherwise
// discards every sibling in silence and nothing reports the loss (L425). So: this
// is not a model of the export, it is the client half of one, and a reader who
// needs a booking must add it here rather than assume it is absent upstream.
//
// THE FLOOR IS 2, AND A MINIMUM RATHER THAN AN EQUALITY. An equality gate turns
// Downbeat's next additive bump into a total outage of the roster, and a payload
// refused whole produces empty data indistinguishable from the data being gone
// (L255). Two is what has been MEASURED rather than what sounds safe: both
// custody snapshots were read before this was written, `downbeat-export-2026-08-27`
// at version 2 and `downbeat-export-v3-2026-09-05` at version 3, and their
// `clients[]` entries carry the same fields with the same meanings, 31 rows each,
// ids that all parse as UUIDs. A floor of 1 would be a claim about a shape nobody
// here has ever seen (L52).
//
// `isTaxExempt` IS OPTIONAL AND THAT IS THE POINT. It is Downbeat's three state
// field: true, false, or never answered, and the third is a real value rather
// than a gap. It was measured on 6 of 31 clients, 5 true and 1 false, which is
// exactly PRD 5a's "6 of 31", and the 25 without it are exactly the roster pass's
// 25. The record said for two weeks that this field did not exist (ovation#215).
import Foundation

/// What reading the export came to.
enum DownbeatExportReading: Equatable, Sendable {
    case read(DownbeatExport)
    case refused(DownbeatReadRefusal)
}

struct DownbeatExport: Equatable, Sendable, Decodable {

    /// The oldest export format this build reads. Everything at or above it is
    /// accepted; see the header for why this is not an equality and why it is 2.
    static let minimumVersion = 2

    let version: Int
    /// When Downbeat wrote this file. Downbeat rewrites it on its own launch, so
    /// this is how old the roster Ovation is about to import actually is.
    let exportedAt: Date
    let clients: [Client]

    /// One client as Downbeat holds it. Every field here is one Downbeat owns;
    /// nothing Ovation owns (a tax status Dan answered here, an acknowledged
    /// shared address, a payment term) has any representation in this type,
    /// because there is nowhere upstream for it to come from.
    struct Client: Equatable, Sendable, Decodable {
        let id: UUID
        let displayName: String
        /// The address of whoever booked. Non optional in the export: the one
        /// client with no override carries an empty string rather than a missing
        /// key, which is why emptiness is treated as absence downstream and never
        /// here (L257).
        let email: String
        let contractEmail: String
        /// Three states. See the header: absent is never false.
        let isTaxExempt: Bool?
    }

    /// Read the export, or say why not.
    ///
    /// THE VERSION IS READ FIRST, on its own, before anything else is decoded, so
    /// that a version this build cannot read is told apart from a damaged file.
    /// A version 1 export would otherwise fail on whichever field it happens to
    /// lack, and the refusal would name a field when the real answer is an older
    /// Downbeat (L11). Reading it separately is also what makes a NEWER version
    /// readable at all: this decodes the fields it knows and ignores the rest,
    /// which is the whole shape of an additive bump.
    static func read(_ data: Data) -> DownbeatExportReading {
        guard !data.isEmpty else {
            return .refused(.notReadable(detail: "the file is empty"))
        }

        let envelope: VersionEnvelope
        do {
            envelope = try JSONDecoder().decode(VersionEnvelope.self, from: data)
        } catch let error as DecodingError {
            switch error {
            case .keyNotFound, .valueNotFound:
                return .refused(.versionMissing)
            case .typeMismatch(_, let context) where context.codingPath.isEmpty == false:
                return .refused(.versionMissing)
            default:
                return .refused(.notReadable(detail: shortDescription(of: error)))
            }
        } catch {
            return .refused(.notReadable(detail: "it is not JSON"))
        }

        guard envelope.version >= minimumVersion else {
            return .refused(.versionBelowMinimum(found: envelope.version,
                                                 minimum: minimumVersion))
        }

        do {
            return .read(try decoder.decode(DownbeatExport.self, from: data))
        } catch let error as DecodingError {
            return .refused(DownbeatReadRefusal.refusal(for: error, fallback: "the export"))
        } catch {
            return .refused(.notReadable(detail: "it is not JSON"))
        }
    }

    /// Just enough to answer the version question, so an export from a version
    /// this build cannot decode is still told apart from a damaged one.
    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    /// The same configuration Downbeat encodes with. `OvertureExportBuilder` uses
    /// `.iso8601`, and a consumer decoding with a different strategy would refuse
    /// every export on a well formed date.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func shortDescription(of error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context): return context.debugDescription
        default: return "it is not a Downbeat export"
        }
    }

    /// What Dan is told, naming the file so the refusal points at something he
    /// can act on (L80).
    ///
    /// IT LIVES HERE AND NOT ON THE CAUSE (ovation#208). The five causes are
    /// shared with the queued booking reader; what a failure COSTS is not. A
    /// queued booking that will not read is a shoot that has not been invoiced.
    /// An export that will not read is a roster that was not refreshed, and every
    /// client Ovation already holds is untouched, which is the reassuring half
    /// and has to be said so a refusal does not read as data loss.
    static func sentence(for refusal: DownbeatReadRefusal, file filename: String) -> String {
        let unchanged = "Ovation's client list has not been changed and is exactly as it was."
        switch refusal {
        case .notReadable(let detail):
            return "Downbeat's export \(filename) could not be read (\(detail)). "
                + "No clients were brought across. \(unchanged)"
        case .versionMissing:
            return "Downbeat's export \(filename) does not say which format it is in, so "
                + "Ovation cannot tell whether it can read it. No clients were brought "
                + "across. \(unchanged)"
        case .versionBelowMinimum(let found, let minimum):
            return "Downbeat's export \(filename) is format version \(found), and Ovation "
                + "reads version \(minimum) and above. It was written by an older Downbeat "
                + "than this one. No clients were brought across. \(unchanged)"
        case .fieldMissing(let field):
            return "Downbeat's export \(filename) has no '\(field)', which Ovation needs to "
                + "bring a client across. No clients were brought across. \(unchanged)"
        case .fieldMalformed(let field, let detail):
            return "Downbeat's export \(filename) has a '\(field)' Ovation could not read "
                + "(\(detail)). No clients were brought across. \(unchanged)"
        }
    }
}

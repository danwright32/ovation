// ovation#33, PRD 5.34 and PRD section 8 item 8. One queued booking, as Downbeat
// wrote it, and the version floor that decides which records Ovation will read.
//
// THE FLOOR IS A MINIMUM, NEVER AN EQUALITY. An equality gate turns the
// producer's next additive bump into a total outage of the consumer, and refusing
// a payload whole produces empty data indistinguishable from the data being gone
// (L255). Overture already learned this: overture#3193 widened its export gate
// for exactly this reason, and Phase 0.2 of Ovation's own plan exists because
// installing a version 3 Downbeat in front of an Overture with an equality gate
// would have made it refuse the export and lose the client roster.
//
// THE MINIMUM IS PUBLISHED WHERE DOWNBEAT CAN READ IT, in
// `integration/downbeat-handoff-accepted-versions.json`. Downbeat's push gate
// refuses a push whose export version has outrun a consumer, and until this
// shipped it answered CANNOT MEASURE for Ovation, which was the correct answer:
// there was no decoder, so no version bump could break anything. The declaration
// and the decoder land together, never the declaration first, because a declared
// minimum with no code behind it turns that honest "cannot measure" into a green
// pass comparing a hand typed number against nothing (L98, L11, L182).
//
// NOTHING HERE READS THAT FILE. The number below is the one that is enforced, and
// `HandoffRecordTests` reads the file and then drives this decoder from either
// side of what it says. A test that read the constant and compared it with the
// file would prove only that one number had been copied to two places (L70).
//
// WHY 3 AND NOT 1. Version 3 is what the installed Downbeat writes, measured from
// a real record rather than from Downbeat's record of itself (ovation#29, L58).
// Ovation has never seen a version 1 or 2 record and could not claim to decode
// one, and a floor of 1 would be a claim about shapes nobody has measured (L52).
//
// WHAT THIS TYPE IS AND IS NOT. It is the WIRE value: the record as it arrived,
// with the day strings still strings and the instants still instants. Turning one
// into an invoice, a client and a shoot is the drain's job (ovation#32), and it
// is kept out of here so that reading a record cannot depend on the store being
// open, and so that a refusal names the file rather than half a saved invoice.
//
// THE DAY STRINGS ARE NOT RE-DERIVED FROM THE INSTANTS, and that is load bearing
// rather than laziness. Downbeat authors them in Dan's shooting zone, pinned
// there rather than to the host's clock, so a consumer that recomputed the day
// from `startsAt` would disagree with both Downbeat and Overture about which day
// a late evening shoot fell on. The measured record proves the case exists: its
// instants cross midnight UTC while both day strings say the 6th.
import Foundation

/// Why a queue file could not be read. The CAUSES are `DownbeatReadRefusal`,
/// shared with the export reader because the ways a versioned Downbeat JSON file
/// can fail to be read are the same for both; the SENTENCE is below on
/// `HandoffRecord`, because what a refusal costs is not shared at all
/// (ovation#208).
typealias HandoffRefusal = DownbeatReadRefusal

/// What reading one queue file came to.
enum HandoffRecordReading: Equatable, Sendable {
    case read(HandoffRecord)
    case refused(HandoffRefusal)
}

struct HandoffRecord: Equatable, Sendable, Decodable {

    /// The oldest handoff format this build reads. Everything at or above it is
    /// accepted; see the header for why this is not an equality and why it is 3.
    ///
    /// Published in `integration/downbeat-handoff-accepted-versions.json`, which
    /// is what Downbeat's push gate reads. The two are tied by a behaviour test
    /// rather than by either reading the other.
    static let minimumVersion = 3

    let version: Int
    /// When the commit that wrote this happened. The invoice is dated from the
    /// shoot rather than from this, but a record turning up unconsumed months
    /// later cannot be reasoned about without it.
    let committedAt: Date
    let booking: Booking
    let client: Client
    /// ABSENT for an ad hoc venue, which has no roster entry to carry, and
    /// `booking.venueName` is the whole answer in that case. This is the part of
    /// the contract a reading of the producer's source is most likely to get
    /// wrong, and the measured record (ovation#29) is the one that settles it: it
    /// has no `venue` key at all rather than an empty one.
    let venue: Venue?

    struct Booking: Equatable, Sendable, Decodable {
        let id: UUID
        /// Downbeat's stable org identity. Every match keys on this rather than
        /// on the display name, which is a human label that changes.
        let clientID: UUID
        let clientDisplayName: String
        /// May legitimately be empty.
        let shootName: String
        /// `YYYY-MM-DD` in Dan's shooting zone, as Downbeat wrote it. Kept as
        /// written; see the header.
        let startDate: String
        let endDate: String
        /// The instants the shoot starts and stops. Every dollar on the invoice
        /// comes from the gap between them.
        let startsAt: Date
        let endsAt: Date
        /// Absent for an ad hoc venue.
        let venueID: UUID?
        /// Always present, roster venue or not.
        let venueName: String
        /// The booking this one re-runs, absent on an ordinary booking. Easy to
        /// drop when mapping, and dropping it drafts a SECOND invoice for one
        /// shoot instead of adding a note to the one that exists (contract item
        /// 3), with nothing reporting it.
        let isRerunOf: UUID?

        enum CodingKeys: String, CodingKey {
            case id
            case clientID = "clientId"
            case clientDisplayName, shootName, startDate, endDate, startsAt, endsAt
            case venueID = "venueId"
            case venueName, isRerunOf
        }
    }

    /// The client as it was AT COMMIT, frozen deliberately (Dan, 2026-08-27) so
    /// that a client edited or removed after the commit does not change what an
    /// unconsumed record resolves to.
    struct Client: Equatable, Sendable, Decodable {
        let id: UUID
        let displayName: String
        let email: String
        let contractEmail: String
        let hasLeftReview: Bool
        let specialBehaviors: [String]
        let hostingSite: String
        // Optional, and OMITTED rather than written as null when absent, which is
        // the contract's convention throughout. Carried rather than dropped: a
        // decoder that declares only the fields it needs today discards its
        // siblings with nothing reporting the loss (L425), and `isTaxExempt` in
        // particular is evidence for ovation#122.
        let shortName: String?
        let phoneNumber: String?
        let isTaxExempt: Bool?
        let notes: String?
    }

    struct Venue: Equatable, Sendable, Decodable {
        let id: UUID
        let name: String
        let editingProfile: String
        let specialBehaviors: [String]
        let staffNotificationEmails: [String]
        let address: String?
        let notes: String?
    }

    // MARK: reading one

    /// Reads one queue file's bytes.
    ///
    /// IT NEVER THROWS. Every way this can fail is a refusal the drain has to
    /// report and act on, and an `Error` at this boundary would arrive at the
    /// call site as one thing that has to be taken apart again to find out which
    /// of them it was.
    ///
    /// THE VERSION IS READ FIRST, on its own, before anything else is decoded.
    /// A version 2 record would otherwise fail on a missing `startsAt`, and the
    /// refusal would name a field when the real answer is an older Downbeat
    /// (L11). It is also what makes a NEWER version readable at all: this decodes
    /// the fields it knows and ignores the rest, which is the whole shape of an
    /// additive bump.
    static func read(_ data: Data) -> HandoffRecordReading {
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
            return .read(try decoder.decode(HandoffRecord.self, from: data))
        } catch let error as DecodingError {
            return .refused(refusal(for: error))
        } catch {
            return .refused(.notReadable(detail: "it is not JSON"))
        }
    }

    /// Just enough to answer the version question, so that a record from a
    /// version this build cannot decode is still told apart from a damaged one.
    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    /// The same configuration Downbeat encodes with. Its `BookingHandoffRecord`
    /// uses `.iso8601` on both sides, and a consumer that decoded with a
    /// different strategy would refuse every record on a well formed date.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Turns Foundation's decoding error into a refusal that NAMES the field.
    /// The mapping is shared with the export reader; only the word for the whole
    /// artifact differs (ovation#208).
    private static func refusal(for error: DecodingError) -> HandoffRefusal {
        DownbeatReadRefusal.refusal(for: error, fallback: "the record")
    }

    /// What Dan is told, naming the file so the refusal points at something he
    /// can act on (PRD 5.34, L80).
    ///
    /// IT LIVES ON THE READER, NOT ON THE CAUSE (ovation#208). The five causes are
    /// shared with the export reader; every sentence here is about a shoot that
    /// has not been invoiced and a file left in the queue, which is true of this
    /// artifact and of nothing else.
    static func sentence(for refusal: HandoffRefusal, file filename: String) -> String {
        switch refusal {
        case .notReadable(let detail):
            return "The queued booking \(filename) could not be read as a handoff record "
                + "(\(detail)). The shoot it holds has not been invoiced, and the file has "
                + "been left in the queue."
        case .versionMissing:
            return "The queued booking \(filename) does not say which handoff format it is "
                + "in, so Ovation cannot tell whether it can read it. The shoot it holds has "
                + "not been invoiced, and the file has been left in the queue."
        case .versionBelowMinimum(let found, let minimum):
            return "The queued booking \(filename) is handoff format version \(found), and "
                + "Ovation reads version \(minimum) and above. It was written by an older "
                + "Downbeat than this one. The shoot it holds has not been invoiced, and the "
                + "file has been left in the queue."
        case .fieldMissing(let field):
            return "The queued booking \(filename) has no '\(field)', which Ovation needs to "
                + "raise the invoice. The shoot it holds has not been invoiced, and the file "
                + "has been left in the queue."
        case .fieldMalformed(let field, let detail):
            return "The queued booking \(filename) has a '\(field)' Ovation could not read "
                + "(\(detail)). The shoot it holds has not been invoiced, and the file has "
                + "been left in the queue."
        }
    }

    private static func shortDescription(of error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context): return context.debugDescription
        default: return "it is not a handoff record"
        }
    }
}

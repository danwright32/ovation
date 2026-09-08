// ovation#21. Which venue a queued booking names, and what to do when the venue
// list cannot answer.
//
// `venueName` IS AUTHORITATIVE AND `venues[]` IS NOT, and that is settled by the
// data rather than by preference. Measured 2026-09-06 against the live version 3
// export and the custody snapshot: of the six distinct venue names bookings
// actually use, THREE have no row in `venues[]` at all, and two rows in
// `venues[]` have no booking pointing at them. So the list is neither a superset
// nor a subset of what the bookings use.
//
// A consumer resolving through `venues[]` would therefore find nothing for three
// real shoots, and would do it silently, writing an invoice with no venue for a
// shoot that plainly had one. `venueName` travels on every booking and is what
// Downbeat's own export contract says is the answer for an ad hoc venue. One of
// them has to be the declared home of this fact (L83), and the measurement makes
// it that one.
//
// `venues[]` IS THEREFORE NOT READ. Not read and ignored, not read as a fallback:
// a fallback reached only when the name is missing would be exercised by almost
// nothing and would be wrong when it finally fired (L173). It is decoration on
// this contract, and saying so is the point.
//
// A PLACEHOLDER IS ITS OWN OUTCOME. One real booking on the live schedule carries
// `TBD`, which is a deliberate "not decided yet" rather than a missing value. It
// must not be written onto an invoice as though it were a venue, and it must not
// be read as absent either, because absent means Downbeat sent nothing and this
// means Dan has not chosen yet. A placeholder rendered in place of a missing
// required value is a DETECTION that the value is absent, so it blocks the thing
// it appears in rather than labelling it (L67).
import Foundation

/// What a booking's venue resolved to.
enum BookingVenue: Equatable {
    /// A real venue, named by the booking.
    case named(String)
    /// The booking says the venue is not decided yet. Dan resolves this in
    /// Downbeat, and an invoice must not be sent naming it.
    case notDecidedYet(placeholder: String)
    /// The booking carries no venue at all, which is different again: nothing
    /// was sent, rather than something meaning "not yet".
    case absent

    /// Whether an invoice carrying this venue may go to a client.
    var mayBeSent: Bool {
        switch self {
        case .named: return true
        case .notDecidedYet, .absent: return false
        }
    }

    /// What goes on the invoice, or nil where nothing should.
    ///
    /// NIL FOR BOTH REFUSING CASES, because the alternative is a document that
    /// prints "TBD" where a venue belongs.
    var forTheInvoice: String? {
        switch self {
        case .named(let name): return name
        case .notDecidedYet, .absent: return nil
        }
    }
}

enum BookingVenueReader {

    /// Values Downbeat's own data uses to mean "not decided yet".
    ///
    /// MATCHED WHOLE AND CASE INSENSITIVELY, never as a substring, because a real
    /// venue can legitimately contain these letters and a substring match would
    /// refuse it. Kept short and derived from what was actually observed rather
    /// than from a list of everything a placeholder might be: an entry nobody has
    /// seen is a guess about the producer, and admitting every unlisted
    /// malformed value is the shape L257 warns about, which is why the caller
    /// still gets `.named` for anything unrecognised and the SEND path checks the
    /// venue rather than trusting this list to be complete.
    static let placeholders: Set<String> = ["tbd", "t.b.d.", "tba"]

    /// Read the venue a booking names.
    ///
    /// It takes the NAME, not the record, so the one place that decides this
    /// cannot be handed a `venues[]` row by accident.
    static func read(venueName: String?) -> BookingVenue {
        let trimmed = (venueName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .absent }
        if placeholders.contains(trimmed.lowercased()) {
            return .notDecidedYet(placeholder: trimmed)
        }
        return .named(trimmed)
    }
}

// Plan 1.6, ovation#55. A money bearing date, stamped with the business day it
// belongs to at the moment it is written.
//
// WHY THE STAMP. A date computed at READ time depends on the calendar in force
// when it is read and on the machine reading it. Once the key is written, the
// year that row belongs to is settled, and re-running last January's export
// produces last January's numbers. That reproducibility is the actual
// requirement: an accountant asking in March about a figure produced in January
// needs the same answer (L37).
//
// BOTH HALVES ARE ONE VALUE, and that is a deliberate strengthening of the
// plan's wording. The plan says every record carries a `businessDayKey` string
// ALONGSIDE its instant. Two properties side by side can be written by two
// different code paths, and a field stamped on the update path but not the
// insert path leaves every freshly created record without it, invisibly, because
// everything ever updated looks correct (L384). A value and the fact describing
// it are one fact and belong in one value (L544), so there is no way to write an
// instant here without also settling its day.
//
// THE STORED KEY ALWAYS WINS ON THE WAY BACK. Decoding does not re-derive: a key
// written under one rule must not change when the rule, the calendar or the
// machine changes. A row whose two halves disagree is still LOADED, and reports
// that it disagrees, because that is either a rule change worth knowing about or
// a corrupt row and both need saying rather than silently correcting (L11).
import Foundation

struct BusinessDate: Equatable, Hashable, Codable, Sendable, Comparable {
    /// When it happened. The fact.
    let instant: Date

    /// Which business day that was, settled at write. The answer.
    let dayKey: String

    /// The ONLY way to make one from an instant. Named for what it does, so a
    /// call site reads as the moment the answer was settled.
    static func stamping(_ instant: Date) -> BusinessDate {
        BusinessDate(storedInstant: instant, storedDayKey: BusinessCalendar.dayKey(for: instant))
    }

    /// Reconstituted from storage, both halves exactly as they were stored.
    ///
    /// Deliberately named `stored`: outside a decoder, the only legitimate caller
    /// is a migration rewriting rows it has already read. Anything else that
    /// wants a `BusinessDate` from an instant uses `stamping`, which is the only
    /// route that can produce a key.
    ///
    /// It does NOT refuse a malformed key. A row is not worth losing over one,
    /// and a decoder that threw would take the whole store with it; the row loads
    /// and answers `nil` for its year, which forces every caller that groups by
    /// year to deal with it rather than being handed a plausible number (L50).
    init(storedInstant: Date, storedDayKey: String) {
        self.instant = storedInstant
        self.dayKey = storedDayKey
    }

    /// The tax year this row belongs to, or nil when the stored key is not a day
    /// key at all.
    var year: Int? { BusinessCalendar.year(forDayKey: dayKey) }

    /// Whether the stored key is what stamping this instant would produce today.
    ///
    /// False is not an error to correct, it is a finding to report: it means the
    /// row was stamped under a different rule, or is corrupt. The surface for
    /// that is the Problems store (ovation#59).
    var agreesWithItsInstant: Bool { dayKey == BusinessCalendar.dayKey(for: instant) }

    /// Ordered by the instant, which is the fact. Two rows on the same business
    /// day still have an order.
    static func < (lhs: BusinessDate, rhs: BusinessDate) -> Bool { lhs.instant < rhs.instant }
}

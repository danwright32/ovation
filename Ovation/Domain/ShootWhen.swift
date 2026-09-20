// ovation#60, PRD 5.3 and 5.3a. When a shoot happened, which is either two real
// instants or a day and nothing more.
//
// ONE VALUE RATHER THAN A DATE BESIDE TWO TIMES. A shoot's day is derivable from
// its start, so holding both as separate fields is one fact written twice, and
// the two can be made to disagree by any writer that sets one and not the other
// (L544, L384). Here the day is ANSWERED by the value rather than stored beside
// it.
//
// WHAT THE TWO INSTANTS MEAN, confirmed by Dan on 2026-08-27: they are when he
// starts and stops shooting, and the gap between them is the number he bills.
// Every dollar Ovation produces comes from that reading, and a wrong one would be
// invisible, because the amount would be well formed and would total correctly
// against its own parts.
//
// A DURATION OF NOTHING OR LESS CANNOT BE CONSTRUCTED. PRD 5.3b refuses it by
// name rather than pricing it, and a value parsed from stored data that reaches
// arithmetic unchecked is how a nonsense figure becomes a confident invoice
// (L23, L50). The refusal is structural here, so no call site can skip it.
//
// NOTHING HERE PRICES ANYTHING, since ovation#432. This value used to derive the
// length of the shoot from its two instants, and after ovation#43 no app code
// read that figure: PRD 3a makes the booking's instants a placeholder and prices
// from the times Dan types, through `ShootDuration`. The derivation survived on
// its own tests alone, which is the shape a docstring later turns into a decision
// nobody revisits (L29, L346). What the two instants are FOR is the record of
// what the booking said, which ovation#95 puts on a surface.
import Foundation

enum ShootWhen: Equatable, Hashable, Codable, Sendable {
    /// Both instants, from a booking that carried times.
    case timed(startsAt: BusinessDate, endsAt: Date)
    /// A day and no more, which is what an invoice raised from scratch has.
    case dayOnly(BusinessDate)

    /// The only way to make a timed one, and it refuses a duration of nothing or
    /// less rather than rounding it into a number.
    init?(startsAt: Date, endsAt: Date) {
        guard endsAt > startsAt else { return nil }
        self = .timed(startsAt: .stamping(startsAt), endsAt: endsAt)
    }

    /// A day with no times.
    init(dayOf instant: Date) {
        self = .dayOnly(.stamping(instant))
    }

    /// The business day this shoot belongs to, settled at write in both cases.
    var day: BusinessDate {
        switch self {
        case .timed(let startsAt, _): return startsAt
        case .dayOnly(let day): return day
        }
    }
}

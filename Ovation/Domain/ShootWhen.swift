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
// THE PLAUSIBILITY CEILING IS NOT HERE, and that is deliberate rather than an
// omission. "Implausibly long" is a judgement about a number, and PRD 5.3b's
// threshold has never been measured against Dan's real bookings; picking one here
// would ship a limit calibrated on nothing and make it read as settled (L172).
// It belongs with pricing, in ovation#43, which is the issue that has the real
// durations to measure against.
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

    /// What is billable, in tenths of an hour, or nil where there are no times to
    /// price from.
    ///
    /// THE ONE HOUR MINIMUM IS NOT APPLIED HERE. It is a pricing rule and belongs
    /// with the line item that charges (ovation#43); this is the length of the
    /// shoot, and a surface reporting how long Dan was there must not be handed a
    /// number that has been rounded up for billing.
    var billableHours: Hours? {
        switch self {
        case .timed(let startsAt, let endsAt):
            let seconds = Int64(endsAt.timeIntervalSince(startsAt.instant).rounded())
            return Hours(tenths: Rounding.halfAwayFromZero(seconds * 10, over: 3_600))
        case .dayOnly:
            return nil
        }
    }
}

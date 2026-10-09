// ovation#655, PRD 1d. WHICH BOOKINGS QUICKBOOKS ALREADY BILLED, decided by one
// rule.
//
// UNTIL LAUNCH EVERY COMMITTED BOOKING WAS INVOICED TWICE OVER, in a sense: it
// left a queue file for Ovation AND was invoiced in QuickBooks, because Ovation
// could not send yet. Nothing joins the two (a draft carries no number, so the
// QuickBooks importer's refusal of a number already held never sees it), so the
// only thing standing between a queued booking and a second invoice to a real
// client is this day. A booking committed before it was billed in QuickBooks and
// is never drafted; one committed on or after it is Ovation's (Dan, 2026-09-12,
// ovation#252).
//
// ONE RULE, ASKED BY EVERY CALLER. `LaunchDay.whoBills` is the predicate, and the
// stopgap draft command (ovation#461) reaches it through `BookingDrafter`, which
// is where ovation#32's drain must reach it too. A second spelling of "before the
// cutoff" in the drain is two rules that agree only until one of them is edited
// (L342, L370). `BookingDrafter.draft` takes a `LaunchDay` with no default, so
// nothing can draft without having one confirmed (L168).
//
// THE DAY IS NEW YORK'S. PRD 1d takes the cutoff "from the one business calendar
// rather than the machine's locale", so `committedAt` is read through
// `BusinessCalendar.dayKey`: a booking committed at 23:30 in New York the evening
// before launch is already launch day in UTC, and reading it there would draft a
// booking QuickBooks billed (L39).
//
// THE PLACEHOLDER IS NOT A CONFIRMED DAY. PRD 1d records the cutoff as 2026-09-12
// AND says that date is a placeholder, and that the drain refuses until it has
// been confirmed as the launch day: a placeholder nothing forces anybody to move
// stays where it was put. So nothing stored means NOT CONFIRMED, never "confirmed
// as the 12th", and the only way to a `.confirmed` value is somebody pressing
// Confirm in Settings (Dan, 2026-10-08: a Settings field with a Confirm control).
//
// WHERE IT IS KEPT, and what that costs. In the app's preferences, like the
// invoice footer (ovation#319), because it is a setting Dan types rather than a
// record. It is therefore NOT in a backup. A Mac restored from one comes back
// with the launch day unconfirmed, which refuses drafting and says so, so the
// loss fails closed rather than open (L42).
import Foundation
import Observation

/// One business day on which Ovation took over billing from QuickBooks.
struct LaunchDay: Equatable, Hashable, Sendable {

    /// `yyyy-MM-dd` in the business calendar.
    let dayKey: String

    /// Nil for a key that is not a calendar day, so a malformed day is refused
    /// rather than made plausible (L50).
    init?(dayKey: String) {
        guard BusinessCalendar.day(forKey: dayKey) != nil else { return nil }
        self.dayKey = dayKey
    }

    /// The business day an instant fell on.
    init(containing instant: Date) {
        dayKey = BusinessCalendar.dayKey(for: instant)
    }

    /// The day's first instant in New York, which a date control shows.
    var instant: Date? { BusinessCalendar.day(forKey: dayKey)?.instant }

    /// "8 Oct 2026", the form the screens use.
    var written: String {
        BusinessCalendar.day(forKey: dayKey).flatMap(BusinessCalendar.shortDate) ?? dayKey
    }

    /// Who billed a booking, decided by the day it was committed on.
    enum WhoBills: Equatable, Sendable {
        /// Committed before launch, so QuickBooks invoiced it. Carries the day it
        /// was committed on, which is what a report about it has to name.
        case quickBooks(committedOn: String)
        /// Committed on launch day or after.
        case ovation
    }

    /// THE RULE. Day keys are ISO ordered, so comparing the strings compares the
    /// days (`BusinessCalendar.dayKeyFormat`).
    func whoBills(bookingCommittedAt committedAt: Date) -> WhoBills {
        let committedOn = BusinessCalendar.dayKey(for: committedAt)
        return committedOn < dayKey ? .quickBooks(committedOn: committedOn) : .ovation
    }
}

/// Where the launch day stands.
enum LaunchCutoff: Equatable, Sendable {
    /// Nothing has been confirmed. The state every installation starts in.
    case notConfirmed
    case confirmed(LaunchDay)
    /// Something is stored and it is not a day. Its own state because the remedy
    /// is the same and the cause is not, and it must never read as confirmed.
    case unreadable(stored: String)

    /// PRD 1d's placeholder, recorded so it is written down once. It confirms
    /// nothing.
    static let placeholder = LaunchDay(dayKey: "2026-09-12")!

    var confirmed: LaunchDay? {
        if case .confirmed(let day) = self { return day }
        return nil
    }

    /// Why the booking queue may not be drafted from, naming where that is fixed,
    /// or nil once a day is confirmed (L111, L399).
    var whyDraftingWaits: String? {
        switch self {
        case .confirmed:
            return nil
        case .notConfirmed:
            return "Confirm Ovation's launch day in Settings, under Bookings, first. "
                + "Bookings committed before that day were invoiced in QuickBooks, "
                + "and drafting them here would bill those clients twice."
        case .unreadable:
            return "The launch day saved in Settings could not be read, so Ovation "
                + "cannot tell which bookings QuickBooks already invoiced. Confirm it "
                + "again in Settings, under Bookings."
        }
    }
}

/// The launch day as stored, shared by the Settings pane that confirms it and the
/// menu command that waits on it.
///
/// OBSERVABLE, AND ONE OBJECT FOR BOTH, so confirming in Settings re-enables the
/// menu entry at once rather than at the next launch (L14). A preference read
/// inside a menu's body is not something SwiftUI watches.
///
/// INJECTED WITH NO DEFAULT RESOLVING TO `.standard`, the same as
/// `InvoiceFooterSetting`: this WRITES, so a test reaching the real domain would
/// confirm a launch day on Dan's Ovation (L201).
@Observable
@MainActor
final class LaunchCutoffSetting {

    static let key = "bookings.launch-day.confirmed"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var cutoff: LaunchCutoff

    init(defaults: UserDefaults) {
        self.defaults = defaults
        cutoff = Self.read(defaults)
    }

    /// Records `day` as the confirmed launch day, replacing any before it.
    func confirm(_ day: LaunchDay) {
        defaults.set(day.dayKey, forKey: Self.key)
        cutoff = .confirmed(day)
    }

    private static func read(_ defaults: UserDefaults) -> LaunchCutoff {
        // `object(forKey:)` rather than `string(forKey:)`, because the latter
        // answers nil for a stored number, which would read damage as absence.
        guard let stored = defaults.object(forKey: key) else { return .notConfirmed }
        guard let text = stored as? String else { return .unreadable(stored: "\(stored)") }
        guard let day = LaunchDay(dayKey: text) else { return .unreadable(stored: text) }
        return .confirmed(day)
    }
}

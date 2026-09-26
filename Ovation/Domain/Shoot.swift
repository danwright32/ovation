// ovation#60. One piece of work an invoice covers.
//
// IT IS ITS OWN RECORD BECAUSE AN INVOICE CAN COVER MORE THAN ONE. PRD 5.1a: the
// unit of billing is the engagement, not the show, so a Wednesday rehearsal and
// a Saturday concert are one invoice with two shoots on it. The agreed list row
// draws the LAST shoot's name, counts the rest and shows a date span, which is
// not answerable from an invoice holding a single name and date.
//
// IT CANNOT HANG OFF A LINE ITEM, which was the shape considered first. Rush
// turnaround and preview images are lines belonging to no shoot, and a venue and
// two real instants are facts about the work rather than about a charge
// (ovation#95).
//
// EVERY FIELD BUT THE NAME CAN BE ABSENT, and that is measured rather than
// defensive: the one real handoff record captured on 2026-09-06 has no venue at
// all, because the venue was ad hoc.
import Foundation
import SwiftData

/// Which of a shoot's two real times has not been given yet (ovation#117).
///
/// A VALUE RATHER THAN TWO BOOLEANS, because "no start" and "no end" and "neither"
/// are one fact with three readings, and a pair of flags admits a fourth that means
/// nothing (L544, L163).
enum ShootTimesMissing: String, CaseIterable, Hashable, Sendable {
    case both
    case end
    case start
}

extension OvationSchemaV4 {
    @Model
    final class Shoot {
        var id: UUID = UUID()

        /// What Dan calls it. Frozen at commit time in the handoff, so it can differ
        /// from whatever the current roster says.
        var name: String = ""

        /// PRD 5.3. Two real instants or a day, held as one value so the day and the
        /// times can never disagree.
        var when: ShootWhen?

        /// Absent on the one real handoff record there is.
        var venue: String?

        /// The Downbeat booking this came from, for LOOKUP only. Never the identity:
        /// PRD 42c.
        var bookingKey: String?

        /// Declared order within its invoice (L343).
        var sortIndex: Int = 0

        var invoice: Invoice?

        /// WHEN DAN ACTUALLY SHOT, typed on the invoice after the event (PRD 3a,
        /// 51a, ovation#43).
        ///
        /// THESE ARE NOT `when`, AND THE DIFFERENCE IS THE WHOLE OF PRD 3a. `when`
        /// carries the BOOKING's instants, whose end Downbeat derives from the start
        /// and which nothing ever goes back to correct: 16 of 19 committed bookings
        /// carry exactly 3600 seconds, while only 16% of Dan's issued invoices over
        /// 2019 to 2024 were one hour. Pricing from `when` would have billed one hour
        /// for every shoot he has ever done, on an invoice totalling correctly
        /// against its own parts and reading as entirely normal on its way to a
        /// client (L161).
        ///
        /// CLOCK TIMES RATHER THAN INSTANTS, because that is what the screen's field
        /// takes and because a shoot running to 00:30 is a rule about the pair rather
        /// than a fact the data carries (docs/design/rules/duration.js).
        ///
        /// TWO FIELDS RATHER THAN ONE PAIR, because a start with no end is the
        /// ORDINARY state of a draft rather than an incomplete one. Dan, 2026-09-08:
        /// "I plan to create drafts with no end time (although I can put the start
        /// time in from the creation). When I go to send the invoice I will always
        /// know the end time."
        var shotFrom: ClockTime?
        var shotUntil: ClockTime?

        init(name: String, when: ShootWhen?, venue: String?) {
            self.name = name
            self.when = when
            self.venue = venue
        }

        /// The business day this shoot was on, or nil where nothing recorded one.
        var day: BusinessDate? { when?.day }

        /// What the times Dan typed come to, or nil while either is still missing.
        ///
        /// NIL IS "NOT YET", NEVER "NOTHING TO CHARGE". A span too long to be a shoot
        /// comes back as `.longerThanAShoot` rather than as nil, because PRD 3b
        /// refuses that by name and the two need opposite sentences: one asks for the
        /// end time, the other says the times already given cannot be right (L11).
        var duration: ShootDuration? {
            guard let shotFrom, let shotUntil else { return nil }
            return ShootDuration.between(shotFrom, and: shotUntil)
        }

        /// What this shoot charges for, where it charges at all.
        var billedHours: Hours? {
            guard case .some(.priced(let priced)) = duration else { return nil }
            return priced.billed
        }

        /// What this shoot still needs before it can be priced, or nil when both
        /// times are in.
        ///
        /// THE THREE ARE THE DESIGN'S OWN, in its own order
        /// (`docs/design/rules/waiting.js`). They are three rather than one because
        /// naming the class of thing instead of the thing is what that rule was
        /// written to stop: the screen drew "Needs the times" over a draft with a
        /// start time plainly on it, and a start with no end is the ORDINARY state
        /// of every draft rather than an edge case (PRD 51b, Dan 2026-09-08).
        var timesMissing: ShootTimesMissing? {
            switch (shotFrom, shotUntil) {
            case (nil, nil): return .both
            case (.some, nil): return .end
            case (nil, .some): return .start
            case (.some, .some): return nil
            }
        }

        /// PRD 3b. The two times given span longer than a shoot can be, so this one
        /// prices nothing and the invoice carrying it may not go out.
        ///
        /// ASKED AS ITS OWN QUESTION rather than by matching the case at each call
        /// site, because the pattern for it reaches through an optional and a copy
        /// of that at every reader is where one of them comes to mean "no times
        /// yet" instead (L263).
        var isLongerThanAShoot: Bool {
            if case .some(.longerThanAShoot) = duration { return true }
            return false
        }
    }
}

// THE NAME THE REST OF THE APP USES (ovation#134). The type belongs to a
// schema VERSION, because a version has to be able to describe a shape that
// is no longer current. Everything outside the store speaks about the shape
// in force, so it says the bare name and this is what points that name at the
// version in force. When a newer version exists, this line moves to it and
// every call site is already correct.
typealias Shoot = OvationSchemaV4.Shoot

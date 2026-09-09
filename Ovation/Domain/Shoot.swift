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

extension OvationSchemaV1 {
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

        init(name: String, when: ShootWhen?, venue: String?) {
            self.name = name
            self.when = when
            self.venue = venue
        }

        /// The business day this shoot was on, or nil where nothing recorded one.
        var day: BusinessDate? { when?.day }
    }
}

// THE NAME THE REST OF THE APP USES (ovation#134). The type belongs to a
// schema VERSION, because a version has to be able to describe a shape that
// is no longer current. Everything outside the store speaks about the shape
// in force, so it says the bare name and this is what points that name at the
// version in force. When a version 2 exists, this line moves to it and every
// call site is already correct.
typealias Shoot = OvationSchemaV1.Shoot

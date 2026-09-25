// ovation#60, PRD 5.4. One charge on an invoice.
//
// THE AMOUNT IS COMPUTED, NEVER STORED. PRD 5.42 requires that no sequence of
// line items can make the sum of parts disagree with the stored total, and the
// cheapest way to guarantee that is to have no second copy of the number: the
// inputs are stored and the amount is arithmetic over them (L107).
//
// NEITHER A DISCOUNT NOR A REFERRAL CREDIT IS A LINE. Both live on the invoice,
// the credit inside the subtotal and the discount below it, and the two net to
// the same tax, which is exactly why they are easy to merge and must not be
// (PRD 5.4b). An amount here can still be below zero: a correction to an
// overcharge is an ordinary negative line and nothing refuses one.
import Foundation
import SwiftData

extension OvationSchemaV4 {
    @Model
    final class LineItem {
        var id: UUID = UUID()

        /// Declared order within its invoice (L343).
        var sortIndex: Int = 0

        /// What the client reads on the line.
        var summary: String = ""

        /// Hours, for a line charged by time. Nil for a flat charge.
        var hours: Hours?

        /// The rate where the line is hourly, and the whole charge where it is flat.
        var unitAmount: Money = Money.zero

        /// Which service type this is, where one was chosen. The type carries the
        /// name Dan gives it; the role on it is what code switches on.
        var serviceType: ServiceType?

        /// Which shoot this line is for, where it is for one at all.
        ///
        /// SETTABLE ONLY BY `hourly(_:at:describedAs:for:)`, which is ovation#431
        /// and is the whole of that fix. PRD 4 says rush turnaround and preview
        /// images belong to the invoice rather than to a shoot, and Dan chose that
        /// again on 2026-09-19 when it was put to him as a choice. It was written
        /// in two docstrings and enforced by nothing (L407), and a flat charge that
        /// reached a shoot was priced as hours times `unitAmount`: $150 of rush
        /// turnaround on a three hour shoot came to $450 on an invoice that
        /// totalled correctly against its own parts (L161).
        ///
        /// REFUSED BY CONSTRUCTION RATHER THAN DETECTED, because the two states are
        /// identical in the data. An hourly line whose shoot's times have been
        /// cleared carries no hours either, so a check asking "no hours and a
        /// shoot" accuses the ordinary waiting draft (measured here, 2026-09-19:
        /// the first version of this fix did exactly that and its own test caught
        /// it). There is no predicate that tells them apart, so there is no
        /// predicate: `flat` takes no shoot and none can be assigned afterwards.
        private(set) var shoot: Shoot?

        var invoice: Invoice?

        private init(summary: String, hours: Hours?, unitAmount: Money) {
            self.summary = summary
            self.hours = hours
            self.unitAmount = unitAmount
        }

        /// A line charged by time at a rate, for a shoot where it is for one.
        ///
        /// THE SHOOT IS TAKEN HERE AND NOWHERE ELSE, so that the only line able to
        /// name one is a line charged by time (ovation#431).
        static func hourly(hours: Hours, at rate: Money, describedAs summary: String,
                           for shoot: Shoot? = nil) -> LineItem {
            let line = LineItem(summary: summary, hours: hours, unitAmount: rate)
            line.shoot = shoot
            return line
        }

        /// A line charged as one amount, which may be negative.
        ///
        /// IT TAKES NO SHOOT, and that absence is the enforcement rather than an
        /// omission (PRD 4, ovation#431).
        static func flat(_ amount: Money, describedAs summary: String) -> LineItem {
            LineItem(summary: summary, hours: nil, unitAmount: amount)
        }

        /// The hours this line charges for.
        ///
        /// THE SHOOT'S TYPED TIMES WIN WHEREVER THEY EXIST (PRD 51a, ovation#43).
        /// Dan, 2026-09-08: the hours are derived from the shoot's real start and end
        /// times and are never typed, because he always has both at the moment it
        /// matters and a second way in would be a second source of truth for one
        /// number (L544, L384). So a line whose shoot has been timed takes that
        /// figure, and a stored one beside it cannot decide the money.
        ///
        /// A LINE KEEPS ITS OWN HOURS WHERE NO TIMES HAVE BEEN TYPED, which is not a
        /// fallback dressed up as redundancy: the two arms read different sources and
        /// answer for different populations (L326). A QuickBooks row imported under
        /// ovation#68 carries hours and no shoot times, and the design record's own
        /// PDF fixtures are built the same way, because they are generated from a
        /// page that draws the finished document rather than from the screen that
        /// prices one.
        ///
        /// A FLAT CHARGE CANNOT REACH THIS EXPRESSION AT ALL, which is what
        /// ovation#431 changed and why this line is once again just the two arms.
        /// `shoot` is settable only by the hourly factory, so a line with a shoot
        /// is a line charged by time, and `?? hours` is reached only by a line that
        /// has some. A flat one has no shoot and no hours and never gets here.
        ///
        /// CLEARING A SHOOT'S TIMES CLEARS THE HOURS BESIDE THEM, in the same write
        /// (`Invoice.clearTimes(of:)`, Dan's decision on 2026-09-19). Without that
        /// this expression would fall through to a stored figure that appears on no
        /// screen once the times producing it were taken away (L46, L544), and the
        /// reader cannot tell that case from an imported row, which is why the
        /// writer settles it.
        var billedHours: Hours? { shoot?.billedHours ?? hours }

        /// What this line comes to.
        var amount: Money {
            guard let billedHours else { return unitAmount }
            return Money.charge(for: billedHours, at: unitAmount)
        }
    }
}

/// What KIND of charge a service type is, in code's own vocabulary.
///
/// The NAME of a service type is Dan's and he can add one from inside an invoice
/// without going to settings first (PRD 5.4). The role is not: code has to know
/// which type is the hourly photography line and which is the referral credit,
/// and keying that off a name a person can rename is how a rename silently
/// changes behaviour (L15).
/// THERE IS NO `referralCredit` ROLE, and its removal is ovation#126 rather than
/// an omission. It existed so code could tell which LINE was the credit, and
/// round 6 of ovation#111 took the credit out of the lines: nothing is left for
/// it to identify. Kept, it would be a value a picker still offers and a branch
/// nothing can reach, which a docstring would in time turn into a decision
/// nobody revisits (L29, L346).
enum ServiceRole: String, CaseIterable, Codable, Hashable, Sendable {
    case hourlyPhotography = "hourly-photography"
    case ordinary = "ordinary"
}

extension OvationSchemaV4 {
    @Model
    final class ServiceType {
        var id: UUID = UUID()
        var name: String = ""
        var role: ServiceRole = ServiceRole.ordinary
        /// What it charges by default, where it has one. A rate for an hourly type,
        /// an amount for a flat one.
        var defaultUnitAmount: Money?
        /// Retired rather than deleted, because invoices already sent refer to it and
        /// Ovation deletes nothing automatically (PRD 5.30).
        var retiredOn: BusinessDate?

        init(name: String, role: ServiceRole, defaultUnitAmount: Money?) {
            self.name = name
            self.role = role
            self.defaultUnitAmount = defaultUnitAmount
        }

    // PRD 5.4's STARTING LIST IS IN `ServiceTypeSeed.swift`, beside the seeder that
    // writes it, and it got there the moment there was something to call it
    // (ovation#107). It was written here during ovation#60 and removed in the same
    // change, because nothing seeded a store then and a seeder nothing calls is dead
    // code that a docstring turns into a decision nobody revisits (L29, L346).
    }
}

// THE NAME THE REST OF THE APP USES (ovation#134). The type belongs to a
// schema VERSION, because a version has to be able to describe a shape that
// is no longer current. Everything outside the store speaks about the shape
// in force, so it says the bare name and this is what points that name at the
// version in force. When a newer version exists, this line moves to it and
// every call site is already correct.
typealias LineItem = OvationSchemaV4.LineItem
typealias ServiceType = OvationSchemaV4.ServiceType

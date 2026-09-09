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

extension OvationSchemaV1 {
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

        /// Which shoot this line is for, where it is for one at all. Rush turnaround
        /// and preview images belong to the invoice rather than to a shoot.
        var shoot: Shoot?

        var invoice: Invoice?

        private init(summary: String, hours: Hours?, unitAmount: Money) {
            self.summary = summary
            self.hours = hours
            self.unitAmount = unitAmount
        }

        /// A line charged by time at a rate.
        static func hourly(hours: Hours, at rate: Money, describedAs summary: String) -> LineItem {
            LineItem(summary: summary, hours: hours, unitAmount: rate)
        }

        /// A line charged as one amount, which may be negative.
        static func flat(_ amount: Money, describedAs summary: String) -> LineItem {
            LineItem(summary: summary, hours: nil, unitAmount: amount)
        }

        /// What this line comes to.
        var amount: Money {
            guard let hours else { return unitAmount }
            return Money.charge(for: hours, at: unitAmount)
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

extension OvationSchemaV1 {
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
// version in force. When a version 2 exists, this line moves to it and every
// call site is already correct.
typealias LineItem = OvationSchemaV1.LineItem
typealias ServiceType = OvationSchemaV1.ServiceType

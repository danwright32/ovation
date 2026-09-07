// ovation#60, PRD 5.4. One charge on an invoice.
//
// THE AMOUNT IS COMPUTED, NEVER STORED. PRD 5.42 requires that no sequence of
// line items can make the sum of parts disagree with the stored total, and the
// cheapest way to guarantee that is to have no second copy of the number: the
// inputs are stored and the amount is arithmetic over them (L107).
//
// A REFERRAL CREDIT IS A NEGATIVE LINE, so an amount here can be below zero, and
// a subtotal can be too. A DISCOUNT IS NOT A LINE and lives on the invoice: the
// two net to the same tax, which is exactly why they are easy to merge and must
// not be (PRD 5.4b).
import Foundation
import SwiftData

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

    /// A line charged as one amount, which may be negative for a referral credit.
    static func flat(_ amount: Money, describedAs summary: String) -> LineItem {
        LineItem(summary: summary, hours: nil, unitAmount: amount)
    }

    /// What this line comes to.
    var amount: Money {
        guard let hours else { return unitAmount }
        return Money.charge(for: hours, at: unitAmount)
    }
}

/// What KIND of charge a service type is, in code's own vocabulary.
///
/// The NAME of a service type is Dan's and he can add one from inside an invoice
/// without going to settings first (PRD 5.4). The role is not: code has to know
/// which type is the hourly photography line and which is the referral credit,
/// and keying that off a name a person can rename is how a rename silently
/// changes behaviour (L15).
enum ServiceRole: String, CaseIterable, Codable, Hashable, Sendable {
    case hourlyPhotography = "hourly-photography"
    case referralCredit = "referral-credit"
    case ordinary = "ordinary"
}

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

    /// PRD 5.4's proposed starting list. It is a STARTING list rather than the
    /// vocabulary: Dan adds to it from inside an invoice, so this seeds an empty
    /// store and is never consulted again.
    static func startingList() -> [ServiceType] {
        [
            ServiceType(name: "Photography", role: .hourlyPhotography,
                        defaultUnitAmount: Money(dollars: 250)),
            ServiceType(name: "Rush turnaround", role: .ordinary, defaultUnitAmount: nil),
            ServiceType(name: "Preview images", role: .ordinary, defaultUnitAmount: nil),
            ServiceType(name: "Referral credit", role: .referralCredit, defaultUnitAmount: nil),
        ]
    }
}

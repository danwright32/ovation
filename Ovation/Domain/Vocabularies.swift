// ovation#60. The closed lists the store holds, each one enumerable.
//
// A VOCABULARY THAT EXISTS IN CODE IS A PICKER AND NEVER A TEXT BOX (L611). A
// free text field for one of these offers every typo as an option and reports
// none of them, and the only symptom is a total that is one row short. Each list
// below is `CaseIterable`, so the screen that offers it, the export that maps it
// and the tests that check it all derive from this one place rather than keeping
// three copies in step by hand (L41).
//
// EACH ONE STORES AS AN EXPLICIT STRING. The raw values are written out rather
// than left to the compiler's default, because the default is the case name and
// renaming a case would then silently rewrite seven years of stored rows.
//
// COMPLETENESS IS ENFORCED BY THE COMPILER. Every property below switches over
// the whole list with no default branch, so adding a case fails the build rather
// than landing somewhere plausible (L113, PRD 5.2a, 5.19a).
//
// DELIBERATELY NOT HERE: the Schedule C map (ovation#62), the asset and duplicate
// flags (ovation#82), and the cleared step's own workflow (ovation#48). This file
// holds what each value IS, not what any one milestone does with it.
import Foundation

/// What an invoice is for. PRD 5.2a, added so print sales and licensing can be
/// totalled apart from Dan's time, and PRD 5.2c, because whether a printed
/// photograph is taxed like his time is the accountant's question and the answer
/// branches on this.
enum InvoiceKind: String, CaseIterable, Codable, Hashable, Sendable {
    case photography = "photography"
    case printSale = "print-sale"
    case licensing = "licensing"
    case other = "other"

    /// NOT A DEFAULT AND NOT AN ERROR. PRD 5.2b: a QuickBooks row carries no such
    /// field, and defaulting those rows to photography would assert a fact nobody
    /// ever recorded, in the direction that reads as complete. Every row filled,
    /// nothing to chase, the gap invisible (L192, L548). It is a real value, it is
    /// visible, and any figure computed per kind can say how much of the money it
    /// could not place.
    case notRecorded = "not-recorded"

    /// The kind an invoice drafted from a Downbeat booking takes without being
    /// asked, because that is the whole population where the answer is obvious.
    static let fromABooking = InvoiceKind.photography

    /// The kind an imported row takes. Separate from `fromABooking` so the two
    /// cannot be made equal by a later edit without a test going red.
    static let fromAnImport = InvoiceKind.notRecorded

    /// Whether this kind says anything about what the money was for.
    var wasRecorded: Bool {
        switch self {
        case .photography, .printSale, .licensing, .other: return true
        case .notRecorded: return false
        }
    }

    /// How the kind appears in its own column in income.csv (PRD 5.25a).
    var exportLabel: String {
        switch self {
        case .photography: return "Photography"
        case .printSale: return "Print sale"
        case .licensing: return "Licensing"
        case .other: return "Other"
        case .notRecorded: return "Not recorded"
        }
    }
}

/// How money arrived. PRD 5.15.
enum PaymentMethod: String, CaseIterable, Codable, Hashable, Sendable {
    case check = "check"
    case zelle = "zelle"
    case venmo = "venmo"
    case payPal = "paypal"

    /// Whether this method has a cleared step after it is recorded.
    ///
    /// ONLY A CHECK, and the reason it is a property of the METHOD rather than of
    /// the payment is PRD 5.15's other half: cleared belongs to the payment and
    /// never to an allocation, so one check clears once however many invoices it
    /// settled, and an invoice can never be cleared on its own.
    var gainsAClearedStep: Bool {
        switch self {
        case .check: return true
        case .zelle, .venmo, .payPal: return false
        }
    }

    var exportLabel: String {
        switch self {
        case .check: return "Check"
        case .zelle: return "Zelle"
        case .venmo: return "Venmo"
        case .payPal: return "PayPal"
        }
    }
}

/// What an expense was for. PRD 5.19, Dan's own list.
///
/// The Schedule C line each one maps to is ovation#62, and it is deliberately
/// absent here: the map has to be complete over this enum and enforced by a test,
/// and putting it in the same file would let one edit satisfy both halves.
enum ExpenseCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case gear = "gear"
    case software = "software"
    case travel = "travel"
    case insurance = "insurance"
    case contractLabour = "contract-labour"
    case professionalFees = "professional-fees"
    case marketing = "marketing"
    case meals = "meals"

    var exportLabel: String {
        switch self {
        case .gear: return "Gear"
        case .software: return "Software"
        case .travel: return "Travel"
        case .insurance: return "Insurance"
        case .contractLabour: return "Contract labour"
        case .professionalFees: return "Professional fees"
        case .marketing: return "Marketing"
        case .meals: return "Meals"
        }
    }
}

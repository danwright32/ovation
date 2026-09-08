// ovation#62, PRD 5.19a. Every expense category maps to a Schedule C line, and
// the completeness of that map is enforced by the compiler rather than by
// review.
//
// WHY COMPLETENESS MATTERS HERE MORE THAN IN MOST LOOKUP TABLES. A missing key
// silently takes the default branch, and a default is indistinguishable from a
// deliberate choice (L113). Here the default branch means an expense quietly
// landing on the wrong Schedule C line, or on none, in a document that goes to
// an accountant and then onto a tax return. Adding a category later without
// adding its mapping is exactly the change that gets made in a hurry.
//
// SO THERE IS NO DEFAULT BRANCH. The switch below is exhaustive over
// `ExpenseCategory`, so adding a category fails the BUILD rather than producing
// a wrong return. That is stronger than a test, which is what PRD 5.19a asks
// for: "enforced by a test, not by a default branch". It was seen to fail before
// it was trusted, by adding a case and confirming the compiler refuses.
//
// THE CATEGORIES ARE DAN'S, NOT THE IRS'S, so this map is the translation
// between them. Several categories legitimately share a line, which is fine.
// What is not fine is a category with no line, or a line chosen because it was
// the closest looking one.
//
// TWO MAPPINGS ARE PROVISIONAL AND SAY SO, rather than being settled by default.
// PRD 9.4 (the asset threshold) and 9.5 are two of the questions carried into
// the accountant conversation (ovation#65), and a mapping that depends on an
// unanswered question must be visibly provisional or it becomes settled by
// nobody having looked (L346). A provisional mapping still produces a line, so
// the export works; it carries the question with it so the export can say which
// figures rest on an answer nobody has.
import Foundation

/// The Schedule C (Form 1040) Part II line an expense is reported on.
///
/// The raw value is the LINE NUMBER as the form prints it, because that is what
/// an accountant reads, and `24a` and `24b` are two different lines on one row
/// of the form.
enum ScheduleCLine: String, CaseIterable, Codable, Hashable, Sendable {
    case advertising = "8"
    case contractLabour = "11"
    case depreciation = "13"
    case insurance = "15"
    case legalAndProfessional = "17"
    case officeExpense = "18"
    case supplies = "22"
    case travel = "24a"
    case deductibleMeals = "24b"
    case otherExpenses = "27a"

    /// What the form calls it, so the CSV reads the way the form does.
    var title: String {
        switch self {
        case .advertising: return "Advertising"
        case .contractLabour: return "Contract labor"
        case .depreciation: return "Depreciation and section 179"
        case .insurance: return "Insurance (other than health)"
        case .legalAndProfessional: return "Legal and professional services"
        case .officeExpense: return "Office expense"
        case .supplies: return "Supplies"
        case .travel: return "Travel"
        case .deductibleMeals: return "Deductible meals"
        case .otherExpenses: return "Other expenses"
        }
    }

    /// How it appears in a column: the number and the title together, because
    /// either alone makes the reader look up the other.
    var exportLabel: String { "\(rawValue) \(title)" }
}

/// A category's line, and whether anybody has confirmed it.
enum ScheduleCMapping: Equatable, Hashable, Sendable {
    /// The line is unambiguous and nobody needs to be asked.
    case settled(ScheduleCLine)
    /// The line is the best available answer and it rests on a question that has
    /// not been answered. It still produces a line, so the export works, and it
    /// carries the question so the export can say what rests on it.
    case provisional(ScheduleCLine, pending: String)

    var line: ScheduleCLine {
        switch self {
        case .settled(let line), .provisional(let line, _): return line
        }
    }

    var isProvisional: Bool {
        switch self {
        case .settled: return false
        case .provisional: return true
        }
    }

    var pendingQuestion: String? {
        switch self {
        case .settled: return nil
        case .provisional(_, let pending): return pending
        }
    }
}

extension ExpenseCategory {

    /// Where this category is reported. EXHAUSTIVE, with no default branch, so a
    /// category added without a mapping stops the build.
    var scheduleC: ScheduleCMapping {
        switch self {
        case .marketing:
            return .settled(.advertising)
        case .contractLabour:
            return .settled(.contractLabour)
        case .insurance:
            // Line 15 is business insurance: equipment, liability. Health
            // insurance is not this category and is not reported here at all,
            // which is worth stating because the line's own title says so and a
            // reader may wonder where it went.
            return .settled(.insurance)
        case .professionalFees:
            return .settled(.legalAndProfessional)
        case .travel:
            return .settled(.travel)
        case .meals:
            // 24b is its own line for a reason: meals are deductible at a
            // different rate from everything above, so folding them into travel
            // would change the return.
            return .settled(.deductibleMeals)

        case .gear:
            // PROVISIONAL, and the reason is PRD 9.4, which is Dan's accountant's
            // to answer (ovation#65). Gear below the threshold is Supplies; gear
            // above it is Depreciation and section 179. $2,500 is the IRS de
            // minimis safe harbour, but the PRD records that it is an ELECTION
            // made on the return and that Section 179 may make it moot, so
            // neither the threshold nor which line applies is settled.
            //
            // It maps to Supplies as the working answer because that is where
            // the ordinary case lands, and PRD 5.20 flags a purchase above the
            // threshold as a LIKELY asset rather than determining it. The asset
            // FLAG (ovation#82) is what moves an individual expense to line 13,
            // so this is a category default that a per expense flag overrides,
            // never the last word.
            return .provisional(.supplies, pending: "PRD 9.4, the asset threshold: "
                + "gear above it is Depreciation and section 179 (line 13) rather than "
                + "Supplies (line 22). The threshold is an election made on the return and "
                + "Section 179 may make it moot, and Ovation sees a receipt TOTAL where the "
                + "threshold is per item.")

        case .software:
            // PROVISIONAL. A subscription and a purchased licence are not
            // obviously the same line: Office expense (18) and Other expenses
            // (27a) are both defensible, and accountants differ. Office expense
            // is the working answer because that is where most photographers'
            // software lands, and it is marked so the accountant can move it in
            // one place rather than being asked to notice it.
            return .provisional(.officeExpense, pending: "whether software subscriptions belong "
                + "on Office expense (line 18) or Other expenses (line 27a). Both are "
                + "defensible and this has not been asked.")
        }
    }
}

enum ScheduleCMap {

    /// Every category and where it goes, in the enum's own order.
    ///
    /// DERIVED FROM `allCases`, never a second list beside the switch, so the map
    /// and the vocabulary cannot disagree about what exists (L41).
    static var all: [(category: ExpenseCategory, mapping: ScheduleCMapping)] {
        ExpenseCategory.allCases.map { ($0, $0.scheduleC) }
    }

    /// The categories whose line rests on a question nobody has answered.
    ///
    /// It exists so the export can SAY which figures are provisional rather than
    /// leaving the accountant to discover it, and so the count can be asserted:
    /// a provisional mapping that quietly becomes settled because somebody
    /// removed the marker is the failure this whole shape guards against.
    static var provisional: [(category: ExpenseCategory, pending: String)] {
        all.compactMap { entry in
            entry.mapping.pendingQuestion.map { (entry.category, $0) }
        }
    }
}

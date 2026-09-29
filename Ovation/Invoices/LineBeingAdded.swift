// ovation#489, PRD 51p to 51t. A line being added on the invoice, as one value.
//
// ONE VALUE, AND AN OPTIONAL ONE ON THE SCREEN. No row, a row with no type yet,
// and a row with a type are three states, and they were two pieces of `@State`
// on the screen (a flag and an optional type) plus a third in the row (whether
// its list was open). Escape has to know about all three at once to decide
// whether it closes the list or the line, so they live together, and "no row"
// is the screen holding nil rather than a flag beside a value (L544).
//
// IT IS A VALUE RATHER THAN A VIEW'S STATE so that every rule Dan settled on
// 2026-09-29 is a case a test can produce. A view tree test cannot press a word
// and then see what a view's `@State` did with it (L442).
import Foundation
import SwiftData

struct LineBeingAdded: Equatable {

    /// The type chosen, or nil while it is still being chosen.
    private(set) var chosen: InvoiceScreenPresenter.ServiceChoice?
    /// What is in the amount field.
    var amount = ""
    /// Whether the list of types is showing.
    var listIsOpen = false

    /// What an Escape did.
    enum AfterEscape: Equatable {
        case listClosed
        /// The line is gone, and the screen drops it.
        case lineCancelled
    }

    /// Chooses a type, or chooses again.
    ///
    /// THE AMOUNT GOES WITH THE OLD TYPE ONLY WHILE IT IS STILL THAT TYPE'S USUAL
    /// ONE (Dan, 2026-09-29, PRD 51r). An amount that came from the old type was never
    /// Dan's figure, and keeping it would price the new line at the wrong type's
    /// rate; an amount he typed himself is his, and changing the type is no
    /// reason to throw it away.
    mutating func choose(_ type: InvoiceScreenPresenter.ServiceChoice) {
        if amountIsStillTheUsual { amount = Self.prefill(for: type) }
        chosen = type
        listIsOpen = false
    }

    /// Whether the field still holds what the type in force would put there.
    ///
    /// COMPARED AS AMOUNTS, not as text, so retyping `150.00` as `150` is still the
    /// usual amount. With no usual amount, or no type yet, the usual is an empty
    /// field, so an amount typed before the type was chosen counts as Dan's.
    private var amountIsStillTheUsual: Bool {
        guard let usual = chosen?.usually else {
            return amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return Money.read(amount) == usual
    }

    /// What Escape does: THE LIST FIRST, THEN THE LINE (Dan, 2026-09-29, PRD 51s), which is
    /// the order a person backs out of anything, the innermost thing first.
    mutating func escape() -> AfterEscape {
        guard listIsOpen else { return .lineCancelled }
        listIsOpen = false
        return .listClosed
    }

    /// The line to write, or nil where there is nothing writable yet.
    ///
    /// AN AMOUNT IT CANNOT READ WRITES NOTHING, rather than a line worth nothing
    /// that would be indistinguishable from a comped one (PRD 5.1b), and the row
    /// stays where it is.
    var written: (type: PersistentIdentifier, amount: Money)? {
        guard let chosen, let figure = Money.read(amount) else { return nil }
        return (chosen.id, figure)
    }

    /// Whether leaving the amount field commits the line.
    ///
    /// NOT WHILE THE ROW'S OWN LIST IS OPEN. The list opens from this row, and a
    /// blur that committed there would write the line at the moment Dan was
    /// changing its type, which would make PRD 51r unreachable through PRD
    /// 51q. Leaving for anywhere else commits a readable amount.
    var leavingTheFieldCommits: Bool { !listIsOpen }

    /// What the amount field starts at when a type is chosen.
    ///
    /// A TYPE WITH NO USUAL AMOUNT LEAVES IT EMPTY, never a zero: the design
    /// record says in terms that a type charging nothing and a type with no usual
    /// amount are different things, and one of them would prefill every line it
    /// is used on with 0.00 (PRD 5.1b).
    static func prefill(for type: InvoiceScreenPresenter.ServiceChoice) -> String {
        type.usually.map(PDFText.amount) ?? ""
    }
}

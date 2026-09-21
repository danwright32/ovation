// ovation#461, PRD 3 and PRD 5.7. The two numbers every draft is created with.
//
// BOTH WERE MISSING UNTIL SOMETHING HAD TO MAKE A DRAFT. Measured 2026-09-21:
// nothing in production decided an hourly rate, and nothing anywhere derived a
// due date, though `Invoice.dueDate` has cited PRD 5.7 since it was written. A
// requirement with no code behind it is a requirement nobody is keeping (L46).
//
// ONE PUBLISHED NUMBER, NOT A LITERAL AT EACH CALL SITE. A second copy is how
// two invoices come to be priced differently for no reason anybody chose, and
// the rate is stored ON the invoice at creation, so a change here can never
// reprice an invoice that already exists.
import Foundation

enum Pricing {

    /// PRD 3, as corrected on 2026-09-08 by ovation#127. "Pricing is $250 per
    /// hour, exact to the QUARTER hour, with a one hour minimum."
    ///
    /// THERE IS NO PER CLIENT RATE and this is not an oversight: the requirement
    /// states one rate for the product, and a rate that varied per client would
    /// need a surface to set it on and a rule for which one wins. Where that
    /// changes, this constant is where the question arrives.
    static let standardHourlyRate = Money(dollars: 250)
}

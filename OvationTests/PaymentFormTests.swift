import Foundation
import Testing

/// ovation#510, PRD 51m. The payment sheet's rules, reached without a window.
@MainActor
struct PaymentFormTests {

    /// 2026-09-26 in New York.
    private static let today = BusinessDate.stamping(Date(timeIntervalSince1970: 1_790_438_400))

    private static func form() -> PaymentForm {
        PaymentForm(starting: .init(amount: "408.28", received: today, method: .zelle))
    }

    @Test("it opens at what is owed, today and Zelle, and a press records exactly that")
    func itOpensAtTheStart() throws {
        let form = Self.form()
        #expect(form.amount == "408.28")
        #expect(form.received == "26 Sep 2026")
        #expect(form.method == .zelle)
        #expect(!form.changed)
        let press = UUID()
        let entry = try #require(form.entry(press: press))
        #expect(entry.amount == Money(cents: 40_828))
        #expect(entry.method == .zelle)
        #expect(entry.press == press)
        // THE DAY, not the instant: a date read back from "26 Sep 2026" is that
        // day's start, and today was stamped at noon. The day is the fact.
        #expect(entry.received.dayKey == Self.today.dayKey)
    }

    @Test("changing any one of the three is a change, and putting it back is not")
    func changesAreMeasuredFromTheStart() {
        var form = Self.form()
        form.amount = "200"
        #expect(form.changed)
        form.amount = "408.28"
        #expect(!form.changed)
        form.method = .check
        #expect(form.changed)
        form.method = .zelle
        form.received = "25 Sep 2026"
        #expect(form.changed)
    }

    @Test("an amount it cannot read, or none, leaves Record unavailable and says so",
          arguments: ["", "  ", "twelve", "0", "0.00", "-5"])
    func anUnreadableAmount(_ typed: String) {
        var form = Self.form()
        form.amount = typed
        #expect(form.whyNot == "Needs an amount.")
        #expect(form.entry(press: UUID()) == nil)
    }

    @Test("a date it cannot read, including a day the month does not have, is refused",
          arguments: ["", "31 Sep 2026", "Sep 26", "26/09/2026"])
    func anUnreadableDate(_ typed: String) {
        var form = Self.form()
        form.received = typed
        #expect(form.whyNot == "Needs a date like 26 Sep 2026.")
        #expect(form.entry(press: UUID()) == nil)
    }

    @Test("a typed payment is read the way every figure and date on the screen is")
    func atypedPayment() throws {
        var form = Self.form()
        form.amount = "$200"
        form.received = "24 Sep 2026"
        form.method = .check
        let entry = try #require(form.entry(press: UUID()))
        #expect(entry.amount == Money(dollars: 200))
        #expect(entry.received.dayKey == "2026-09-24")
        #expect(entry.method == .check)
    }
}

import Foundation
import SwiftData
import Testing

/// ovation#500. The app's invoice money held to the DESIGN RECORD'S OWN cases.
///
/// `docs/design/rules/money.cases.js` holds the worked examples of how an
/// invoice's figures combine: the referral credit inside the subtotal, the
/// discount on what is left, the tax on that. `scripts/test-design-rules.sh`
/// runs them against the design's `money.js`, and until this suite nothing ran
/// them against the app, whose arithmetic was tested by cases written separately.
/// Two implementations each tested by cases of their own agree on the day they
/// are written and then drift (L26), so this reads the design file itself rather
/// than restating its figures (L638).
///
/// THE CREDIT GOES THROUGH THE WRITER, because that is where the app caps it:
/// `InvoiceReferralCreditWriter` spends the smaller of the banked balance and
/// `ReferralCredit.mostThatFits`, and `Invoice` only adds up what it is given.
/// Asserting over `Invoice` alone would have to restate the cap here, which is
/// the rule under test. The balance is earned through the ledger for the same
/// reason the writer's own suite does it: it is a sum over the log (L48).
@MainActor
struct DesignMoneyCasesTests {

    private struct Expect: Decodable {
        let credit: Decimal; let subtotal: Decimal; let discount: Decimal
        let tax: Decimal; let total: Decimal
    }
    private struct MoneyCase: Decodable {
        let lines: Decimal; let rate: Decimal; let balanceHundredths: Int64
        let kind: String?; let value: Decimal?
        let expect: Expect; let why: String
    }

    /// Located from this file, never from the working directory (L372).
    private static func cases(_ file: StaticString = #filePath) throws -> [MoneyCase] {
        let url = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/design/rules/money.cases.js")
        let text = try String(contentsOf: url, encoding: .utf8)
        // THE TABLE IS STRICT JSON between its declaration and the line closing
        // it, which the design file states in its own header. A missing anchor is
        // a refusal, never an empty table (L98).
        let opening = try #require(text.range(of: "var MONEY_CASES = ["),
                                   "money.cases.js no longer declares MONEY_CASES")
        let closing = try #require(text.range(of: "\n];", range: opening.upperBound..<text.endIndex),
                                   "MONEY_CASES has no closing line")
        let json = "[" + text[opening.upperBound..<closing.lowerBound] + "]"
        return try JSONDecoder().decode([MoneyCase].self, from: Data(json.utf8))
    }

    private static func money(_ dollars: Decimal) -> Money {
        Money(cents: NSDecimalNumber(decimal: dollars * 100).int64Value)
    }

    @Test("the design's money cases are read and hold something, so the test below runs over them")
    func theDesignCasesAreThere() throws {
        let cases = try Self.cases()
        #expect(cases.count >= 9)
        #expect(cases.contains { $0.balanceHundredths == 0 }, "the no balance refusal is a case too")
        #expect(cases.contains { $0.kind == "percent" } && cases.contains { $0.kind == "amount" })
    }

    @Test("every design money case comes to the same credit, subtotal, discount, tax and total in the app")
    func everyCaseAgrees() async throws {
        let day = try #require(BusinessCalendar.day(forKey: "2026-11-12"))
        for item in try Self.cases() {
            let container = try OvationSchema.container(inMemory: true)
            let context = ModelContext(container)
            let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
            context.insert(client)
            let invoice = Invoice(client: client, kind: .photography, invoiceDate: day,
                                  hourlyRate: Self.money(item.rate), taxRate: .newYorkCity,
                                  createdOn: nil)
            invoice.add(LineItem.flat(Self.money(item.lines), describedAs: "Photography"))
            context.insert(invoice)
            try context.save()

            let writer = InvoiceReferralCreditWriter(modelContainer: container)
            if item.balanceHundredths > 0 {
                try await ReferralLedger(modelContainer: container)
                    .earn(Hours(hundredths: item.balanceHundredths), for: client.persistentModelID,
                          fromBooking: "cedar-hill-2026-10-01", on: day)
                try await writer.applyReferralCredit(on: invoice.persistentModelID, on: day)
            } else {
                // NO BALANCE IS A REFUSAL IN THE APP, and the design's zero credit
                // is what that refusal leaves on the invoice.
                await #expect(throws: InvoiceReferralCreditRefusal.noCreditToSpend, "\(item.why)") {
                    try await writer.applyReferralCredit(on: invoice.persistentModelID, on: day)
                }
            }

            let read = try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
                .first { $0.persistentModelID == invoice.persistentModelID })
            switch item.kind {
            case "percent":
                let value = try #require(item.value)
                read.discount = try #require(Discount(
                    percentBasisPoints: NSDecimalNumber(decimal: value * 100).int64Value))
            case "amount":
                read.discount = try #require(Discount(dollars: Self.money(try #require(item.value))))
            case nil:
                break
            default:
                Issue.record("an unknown discount kind \(item.kind ?? "") in the design's cases")
            }

            #expect(read.referralCreditAmount == Self.money(item.expect.credit), "credit: \(item.why)")
            #expect(read.subtotal == Self.money(item.expect.subtotal), "subtotal: \(item.why)")
            #expect(read.discountAmount == Self.money(item.expect.discount), "discount: \(item.why)")
            #expect(read.tax == Self.money(item.expect.tax), "tax: \(item.why)")
            #expect(read.total == Self.money(item.expect.total), "total: \(item.why)")
        }
    }
}

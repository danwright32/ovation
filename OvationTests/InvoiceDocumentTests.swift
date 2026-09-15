import Foundation
import SwiftData
import Testing

/// ovation#167, PRD 50 to 50f. WHAT THE INVOICE PDF SAYS, before anything is drawn.
///
/// THE EXPECTATION IS THE DESIGN'S OWN TEXT. `docs/design/invoice-pdf.expected.json`
/// is what the settled page draws for its seven fixture invoices, written by
/// `scripts/build-invoice-pdf-text.sh` from a rendering of `invoice-pdf.html`, and a
/// test asserting agreement with a design has to read the design (L638).
///
/// THE INVOICES ARE BUILT FROM THE SAME FILE. Each fixture carries the input the
/// design builds it from, so this test holds no second copy of the fixtures to drift
/// from the first (L26). What it asserts is that the app, given what the design was
/// given, writes what the design wrote.
struct InvoiceDocumentTests {

    // MARK: the committed expectation

    private struct Line: Decodable {
        let kind: String
        let shoot: String?
        let venue: String?
        let date: String?
        let hours: Double?
        let rate: Double?
        let amount: Double
    }
    private struct Given: Decodable {
        let number: String
        let issued: String
        let due: String
        let client: String
        let exempt: Bool
        let discount: [String: Double]?
        let credit: Double?
        /// Money already applied to the invoice (PRD 14k).
        let paid: Double?
        let lines: [Line]
    }
    private struct Head: Decodable { let label: String; let amount: String; let due: String }
    private struct Fixture: Decodable {
        let label: String
        let input: Given
        let head: Head
        let strip: [[String]]
        let title: String
        let columns: [String]
        let items: [[String]]
        let money: [[String]]
        let foot: [FootBlock]
    }
    /// `["Payment", ["one line", "another"]]` in the file.
    private struct FootBlock: Decodable {
        let label: String
        let lines: [String]
        init(from decoder: Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            label = try pair.decode(String.self)
            lines = try pair.decode([String].self)
        }
    }
    private struct Expected: Decodable { let fixtures: [Fixture] }

    /// Located from this file, never from the working directory (L372).
    private static func expected(_ file: StaticString = #filePath) throws -> [Fixture] {
        let repository = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository.appending(path: "docs/design/invoice-pdf.expected.json")
        return try JSONDecoder().decode(Expected.self, from: Data(contentsOf: url)).fixtures
    }

    // MARK: building an invoice from a fixture's input

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    private static func cents(_ dollars: Double) -> Int64 { Int64((dollars * 100).rounded()) }

    /// "December 5, 2026" as noon on that day in New York, so the business day is
    /// that day whatever the host's zone (L39).
    private static func businessDate(_ written: String) throws -> BusinessDate {
        let months = ["January", "February", "March", "April", "May", "June", "July",
                      "August", "September", "October", "November", "December"]
        let words = written.replacingOccurrences(of: ",", with: "").split(separator: " ")
        let month = try #require(words.count == 3 ? months.firstIndex(of: String(words[0])) : nil,
                                 "\(written) is not a date the fixtures write")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let components = DateComponents(year: Int(words[2]), month: month + 1, day: Int(words[1]), hour: 12)
        return .stamping(try #require(calendar.date(from: components)))
    }

    private static func invoice(from given: Given, in context: ModelContext) throws -> Invoice {
        let client = Client(name: given.client, taxStatus: given.exempt ? .exempt : .notExempt)
        context.insert(client)
        let rate = Money(dollars: 250)
        let invoice = Invoice(client: client, kind: .fromABooking,
                              invoiceDate: try businessDate(given.issued),
                              hourlyRate: rate, taxRate: .newYorkCity)
        context.insert(invoice)
        invoice.number = try #require(Int64(given.number))
        invoice.dueDate = try businessDate(given.due)
        if let percent = given.discount?["percent"] {
            invoice.discount = Discount(percentBasisPoints: Int64((percent * 100).rounded()))
        } else if let amount = given.discount?["amount"] {
            invoice.discount = Discount(dollars: Money(cents: cents(amount)))
        }
        if let credit = given.credit {
            // Earned in hours at the invoice's rate. The fixtures' credits are whole
            // multiples of it, and a fixture that is not cannot be expressed.
            let hundredths = cents(credit) * 100 / rate.cents
            #expect(hundredths * rate.cents == cents(credit) * 100, "a credit the rate cannot express")
            invoice.referralCredit = ReferralCredit(hours: Hours(hundredths: hundredths), at: rate,
                                                    earnedFrom: nil)
        }
        for line in given.lines {
            let item: LineItem
            if let hours = line.hours, let lineRate = line.rate {
                item = LineItem.hourly(hours: Hours(hundredths: cents(hours)),
                                       at: Money(cents: cents(lineRate)), describedAs: line.kind)
            } else {
                item = LineItem.flat(Money(cents: cents(line.amount)), describedAs: line.kind)
            }
            if let name = line.shoot {
                let date = try line.date.map { try businessDate($0) }
                let shoot = Shoot(name: name, when: date.map { .dayOnly($0) }, venue: line.venue)
                invoice.add(shoot)
                item.shoot = shoot
            }
            invoice.add(item)
        }
        if let paid = given.paid {
            // Applied the only way the app records it: a payment from the client and
            // one allocation of it to this invoice.
            let received = try businessDate(given.issued)
            let payment = Payment(client: client, amount: Money(cents: cents(paid)),
                                  method: .zelle, receivedOn: received)
            context.insert(payment)
            let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                               amount: Money(cents: cents(paid)), allocatedOn: received)
            context.insert(allocation)
            payment.allocations.append(allocation)
            invoice.allocations.append(allocation)
            #expect(invoice.amountPaid == Money(cents: cents(paid)), "the payment reached the invoice")
        }
        return invoice
    }

    // MARK: agreement with the design

    @Test("all seven design fixtures are read, so no comparison below runs over nothing")
    func theFixturesAreThere() throws {
        #expect(try Self.expected().count == 7)
    }

    @Test("each fixture's page says what the settled design draws, section by section")
    func eachFixtureSaysWhatTheDesignDraws() throws {
        for fixture in try Self.expected() {
            let context = try Self.store()
            let document = try InvoiceDocument(invoice: try Self.invoice(from: fixture.input, in: context),
                                               footer: .fixed)
            let name = fixture.label
            #expect(document.amountDueLabel == fixture.head.label, "\(name): the amount due label")
            #expect(document.amountDue == fixture.head.amount, "\(name): the amount due")
            #expect(document.dueLine == fixture.head.due, "\(name): the due line")
            #expect(document.strip == fixture.strip, "\(name): the strip")
            #expect(document.title == fixture.title, "\(name): the title")
            #expect(document.columns == fixture.columns, "\(name): the columns")
            #expect(document.items == fixture.items, "\(name): the lines, cell by cell and in order")
            #expect(document.money == fixture.money, "\(name): the money rows, in order")
            #expect(document.foot.map(\.label) == fixture.foot.map(\.label), "\(name): the footer blocks")
            #expect(document.foot.map(\.lines) == fixture.foot.map(\.lines), "\(name): the footer text")
        }
    }

    // MARK: refusals, each by name (L11, L100)

    private static func ordinary(_ context: ModelContext) throws -> Invoice {
        let fixture = try #require(try expected().first { $0.label == "Ordinary" })
        return try invoice(from: fixture.input, in: context)
    }

    private static func refusal(_ invoice: Invoice) -> InvoiceDocument.Refusal? {
        do {
            _ = try InvoiceDocument(invoice: invoice, footer: .fixed)
            return nil
        } catch let refusal as InvoiceDocument.Refusal {
            return refusal
        } catch {
            return nil
        }
    }

    @Test("an invoice with no number is refused, because the number is printed on what ships")
    func noNumberIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.number = nil
        #expect(Self.refusal(invoice) == .noNumber)
    }

    @Test("an invoice with no date is refused rather than printed undated")
    func noInvoiceDateIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.invoiceDate = nil
        #expect(Self.refusal(invoice) == .noInvoiceDate)
    }

    @Test("an invoice with no due date is refused, because the page leads with it")
    func noDueDateIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.dueDate = nil
        #expect(Self.refusal(invoice) == .noDueDate)
    }

    @Test("an invoice with no client is refused, because Bill to would be empty")
    func noClientIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.client = nil
        #expect(Self.refusal(invoice) == .noClient)
    }

    @Test("a discount larger than the subtotal is refused rather than printing a negative amount due")
    func anOversizedDiscountIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.discount = Discount(dollars: Money(dollars: 400))
        #expect(Self.refusal(invoice) == .discountExceedsSubtotal)
    }

    /// Dan, 2026-09-14: the footer's terms count the days between THIS invoice's date
    /// and its due date, because PRD 7 lets a due date move per client or per invoice
    /// and a fixed "14 days" would then contradict the date at the top of the page.
    /// Every design fixture is due in 14, so the moved date is asserted here (L101).
    @Test("a due date moved to 30 days is what the terms say, beside the due date at the top")
    func movedTermsFollowTheDueDate() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.dueDate = try Self.businessDate("November 24, 2026")
        let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
        #expect(document.dueLine == "by November 24, 2026")
        let payment = try #require(document.foot.first { $0.label == "Payment" })
        #expect(payment.lines.contains("Payment due within 30 days of the invoice date."))
        #expect(!payment.lines.contains { $0.contains("14") }, "no line may still state the old term")
    }

    @Test("a due date before the invoice date is refused rather than printed as a negative term")
    func aDueDateBeforeTheInvoiceIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.dueDate = try Self.businessDate("October 24, 2026")
        #expect(Self.refusal(invoice) == .dueBeforeInvoiceDate)
    }

    /// A day key is stored beside its instant, and a store can hold one that is not a
    /// calendar day. Both places a date is written are asserted, because each reaches
    /// the refusal by its own route (L173).
    @Test("a stored date that is not a calendar day is refused, on the invoice or on a shoot")
    func anUnreadableDateIsRefused() throws {
        let nonsense = BusinessDate(storedInstant: Date(timeIntervalSince1970: 1_798_000_000),
                                    storedDayKey: "2026-13-40")

        let undated = try Self.ordinary(try Self.store())
        #expect(Self.refusal(undated) == nil, "the ordinary fixture is a page, so the refusal below is the date's")
        undated.invoiceDate = nonsense
        #expect(Self.refusal(undated) == .unreadableDate)

        let badShoot = try Self.ordinary(try Self.store())
        let shoot = try #require(badShoot.orderedShoots.first)
        shoot.when = .dayOnly(nonsense)
        #expect(Self.refusal(badShoot) == .unreadableDate)
    }

    // MARK: the discount's label

    /// PRD 5.4a: a discount is given as a percentage or an amount, and the page says
    /// which. The six fixtures only reach a whole ten percent, so a share with a
    /// fraction, and an amount, are asserted here where nothing else would (L101).
    /// Labels only, so no rounding of the figures can move what is judged.
    @Test("a percentage discount names its share to the precision given, and an amount names none")
    func theDiscountLabelSaysWhatWasGiven() throws {
        for (discount, label) in [
            (Discount(percentBasisPoints: 1_000), "Discount (10%)"),
            (Discount(percentBasisPoints: 1_250), "Discount (12.5%)"),
            (Discount(percentBasisPoints: 3_333), "Discount (33.33%)"),
            (Discount(dollars: Money(dollars: 50)), "Discount"),
        ] {
            let invoice = try Self.ordinary(try Self.store())
            invoice.discount = try #require(discount)
            let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
            #expect(document.money.contains { $0.first == label }, "expected a row labelled \(label)")
        }
    }

    // MARK: PRD 5b

    /// The warning about an unrecorded status is Dan's and never the client's: the
    /// PDF charges the tax and shows it like any other invoice, and says nothing
    /// about the status.
    @Test("a client whose tax status was never recorded is charged and shown the tax, and told nothing")
    func anUnrecordedStatusChargesTaxSilently() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.client?.taxStatus = .neverRecorded
        let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
        #expect(document.money.contains(["Sales tax (8.875%)", "$22.19"]))
        let everything = ([document.amountDueLabel, document.amountDue, document.dueLine, document.title]
            + document.strip.flatMap { $0 } + document.items.flatMap { $0 }
            + document.money.flatMap { $0 } + document.foot.flatMap { [$0.label] + $0.lines })
            .joined(separator: " ").lowercased()
        #expect(!everything.contains("status"))
        #expect(!everything.contains("recorded"))
        #expect(!everything.contains("exempt"))
    }
}

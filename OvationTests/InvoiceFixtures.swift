import Foundation
import SwiftData
import Testing

/// ovation#167. The design's fixture invoices, built as the app records them.
///
/// ONE BUILDER FOR EVERY SUITE THAT NEEDS THEM. `docs/design/invoice-pdf.expected.json`
/// carries each fixture's input beside the text the design draws for it, and both
/// InvoiceDocumentTests and InvoicePDFRendererTests build their invoices from that
/// input through here. A second copy of this builder would drift from the first,
/// and the renderer would then be judged on invoices the document tests never saw
/// (L26, L370).
enum InvoiceFixtures {

    struct Line: Decodable {
        let kind: String
        let shoot: String?
        let venue: String?
        let date: String?
        let hours: Double?
        let rate: Double?
        let amount: Double
    }

    struct Given: Decodable {
        let number: String
        let issued: String
        let due: String
        let client: String
        let exempt: Bool
        let discount: [String: Double]?
        let credit: Double?
        /// Money already applied to the invoice (PRD 14k).
        let paid: Double?
        /// The day that money arrived, which is NOT the invoice date: a deposit
        /// is taken before the shoot (ovation#326). The receipt head states it.
        let paidOn: String?
        let lines: [Line]
    }

    struct Head: Decodable { let label: String; let amount: String; let due: String }

    struct Fixture: Decodable {
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
    struct FootBlock: Decodable {
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
    static func expected(_ file: StaticString = #filePath) throws -> [Fixture] {
        let repository = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository.appending(path: "docs/design/invoice-pdf.expected.json")
        return try JSONDecoder().decode(Expected.self, from: Data(contentsOf: url)).fixtures
    }

    /// Every fixture's label, in the design's order.
    static var labels: [String] {
        get throws { try expected().map(\.label) }
    }

    /// The fixture with this label, built into `context`.
    static func invoice(_ label: String, in context: ModelContext) throws -> Invoice {
        let fixture = try #require(try expected().first { $0.label == label }, "no design fixture is called \(label)")
        return try invoice(from: fixture.input, in: context)
    }

    static func cents(_ dollars: Double) -> Int64 { Int64((dollars * 100).rounded()) }

    /// "December 5, 2026" as noon on that day in New York, so the business day is
    /// that day whatever the host's zone (L39).
    static func businessDate(_ written: String) throws -> BusinessDate {
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

    static func invoice(from given: Given, in context: ModelContext) throws -> Invoice {
        let client = Client(name: given.client, taxStatus: given.exempt ? .exempt : .notExempt)
        context.insert(client)
        let rate = Money(dollars: 250)
        let invoice = Invoice(client: client, kind: .fromABooking,
                              invoiceDate: try businessDate(given.issued),
                              hourlyRate: rate, taxRate: .newYorkCity, createdOn: nil)
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
            // THE SHOOT IS BUILT FIRST, because a line can only be given one as it
            // is made (ovation#431). It is added to the invoice whether or not a
            // line ends up naming it, exactly as before.
            var shoot: Shoot?
            if let name = line.shoot {
                let date = try line.date.map { try businessDate($0) }
                let made = Shoot(name: name, when: date.map { .dayOnly($0) }, venue: line.venue)
                invoice.add(made)
                shoot = made
            }
            let item: LineItem
            if let hours = line.hours, let lineRate = line.rate {
                item = LineItem.hourly(hours: Hours(hundredths: cents(hours)),
                                       at: Money(cents: cents(lineRate)), describedAs: line.kind,
                                       for: shoot)
            } else {
                // PRD 4: rush turnaround and preview images belong to the invoice, so
                // a fixture pairing a flat charge with a shoot describes a state the
                // product does not have. Said here rather than dropped silently,
                // because a fixture quietly losing its shoot is a fixture that stops
                // testing what it was written for.
                #expect(shoot == nil,
                        "a flat line in a fixture names a shoot, which PRD 4 refuses: \(line.kind)")
                item = LineItem.flat(Money(cents: cents(line.amount)), describedAs: line.kind)
            }
            invoice.add(item)
        }
        if let paid = given.paid {
            // Applied the only way the app records it: a payment from the client and
            // one allocation of it to this invoice.
            //
            // DATED BY `paidOn` WHERE THE DESIGN GIVES ONE, because a deposit
            // arrives BEFORE the shoot and the receipt head states the day the
            // money came in (ovation#326). Falling back to the invoice date keeps
            // every fixture written before that unchanged.
            let received = try businessDate(given.paidOn ?? given.issued)
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
}

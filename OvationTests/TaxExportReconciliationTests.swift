import Foundation
import SwiftData
import Testing

/// ovation#63. Not "did the export write without error" but "is everything that
/// should be in it actually in it".
///
/// THOSE COME APART EXACTLY WHEN IT MATTERS. A fetch that quietly returned fewer
/// rows than the store holds, a row whose day key put it in a neighbouring year,
/// an invoice whose client could not be resolved: each leaves a CSV that is well
/// formed, totals cleanly against its own parts, and is SHORT.
///
/// THE EXPECTATION COMES FROM A DIFFERENT PLACE THAN THE ROWS. Comparing the
/// export against the list that produced it is arithmetically always zero and
/// proves the export self consistent and nothing else (L70). So the export is
/// handed whatever a fetch returned, and the reconciliation is handed the WHOLE
/// store; the rule they apply is one shared predicate (L16) and the POPULATION is
/// what differs. That is what catches a short fetch, which is the failure that
/// ruins January and the one nothing else here can see.
///
/// AND IT READS THE RENDERED ROWS, not the selection. A document built from the
/// right invoices and rendered wrong is still a wrong file.
struct TaxExportReconciliationTests {

    // MARK: the whole point: a short fetch

    @Test("an invoice the export never saw is REPORTED, not balanced away")
    func ashortFetchIsCaught() throws {
        // The export is given two invoices; the store holds three. Every number
        // inside the export agrees with itself, and the file is short by one.
        let world = try World()
        let seen = [world.invoice(dayKey: "2026-03-01", sent: true, number: 1),
                    world.invoice(dayKey: "2026-04-01", sent: true, number: 2)]
        let unseen = world.invoice(dayKey: "2026-05-01", sent: true, number: 3)

        let export = TaxExport.income(from: seen, in: .calendarYear(2026))
        let reconciliation = TaxExportReconciliation.check(
            income: export,
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: seen + [unseen], everyExpense: [],
            everyPayment: [], everyRefund: [])

        #expect(!reconciliation.isComplete)
        #expect(reconciliation.findings.contains(.missingFromIncome(invoiceNumber: 3,
                                                                    dayKey: "2026-05-01")))
        #expect(unseen.number == 3, "the finding names the invoice by its number, not its client")
    }

    @Test("with nothing missing it says so, so a green answer is a measurement")
    func acompleteExportSaysSo() throws {
        // The positive control. A reconciliation that reported a finding on
        // everything would satisfy the test above and be useless (L159, L557).
        let world = try World()
        let invoices = [world.invoice(dayKey: "2026-03-01", sent: true, number: 1),
                        world.invoice(dayKey: "2026-04-01", sent: true, number: 2)]

        let export = TaxExport.income(from: invoices, in: .calendarYear(2026))
        let reconciliation = TaxExportReconciliation.check(
            income: export,
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: invoices, everyExpense: [],
            everyPayment: [], everyRefund: [])

        #expect(reconciliation.isComplete)
        #expect(reconciliation.findings.isEmpty)
    }

    @Test("an expense the export never saw is reported too")
    func ashortExpenseFetchIsCaught() throws {
        let world = try World()
        let seen = world.expense(dayKey: "2026-02-02", amount: Money(dollars: 10))
        let unseen = world.expense(dayKey: "2026-02-03", amount: Money(dollars: 20))

        let expenses = TaxExport.expenses(from: [seen], in: .calendarYear(2026))
        let reconciliation = TaxExportReconciliation.check(
            income: TaxExport.income(from: [], in: .calendarYear(2026)),
            expenses: expenses,
            everyInvoice: [], everyExpense: [seen, unseen],
            everyPayment: [], everyRefund: [])

        #expect(!reconciliation.isComplete)
        #expect(reconciliation.findings.contains(
            .expenseRowsDisagree(expected: 2, found: 1)))
    }

    // MARK: exactly one row, never two

    @Test("one invoice handed in twice is reported as a duplicate row")
    func aduplicatedRowIsCaught() throws {
        // A fetch that joined badly can hand the same invoice back twice, and the
        // file then totals to more income than exists. The count alone would not
        // catch it against a store that also holds two, which is why the rendered
        // rows are read by identity rather than counted (L228).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1)

        let export = TaxExport.income(from: [invoice, invoice], in: .calendarYear(2026))
        let reconciliation = TaxExportReconciliation.check(
            income: export,
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [invoice], everyExpense: [],
            everyPayment: [], everyRefund: [])

        #expect(!reconciliation.isComplete)
        #expect(reconciliation.findings.contains(.duplicateIncomeRow(invoiceNumber: 1)))
    }

    @Test("an issued invoice with NO number cannot be matched, and that is its own finding")
    func anissuedInvoiceWithoutANumberIsAFinding() throws {
        // It is a real defect rather than a reconciliation problem: an invoice
        // whose Sent was established and which never got a number means the
        // allocator did not run or lost its write (ovation#37, ovation#133). Said
        // as itself rather than reported as missing, because the remedies differ
        // (L11).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: nil)

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))
        let reconciliation = TaxExportReconciliation.check(
            income: export,
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [invoice], everyExpense: [],
            everyPayment: [], everyRefund: [])

        #expect(!reconciliation.isComplete)
        #expect(reconciliation.findings.contains(.issuedWithoutANumber(dayKey: "2026-03-01")))
    }

    // MARK: the boundary fixtures the issue names

    @Test("the last evening of the year is in one file and out of the neighbouring one")
    func fixtureOne_theYearBoundary() throws {
        let world = try World()
        let lateOnNewYearsEve = ISO8601DateFormatter().date(from: "2027-01-01T04:30:00Z")!
        let invoice = world.invoice(stamping: lateOnNewYearsEve, sent: true, number: 1)

        for (year, expected) in [(2026, 1), (2027, 0)] {
            let export = TaxExport.income(from: [invoice], in: .calendarYear(year))
            let reconciliation = TaxExportReconciliation.check(
                income: export,
                expenses: TaxExport.expenses(from: [], in: .calendarYear(year)),
                everyInvoice: [invoice], everyExpense: [],
                everyPayment: [], everyRefund: [])
            #expect(export.rowsIncluded == expected,
                    Comment(rawValue: "\(year) had \(export.rowsIncluded) rows"))
            #expect(reconciliation.isComplete,
                    Comment(rawValue: "\(year) did not reconcile"))
        }
    }

    @Test("an invoice issued in one year and paid in the next reconciles in both")
    func fixtureTwo_paidTheFollowingJanuary() throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-12-30", sent: true, number: 1)
        let payment = world.pay(invoice, Money(dollars: 100), on: "2027-01-15")

        let issuedYear = TaxExportReconciliation.check(
            income: TaxExport.income(from: [invoice], in: .calendarYear(2026)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [invoice], everyExpense: [],
            everyPayment: [payment], everyRefund: [])
        #expect(issuedYear.isComplete)

        // And in the year the money moved, where the invoice is correctly absent,
        // the payment is ACCOUNTED FOR as belonging to an invoice outside the
        // range rather than being silently unattached.
        let paidYear = TaxExportReconciliation.check(
            income: TaxExport.income(from: [invoice], in: .calendarYear(2027)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2027)),
            everyInvoice: [invoice], everyExpense: [],
            everyPayment: [payment], everyRefund: [])
        #expect(paidYear.isComplete)
        #expect(paidYear.paymentsAgainstInvoicesOutsideTheRange == 1)
    }

    @Test("a draft whose shoot has passed is out of the file and in the manifest's count")
    func fixtureThree_theUnissuedDraft() throws {
        let world = try World()
        let draft = world.invoice(dayKey: "2026-12-10", sent: false, number: nil)

        let export = TaxExport.income(from: [draft], in: .calendarYear(2026))
        let reconciliation = TaxExportReconciliation.check(
            income: export,
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [draft], everyExpense: [],
            everyPayment: [], everyRefund: [])

        #expect(export.rowsIncluded == 0)
        #expect(reconciliation.isComplete, "a draft is not a missing row")
        #expect(reconciliation.manifest.notIncluded[IncomeOmission.neverIssued.rawValue] == 1)
    }

    // MARK: every payment is accounted for

    @Test("a payment attached to no invoice at all is reported")
    func anunattachedPaymentIsReported() throws {
        // Money that arrived and belongs to nothing is either a payment nobody
        // allocated or a released allocation nobody redid. Either way it is not
        // on the return and somebody has to look.
        let world = try World()
        let payment = world.unallocatedPayment(Money(dollars: 75), on: "2026-06-06")

        let reconciliation = TaxExportReconciliation.check(
            income: TaxExport.income(from: [], in: .calendarYear(2026)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [], everyExpense: [],
            everyPayment: [payment], everyRefund: [])

        #expect(!reconciliation.isComplete)
        #expect(reconciliation.findings.contains(.paymentAttachedToNothing(dayKey: "2026-06-06")))
    }

    @Test("an allocation whose invoice was destroyed is its own finding, not an unattached payment")
    func anorphanedAllocationIsItsOwnFinding() throws {
        // ovation#176. `Invoice.allocations` is nullify, so deleting an invoice
        // sets `PaymentAllocation.invoice` to nil and leaves the allocation
        // ACTIVE, with `releasedOn` still nil. Reading a payment's invoices as
        // `active.compactMap(\.invoice)` then makes that allocation VANISH, and
        // the payment reports exactly as one nobody ever allocated.
        //
        // The two are opposite situations: one is money correctly sitting on a
        // client, the other is an allocation whose invoice was destroyed
        // underneath it, which is a real corruption needing a different fix. One
        // message for both is the shape L11 exists for.
        let world = try World()
        let payment = world.paymentWithAnOrphanedAllocation(Money(dollars: 75), on: "2026-06-06")

        let reconciliation = TaxExportReconciliation.check(
            income: TaxExport.income(from: [], in: .calendarYear(2026)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [], everyExpense: [],
            everyPayment: [payment], everyRefund: [])

        #expect(!reconciliation.isComplete)
        #expect(reconciliation.findings.contains(
            .allocationOutlivedItsInvoice(dayKey: "2026-06-06", amount: "75.00")))
        #expect(!reconciliation.findings.contains(.paymentAttachedToNothing(dayKey: "2026-06-06")),
                "the two must not both fire, or the count of things to look at doubles")
    }

    @Test("the orphaned finding carries the amount at stake, which the other one cannot")
    func theorphanedFindingCarriesItsAmount() throws {
        // The two findings need different work, so they carry different facts. A
        // payment attached to nothing is answered by allocating it; an
        // allocation that outlived its invoice is answered by finding out what
        // that invoice was, and how much money is standing against nothing is
        // the first thing anybody will ask.
        let world = try World()
        let payment = world.paymentWithAnOrphanedAllocation(Money(dollars: 75), on: "2026-06-06")

        let reconciliation = TaxExportReconciliation.check(
            income: TaxExport.income(from: [], in: .calendarYear(2026)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [], everyExpense: [],
            everyPayment: [payment], everyRefund: [])

        let orphaned = try #require(reconciliation.findings.first {
            if case .allocationOutlivedItsInvoice = $0 { return true }
            return false
        })
        guard case .allocationOutlivedItsInvoice(_, let amount) = orphaned else {
            Issue.record("the finding changed shape")
            return
        }
        #expect(amount == "75.00")
    }

    @Test("a payment with a RELEASED allocation is still just an unattached payment")
    func areleasedAllocationIsNotACorruption() throws {
        // The case that proves the new finding is not simply always firing. A
        // released allocation is the ordinary end of a cancellation: the row is
        // kept, the invoice is still there, and the money is back on the client.
        let world = try World()
        let payment = world.paymentWithAReleasedAllocation(Money(dollars: 75), on: "2026-06-06")

        let reconciliation = TaxExportReconciliation.check(
            income: TaxExport.income(from: [], in: .calendarYear(2026)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [], everyExpense: [],
            everyPayment: [payment], everyRefund: [])

        #expect(reconciliation.findings.contains(.paymentAttachedToNothing(dayKey: "2026-06-06")))
        #expect(!reconciliation.findings.contains(where: {
            if case .allocationOutlivedItsInvoice = $0 { return true }
            return false
        }))
    }

    @Test("a refund against an exported invoice is accounted for by that row")
    func arefundOnAnExportedInvoiceIsAccountedFor() throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 1)
        let refund = world.refund(invoice, Money(dollars: 50), on: "2026-07-01")

        let reconciliation = TaxExportReconciliation.check(
            income: TaxExport.income(from: [invoice], in: .calendarYear(2026)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [invoice], everyExpense: [],
            everyPayment: [], everyRefund: [refund])

        #expect(reconciliation.isComplete)
        #expect(reconciliation.refundsAgainstInvoicesOutsideTheRange == 0)
    }

    // MARK: a short read is a refusal, not a smaller export

    @Test("a source that could not be fully read REFUSES the run rather than exporting part")
    func ashortReadRefusesTheRun() throws {
        // Exporting what could be reached would produce a file that is short for
        // a reason nothing records, and it would total against itself perfectly.
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1)

        let reconciliation = TaxExportReconciliation.check(
            income: TaxExport.income(from: [invoice], in: .calendarYear(2026)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [invoice], everyExpense: [],
            everyPayment: [], everyRefund: [],
            couldNotBeFullyRead: ["invoices": 12])

        #expect(!reconciliation.isComplete)
        #expect(reconciliation.findings.contains(
            .sourceCouldNotBeFullyRead(source: "invoices", rowsNotConsulted: 12)))
    }

    // MARK: the manifest

    @Test("the manifest's counts come from the same selection as the rows")
    func themanifestAgreesWithTheRowsByConstruction() throws {
        let world = try World()
        let invoices = [world.invoice(dayKey: "2026-03-01", sent: true, number: 1),
                        world.invoice(dayKey: "2026-04-01", sent: true, number: 2)]
        let expenses = [world.expense(dayKey: "2026-02-02", amount: Money(dollars: 10))]

        let income = TaxExport.income(from: invoices, in: .calendarYear(2026))
        let expenseExport = TaxExport.expenses(from: expenses, in: .calendarYear(2026))
        let manifest = TaxExportReconciliation.check(
            income: income, expenses: expenseExport,
            everyInvoice: invoices, everyExpense: expenses,
            everyPayment: [], everyRefund: []).manifest

        #expect(manifest.incomeRows == income.document.rowCount)
        #expect(manifest.incomeTotal == income.total.exportAmount)
        #expect(manifest.salesTax == income.salesTax.exportAmount)
        #expect(manifest.expenseRows == expenseExport.document.rowCount)
        #expect(manifest.expenseTotal == expenseExport.total.exportAmount)
    }

    @Test("the manifest states the rule in force about which date decides the year")
    func themanifestCarriesTheDateRule() throws {
        // PRD 9.3 is unanswered, so the choice travels with the export rather
        // than living only in the code, and the answer changes what a re-run
        // means (L316).
        let manifest = try World().emptyManifest()
        #expect(manifest.dateRule == TaxExport.dateRuleInForce)
        #expect(manifest.dateRule.lowercased().contains("invoice date"))
    }

    @Test("the manifest round trips as JSON, because it has to be readable in March")
    func themanifestIsDurable() throws {
        let manifest = try World().emptyManifest()
        let data = try JSONEncoder().encode(manifest)
        let read = try JSONDecoder().decode(TaxExportManifest.self, from: data)
        #expect(read == manifest)
    }

    @Test("nothing in the manifest or a finding is a client's name")
    func themanifestNamesNobody() throws {
        // docs/PRIVACY-FLOOR.md. The manifest travels beside the file and is what
        // gets read out, pasted and logged; the CSV is the only thing that may
        // hold a name (L222).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1,
                                    clientNamed: "Ashgrove Chamber Players")
        let unseen = world.invoice(dayKey: "2026-05-01", sent: true, number: 3,
                                   clientNamed: "Ashgrove Chamber Players")

        let reconciliation = TaxExportReconciliation.check(
            income: TaxExport.income(from: [invoice], in: .calendarYear(2026)),
            expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
            everyInvoice: [invoice, unseen], everyExpense: [],
            everyPayment: [], everyRefund: [])

        let text = String(decoding: try JSONEncoder().encode(reconciliation.manifest), as: UTF8.self)
        #expect(!text.contains("Ashgrove"))
        #expect(!reconciliation.summary.contains("Ashgrove"))
        #expect(reconciliation.summary.contains("1 finding"))
    }

    // MARK: fixtures

    private final class World {
        let context: ModelContext

        init() throws {
            context = ModelContext(try OvationSchema.container(inMemory: true))
        }

        func emptyManifest() throws -> TaxExportManifest {
            TaxExportReconciliation.check(
                income: TaxExport.income(from: [], in: .calendarYear(2026)),
                expenses: TaxExport.expenses(from: [], in: .calendarYear(2026)),
                everyInvoice: [], everyExpense: [],
                everyPayment: [], everyRefund: []).manifest
        }

        @discardableResult
        func invoice(dayKey: String? = nil, stamping instant: Date? = nil,
                     sent: Bool, number: Int64?,
                     clientNamed name: String = "A fictional ensemble") -> Invoice {
            let date = instant ?? dayKey.flatMap { BusinessCalendar.startOfDay(forDayKey: $0) }
            let client = Client(name: name, taxStatus: .notExempt)
            context.insert(client)
            let invoice = Invoice(client: client, kind: .photography,
                                  invoiceDate: date.map { BusinessDate.stamping($0) },
                                  hourlyRate: Money(dollars: 100), taxRate: .newYorkCity)
            context.insert(invoice)
            invoice.number = number
            invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
            if sent {
                invoice.sentStatus = .sent(route: .ovationSentIt,
                                           at: Date(timeIntervalSince1970: 1_780_000_000))
            }
            return invoice
        }

        @discardableResult
        func pay(_ invoice: Invoice, _ amount: Money, on dayKey: String) -> Payment {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let payment = Payment(client: invoice.client, amount: amount,
                                  method: .zelle, receivedOn: .stamping(instant))
            context.insert(payment)
            let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                               amount: amount, allocatedOn: .stamping(instant))
            context.insert(allocation)
            payment.allocations.append(allocation)
            invoice.allocations.append(allocation)
            return payment
        }

        /// A payment whose allocation still STANDS and whose invoice is gone,
        /// which is what the nullify rule leaves behind when an invoice is
        /// deleted. Built directly rather than by deleting an invoice, because
        /// what is under test is how the reconciliation READS that state.
        func paymentWithAnOrphanedAllocation(_ amount: Money, on dayKey: String) -> Payment {
            let payment = unallocatedPayment(amount, on: dayKey)
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let allocation = PaymentAllocation(payment: payment, invoice: nil,
                                               amount: amount,
                                               allocatedOn: .stamping(instant))
            context.insert(allocation)
            payment.allocations.append(allocation)
            return payment
        }

        /// The ordinary end of a cancellation: the row is kept, it no longer
        /// stands, and the money is back on the client.
        func paymentWithAReleasedAllocation(_ amount: Money, on dayKey: String) -> Payment {
            let payment = unallocatedPayment(amount, on: dayKey)
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let allocation = PaymentAllocation(payment: payment, invoice: nil,
                                               amount: amount,
                                               allocatedOn: .stamping(instant))
            allocation.releasedOn = .stamping(instant)
            context.insert(allocation)
            payment.allocations.append(allocation)
            return payment
        }

        func unallocatedPayment(_ amount: Money, on dayKey: String) -> Payment {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let payment = Payment(client: nil, amount: amount, method: .zelle,
                                  receivedOn: .stamping(instant))
            context.insert(payment)
            return payment
        }

        @discardableResult
        func refund(_ invoice: Invoice, _ amount: Money, on dayKey: String) -> Refund {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let refund = Refund(invoice: invoice, payment: nil, amount: amount,
                                refundedOn: .stamping(instant), method: nil)
            context.insert(refund)
            invoice.refunds.append(refund)
            return refund
        }

        @discardableResult
        func expense(dayKey: String, amount: Money) -> Expense {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let expense = Expense(amount: amount, incurredOn: .stamping(instant),
                                  receipt: .noneRecorded)
            expense.category = .gear
            context.insert(expense)
            return expense
        }
    }
}

import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#61, PRD 23 to 25a. The two CSVs an accountant works from in January.
///
/// INCOME IS ACCRUAL, and that is the opposite of the intuitive cash view, so it
/// is asserted here rather than left to the reader of the code: one row per
/// ISSUED invoice, dated by the invoice date, whether or not it has been paid.
/// An invoice issued in December and paid in January belongs entirely to the
/// December year (PRD 24, Dan 2026-08-27).
///
/// ISSUED MEANS SENT ESTABLISHED, NEVER CREATED (PRD 24b, ovation#45). Sent is
/// only ever observed, so the set of invoices on the return is exactly the set
/// whose Sent was established. That puts the derived match on the tax path: an
/// invoice Dan sent from Spark that the match misses is MISSING INCOME, which is
/// why the two states that are not "sent" are COUNTED and NAMED rather than
/// silently left out.
///
/// THE DATES ARE STAMPED DAY KEYS, so this does no timezone arithmetic and
/// re-running last January's export produces last January's numbers (ovation#55,
/// L37). The boundary fixtures below are the proof: an evening shoot on 31
/// December is stamped in Dan's shooting zone, and its instant is in the next
/// year UTC.
struct TaxExportTests {

    // MARK: what is in the file, and what is deliberately not

    @Test("an issued invoice inside the range is one row")
    func anissuedInvoiceIsARow() throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, total: Money(dollars: 500))

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))

        #expect(export.document.rowCount == 1)
        #expect(export.document.isWellFormed)
        #expect(export.rowsIncluded == 1)
    }

    @Test("an UNPAID issued invoice is still income, which is the whole meaning of accrual")
    func anunpaidInvoiceIsStillIncome() throws {
        // The requirement most likely to be got backwards, and it changes the
        // number on a return rather than the look of a file (PRD 24).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, total: Money(dollars: 500))
        #expect(invoice.amountPaid == .zero)

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))

        #expect(export.rowsIncluded == 1)
        #expect(export.document.text.contains("Unpaid"))
        // The total is what was BILLED, sales tax included, and the tax is
        // carried separately so the accountant can take it back out: tax
        // collected is a liability rather than income, which is the whole reason
        // PRD 25 asks for its own column.
        #expect(export.total == invoice.total)
        #expect(export.salesTax == invoice.tax)
        #expect(export.total - export.salesTax == Money(dollars: 500))
    }

    @Test("an invoice issued in December and paid in January is in the DECEMBER year only")
    func paymentDoesNotDecideTheYear() throws {
        // ovation#63 names this as fixture 2, and it is the one an intuitive cash
        // reading gets wrong in both directions at once: it would be missing from
        // 2026 and present in 2027.
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-12-30", sent: true, total: Money(dollars: 400))
        world.pay(invoice, Money(dollars: 400), on: "2027-01-15")

        let inTheYearItWasIssued = TaxExport.income(from: [invoice], in: .calendarYear(2026))
        let inTheYearItWasPaid = TaxExport.income(from: [invoice], in: .calendarYear(2027))

        #expect(inTheYearItWasIssued.rowsIncluded == 1)
        #expect(inTheYearItWasPaid.rowsIncluded == 0)
        #expect(inTheYearItWasIssued.document.text.contains("2027-01-15"),
                "and the payment still shows on the row, in the year it was billed")
    }

    @Test("the last evening of the year is IN it, and out of the next one")
    func theyearBoundaryIsTheStampedDayNotTheInstant() throws {
        // ovation#63 fixture 1. A shoot at 23:30 on 31 December in Dan's shooting
        // zone is already 2027 in UTC, so anything deriving the year from the
        // instant puts this invoice in the wrong return. The stamped key is what
        // decides, and that is why it is stamped.
        let world = try World()
        let lateOnNewYearsEve = ISO8601DateFormatter().date(from: "2027-01-01T04:30:00Z")!
        #expect(BusinessCalendar.dayKey(for: lateOnNewYearsEve) == "2026-12-31",
                "the fixture only means anything if the zones really do disagree")
        let invoice = world.invoice(stamping: lateOnNewYearsEve, sent: true,
                                    total: Money(dollars: 300))

        #expect(TaxExport.income(from: [invoice], in: .calendarYear(2026)).rowsIncluded == 1)
        #expect(TaxExport.income(from: [invoice], in: .calendarYear(2027)).rowsIncluded == 0)
    }

    @Test("a DRAFT is not income, and it is counted rather than silently left out")
    func adraftIsNotIncomeAndIsCounted() throws {
        // ovation#63 fixture 3. A draft whose shoot has passed and was never sent
        // is not income, and it is also the likeliest sign of a real omission, so
        // the count is the thing that makes it findable (PRD 24b).
        let world = try World()
        let draft = world.invoice(dayKey: "2026-12-10", sent: false, total: Money(dollars: 700))

        let export = TaxExport.income(from: [draft], in: .calendarYear(2026))

        #expect(export.rowsIncluded == 0)
        #expect(export.notIncluded[.neverIssued] == 1)
        #expect(export.total == .zero)
    }

    @Test("an invoice whose Sent could NOT be determined has its own count, not the draft one")
    func couldNotDetermineIsItsOwnCount() throws {
        // The dangerous case and it must not be folded in with the drafts. A
        // draft is a decision Dan has not made; this is a question Ovation could
        // not answer, and it may be real income that is missing from the return.
        // Distinct causes, distinct counts (L11).
        let world = try World()
        let unknown = world.invoice(dayKey: "2026-05-05", sent: false,
                                    total: Money(dollars: 250))
        unknown.sentStatus = .couldNotDetermine(checkedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let export = TaxExport.income(from: [unknown], in: .calendarYear(2026))

        #expect(export.rowsIncluded == 0)
        #expect(export.notIncluded[.sentCouldNotBeDetermined] == 1)
        #expect(export.notIncluded[.neverIssued] == nil)
    }

    @Test("an invoice with NO DATE cannot be placed in a year and is counted as that")
    func adatelessInvoiceIsCountedNotDropped() throws {
        // A draft with no date at all is a real state (ovation#49). It cannot be
        // in or out of a range, so it is neither, and the count is what stops it
        // vanishing between two exports that each correctly excluded it.
        let world = try World()
        let undated = world.invoice(dayKey: nil, sent: true, total: Money(dollars: 100))

        let export = TaxExport.income(from: [undated], in: .calendarYear(2026))

        #expect(export.rowsIncluded == 0)
        #expect(export.notIncluded[.noInvoiceDate] == 1)
    }

    @Test("an invoice whose stored day key cannot be READ is counted, never silently dropped")
    func anunreadableDayKeyIsCounted() throws {
        // `BusinessDate` deliberately loads a row whose stored key is malformed
        // rather than throwing and taking the store with it, so such a row
        // reaches the export. `contains(dayKey:)` correctly answers false for it,
        // and without a bucket of its own the invoice would then be in no file,
        // in no count, and reported by nothing: a value parsed from storage that
        // feeds a comparison lands on the quiet side unless the parse failure is
        // given somewhere to go (L50).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, total: Money(dollars: 100))
        invoice.invoiceDate = BusinessDate(storedInstant: Date(timeIntervalSince1970: 1_780_000_000),
                                           storedDayKey: "not-a-day")

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))

        #expect(export.rowsIncluded == 0)
        #expect(export.notIncluded[.invoiceDateUnreadable] == 1)
        #expect(export.notIncluded[.noInvoiceDate] == nil, "it HAS a date, and it cannot be read")
    }

    @Test("an expense whose stored day key cannot be read is counted for the same reason")
    func anunreadableExpenseDayKeyIsCounted() throws {
        let world = try World()
        let expense = world.expense(dayKey: "2026-03-15", amount: Money(dollars: 10),
                                    category: .gear, vendor: nil)
        expense.incurredOn = BusinessDate(storedInstant: Date(timeIntervalSince1970: 1_780_000_000),
                                          storedDayKey: "")

        let export = TaxExport.expenses(from: [expense], in: .calendarYear(2026))

        #expect(export.rowsIncluded == 0)
        #expect(export.withAnUnreadableDate == 1)
        #expect(export.summary.contains("unreadable date 1"))
    }

    @Test("an invoice outside the range is not counted as a problem, because it is not one")
    func anOutOfRangeInvoiceIsNotAnOmission() throws {
        // The counts exist to name what is MISSING from a year it should have
        // been in. An invoice that belongs to another year is not that, and
        // putting it in the same bucket would make the number meaningless (L540).
        let world = try World()
        let lastYear = world.invoice(dayKey: "2025-06-01", sent: true, total: Money(dollars: 900))

        let export = TaxExport.income(from: [lastYear], in: .calendarYear(2026))

        #expect(export.rowsIncluded == 0)
        #expect(export.notIncluded.isEmpty)
    }

    @Test("a CANCELLED invoice that was issued is still a row, saying it was cancelled")
    func acancelledInvoiceIsExportedAsCancelled() throws {
        // It was issued, so it was income, and what happened to it afterwards is
        // a fact the accountant needs rather than a reason to hide the row. PRD
        // 24a's whole point is that an invoice must be findable rather than
        // silently indistinguishable.
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-03", sent: true, total: Money(dollars: 800))
        invoice.closure = .cancelled(on: .stamping(Date(timeIntervalSince1970: 1_780_000_000)),
                                     reason: "the show was called off")

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))

        #expect(export.rowsIncluded == 1)
        #expect(export.document.text.contains("Cancelled"))
    }

    // MARK: the columns PRD 25 and 25a ask for by name

    @Test("sales tax is its own column, so it can be totalled for the sales tax filing")
    func salesTaxHasItsOwnColumn() throws {
        let world = try World()
        // A rate that produces a tax nobody could mistake for part of the total.
        let invoice = world.invoice(dayKey: "2026-02-02", sent: true, total: Money(dollars: 100))

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))

        let columns = try #require(Self.headerColumns(export.document))
        let taxColumn = try #require(columns.firstIndex(of: "Sales tax"))
        let row = try #require(Self.dataRows(export.document).first)
        #expect(row[taxColumn] == invoice.tax.exportAmount)
        #expect(invoice.tax > .zero, "a zero tax would pass this without measuring anything")
    }

    @Test("the kind is its own column, including the rows whose kind was never recorded")
    func thekindHasItsOwnColumn() throws {
        // PRD 25a. An imported row whose kind nobody recorded must be countable
        // rather than silently mixed in with photography.
        let world = try World()
        let photography = world.invoice(dayKey: "2026-02-02", sent: true, total: Money(dollars: 100))
        let imported = world.invoice(dayKey: "2026-02-03", sent: true, total: Money(dollars: 100))
        imported.kind = .notRecorded

        let export = TaxExport.income(from: [photography, imported], in: .calendarYear(2026))

        let columns = try #require(Self.headerColumns(export.document))
        let kindColumn = try #require(columns.firstIndex(of: "Kind"))
        let rows = Self.dataRows(export.document)
        #expect(rows.map { $0[kindColumn] }.sorted() == ["Not recorded", "Photography"])
    }

    @Test("every payment against the invoice reaches its row, with dates and amounts")
    func paymentsAreOnTheRow() throws {
        // PRD 24a: the payment state on every row, and the payment dates and
        // amounts as columns, so an invoice billed and never collected is
        // findable. Two payments, because one would pass a writer that only ever
        // shows the first (L521).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-04-04", sent: true, total: Money(dollars: 600))
        world.pay(invoice, Money(dollars: 200), on: "2026-05-01")
        world.pay(invoice, Money(dollars: 150), on: "2026-06-01")

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))
        let columns = try #require(Self.headerColumns(export.document))
        let row = try #require(Self.dataRows(export.document).first)

        #expect(row[try #require(columns.firstIndex(of: "Payment dates"))] == "2026-05-01; 2026-06-01")
        #expect(row[try #require(columns.firstIndex(of: "Payment amounts"))] == "200.00; 150.00")
        #expect(row[try #require(columns.firstIndex(of: "Payment state"))] == "Partly paid")
        #expect(row[try #require(columns.firstIndex(of: "Amount paid"))] == "350.00")
    }

    @Test("a released allocation stops counting, the way the invoice's own arithmetic does")
    func areleasedAllocationIsNotOnTheRow() throws {
        // The export must not be a second definition of what has been paid. It
        // reads the invoice's own answer, so a released allocation stops counting
        // here for the same reason it stops counting there (L107).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-04-04", sent: true, total: Money(dollars: 600))
        let allocation = world.pay(invoice, Money(dollars: 200), on: "2026-05-01")
        allocation.releasedOn = .stamping(Date(timeIntervalSince1970: 1_790_000_000))

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))
        let columns = try #require(Self.headerColumns(export.document))
        let row = try #require(Self.dataRows(export.document).first)

        #expect(row[try #require(columns.firstIndex(of: "Amount paid"))] == "0.00")
        #expect(row[try #require(columns.firstIndex(of: "Payment dates"))] == "")
    }

    @Test("a cleared check shows its cleared date, and one that has not cleared shows none")
    func clearedDatesAreOnTheRow() throws {
        // PRD 5.15 puts cleared on the payment rather than the invoice, so this
        // column is per payment and can legitimately be empty beside a payment
        // that is there.
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-04-04", sent: true, total: Money(dollars: 600))
        let cleared = world.pay(invoice, Money(dollars: 100), on: "2026-05-01", method: .check)
        cleared.payment?.clearedOn = .stamping(BusinessCalendar.startOfDay(forDayKey: "2026-05-08")!)
        world.pay(invoice, Money(dollars: 100), on: "2026-05-02", method: .check)

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))
        let columns = try #require(Self.headerColumns(export.document))
        let row = try #require(Self.dataRows(export.document).first)

        #expect(row[try #require(columns.firstIndex(of: "Cleared dates"))] == "2026-05-08; ")
    }

    @Test("the client's name is a text field, so a comma in it cannot make a column")
    func theclientNameIsEscaped() throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-07-07", sent: true, total: Money(dollars: 100),
                                    clientNamed: "Ashgrove, Chamber Players")

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))

        #expect(export.document.text.contains("\"Ashgrove, Chamber Players\""))
        let row = try #require(Self.dataRows(export.document).first)
        #expect(row.count == export.document.header.count)
    }

    // MARK: the rows and the numbers come from ONE predicate

    @Test("the row count and the rows it promises are the same selection")
    func thecountAndTheRowsAgree() throws {
        // A count derived beside the rows drifts from them, and the number is the
        // half a person reads (L16, L107). Both come from `TaxExport.included`.
        let world = try World()
        let invoices = [
            world.invoice(dayKey: "2026-01-01", sent: true, total: Money(dollars: 100)),
            world.invoice(dayKey: "2026-12-31", sent: true, total: Money(dollars: 100)),
            world.invoice(dayKey: "2027-01-01", sent: true, total: Money(dollars: 100)),
            world.invoice(dayKey: "2026-06-06", sent: false, total: Money(dollars: 100))
        ]

        let export = TaxExport.income(from: invoices, in: .calendarYear(2026))

        #expect(export.rowsIncluded == export.document.rowCount)
        #expect(export.rowsIncluded == TaxExport.included(from: invoices, in: .calendarYear(2026)).count)
        #expect(export.rowsIncluded == 2)
    }

    @Test("the total is the sum of the rows it wrote, not of everything it was given")
    func thetotalIsOfTheRows() throws {
        let world = try World()
        let invoices = [
            world.invoice(dayKey: "2026-01-01", sent: true, total: Money(dollars: 100)),
            world.invoice(dayKey: "2027-01-01", sent: true, total: Money(dollars: 999))
        ]

        let export = TaxExport.income(from: invoices, in: .calendarYear(2026))

        #expect(export.total == invoices[0].total)
        #expect(export.total < invoices[1].total, "the 2027 invoice is not in this number")
    }

    @Test("the rows are ordered by date, so two runs of one range are the same file")
    func therowsHaveADeclaredOrder() throws {
        // A collection read from a store carries no order unless the read
        // declares one (L343), and an export whose row order moves between runs
        // cannot be compared with the copy the accountant already has.
        let world = try World()
        let invoices = [
            world.invoice(dayKey: "2026-09-09", sent: true, total: Money(dollars: 100)),
            world.invoice(dayKey: "2026-02-02", sent: true, total: Money(dollars: 100)),
            world.invoice(dayKey: "2026-05-05", sent: true, total: Money(dollars: 100))
        ]

        let export = TaxExport.income(from: invoices, in: .calendarYear(2026))
        let columns = try #require(Self.headerColumns(export.document))
        let dateColumn = try #require(columns.firstIndex(of: "Invoice date"))

        #expect(Self.dataRows(export.document).map { $0[dateColumn] }
                == ["2026-02-02", "2026-05-05", "2026-09-09"])
    }

    // MARK: expenses

    @Test("an expense inside the range is a row, with its category and its Schedule C line")
    func anexpenseIsARow() throws {
        let world = try World()
        let expense = world.expense(dayKey: "2026-03-15", amount: Money(dollars: 42),
                                    category: .software, vendor: "A software vendor")

        let export = TaxExport.expenses(from: [expense], in: .calendarYear(2026))
        let columns = try #require(Self.headerColumns(export.document))
        let row = try #require(Self.dataRows(export.document).first)

        #expect(export.rowsIncluded == 1)
        #expect(row[try #require(columns.firstIndex(of: "Category"))] == "Software")
        #expect(row[try #require(columns.firstIndex(of: "Schedule C line"))]
                == ExpenseCategory.software.scheduleC.line.exportLabel)
        #expect(row[try #require(columns.firstIndex(of: "Amount"))] == "42.00")
    }

    @Test("an expense with NO category is exported and counted, never dropped")
    func anuncategorisedExpenseIsStillExported() throws {
        // It is money that was spent. Leaving it out would understate the
        // deduction and nothing would say so; the count is what makes the gap
        // visible instead (L67).
        let world = try World()
        let expense = world.expense(dayKey: "2026-03-15", amount: Money(dollars: 10),
                                    category: nil, vendor: nil)

        let export = TaxExport.expenses(from: [expense], in: .calendarYear(2026))
        let columns = try #require(Self.headerColumns(export.document))
        let row = try #require(Self.dataRows(export.document).first)

        #expect(export.rowsIncluded == 1)
        #expect(export.needingACategory == 1)
        #expect(row[try #require(columns.firstIndex(of: "Category"))] == "Not categorised")
    }

    @Test("an expense with no receipt says WHICH kind of no receipt it is")
    func thereceiptStateIsNamed() throws {
        // "No receipt" and "imported without one" are different facts about the
        // same missing image, and the accountant does different things about each
        // (L11). The vocabulary is the expense's own, not a second one here.
        let world = try World()
        let none = world.expense(dayKey: "2026-03-15", amount: Money(dollars: 10),
                                 category: .gear, vendor: nil)
        let imported = world.expense(dayKey: "2026-03-16", amount: Money(dollars: 10),
                                     category: .gear, vendor: nil)
        imported.receipt = .importedWithoutOne

        let export = TaxExport.expenses(from: [none, imported], in: .calendarYear(2026))
        let columns = try #require(Self.headerColumns(export.document))
        let receiptColumn = try #require(columns.firstIndex(of: "Receipt"))
        let rows = Self.dataRows(export.document)

        #expect(rows[0][receiptColumn] == none.receiptMissingNote)
        #expect(rows[1][receiptColumn] == imported.receiptMissingNote)
        #expect(rows[0][receiptColumn] != rows[1][receiptColumn])
    }

    @Test("an expense outside the range is not in the file")
    func anout_of_rangeExpenseIsExcluded() throws {
        let world = try World()
        let expense = world.expense(dayKey: "2025-12-31", amount: Money(dollars: 10),
                                    category: .gear, vendor: nil)

        #expect(TaxExport.expenses(from: [expense], in: .calendarYear(2026)).rowsIncluded == 0)
    }

    @Test("the expenses total is the sum of the rows written")
    func theexpenseTotalIsOfTheRows() throws {
        let world = try World()
        let expenses = [
            world.expense(dayKey: "2026-01-01", amount: Money(dollars: 10), category: .gear, vendor: nil),
            world.expense(dayKey: "2026-01-02", amount: Money(dollars: 15), category: .gear, vendor: nil),
            world.expense(dayKey: "2027-01-01", amount: Money(dollars: 99), category: .gear, vendor: nil)
        ]

        #expect(TaxExport.expenses(from: expenses, in: .calendarYear(2026)).total
                == Money(dollars: 25))
    }

    @Test("a vendor name is a text field, because it came from outside Ovation")
    func thevendorIsEscaped() throws {
        let world = try World()
        let expense = world.expense(dayKey: "2026-03-15", amount: Money(dollars: 10),
                                    category: .gear, vendor: "=Gear Shop")

        let export = TaxExport.expenses(from: [expense], in: .calendarYear(2026))

        #expect(export.document.text.contains("'=Gear Shop"))
    }

    // MARK: the range

    @Test("a calendar year is the whole year, both ends included")
    func acalendarYearIncludesBothEnds() {
        let year = TaxExportRange.calendarYear(2026)
        #expect(year.contains(dayKey: "2026-01-01"))
        #expect(year.contains(dayKey: "2026-12-31"))
        #expect(!year.contains(dayKey: "2025-12-31"))
        #expect(!year.contains(dayKey: "2027-01-01"))
    }

    @Test("any range works, not only a year, because that is what the requirement says")
    func anarbitraryRangeWorks() {
        // PRD 23: any date range, DEFAULTING to the calendar year. A partial year
        // is what ovation#65 puts in front of the accountant.
        let range = TaxExportRange(firstDayKey: "2026-03-01", lastDayKey: "2026-05-31")
        #expect(range.contains(dayKey: "2026-03-01"))
        #expect(range.contains(dayKey: "2026-05-31"))
        #expect(!range.contains(dayKey: "2026-02-28"))
        #expect(!range.contains(dayKey: "2026-06-01"))
    }

    @Test("a day key that is not a day key is not in any range")
    func amalformedDayKeyIsInNoRange() {
        // `BusinessDate` deliberately loads a row with a malformed key rather
        // than throwing, so one can reach here. It must not compare as inside a
        // range by accident of string ordering.
        #expect(!TaxExportRange.calendarYear(2026).contains(dayKey: ""))
        #expect(!TaxExportRange.calendarYear(2026).contains(dayKey: "2026-13"))
    }

    // MARK: nothing about producing this may print a name

    @Test("what the export ANSWERS carries counts and paths, never a client name")
    func thesummaryNamesNobody() throws {
        // docs/PRIVACY-FLOOR.md. The file itself necessarily holds real names,
        // because that is what an accountant needs. Nothing about producing it
        // may put one into terminal output, a log or a transcript, and the
        // summary value is what those would print (L222).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-07-07", sent: true, total: Money(dollars: 100),
                                    clientNamed: "Ashgrove Chamber Players")

        let export = TaxExport.income(from: [invoice], in: .calendarYear(2026))

        #expect(!export.summary.contains("Ashgrove"))
        #expect(export.summary.contains("1"))
    }

    // MARK: fixtures

    private static func headerColumns(_ document: CSVDocument) -> [String]? { document.header }

    /// The rows as rendered, parsed back out of the document, so a column test
    /// reads what a spreadsheet would rather than what the builder intended.
    private static func dataRows(_ document: CSVDocument) -> [[String]] {
        document.rows.map { row in
            row.map { field in
                switch field {
                case .text(let value), .formatted(let value): return value
                }
            }
        }
    }

    /// An in memory store. Nothing here can reach the live one: the resolver on
    /// the isolation floor refuses under a disposable launch, and this never asks
    /// it for a path at all.
    private final class World {
        let context: ModelContext

        init() throws {
            context = ModelContext(try OvationSchema.container(inMemory: true))
        }

        @discardableResult
        func invoice(dayKey: String?, sent: Bool, total: Money,
                     clientNamed name: String = "A fictional ensemble") -> Invoice {
            let date = dayKey.flatMap { BusinessCalendar.startOfDay(forDayKey: $0) }
            return invoice(stamping: date, sent: sent, total: total, clientNamed: name)
        }

        @discardableResult
        func invoice(stamping instant: Date?, sent: Bool, total: Money,
                     clientNamed name: String = "A fictional ensemble") -> Invoice {
            let client = Client(name: name, taxStatus: .notExempt)
            context.insert(client)
            let invoice = Invoice(client: client, kind: .photography,
                                  invoiceDate: instant.map { BusinessDate.stamping($0) },
                                  hourlyRate: Money(dollars: 100), taxRate: .newYorkCity)
            context.insert(invoice)
            // A flat line so the total is exactly what the test asked for, before
            // tax, which the invoice adds on its own terms.
            invoice.add(LineItem.flat(total, describedAs: "Photography"))
            if sent {
                invoice.sentStatus = .sent(route: .ovationSentIt,
                                           at: Date(timeIntervalSince1970: 1_780_000_000))
            }
            return invoice
        }

        @discardableResult
        func pay(_ invoice: Invoice, _ amount: Money, on dayKey: String,
                 method: PaymentMethod = .zelle) -> PaymentAllocation {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let payment = Payment(client: invoice.client, amount: amount,
                                  method: method, receivedOn: .stamping(instant))
            context.insert(payment)
            let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                               amount: amount,
                                               allocatedOn: .stamping(instant))
            context.insert(allocation)
            payment.allocations.append(allocation)
            invoice.allocations.append(allocation)
            return allocation
        }

        @discardableResult
        func expense(dayKey: String, amount: Money, category: ExpenseCategory?,
                     vendor: String?) -> Expense {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let expense = Expense(amount: amount, incurredOn: .stamping(instant),
                                  receipt: .noneRecorded)
            expense.vendor = vendor
            expense.category = category
            context.insert(expense)
            return expense
        }
    }
}

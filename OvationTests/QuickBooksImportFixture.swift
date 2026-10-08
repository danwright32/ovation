import Foundation
import SwiftData

/// ovation#68 to ovation#72. A whole QuickBooks import, three exports that agree
/// with each other, built from a short description of each invoice, so a test can
/// say "an invoice numbered 1130 for this client, half paid" and get files in the
/// measured shape (`QuickBooksFixture`) whose rows reconcile.
///
/// EVERY VALUE IS INVENTED, as `QuickBooksFixture` requires: the repository is
/// public (docs/PRIVACY-FLOOR.md).
///
/// IT NEVER TOUCHES A STORE ON DISK. `store` is in memory, so nothing here can reach
/// Dan's own (L2).
enum QuickBooksImportFixture {

    private typealias F = QuickBooksFixture

    struct Line {
        var description = "Imaginary gala"
        /// Hundredths of an hour and a price, for a line charged by time; nil for a
        /// flat one.
        var quantity: String?
        var price: String?
        var cents: Int64
    }

    struct Spec {
        var number: String
        var client = "Fictive Quartet"
        var date = "1/19/2026"
        var due = "2/18/2026"
        var lines: [Line] = [Line(cents: 10_000)]
        /// What QuickBooks says was paid, as one payment. Nil is paid in full, and
        /// zero is unpaid.
        var paidCents: Int64?

        var cents: Int64 { lines.map(\.cents).reduce(0, +) }
        var paid: Int64 { paidCents ?? cents }
    }

    /// A figure as the export writes it in a data row: two decimals, a thousands
    /// comma where thousands fall, and quoted when it carries one.
    static func figure(_ cents: Int64) -> String {
        let text = bare(cents)
        return text.contains(",") ? "\"\(text)\"" : text
    }

    /// A figure as a TOTAL row writes it, with the dollar sign only TOTAL rows carry.
    static func dollars(_ cents: Int64) -> String {
        "\"" + (cents < 0 ? "-$" : "$") + bare(abs(cents)) + "\""
    }

    private static func bare(_ cents: Int64) -> String {
        let sign = cents < 0 ? "-" : ""
        let whole = abs(cents) / 100
        let digits = whole >= 1_000 ? "\(whole / 1_000)," + String(format: "%03lld", whole % 1_000) : "\(whole)"
        return sign + digits + "." + String(format: "%02lld", abs(cents) % 100)
    }

    /// The four exports for these invoices, read.
    static func run(_ invoices: [Spec]) -> QuickBooksImportRun {
        let total = invoices.map(\.cents).reduce(0, +)
        let open = invoices.map { $0.cents - $0.paid }.reduce(0, +)
        let list = F.invoiceList(invoices.map { invoice in
            F.invoice(invoice.date, number: invoice.number, name: invoice.client, due: invoice.due,
                      amount: figure(invoice.cents), open: figure(invoice.cents - invoice.paid))
        }, total: dollars(total), openBalance: dollars(open))
        var lineRows: [String] = []
        for invoice in invoices {
            for line in invoice.lines {
                lineRows.append(F.line(invoice.date, number: invoice.number, client: invoice.client,
                                       description: line.description, quantity: line.quantity ?? "",
                                       price: line.price ?? "", amount: figure(line.cents),
                                       balance: figure(line.cents)))
            }
        }
        lineRows.append(F.groupTotal("--", amount: dollars(total)))
        var ledgerRows: [String] = []
        for invoice in invoices {
            ledgerRows.append(F.client(invoice.client))
            ledgerRows.append(F.ledgerInvoice(invoice.date, number: invoice.number, amount: figure(invoice.cents)))
            if invoice.paid != 0 {
                ledgerRows.append(F.ledgerPayment("1/25/2026", amount: figure(invoice.paid)))
            }
        }
        return QuickBooksImportRun(
            invoiceList: QuickBooksExport.invoiceList(list),
            payments: QuickBooksExport.payments(F.payments([F.payment()], total: "$100.00")),
            salesLines: QuickBooksExport.salesLines(F.salesLines(lineRows, total: dollars(total))),
            invoicesAndPayments: QuickBooksExport.invoicesAndPayments(F.invoicesAndPayments(ledgerRows)))
    }

    /// An in memory store holding these clients and nothing else.
    static func store(clients: [(String, TaxStatus)] = [("Fictive Quartet", .exempt)]) throws -> ModelContainer {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        for (name, status) in clients { context.insert(Client(name: name, taxStatus: status)) }
        try context.save()
        return container
    }

    /// Imports `run` through the one writer that writes imported rows.
    @discardableResult
    static func write(_ run: QuickBooksImportRun, into container: ModelContainer,
                      batch: UUID = UUID(), version: Int = QuickBooksImportKey.importerVersion)
        async throws -> QuickBooksImportWrite {
        try await InvoiceNumberAllocator(modelContainer: container)
            .importInvoices(run.candidates(version: version), batch: batch)
    }

    static func invoices(in container: ModelContainer) throws -> [Invoice] {
        try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .sorted { ($0.number ?? 0) < ($1.number ?? 0) }
    }

    static func payments(in container: ModelContainer) throws -> [Payment] {
        try ModelContext(container).fetch(FetchDescriptor<Payment>())
    }
}

#if DEBUG
import Foundation
import SwiftData

/// The invoices the review sheet is looked at with, in the Debug build only
/// (ovation#318 B5, and decision 1 of the plan on ovation#167).
///
/// WHY IT EXISTS. Real invoices reach the sheet with ovation#42, so until then the
/// only way to see the sheet at all is over samples. A screen nothing links to
/// works perfectly for whoever built it and is invisible to every review (L546),
/// and judging this one is the whole point of PRD 52.
///
/// IT IS `#if DEBUG` AND IT NEVER TOUCHES THE REAL STORE. The container is in
/// memory, so no sample can reach Dan's records even by mistake (L2), and a check
/// proves none of these words are in the Release product.
enum ReviewSampleWorld {

    /// A sheet presenter over one sample client and the Ordinary fixture.
    ///
    /// The addresses are PARAMETERS rather than a fixed set, because the states
    /// worth looking at are exactly the ones the real data does not have: 30 of the
    /// 31 real clients carry an override that copies the main address, and not one
    /// has a genuine override (PRD 52c).
    @MainActor
    static func presenter(mainAddress: String = "booker@example.com",
                          overrideAddress: String? = nil,
                          named name: String = "A Client",
                          dueDate: BusinessDate? = nil,
                          now: @escaping () -> Date = Date.init) throws -> ReviewSheetPresenter {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: name, taxStatus: .notExempt)
        client.email = mainAddress
        client.contractEmail = overrideAddress
        context.insert(client)

        let invoice = try sampleInvoice(in: context, for: client)
        // A GIVEN DUE DATE MOVES THE INVOICE DATE WITH IT. The document refuses a due
        // date before the invoice date (PRD 7 and InvoiceDocument.Refusal), so a
        // sample staged only at one end is refused rather than showing the state the
        // caller asked for, with the refusal naming something the caller did not do.
        if let dueDate {
            invoice.dueDate = dueDate
            if let dueStart = BusinessCalendar.startOfDay(forDayKey: dueDate.dayKey) {
                invoice.invoiceDate = .stamping(dueStart.addingTimeInterval(-14 * 24 * 60 * 60))
            }
        }
        try context.save()

        let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
        let session = ReviewSession(document: document, resources: try InvoicePDFResources.bundled())
        return ReviewSheetPresenter(session: session, document: document, client: client,
                                    dueDate: invoice.dueDate, now: now)
    }

    /// The presenter for one named sample (ovation#318 B5). Every state the sheet
    /// can be in is reachable from the menu, including the ones the real data does
    /// not have.
    @MainActor
    static func presenter(for sample: ReviewSample) throws -> ReviewSheetPresenter {
        // The clock is pinned per sample, so a state about a date is the same state
        // tomorrow (L130).
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        switch sample {
        case .ordinary:
            return try presenter(now: { day })
        case .genuineOverride:
            return try presenter(mainAddress: "booker@example.com",
                                 overrideAddress: "accounts@example.com", now: { day })
        case .twoAddressesInOneField:
            return try presenter(mainAddress: "one@example.com, two@example.com", now: { day })
        case .nowhereToSend:
            return try presenter(mainAddress: "", now: { day })
        case .pastDue:
            return try presenter(dueDate: .stamping(day.addingTimeInterval(-7 * 86_400)),
                                 now: { day })
        case .dueSoon:
            return try presenter(dueDate: .stamping(day.addingTimeInterval(3 * 86_400)),
                                 now: { day })
        case .waitingOnTaxStatus, .discountTooLarge:
            // These never reach the sheet: ReviewGate refuses them and the menu says
            // the sentence instead (PRD 52g). A presenter is still built, so a
            // sample that stopped refusing would show rather than crash.
            return try presenter(now: { day })
        }
    }

    /// One shoot, one line, numbered and dated, which is what the Ordinary design
    /// fixture is. It is built here rather than read from the design's JSON because
    /// that file is a test fixture and the app does not read test fixtures.
    @MainActor
    private static func sampleInvoice(in context: ModelContext, for client: Client) throws -> Invoice {
        let issued = BusinessDate.stamping(Date(timeIntervalSince1970: 1_790_000_000))
        let rate = Money(dollars: 250)
        let invoice = Invoice(client: client, kind: .fromABooking, invoiceDate: issued,
                              hourlyRate: rate, taxRate: .newYorkCity, createdOn: issued)
        context.insert(invoice)
        invoice.number = 1_123
        invoice.dueDate = BusinessDate.stamping(Date(timeIntervalSince1970: 1_791_209_600))

        let shoot = Shoot(name: "Autumn Concert", when: .dayOnly(issued),
                          venue: "Calder Street Theatre")
        invoice.add(shoot)
        let line = LineItem.hourly(hours: Hours(quarters: 10), at: rate,
                                   describedAs: "Concert photography", for: shoot)
        invoice.add(line)
        return invoice
    }

}
#endif

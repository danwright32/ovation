import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#60, PRD 5.4. The service types a line item picks from, which are DATA
/// rather than a vocabulary in code, because Dan adds one from inside an invoice
/// without going to settings first.
struct ServiceTypeTests {

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    @Test("a new type can be made and used without anything being edited in code")
    func aNewTypeCanBeAddedFromInsideAnInvoice() throws {
        let context = try Self.store()
        let type = ServiceType(name: "Second photographer", role: .ordinary,
                               defaultUnitAmount: Money(dollars: 400))
        context.insert(type)
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<ServiceType>()).first)
        #expect(read.name == "Second photographer")
        #expect(read.defaultUnitAmount == Money(dollars: 400))
    }

    @Test("the ROLE is code's handle and the NAME is Dan's, so a rename changes no behaviour")
    func renamingATypeDoesNotChangeWhatItIs() throws {
        let context = try Self.store()
        let hourly = ServiceType(name: "Photography", role: .hourlyPhotography,
                                 defaultUnitAmount: Money(dollars: 250))
        context.insert(hourly)
        try context.save()

        hourly.name = "Event coverage"
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<ServiceType>()).first)
        #expect(read.role == .hourlyPhotography,
                "keying behaviour off a name a person can rename is how a rename breaks it")
    }

    @Test("the roles are the two code actually switches on")
    func theRolesAreTwo() {
        // `referralCredit` was removed by ovation#126. It existed so code could
        // tell which LINE was the credit, and round 6 of ovation#111 took the
        // credit out of the lines: there is nothing left for it to identify. A
        // role nothing switches on is a value a picker would still offer.
        #expect(Set(ServiceRole.allCases) == [.hourlyPhotography, .ordinary])
    }

    @Test("a type is retired rather than deleted, because sent invoices still refer to it")
    func aTypeIsRetiredRatherThanDeleted() throws {
        let context = try Self.store()
        let type = ServiceType(name: "Preview images", role: .ordinary, defaultUnitAmount: nil)
        context.insert(type)
        let invoice = Invoice(client: nil, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        let line = LineItem.flat(Money(dollars: 75), describedAs: "Preview images")
        line.serviceType = type
        invoice.add(line)
        try context.save()

        type.retiredOn = .stamping(Date(timeIntervalSince1970: 1_794_531_600))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        #expect(read.orderedLineItems.first?.serviceType?.name == "Preview images",
                "the invoice still says what was charged, which a delete would have taken")
        #expect(read.orderedLineItems.first?.serviceType?.retiredOn != nil)
    }

    @Test("a line item needs no service type at all, so a one off charge is not blocked")
    func aLineNeedsNoType() throws {
        let context = try Self.store()
        let line = LineItem.flat(Money(dollars: 75), describedAs: "A one off")
        #expect(line.serviceType == nil)
        #expect(line.amount == Money(dollars: 75))
        _ = context
    }
}

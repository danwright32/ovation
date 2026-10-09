import Foundation
import SwiftData
import Testing

/// ovation#70. The stamp an import records on each row it writes, which a revert
/// compares the row against to tell untouched from edited.
///
/// BOTH WAYS IT CAN BE WRONG FAIL TOWARDS REFUSING (review of 7c5bcda). A stamp
/// this build cannot recompute, and a recomputation that could not be made, are
/// each an answer nobody has, and an answer nobody has must never read as
/// "nothing changed", because that answer deletes the row (L42).
struct ImportedStateTests {

    private static func importedInvoice() throws -> Invoice {
        let client = Client(name: "Fictive Quartet", taxStatus: .exempt)
        let day = try #require(BusinessCalendar.day(forKey: "2026-01-19"))
        return Invoice.imported(number: 1_041,
                                key: QuickBooksImportKey(sources: [.init(fileSHA256: "f", row: 6, rawRowSHA256: "r")]),
                                batch: UUID(), client: client, invoiceDate: day, dueDate: day)
    }

    @Test("a row is compared under the version its stamp was written in")
    func astampIsReadUnderItsOwnVersion() throws {
        let invoice = try Self.importedInvoice()
        let stamp = try #require(ImportedState.fingerprint(of: invoice))
        #expect(stamp.hasPrefix("v1:"))
        #expect(ImportedState.matches(stamp, invoice))
        // The same digest claimed for a version this build has never written is not
        // something it can recompute, so it is never a match.
        let digest = stamp.dropFirst("v1:".count)
        #expect(!ImportedState.matches("v99:" + digest, invoice))
        #expect(!ImportedState.matches(String(digest), invoice), "a stamp with no version is not version 1")
    }

    @Test("a version this build knows is recomputed by that version's own rule, not the newest one")
    func eachVersionHasItsOwnRule() throws {
        let invoice = try Self.importedInvoice()
        #expect(ImportedState.fingerprint(of: invoice, version: 1) == ImportedState.fingerprint(of: invoice))
        #expect(ImportedState.fingerprint(of: invoice, version: 99) == nil)
    }

    @Test("a shoot changed on an imported invoice changes its stamp, its times and its name included")
    func ashootIsPartOfTheStamp() throws {
        // REVIEW OF 42fdc47: the stamp listed each shoot by its id alone, so a shoot
        // whose name, venue or times changed left the stamp matching, and a revert
        // would delete the change.
        let invoice = try Self.importedInvoice()
        let shoot = Shoot(name: "Imaginary gala", when: nil, venue: nil)
        invoice.shoots.append(shoot)
        let stamp = try #require(ImportedState.fingerprint(of: invoice))

        shoot.shotFrom = try #require(ClockTime(hour: 19, minute: 0))
        #expect(!ImportedState.matches(stamp, invoice), "a time typed on the shoot went unseen")
        shoot.shotFrom = nil
        #expect(ImportedState.matches(stamp, invoice))
        shoot.venue = "Fictive Hall"
        #expect(!ImportedState.matches(stamp, invoice), "a venue changed on the shoot went unseen")
    }

    /// What the stamp deliberately leaves out of each entity, each with its reason.
    /// EVERYTHING ELSE THE MODEL STORES MUST BE IN IT, and the list of what the model
    /// stores is read from the schema, never written here (review of 42fdc47, L41):
    /// a field added to a model later fails the case below until it is stamped or
    /// named here.
    private static let leftOut: [String: [String: String]] = [
        "Invoice": [
            "id": "its identity, which nothing edits",
            "importKey": "provenance, written once by the import",
            "importBatchID": "provenance, written once by the import",
            "importedFingerprint": "the stamp itself",
            "allocations": "a record of its own, which the revert names as a dependent",
            "refunds": "a record of its own, which the revert names as a dependent",
            "sentMessages": "a record of its own, which the revert names as a dependent",
        ],
        "LineItem": ["invoice": "the invoice that owns it, which is the row being stamped"],
        "Shoot": ["invoice": "the invoice that owns it, which is the row being stamped"],
        "Payment": [
            "id": "its identity, which nothing edits",
            "importKey": "provenance, written once by the import",
            "importBatchID": "provenance, written once by the import",
            "importedFingerprint": "the stamp itself",
            "allocations": "the batch's own are written with it; any other is named as a dependent",
            "refunds": "a record of its own, which the revert names as a dependent",
        ],
    ]

    @Test("the stamp covers every field the schema stores on an invoice, its lines, its shoots and a payment")
    func theStampCoversTheModel() throws {
        let invoice = try Self.importedInvoice()
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Imaginary gala"))
        invoice.shoots.append(Shoot(name: "Imaginary gala", when: nil, venue: nil))
        let payment = Payment.imported(key: QuickBooksImportKey(sources: [.init(fileSHA256: "f", row: 7, rawRowSHA256: "p")]),
                                       batch: UUID(), client: try #require(invoice.client),
                                       amount: Money(dollars: 100), receivedOn: try #require(invoice.invoiceDate))
        let covered = ImportedState.coverage(of: invoice, and: payment)
        let schema = Schema(OvationSchema.models)
        for name in ["Invoice", "LineItem", "Shoot", "Payment"] {
            let entity = try #require(schema.entities.first { $0.name == name }, "no \(name) in the schema")
            let stored = Set(entity.properties.map(\.name))
            #expect(stored.count > 3, "\(name): the schema listed \(stored.count) properties, so it is not being read")
            let excused = Set((Self.leftOut[name] ?? [:]).keys)
            let missing = stored.subtracting(covered[name] ?? []).subtracting(excused)
            #expect(missing.isEmpty, "\(name) stores fields the stamp does not cover: \(missing.sorted())")
            let stale = excused.subtracting(stored)
            #expect(stale.isEmpty, "\(name): left out but no longer stored: \(stale.sorted())")
        }
    }

    @Test("an answer that could not be computed never agrees with anything, not even another one")
    func amissingAnswerNeverAgrees() {
        #expect(!ImportedState.agree(stored: nil, computed: nil))
        #expect(!ImportedState.agree(stored: "v1:abc", computed: nil))
        #expect(!ImportedState.agree(stored: nil, computed: "v1:abc"))
        #expect(ImportedState.agree(stored: "v1:abc", computed: "v1:abc"))
        #expect(!ImportedState.agree(stored: "v1:abc", computed: "v1:abd"))
    }
}

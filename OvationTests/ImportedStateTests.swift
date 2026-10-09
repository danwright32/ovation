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
                                key: QuickBooksImportKey(sources: [.init(fileSHA256: "f", rawRowSHA256: "r")]),
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

    @Test("an answer that could not be computed never agrees with anything, not even another one")
    func amissingAnswerNeverAgrees() {
        #expect(!ImportedState.agree(stored: nil, computed: nil))
        #expect(!ImportedState.agree(stored: "v1:abc", computed: nil))
        #expect(!ImportedState.agree(stored: nil, computed: "v1:abc"))
        #expect(ImportedState.agree(stored: "v1:abc", computed: "v1:abc"))
        #expect(!ImportedState.agree(stored: "v1:abc", computed: "v1:abd"))
    }
}

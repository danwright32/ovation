import Foundation
import Testing

/// ovation#208. Reading the export off disk, carrying out the plan, and saying
/// what happened.
///
/// NOTHING HERE TOUCHES THE FILESYSTEM. The bytes arrive through an injected
/// closure, so a test can make the read FAIL without damaging anything, which a
/// runner that opened the file itself would be beyond the reach of (L196). The
/// failure paths are the point of this suite: an export that is absent and one
/// that is damaged are different facts needing different work, and both must be
/// told apart from a run that correctly found nothing to do (L11, L98).
struct ClientImportRunnerTests {

    private static let path = "/somewhere/Overture/downbeat-export.json"
    private static let url = URL(fileURLWithPath: path)

    private static func bytes(clients: String) -> Data {
        Data("""
        { "version": 3, "exportedAt": "2026-08-29T15:07:27Z",
          "bookings": [], "venues": [], "blockedDates": [],
          "clients": \(clients) }
        """.utf8)
    }

    private static func oneRow(id: UUID = UUID(), name: String = "A choir",
                               email: String = "a@example.com") -> String {
        """
        [{"id": "\(id.uuidString)", "displayName": "\(name)",
          "email": "\(email)", "contractEmail": ""}]
        """
    }

    private static func held(_ name: String, email: String = "",
                             downbeat: UUID? = nil) -> Client {
        let client = Client(name: name, taxStatus: .neverRecorded)
        client.email = email
        client.downbeatClientID = downbeat
        return client
    }

    // MARK: the file is not there

    /// A Mac where Downbeat has never been launched has no export at all. That is
    /// a different fact from a damaged one and has a different remedy, which is to
    /// open Downbeat once.
    @Test("an export that is not there is its own notice, and nothing is changed")
    func aMissingExportIsItsOwnNotice() {
        var store = [Self.held("Already here")]
        let result = ClientImportRunner.run(file: Self.url, held: &store) { _ in
            throw CocoaError(.fileReadNoSuchFile)
        }
        #expect(result.created.isEmpty)
        #expect(store.count == 1)
        #expect(result.notices.count == 1)
        guard case .exportMissing = result.notices[0] else {
            Issue.record("expected exportMissing, got \(result.notices[0])")
            return
        }
    }

    /// A file that is there and cannot be READ is not the same as one that is not
    /// there. Folding the two together would send Dan to launch Downbeat when the
    /// real answer is a damaged file, or the other way about.
    @Test("an export that cannot be opened is told apart from one that is absent")
    func anUnreadableFileIsNotAMissingOne() {
        var store: [Client] = []
        let result = ClientImportRunner.run(file: Self.url, held: &store) { _ in
            throw CocoaError(.fileReadNoPermission)
        }
        guard case .couldNotRead = result.notices[0] else {
            Issue.record("expected couldNotRead, got \(result.notices[0])")
            return
        }
    }

    // MARK: the file is there and will not decode

    @Test("an export that does not decode is reported with its cause, and changes nothing")
    func aDamagedExportChangesNothing() {
        var store = [Self.held("Already here", email: "held@example.com")]
        let result = ClientImportRunner.run(file: Self.url, held: &store) { _ in
            Data("not json at all".utf8)
        }
        #expect(result.created.isEmpty)
        #expect(store.count == 1)
        #expect(store[0].email == "held@example.com")
        guard case .couldNotRead(_, let refusal) = result.notices[0] else {
            Issue.record("expected couldNotRead, got \(result.notices[0])")
            return
        }
        guard case .notReadable = refusal else {
            Issue.record("expected the cause to be carried, got \(refusal)")
            return
        }
    }

    /// THE SENTENCE MUST SAY THE ROSTER IS UNHARMED. A refusal that only says it
    /// failed reads as data loss on a screen about clients, and the true and
    /// reassuring half is that nothing was touched.
    @Test("a refusal says the client list has not been changed")
    func aRefusalSaysTheRosterIsUntouched() {
        var store: [Client] = []
        let result = ClientImportRunner.run(file: Self.url, held: &store) { _ in
            Data("not json at all".utf8)
        }
        #expect(result.notices[0].sentence.contains("has not been changed"))
        #expect(result.notices[0].sentence.contains("downbeat-export.json"))
    }

    // MARK: the file is there and reads

    @Test("a good export against an empty store creates its clients and says so")
    func aGoodExportPopulatesTheRoster() {
        var store: [Client] = []
        let result = ClientImportRunner.run(file: Self.url, held: &store) { _ in
            Self.bytes(clients: Self.oneRow())
        }
        #expect(result.created.count == 1)
        #expect(store.count == 1)
        guard case .broughtAcross(let count) = result.notices[0] else {
            Issue.record("expected broughtAcross, got \(result.notices[0])")
            return
        }
        #expect(count == 1)
    }

    /// EVERY LAUNCH AFTER THE FIRST IS THIS ONE. A run that only refreshed fields
    /// nobody can see must say nothing at all, or the notice appears on every
    /// launch and becomes the one Dan learns to click past (L36).
    @Test("a run with nothing new to say says nothing")
    func aQuietRunIsSilent() {
        let id = UUID()
        var store = [Self.held("A choir", email: "a@example.com", downbeat: id)]
        let result = ClientImportRunner.run(file: Self.url, held: &store) { _ in
            Self.bytes(clients: Self.oneRow(id: id))
        }
        #expect(result.created.isEmpty)
        #expect(result.notices.isEmpty)
    }

    /// A row that could not be acted on needs Dan, so it is the one outcome that
    /// speaks even though nothing changed.
    @Test("rows that could not be acted on are reported, with their count")
    func rowsNeedingDanAreReported() {
        var store = [Self.held("Shared one", email: "shared@example.com"),
                     Self.held("Shared two", email: "shared@example.com")]
        let result = ClientImportRunner.run(file: Self.url, held: &store) { _ in
            Self.bytes(clients: Self.oneRow(email: "shared@example.com"))
        }
        #expect(result.created.isEmpty)
        guard case .needsYou(let count) = result.notices[0] else {
            Issue.record("expected needsYou, got \(result.notices[0])")
            return
        }
        #expect(count == 1)
    }

    // MARK: where the file is

    /// THE ONE PATH DOWNBEAT WRITES. It sits under Overture's folder rather than
    /// Ovation's, because Downbeat wrote it for Overture first and all three apps
    /// now read the same file; Downbeat publishes it in its own CONTRACT.md. This
    /// asserts the value so a rename on either side is caught here rather than by
    /// an empty roster.
    @Test("the export is read from the one path Downbeat writes")
    func theProductionPathIsTheOneDownbeatWrites() {
        let support = URL(fileURLWithPath: "/Users/someone/Library/Application Support")
        let url = ClientImportRunner.productionURL(applicationSupportDirectory: support)
        #expect(url.path == "/Users/someone/Library/Application Support/Overture/downbeat-export.json")
    }

    /// Every notice has to be a sentence Dan can act on rather than a case name,
    /// and each has to name the file it is about.
    @Test("every notice says something, and names what it is about")
    func everyNoticeHasASentence() {
        let notices: [ClientImportNotice] = [
            .exportMissing(file: "downbeat-export.json"),
            .couldNotRead(file: "downbeat-export.json", refusal: .versionMissing),
            .broughtAcross(count: 31),
            .needsYou(count: 2)
        ]
        for notice in notices {
            #expect(notice.sentence.count > 40,
                    Comment(rawValue: "\(notice) says too little"))
            #expect(!notice.subject.isEmpty,
                    Comment(rawValue: "\(notice) has nothing to be deduplicated on"))
        }
    }

    /// THE SUBJECT IS STABLE ACROSS LAUNCHES, so one standing condition seen on
    /// ten launches is one problem seen ten times rather than ten problems. This
    /// is the same rule `ExportNotice` already follows.
    @Test("the same standing condition keeps the same subject")
    func aStandingConditionKeepsItsSubject() {
        #expect(ClientImportNotice.exportMissing(file: "a.json").subject
                == ClientImportNotice.exportMissing(file: "a.json").subject)
        #expect(ClientImportNotice.broughtAcross(count: 1).subject
                == ClientImportNotice.broughtAcross(count: 31).subject)
    }
}

import BackstageGoogle
import Foundation
import SwiftData
import Testing

/// ovation#362. A review's number given back after the app quits mid review, and a
/// sent one never reissued, whatever moment the app dies at.
///
/// WHY A RECORD AND NOT A GUESS. At launch a numbered, unsent invoice looks the same
/// whether the app quit mid review or a moment after Gmail accepted the message and
/// before the send was recorded. In the second case the client holds that number, and
/// giving it back puts one number on two invoices (PRD 6, L186, L33). So the invoice
/// records that a review holds its number, in the save that takes it, and the send's
/// attempt, written BEFORE Gmail is called, lets go of it in its own save. A crash on
/// either side of the Gmail call can then only keep a number, never return a sent one.
///
/// THE CRASH IS A REAL ONE, as far as a test can make it: a store on disk, the
/// container that wrote it dropped without anything closing the review, and a new
/// container opened over the same file, which is what the next launch does.
@MainActor
struct ReviewHeldNumberTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let clients = #"{"fromName":"Dan Wright","fromEmail":"dan@studio.example","destination":"clients"}"#

    private static func scratchStore(_ label: String) throws -> URL {
        let directory = URL.temporaryDirectory
            .appending(path: "ovation-held-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Ovation.store")
    }

    private static func settingsFile() throws -> URL {
        let folder = URL.temporaryDirectory
            .appending(path: "ovation-held-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "sending.json")
        try Data(Self.clients.utf8).write(to: url)
        return url
    }

    /// A reviewable draft with no number, the way a real draft reaches Review. Its
    /// `id` is returned rather than its persistent identifier, because the identifier
    /// is re-read from whichever container is open after the "crash".
    @discardableResult
    private static func draft(in container: ModelContainer, name: String = "Ordinary") throws -> UUID {
        let context = container.mainContext
        let invoice = try InvoiceFixtures.invoice(name, in: context)
        invoice.client?.email = "booker@client.example"
        // THE DESIGN FIXTURES CARRY THE NUMBER THEIR PAGE PRINTS, and a real draft
        // reaches Review with none.
        invoice.number = nil
        for shoot in invoice.shoots {
            shoot.shotFrom = ClockTime("19:00")
            shoot.shotUntil = ClockTime("20:00")
        }
        try context.save()
        return invoice.id
    }

    /// A second design fixture, so two drafts are two different invoices.
    private static func anotherFixture() throws -> String {
        try #require(try InvoiceFixtures.labels.first { $0 != "Ordinary" })
    }

    /// What the STORE holds for one invoice, through a fresh context (L225).
    private static func stored(_ id: UUID, in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
    }

    private static func modelID(_ id: UUID, in container: ModelContainer) throws -> PersistentIdentifier {
        try Self.stored(id, in: container).persistentModelID
    }

    private static func reviewer(_ container: ModelContainer, settings: URL?,
                                 gmail: any MailSender) -> InvoiceReviewer {
        let noon = Self.noon
        return InvoiceReviewer(container: container, footer: { .fixed }, settingsFile: settings,
                               makeSender: { _ in .success(SendingRoute(sender: gmail, ready: { nil })) },
                               clock: { noon })
    }

    /// Gmail that, at the moment it is handed the message, reads what the STORE says
    /// about the invoice, and then never answers. What it read is the proof the hold
    /// was let go of before the external call rather than after it.
    final class StoreReadingGmail: MailSender, @unchecked Sendable {
        let container: ModelContainer
        let invoiceID: UUID
        private(set) var heldWhenHandedOver: Bool?
        private(set) var statusWhenHandedOver: SentStatus?

        init(container: ModelContainer, invoiceID: UUID) {
            self.container = container
            self.invoiceID = invoiceID
        }

        func send(_ mail: OutgoingMail) async throws -> SentReceipt {
            let row = try ModelContext(container).fetch(FetchDescriptor<Invoice>()).first { $0.id == invoiceID }
            heldWhenHandedOver = row?.numberHeldByAReview
            statusWhenHandedOver = row?.sentStatus
            throw URLError(.timedOut)
        }

        func measure(_ mail: OutgoingMail) throws -> MailSizeMeasurement {
            MailSizeMeasurement(encodedBytes: mail.attachments.reduce(0) { $0 + $1.data.count },
                                limitBytes: GmailSendLimits.maxRequestBytes)
        }
    }

    // MARK: the record

    @Test("a review's number is recorded as held in the same save that takes it, and an import's is not")
    func theHoldIsWrittenWithTheNumber() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let reviewed = Invoice(client: nil, kind: .fromABooking, invoiceDate: .stamping(Self.noon),
                               hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(reviewed)
        context.insert(Client(name: "Fictive Quartet", taxStatus: .exempt))
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: reviewed.persistentModelID)
        try await QuickBooksImportFixture.write(QuickBooksImportFixture.run([.init(number: "1500")]),
                                                into: container)

        let heldRow = try Self.stored(reviewed.id, in: container)
        #expect(heldRow.number == number)
        #expect(heldRow.numberHeldByAReview, "the number went in without the record that a review holds it")
        let imported = try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.number == 1_500 })
        #expect(!imported.numberHeldByAReview, "a number QuickBooks issued is not a review's to give back")
    }

    @Test("the send lets go of the hold in the save written before Gmail is called")
    func theAttemptLetsGoBeforeGmail() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let id = try Self.draft(in: container)
        let gmail = StoreReadingGmail(container: container, invoiceID: id)
        let reviewer = Self.reviewer(container, settings: try Self.settingsFile(), gmail: gmail)

        let review = try await reviewer.open(try Self.modelID(id, in: container)).get()
        #expect(try Self.stored(id, in: container).numberHeldByAReview)
        await review.send()

        guard case .couldNotTell = review.state else { Issue.record("got \(review.state)"); return }
        #expect(gmail.heldWhenHandedOver == false,
                "Gmail was handed the message while the store still said a review held the number")
        if case .attempting = gmail.statusWhenHandedOver {} else {
            Issue.record("the attempt was not in the store when Gmail was called: \(String(describing: gmail.statusWhenHandedOver))")
        }
    }

    // MARK: a sent number is never reissued

    /// THE RULE DAN SET ON 2026-09-21, asked of the allocator itself rather than of the
    /// order the screens happen to call it in. An invoice whose send was attempted and
    /// then cleared as not gone is a draft again, `notSent`, which is the one state
    /// `release` used to allow. It must still refuse, because Dan can be wrong about
    /// whether it went, and the next number issued must be a new one.
    @Test("a number a send was attempted with is refused, even once it is a draft again, and never reissued",
          arguments: ["cleared by Dan", "refused by Gmail"])
    func anAttemptedNumberIsNeverReissued(how: String) async throws {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let attempted = Invoice(client: nil, kind: .fromABooking, invoiceDate: .stamping(Self.noon),
                                hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        let next = Invoice(client: nil, kind: .fromABooking, invoiceDate: .stamping(Self.noon),
                           hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(attempted)
        context.insert(next)
        try context.save()
        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let number = try await allocator.allocate(to: attempted.persistentModelID)

        let writer = ModelContext(container)
        let row = try #require(try writer.fetch(FetchDescriptor<Invoice>()).first { $0.id == attempted.id })
        row.recordSendState(.attempting(SendAttempt(destination: ["booker@client.example"], wasRedirected: false,
                                                    renderSHA256: "abc", startedAt: Self.noon)))
        try writer.save()
        if how == "cleared by Dan" {
            try await SendSettler(modelContainer: container).markNotSent(attempted.persistentModelID)
        } else {
            row.recordSendState(.notSent)
            try writer.save()
        }
        #expect(try Self.stored(attempted.id, in: container).sentStatus == .notSent)

        await #expect(throws: InvoiceNumberRefusal.notHeldByAReview(number: number)) {
            try await allocator.release(number, from: attempted.persistentModelID)
        }
        let sweep = try await allocator.releaseNumbersAbandonedReviewsHeld()
        #expect(sweep.released.isEmpty, "the launch sweep gave back a number a client may hold")
        #expect(try Self.stored(attempted.id, in: container).number == number)
        #expect(try await allocator.allocate(to: next.persistentModelID) == number + 1,
                "the next invoice was issued a number a send was attempted with")
    }

    // MARK: the crash, on either side of the Gmail call

    @Test("a quit between taking the number and the send gives the number back at the next launch")
    func aQuitBeforeTheSendGivesItBack() async throws {
        let url = try Self.scratchStore("before-send")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reviewedID: UUID
        let number: Int64
        do {
            let container = try OvationSchema.container(at: url)
            reviewedID = try Self.draft(in: container)
            let gmail = InvoiceSenderTests.FakeGmail()
            let review = try await Self.reviewer(container, settings: try Self.settingsFile(), gmail: gmail)
                .open(try Self.modelID(reviewedID, in: container)).get()
            number = review.number
            // THE APP DIES HERE: the sheet is open, nothing closes it, nothing is sent.
            #expect(gmail.sent.isEmpty)
        }

        let relaunched = try OvationSchema.container(at: url)
        #expect(try Self.stored(reviewedID, in: relaunched).number == number,
                "the store did not hold what the review took, so this proves nothing")
        let sweep = try await InvoiceNumberAllocator(modelContainer: relaunched).releaseNumbersAbandonedReviewsHeld()

        #expect(sweep.released == [number])
        let after = try Self.stored(reviewedID, in: relaunched)
        #expect(after.number == nil)
        #expect(!after.numberHeldByAReview)
        let nextID = try Self.draft(in: relaunched, name: try Self.anotherFixture())
        #expect(try await InvoiceNumberAllocator(modelContainer: relaunched)
            .allocate(to: try Self.modelID(nextID, in: relaunched)) == number,
                "the number went back into the sequence rather than leaving a hole")
    }

    @Test("a quit after the attempt was written keeps the number, whatever Dan says afterwards")
    func aQuitDuringTheSendKeepsIt() async throws {
        let url = try Self.scratchStore("during-send")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reviewedID: UUID
        let number: Int64
        do {
            let container = try OvationSchema.container(at: url)
            reviewedID = try Self.draft(in: container)
            let gmail = StoreReadingGmail(container: container, invoiceID: reviewedID)
            let review = try await Self.reviewer(container, settings: try Self.settingsFile(), gmail: gmail)
                .open(try Self.modelID(reviewedID, in: container)).get()
            number = review.number
            await review.send()
            // THE APP DIES HERE: Gmail has the message, and it never answered.
        }

        let relaunched = try OvationSchema.container(at: url)
        let allocator = InvoiceNumberAllocator(modelContainer: relaunched)
        #expect(try await allocator.releaseNumbersAbandonedReviewsHeld().released.isEmpty)
        #expect(try Self.stored(reviewedID, in: relaunched).number == number)

        // DAN SAYS IT DID NOT GO, and the number still stays (Dan, 2026-09-21).
        try await SendSettler(modelContainer: relaunched)
            .markNotSent(try Self.modelID(reviewedID, in: relaunched))
        #expect(try await allocator.releaseNumbersAbandonedReviewsHeld().released.isEmpty,
                "a later launch gave back the number of an invoice that may have gone")
        #expect(try Self.stored(reviewedID, in: relaunched).number == number)
        let nextID = try Self.draft(in: relaunched, name: try Self.anotherFixture())
        #expect(try await allocator.allocate(to: try Self.modelID(nextID, in: relaunched)) == number + 1)
    }

    // MARK: the sweep's own rules

    /// Two reviews open at the quit. Each give back is refused unless it is the
    /// highest, so the sweep has to work down from the top, or it would keep the
    /// lower one for no reason.
    @Test("the sweep gives back several held numbers from the top down, leaving no gap")
    func theSweepWorksDownFromTheTop() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        var drafts: [Invoice] = []
        for _ in 0..<3 {
            let draft = Invoice(client: nil, kind: .fromABooking, invoiceDate: .stamping(Self.noon),
                                hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
            context.insert(draft)
            drafts.append(draft)
        }
        try context.save()
        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let first = try await allocator.allocate(to: drafts[0].persistentModelID)
        let second = try await allocator.allocate(to: drafts[1].persistentModelID)
        let third = try await allocator.allocate(to: drafts[2].persistentModelID)

        let sweep = try await allocator.releaseNumbersAbandonedReviewsHeld()

        #expect(sweep.released == [third, second, first])
        #expect(sweep.kept.isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Invoice>()).allSatisfy { $0.number == nil })
    }

    /// A held number under one that is not held cannot go back without a hole, so the
    /// sweep keeps it and says why, and the invoice's next review REUSES it rather
    /// than refusing to open (the issue's last sentence).
    @Test("a held number under a higher one is kept, and the invoice's next review reuses it")
    func aKeptHoldIsReusedByTheNextReview() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let heldID = try Self.draft(in: container)
        let aboveID = try Self.draft(in: container, name: try Self.anotherFixture())
        let allocator = InvoiceNumberAllocator(modelContainer: container)
        let held = try await allocator.allocate(to: try Self.modelID(heldID, in: container))
        let above = try await allocator.allocate(to: try Self.modelID(aboveID, in: container))
        // The one above went to Gmail and never came back, so it is not held.
        let writer = ModelContext(container)
        let aboveRow = try #require(try writer.fetch(FetchDescriptor<Invoice>()).first { $0.id == aboveID })
        aboveRow.recordSendState(.attempting(SendAttempt(destination: ["booker@client.example"], wasRedirected: false,
                                                         renderSHA256: "abc", startedAt: Self.noon)))
        try writer.save()

        let sweep = try await allocator.releaseNumbersAbandonedReviewsHeld()
        #expect(sweep.released.isEmpty)
        #expect(sweep.kept == [held: .notTheHighest(number: held, highest: above)])

        let review = try await Self.reviewer(container, settings: nil, gmail: InvoiceSenderTests.FakeGmail())
            .open(try Self.modelID(heldID, in: container)).get()
        #expect(review.number == held)
        #expect(review.numberTakenHere == held, "the review did not take up the number its earlier review left")
        #expect(try Self.stored(heldID, in: container).numberHeldByAReview)
    }

    /// And where nothing stands above it, closing that reused review gives the number
    /// back, so a sweep that could not run leaves nothing stuck.
    @Test("closing a review that reused a held number gives it back")
    func closingAReusedHoldGivesItBack() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let id = try Self.draft(in: container)
        let number = try await InvoiceNumberAllocator(modelContainer: container)
            .allocate(to: try Self.modelID(id, in: container))
        let reviewer = Self.reviewer(container, settings: nil, gmail: InvoiceSenderTests.FakeGmail())

        let review = try await reviewer.open(try Self.modelID(id, in: container)).get()
        #expect(review.number == number)
        await reviewer.close(review)

        #expect(try Self.stored(id, in: container).number == nil)
    }

    /// A number with no hold, which is every number an older version of the app took,
    /// is kept by the sweep: nothing recorded whether a send was attempted with it, and
    /// not knowing is not knowing it was not.
    @Test("a numbered draft with no hold recorded is never given back by the sweep")
    func aNumberWithNoHoldIsKept() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let old = Invoice(client: nil, kind: .fromABooking, invoiceDate: .stamping(Self.noon),
                          hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        old.number = 1_140
        context.insert(old)
        try context.save()

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        #expect(try await allocator.releaseNumbersAbandonedReviewsHeld() == .init(released: [], kept: [:]))
        await #expect(throws: InvoiceNumberRefusal.notHeldByAReview(number: 1_140)) {
            try await allocator.release(1_140, from: old.persistentModelID)
        }
        #expect(try Self.stored(old.id, in: container).number == 1_140)
    }

    // MARK: a sweep that fails is said, and clears itself (Dan, 2026-09-29)

    /// THE SENTENCE IS DAN'S, word for word, so it is asserted whole rather than by a
    /// fragment a different sentence could also contain (L347).
    @Test("a launch sweep that fails is raised in the problems list with Dan's sentence")
    func aFailedSweepIsSaid() async throws {
        struct Refused: Error {}
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())

        await AbandonedReviewNumbers.giveBack(sweep: { throw Refused() }, problems: problems, now: Self.noon)

        let said = try #require(problems.open.first { $0.kind == .reviewNumbersNotReleased })
        #expect(said.sentence == "Unused invoice numbers could not be released. Ovation will try again next launch.")
    }

    @Test("a later launch whose sweep succeeds clears the problem, and one that finds nothing clears it too")
    func aLaterSweepClearsIt() async throws {
        struct Refused: Error {}
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        await AbandonedReviewNumbers.giveBack(sweep: { throw Refused() }, problems: problems, now: Self.noon)
        #expect(problems.open.contains { $0.kind == .reviewNumbersNotReleased })

        await AbandonedReviewNumbers.giveBack(sweep: { AbandonedReviewSweep(released: [], kept: [:]) },
                                              problems: problems, now: Self.noon.addingTimeInterval(86_400))

        #expect(!problems.open.contains { $0.kind == .reviewNumbersNotReleased },
                "a sweep that worked left the failure standing")
    }

    /// And over a real store: the launch's own entry point runs the sweep.
    @Test("the launch entry point gives back a held number over a real store and raises nothing")
    func theLaunchEntryPointSweeps() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let id = try Self.draft(in: container)
        _ = try await InvoiceNumberAllocator(modelContainer: container)
            .allocate(to: try Self.modelID(id, in: container))
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())

        await AbandonedReviewNumbers.giveBack(over: container, problems: problems, now: Self.noon)

        #expect(try Self.stored(id, in: container).number == nil)
        #expect(problems.open.isEmpty)
    }

    /// A SWEEP THAT RAN IS NOT A SWEEP THAT WORKED (review of fb781b4). A number the
    /// store would not let go of, which the allocator calls not ignorable, is the same
    /// failure as a sweep that threw: it raises the problem, and it never resolves one.
    @Test("a number the store would not let go of raises the problem, and does not resolve an open one")
    func aReadBackFailureIsSaid() async throws {
        struct Refused: Error {}
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        let disagreed = AbandonedReviewSweep(
            released: [], kept: [1_123: .readBackDisagreed(wrote: 1_123, found: 1_123)])

        await AbandonedReviewNumbers.giveBack(sweep: { disagreed }, problems: problems, now: Self.noon)
        let said = try #require(problems.open.first { $0.kind == .reviewNumbersNotReleased })
        #expect(said.sentence == AbandonedReviewNumbers.couldNotRelease)

        await AbandonedReviewNumbers.giveBack(sweep: { disagreed }, problems: problems,
                                              now: Self.noon.addingTimeInterval(86_400))
        #expect(problems.open.contains { $0.kind == .reviewNumbersNotReleased },
                "a sweep that could not release a number resolved the problem saying so")
    }

    /// And a number kept BY RULE is the sweep working: a lower number with a higher one
    /// above it, or a deleted draft's, stays by design and its next review takes it up.
    @Test("numbers kept by rule are a sweep that worked, so they resolve the problem and raise nothing")
    func numbersKeptByRuleResolve() async throws {
        struct Refused: Error {}
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        await AbandonedReviewNumbers.giveBack(sweep: { throw Refused() }, problems: problems, now: Self.noon)

        let byRule = AbandonedReviewSweep(released: [1_130], kept: [
            1_125: .notTheHighest(number: 1_125, highest: 1_129),
            1_126: .invoiceIsClosed(number: 1_126),
        ])
        await AbandonedReviewNumbers.giveBack(sweep: { byRule }, problems: problems,
                                              now: Self.noon.addingTimeInterval(86_400))

        #expect(!problems.open.contains { $0.kind == .reviewNumbersNotReleased })
    }

    // MARK: who may write the hold (review of 8a0073b)

    /// The app's source files calling `name(`, by file name. Tests are not scanned: a
    /// test constructing an unsaved invoice is not a writer of the store.
    private static func callers(of name: String, _ file: StaticString = #filePath) throws -> Set<String> {
        let root = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Ovation")
        var found: Set<String> = []
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            // A CALL, not the declaration: `func name(` is where it is written.
            let calls = text.components(separatedBy: "\(name)(").count - 1
            let declarations = text.components(separatedBy: "func \(name)(").count - 1
            if calls > declarations { found.insert(url.lastPathComponent) }
        }
        return found
    }

    /// SWIFT CANNOT LIMIT A METHOD TO ONE OTHER FILE, so "only the allocator calls
    /// it" is a convention, and this is what holds it (L407). A second writer of the
    /// hold would decide which numbers a launch gives back without the allocator's
    /// refusals, which is the one thing ovation#362 exists to prevent.
    @Test("only the allocator takes or gives back a review's hold, anywhere in the app")
    func onlyTheAllocatorWritesTheHold() throws {
        for name in ["holdNumberForAReview", "giveBackReviewedNumber"] {
            #expect(try Self.callers(of: name) == ["InvoiceNumberAllocator.swift"],
                    "\(name) is called outside the allocator")
        }
        // The control (L98): a scan that read nothing would find no callers at all,
        // and the expectation above would fail on that rather than pass.
        #expect(try Self.callers(of: "recordSendState").count >= 2)
    }
}

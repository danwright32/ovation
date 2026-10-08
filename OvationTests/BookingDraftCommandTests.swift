import Foundation
import SwiftData
import Testing

/// ovation#461. The control that turns what is in the queue into drafts.
///
/// BUILT IS NOT WIRED (L3). `BookingDrafter` could be perfect and reached by
/// nothing, which is the state `YearEndExport` shipped in and ovation#162 had to
/// go back and fix: a remedy nobody can reach leaves pressing on as the only
/// diagnosis available.
///
/// EVERY PATH SAYS SOMETHING, including the ones that drafted nothing. A press
/// that worked and said nothing is indistinguishable from one that did nothing,
/// and the two ways of drafting nothing (never queued, queued and empty) are two
/// sentences because they mean different things (L98, L215).
@MainActor
struct BookingDraftCommandTests {

    private static func fixtureData(_ file: StaticString = #filePath) throws -> Data {
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appending(path: "Fixtures/handoff-record-v3-2026-09-06.json"))
    }

    private static func directory(holding files: [String: Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ovation-press-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: url.appending(path: name)) }
        return url
    }

    private static func problems() -> ProblemsStore {
        ProblemsStore(journal: InMemoryProblemsJournal())
    }

    /// A launch day confirmed in a throwaway defaults suite, never Dan's (L201).
    /// The default is a day before the fixture was committed (2026-09-06 in New
    /// York), so the cases that are not about the cutoff draft as they always did.
    private static func launchedEarlier(_ day: String = "2026-09-01") throws -> LaunchCutoffSetting {
        let throwaway = try ThrowawayDefaults()
        let setting = LaunchCutoffSetting(defaults: throwaway.defaults)
        setting.confirm(try #require(LaunchDay(dayKey: day)))
        return setting
    }

    private static let fixtureFile = "5FEBD76A-2685-4967-8C39-8D40B7151D34.json"

    /// Presses and waits for the press to FINISH, on the condition itself rather
    /// than on a duration, because a fixed wait asserts about the machine's load
    /// (L290).
    private static func press(_ command: BookingDraftCommand, container: ModelContainer?,
                              problems: ProblemsStore) async {
        await withCheckedContinuation { resumed in
            command.press(now: Date(), container: container, problems: problems) {
                resumed.resume()
            }
        }
    }

    // MARK: a press that drafts

    @Test("a press over a queue holding one record leaves one draft in the store, and says so")
    func apressDraftsWhatIsThere() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let command = BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: try Self.directory(holding: [
            "5FEBD76A-2685-4967-8C39-8D40B7151D34.json": try Self.fixtureData(),
        ]))
        let problems = Self.problems()

        await Self.press(command, container: container, problems: problems)

        let invoices = try ModelContext(container).fetch(FetchDescriptor<Invoice>())
        #expect(invoices.count == 1)
        guard case .finished(_, let said) = command.progress else {
            Issue.record("the press did not finish: \(command.progress)")
            return
        }
        #expect(said.contains("drafted 1"), "the press said \(said)")
        #expect(problems.open.contains { $0.kind == .bookingsDrafted })
    }

    /// PRESSED TWICE, ONE DRAFT. The queue is not consumed, so the second press
    /// reads the same record, and this is the surface where that would show.
    @Test("pressing twice over the same queue still leaves one draft")
    func pressingTwiceLeavesOneDraft() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let command = BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: try Self.directory(holding: [
            "5FEBD76A-2685-4967-8C39-8D40B7151D34.json": try Self.fixtureData(),
        ]))
        let problems = Self.problems()

        await Self.press(command, container: container, problems: problems)
        await Self.press(command, container: container, problems: problems)

        let invoices = try ModelContext(container).fetch(FetchDescriptor<Invoice>())
        #expect(invoices.count == 1, "two presses left \(invoices.count) drafts")
        guard case .finished(_, let said) = command.progress else {
            Issue.record("the second press did not finish")
            return
        }
        #expect(said.contains("1 already drafted"), "the second press said \(said)")
    }

    /// AND THE QUEUE IS NOT TOUCHED BY A PRESS. The one instrument that watches
    /// the disk deliberately does not watch this directory, so the assertion has
    /// to be made here (L201, L212, L375).
    @Test("a press leaves the queue file exactly as it found it")
    func apressLeavesTheQueueAlone() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let queue = try Self.directory(holding: [
            "5FEBD76A-2685-4967-8C39-8D40B7151D34.json": try Self.fixtureData(),
        ])
        let file = queue.appending(path: "5FEBD76A-2685-4967-8C39-8D40B7151D34.json")
        let before = try Data(contentsOf: file)
        let written = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]
            as? Date

        await Self.press(BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: queue), container: container,
                         problems: Self.problems())

        let after = try Data(contentsOf: file)
        let names = try FileManager.default.contentsOfDirectory(atPath: queue.path)
        let writtenAfter = try FileManager.default
            .attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        #expect(after == before)
        #expect(names.count == 1)
        #expect(writtenAfter == written)
    }

    // MARK: the ways a press drafts nothing, which are not one way

    @Test("a queue folder that was never created says that, and not that the queue is empty")
    func anevermadeQueueSaysSo() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "ovation-never-\(UUID().uuidString)", directoryHint: .isDirectory)
        let problems = Self.problems()

        await Self.press(BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: missing), container: container,
                         problems: problems)

        let raised = try #require(problems.open.first { $0.kind == .bookingDraftRefused })
        #expect(raised.sentence.contains("never handed a booking over"))
    }

    @Test("a queue folder that is there and empty says something else")
    func anemptyQueueSaysSomethingElse() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let problems = Self.problems()

        await Self.press(BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: try Self.directory(holding: [:])),
                         container: container, problems: problems)

        let raised = try #require(problems.open.first { $0.kind == .bookingDraftRefused })
        #expect(raised.sentence.contains("is empty"), "it said \(raised.sentence)")
    }

    /// AN UNREADABLE RECORD IS A BOOKING THAT MAY NEVER BE INVOICED, which is the
    /// one outcome that means a shoot went unbilled (PRD 1). It is raised by
    /// NAME, and it does not stop the readable record beside it being drafted.
    @Test("a damaged record is raised by name, and the good one beside it is still drafted")
    func adamagedRecordIsRaisedAndTheOtherDrafted() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let problems = Self.problems()
        let queue = try Self.directory(holding: [
            "5FEBD76A-2685-4967-8C39-8D40B7151D34.json": try Self.fixtureData(),
            "damaged.json": Data("{ not json".utf8),
        ])

        await Self.press(BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: queue), container: container,
                         problems: problems)

        let raised = try #require(problems.open.first { $0.kind == .bookingRecordUnreadable })
        #expect(raised.sentence.contains("damaged.json"))
        let invoices = try ModelContext(container).fetch(FetchDescriptor<Invoice>())
        #expect(invoices.count == 1, "the damaged record stopped the readable one")
    }

    // MARK: what the control says when it cannot run

    /// A DISABLED CONTROL WITH NO REASON IS A DEAD CONTROL (L109), and a press
    /// that cannot run still SAYS so rather than doing nothing quietly.
    @Test("a launch with no store open refuses by name rather than doing nothing")
    func nostoreRefusesByName() async throws {
        let command = BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: try Self.directory(holding: [:]))
        let problems = Self.problems()
        #expect(command.whyItCannotRun(container: nil)?.contains("no store open") == true)

        await Self.press(command, container: nil, problems: problems)

        #expect(problems.open.contains { $0.kind == .bookingDraftRefused })
    }

    /// A THROWAWAY LAUNCH HAS NO QUEUE AT ALL, which is the isolation floor doing
    /// its job rather than a fault, and it is said in those words.
    @Test("a launch with nowhere real to read from says that, and is not offered")
    func athrowawayLaunchSaysSo() async throws {
        let command = BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: nil)
        let problems = Self.problems()

        #expect(command.mayRun == false)
        #expect(command.whyItCannotRun(container: try OvationSchema.container(inMemory: true))?
                    .contains("throwaway run") == true)

        await Self.press(command, container: try OvationSchema.container(inMemory: true),
                         problems: problems)

        #expect(problems.open.contains { $0.kind == .bookingDraftRefused })
    }

    /// AND THE LIVE PATH IS THE ONE THE ISOLATION FLOOR ALREADY GUARDS, never a
    /// second resolver written here.
    /// `StoreLocation.liveBookingQueueDirectory` refuses a disposable launch and
    /// is registered in `LiveDataFloor`; building the path from
    /// `bookingQueueDirectory` instead would reach the real queue on a throwaway
    /// run, which is exactly what the floor exists to prevent (L196, L263).
    ///
    /// THE SUITE RUNS DISPOSABLE, so this asserts the refusal rather than the
    /// path: a case that saw a real directory here would mean the floor had
    /// stopped holding.
    @Test("the command built for this launch inherits the floor's refusal")
    func thecommandInheritsTheFloorsRefusal() throws {
        #expect(AppEnvironment.isDisposableLaunch(),
                "the suite is not running disposable, so the floor is not in force")

        let command = BookingDraftCommand.forThisLaunch(launchCutoff: try Self.launchedEarlier())

        #expect(command.queue == nil)
        #expect(command.mayRun == false)
    }

    /// WORKING, STILL ALIVE AND FAILED ARE THREE VISIBLE STATES, which is a
    /// standing rule in this product. `elapsed` is a measurement rather than a
    /// spinner, so a view can say how long a press has been going.
    @Test("a press in flight reports how long it has been going, and a finished one does not")
    func apressInFlightReportsItsAge() async throws {
        let command = BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: try Self.directory(holding: [:]))
        let started = Date(timeIntervalSince1970: 1_794_531_600)
        #expect(command.elapsed(now: started) == nil)

        command.press(now: started, container: try OvationSchema.container(inMemory: true),
                      problems: Self.problems())

        // Read while it is running, before the press's own task resumes.
        #expect(command.elapsed(now: started.addingTimeInterval(9)) == 9)
        #expect(command.mayRun == false)
        #expect(command.whyItCannotRun(container: try OvationSchema.container(inMemory: true))?
                    .contains("has not finished") == true)
    }

    // MARK: the launch cutoff (ovation#655, PRD 1d)

    /// THE DRAFT COMMAND WAITS ON THE LAUNCH DAY. The cutoff is recorded as a
    /// placeholder, and a placeholder nothing forces anybody to move drafts a
    /// second invoice for every booking QuickBooks billed in between. So the
    /// command is not offered, it says why and where that is fixed (L111), and a
    /// press anyway drafts nothing and says the same in the rail.
    @Test("with the launch day not confirmed the command refuses by name and drafts nothing")
    func anunconfirmedLaunchDayRefuses() async throws {
        let throwaway = try ThrowawayDefaults()
        let unconfirmed = LaunchCutoffSetting(defaults: throwaway.defaults)
        let container = try OvationSchema.container(inMemory: true)
        let command = BookingDraftCommand(launchCutoff: unconfirmed, queue: try Self.directory(holding: [
            Self.fixtureFile: try Self.fixtureData(),
        ]))
        let problems = Self.problems()

        #expect(command.mayRun == false)
        let why = try #require(command.whyItCannotRun(container: container))
        #expect(why == LaunchCutoff.notConfirmed.whyDraftingWaits)

        await Self.press(command, container: container, problems: problems)

        let raised = try #require(problems.open.first { $0.kind == .bookingDraftRefused })
        #expect(raised.sentence == why)
        let invoices = try ModelContext(container).fetch(FetchDescriptor<Invoice>())
        #expect(invoices.isEmpty, "a draft was made with the launch day unconfirmed")
    }

    /// CONFIRMING IN SETTINGS OPENS THE COMMAND WITHOUT A RELAUNCH. The menu reads
    /// the same setting object Settings writes, so the reason goes the moment the
    /// day is confirmed rather than at the next launch (L14, L175).
    @Test("confirming the launch day lets the same command run")
    func confirmingOpensTheCommand() async throws {
        let throwaway = try ThrowawayDefaults()
        let setting = LaunchCutoffSetting(defaults: throwaway.defaults)
        let command = BookingDraftCommand(launchCutoff: setting,
                                          queue: try Self.directory(holding: [:]))
        let container = try OvationSchema.container(inMemory: true)
        #expect(command.whyItCannotRun(container: container) != nil)

        setting.confirm(try #require(LaunchDay(dayKey: "2026-10-08")))

        #expect(command.whyItCannotRun(container: container) == nil)
        #expect(command.mayRun)
    }

    /// The measured record was committed on 2026-09-06; with launch day the 7th it
    /// was billed in QuickBooks, so the press makes no draft and SAYS so, rather
    /// than drafting nothing in silence (L98, L12).
    @Test("a booking from before launch day is left to QuickBooks, and the press says so")
    func abookingBeforeLaunchIsLeftToQuickBooks() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let command = BookingDraftCommand(launchCutoff: try Self.launchedEarlier("2026-09-07"),
                                          queue: try Self.directory(holding: [
                                            Self.fixtureFile: try Self.fixtureData(),
                                          ]))
        let problems = Self.problems()

        await Self.press(command, container: container, problems: problems)

        let invoices = try ModelContext(container).fetch(FetchDescriptor<Invoice>())
        #expect(invoices.isEmpty, "a draft was made for a booking QuickBooks billed")
        let raised = try #require(problems.open.first { $0.kind == .bookingsLeftToQuickBooks })
        #expect(raised.sentence.contains("QuickBooks"), "it said \(raised.sentence)")
        #expect(raised.sentence.contains("7 Sep 2026"), "it does not name launch day: \(raised.sentence)")
        guard case .finished(_, let said) = command.progress else {
            Issue.record("the press did not finish: \(command.progress)")
            return
        }
        #expect(said.contains("1 left to QuickBooks"), "the press said \(said)")
    }

    /// A draft the earlier build made for a booking QuickBooks billed is a second
    /// invoice waiting to be sent, and it is named by file so Dan can find it.
    @Test("a draft that already exists for a booking from before launch is raised by name")
    func anearlierDraftOfAQuickBooksBookingIsRaised() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let queue = try Self.directory(holding: [Self.fixtureFile: try Self.fixtureData()])
        await Self.press(BookingDraftCommand(launchCutoff: try Self.launchedEarlier(), queue: queue),
                         container: container, problems: Self.problems())
        let problems = Self.problems()

        await Self.press(BookingDraftCommand(launchCutoff: try Self.launchedEarlier("2026-09-07"),
                                             queue: queue),
                         container: container, problems: problems)

        let raised = try #require(problems.open.first {
            $0.kind == .bookingDraftAlsoBilledInQuickBooks
        })
        #expect(raised.sentence.contains(Self.fixtureFile), "it said \(raised.sentence)")
        #expect(!ProblemKind.closingOnceRead.contains(.bookingDraftAlsoBilledInQuickBooks),
                "a duplicate invoice still needs Dan, so it must stay open once read")
    }
}

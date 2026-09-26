// ovation#461. The control that turns what is in the queue into drafts, and the
// three states a press has to be able to be told apart in.
//
// WHY A CONTROL AND NOT A LAUNCH STEP. ovation#32's drain runs on its own and
// replaces this; until it exists, a press is the honest shape. A launch step
// would draft silently on every start, and a booking becoming an invoice is not
// something to discover afterwards (PRD 1b: a booking has three endings and each
// is RECORDED rather than inferred).
//
// WORKING, STILL ALIVE AND FAILED ARE THREE VISIBLE STATES. That is a standing
// rule in this product rather than a detail here, and `Progress` is how it is
// kept: `elapsed` is a measurement from a clock the caller passes, so a view can
// say how long a press has been going rather than only that it is going.
//
// IT IS NEVER HIDDEN, only disabled with the reason said out loud, because a
// control that is not there cannot be asked why (L49, L109).
//
// PRIVACY. What this SAYS carries counts, file names and booking ids, which are
// opaque. A client's display name reaches one sentence, the name only refusal,
// and it has to: the whole point of that refusal is that Dan looks at the client
// it found. Nothing here is written to the repository (L222,
// docs/PRIVACY-FLOOR.md).
import Foundation
import Observation
import SwiftData

extension ProblemKind {
    /// Drafts were made from the queue. Raised on success as well as failure,
    /// because a press that worked and said nothing is indistinguishable from one
    /// that did nothing (L98, L12).
    static let bookingsDrafted = ProblemKind("booking-queue.drafted")
    /// The press could not run at all, or ran and drafted nothing.
    static let bookingDraftRefused = ProblemKind("booking-queue.refused")
    /// A record is in the queue and Ovation cannot read it, which is a booking
    /// that may never be invoiced (PRD 1).
    static let bookingRecordUnreadable = ProblemKind("booking-queue.unreadable")
}

@Observable
@MainActor
final class BookingDraftCommand {

    /// The words on the control, in one place, so nothing quoting it can send Dan
    /// to a menu item that is not there (L70, L399).
    nonisolated static let title = "Draft from the booking queue"

    enum Progress: Equatable {
        case notStarted
        case running(since: Date)
        case finished(at: Date, said: String)
    }

    private(set) var progress: Progress = .notStarted

    /// Nil on a launch that may not touch anything real. Held as the ABSENCE
    /// rather than as a flag beside a path, so there is no way to run with one
    /// and not the other (L544).
    let queue: URL?

    init(queue: URL?) { self.queue = queue }

    /// The command for THIS launch.
    ///
    /// IT RESOLVES NOTHING NEW, and that is deliberate.
    /// `StoreLocation.liveBookingQueueDirectory` is already registered in
    /// `LiveDataFloor` and already refuses a throwaway launch, so composing it is
    /// what keeps the refusal structural rather than conventional. Building the
    /// path here from `bookingQueueDirectory` would reach the real queue on a
    /// disposable run, which is the one thing the floor exists to prevent (L196).
    ///
    /// NOT CALLED `live...`, because in this codebase that prefix names a
    /// resolver returning a URL and `check-isolation-floor.sh` requires every one
    /// of them in the floor. This composes one that is already there.
    static func forThisLaunch() -> BookingDraftCommand {
        BookingDraftCommand(queue: StoreLocation.liveBookingQueueDirectory())
    }

    var mayRun: Bool {
        guard queue != nil else { return false }
        if case .running = progress { return false }
        return true
    }

    /// Why a press would do nothing, or nil when it would run. Each cause is
    /// worded differently because each needs different work (L11).
    func whyItCannotRun(container: ModelContainer?) -> String? {
        if container == nil {
            return "There is no store open on this launch, so there is nowhere to "
                + "put a draft. The launch sequence either refused or has not run."
        }
        if case .running(let since) = progress {
            return "A run started at \(BusinessCalendar.dayKey(for: since)) has not "
                + "finished. Two at once would read the same records twice."
        }
        guard queue != nil else {
            return "This launch has no booking queue to read. It is a throwaway run, "
                + "kept away from the real records on purpose."
        }
        return nil
    }

    func elapsed(now: Date) -> TimeInterval? {
        guard case .running(let since) = progress else { return nil }
        return now.timeIntervalSince(since)
    }

    /// One press. Reads the queue, drafts what it can, and says what happened,
    /// on every path including the ones that drafted nothing.
    func press(now: Date, container: ModelContainer?, problems: ProblemsStore,
               afterwards: @escaping @MainActor () -> Void = {}) {
        guard let container, mayRun, let queue else {
            // ALWAYS SAYS SOMETHING, and the fallback is a sentence rather than
            // silence: the guard and the reasons are meant to cover the same
            // cases, and if they stop agreeing Dan hears about THAT (L109, L622).
            let why = whyItCannotRun(container: container)
                ?? "Ovation could not read the booking queue and cannot say why, "
                 + "which is a fault in Ovation rather than in the queue."
            _ = problems.raise(kind: .bookingDraftRefused, subject: "booking-queue",
                               sentence: why, now: now)
            afterwards()
            return
        }
        progress = .running(since: now)
        Task { @MainActor in
            let report = await Self.offTheMainActor(queue: queue, container: container,
                                                    today: .stamping(now))
            let finished = Date()
            for said in report.sentences {
                _ = problems.raise(kind: said.kind, subject: said.subject,
                                   sentence: said.sentence, now: finished)
            }
            progress = .finished(at: finished, said: report.summary)
            afterwards()
        }
    }

    /// What one press came to, as values only: nothing here is a stored model, so
    /// nothing crosses back out of the context that fetched it.
    struct Report: Equatable, Sendable {
        struct Said: Equatable, Sendable {
            let kind: ProblemKind
            let subject: String
            let sentence: String
        }
        let summary: String
        let sentences: [Said]
    }

    /// THE WORK HAPPENS OFF THIS ACTOR. It reads a directory and writes the
    /// store, and doing that on the thread that draws the result is how the whole
    /// window stops responding rather than the one surface that asked (L236,
    /// L241).
    /// `today` is the day of the press, which each drafted invoice is created on
    /// (ovation#510). Passed rather than read here, so no clock is hidden inside.
    private static func offTheMainActor(queue: URL, container: ModelContainer,
                                        today: BusinessDate) async -> Report {
        let reading = BookingQueue.read(directory: queue)
        var said: [Report.Said] = []

        for bad in reading.unreadable {
            said.append(Report.Said(
                kind: .bookingRecordUnreadable, subject: bad.file,
                sentence: "\(bad.file) is in the booking queue and Ovation cannot read it: "
                        + "\(HandoffRecord.sentence(for: bad.refusal, file: bad.file))"))
        }

        switch reading.state {
        case .directoryIsNotThere:
            return Report(summary: "Downbeat has never queued a booking on this Mac.",
                          sentences: said + [Report.Said(
                            kind: .bookingDraftRefused, subject: "booking-queue",
                            sentence: "There is no booking queue folder, so Downbeat has "
                                    + "never handed a booking over from this build.")])
        case .nothingQueued:
            return Report(summary: "The queue is there and empty.",
                          sentences: said + [Report.Said(
                            kind: .bookingDraftRefused, subject: "booking-queue",
                            sentence: "The booking queue is empty. Downbeat has handed "
                                    + "bookings over before, and there is nothing waiting now.")])
        case .read:
            break
        }

        let drafter = BookingDrafter(modelContainer: container)
        var drafted = 0
        var already = 0
        for queued in reading.records {
            do {
                switch try await drafter.draft(from: queued.record,
                                               at: Pricing.standardHourlyRate, on: today) {
                case .drafted:
                    drafted += 1
                case .alreadyDrafted:
                    already += 1
                case .refused(let refusal):
                    said.append(Report.Said(
                        kind: .bookingDraftRefused, subject: queued.file,
                        sentence: "\(queued.file) was not drafted. \(refusal.sentence)"))
                }
            } catch {
                // A THROW IS REPORTED, NEVER SWALLOWED. The store refused the
                // write, and a press that quietly drafted one fewer than it read
                // is the failure this whole surface exists to prevent (L10).
                said.append(Report.Said(
                    kind: .bookingDraftRefused, subject: queued.file,
                    sentence: "\(queued.file) could not be written to the store: \(error)"))
            }
        }

        if drafted > 0 {
            said.append(Report.Said(
                kind: .bookingsDrafted, subject: "booking-queue",
                sentence: "\(drafted) booking(s) from the queue are now drafts, waiting on "
                        + "the shoot times before they can be sent."))
        }
        let summary = "Read \(reading.records.count), drafted \(drafted), "
            + "\(already) already drafted, \(reading.unreadable.count) unreadable."
        return Report(summary: summary, sentences: said)
    }
}

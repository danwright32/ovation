// Plan 1.3, PRD 5.37, ovation#84. A second running copy stands aside and NAMES
// the copy it stood aside for.
//
// WHY IT MATTERS HERE. Two copies of Ovation over one store are two writers of
// Dan's invoices, and the serialized writers that make the rules enforceable
// (`PaymentAllocator`, `InvoiceNumberAllocator`, `ReferralLedger`) serialize
// within ONE process. Nothing in them can see a second process at all, so an
// invoice number issued twice, or a referral credit granted twice, is reachable
// only this way and by no test that runs inside one process.
//
// IT IS NOT `LSMultipleInstancesProhibited`, and that is a decision with a
// measured cost behind it rather than a preference. That key appears in
// Overture's Info.plist and nowhere in Downbeat, and Overture's own test runner
// records what it cost: a running Debug app holding that lock makes the xctest
// host fail to launch, so the run dies AFTER a full build, and the misdiagnosis
// "sent hours of elimination in the wrong direction". Downbeat implements the
// refusal in application code instead, and that is the sibling pattern rather
// than a workaround.
//
// IDENTIFY BY PID RESOLVED FROM THE EXECUTABLE PATH, never by name or bundle
// identifier, and the reason is measured in this estate: on 2026-08-04 a lookup
// by bundle identifier resolved to the Release app while the Debug one was
// intended, and a keystroke meant for one quit the other. Two copies of one app
// can be running and they differ only by where their executable is.
//
// THE DEBUG AND RELEASE BUILDS ARE NOT EACH OTHER'S SECOND COPY. They carry
// different bundle identities and different data directories on purpose
// (project.yml), so they share no store and must not stand aside for one
// another. Comparing executable PATHS is what gets this right for free: two
// builds live at two paths.
//
// HOW IT REACHES DAN: through the one launch presenter (ovation#59), never as an
// independent alert. It is one of the launch conditions that presenter exists to
// hold, and an independent alert is how all but one of them silently vanishes
// (L242, L243).
import Foundation

struct SecondInstance {

    /// What this launch found. Two answers, and the second carries WHICH copy, so
    /// the message can name it rather than saying that something is running (L11).
    enum Verdict: Equatable {
        case theOnlyCopy
        /// Another process is running the same executable. Carries its PID so Dan
        /// can find it, and the path so he can tell which build it is.
        case standingAsideFor(pid: Int32, executablePath: String)

        var mayRun: Bool {
            switch self {
            case .theOnlyCopy: return true
            case .standingAsideFor: return false
            }
        }
    }

    /// Every process running this exact executable, this one included.
    ///
    /// INJECTED, because a test that had to start a second copy of Ovation would
    /// have to open a window on Dan's screen to do it, and a check that
    /// constructs its own way of looking is beyond every refusal that lookup
    /// could offer (L196).
    typealias RunningPIDs = @Sendable (String) -> [Int32]

    /// The verdict for a launch.
    ///
    /// THE OWN PID IS EXCLUDED BY IDENTITY, not by taking all but the first or
    /// the lowest. A process list has no promised order, and "the other one" is
    /// whichever PID is not this one.
    static func check(
        executablePath: String,
        ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        runningPIDs: RunningPIDs
    ) -> Verdict {
        let others = runningPIDs(executablePath).filter { $0 != ownPID }
        // The LOWEST other PID is named, so two launches racing name the same
        // copy rather than each naming the other and reading as a disagreement.
        guard let other = others.min() else { return .theOnlyCopy }
        return .standingAsideFor(pid: other, executablePath: executablePath)
    }

    /// The sentence Dan reads. It names the PID and the path, because "Ovation is
    /// already running" is what somebody sees while looking at a Dock with two
    /// identical icons in it (ovation#103).
    static func sentence(for verdict: Verdict) -> String? {
        guard case .standingAsideFor(let pid, let path) = verdict else { return nil }
        return "Another copy of Ovation is already running (process \(pid), at \(path)). "
            + "This one has stood aside and opened nothing, because two copies sharing one "
            + "database can each believe they are the only writer, and an invoice number or a "
            + "referral credit issued twice is not something either of them would report. "
            + "Use the copy that is already open."
    }

    /// Every process running the executable at this path, by PID.
    ///
    /// `pgrep -f ^<path>$` is the same resolution `scripts/smoke-launch.sh`
    /// already uses and is anchored at both ends, so a path that is a PREFIX of
    /// another build's path cannot match it.
    static func pidsRunning(_ executablePath: String) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "^\(executablePath)$"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            // A LOOKUP THAT COULD NOT RUN IS NOT AN EMPTY ANSWER. Returning []
            // here would say "no other copy" on the strength of a failure, which
            // is the permissive answer arrived at by not looking (L215, L98).
            // Reported as its own pid so the caller sees a copy it cannot name,
            // which errs toward standing aside.
            return [-1]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }
}

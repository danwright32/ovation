// Ported-From: danwright32/downbeat Downbeat/Downbeat/App/AppStoreConfiguration.swift @ c199268e5d48101db73eca195eee300eabe731dc
//
// Port discipline: docs/PORT-DISCIPLINE.md. Only the launch scope predicate is
// taken from the source; the paths beside it in that file are Downbeat's own and
// Ovation's live in StoreLocation.
//
// WHAT DIFFERS FROM THE SOURCE, and why, rather than inherited:
//
//   The source carries THREE functions: isRunningUnderTests, isSyntheticStore
//   and isDisposableLaunch, the last being the union. Ovation takes ONE, named
//   for the question every call site actually has to ask.
//
//   The reason is the source's own history. Before downbeat#450 every refusal in
//   Downbeat asked isRunningUnderTests directly, so when a second way to be
//   not-real arrived, a synthetic launch would have fired real calendar URLs and
//   written real tasks while claiming to be safe. Several behaviours a design
//   treats as one condition must read ONE predicate, or the second is missing
//   wherever somebody only thought of the first (L261).
//
//   Ovation has one reason today. Naming it isRunningUnderTests would recreate
//   the exact defect the source had to repair, because the next reason would
//   arrive as a second function and every existing call site would go on asking
//   the old question. So there is one name, it asks the durable question, and a
//   second reason grows inside this function rather than beside it.
//
//   Downbeat also carries scripts/test-disposable-launch-scope.sh, which fails a
//   push that asks isRunningUnderTests anywhere outside that file. Ovation needs
//   no such guard while there is only one function to ask, and that is exactly
//   what changes on the day a second one is added: whoever adds it owns the
//   guard (ovation#58, the isolation floor).
//
// Downbeat has no open issue against this file.
import Foundation

enum AppEnvironment {
    /// Whether this launch may touch anything real: Dan's store, his documents,
    /// his mailbox, the queue Downbeat writes and Ovation drains by deleting.
    ///
    /// Every refusal in the app reads this one predicate. It is deliberately not
    /// called `isRunningUnderTests`: a caller asking "is this a test" writes a
    /// guard that is correct only for the reason it was written, and the reasons
    /// arrive later than the guards.
    ///
    /// `nonisolated` because it reads the process environment and nothing else,
    /// and the things that ask it are not all on the main actor. The project
    /// defaults unmarked declarations to the main actor.
    ///
    /// The default argument reads THIS process. A resolver that defaults to it
    /// refuses a caller who passes nothing, which is every test that was not
    /// written with the isolation floor in mind.
    nonisolated static func isDisposableLaunch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        // Xcode injects these into the process hosting a test bundle. Ovation's
        // suite is unhosted, so it is this process that carries them.
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    /// Whether this launch may reach live Google: Dan's real mailbox, and the
    /// token file that opens it.
    ///
    /// STRICTLY NARROWER THAN `isDisposableLaunch`, AND IT HAS TO BE ITS OWN
    /// QUESTION. ovation#425 asked for the Debug reason to grow INSIDE
    /// `isDisposableLaunch`, on the principle that several behaviours a design
    /// treats as one condition must read one predicate (L261). Followed literally
    /// it breaks the Debug build: every reader of `isDisposableLaunch` refuses
    /// under it, so `liveStoreURL`, the problems journal, the documents root, the
    /// export folder and the backups folder would all answer nil, and a Debug run
    /// would have no store at all. The whole point of the `Ovation-Debug` folder
    /// is that a Debug build HAS one, separate from Dan's.
    ///
    /// SO THEY ARE NOT ONE CONDITION. A disposable launch may touch nothing real.
    /// A Debug build is a real run with a real store of its own, and it may not
    /// touch Dan's mailbox (Dan, 2026-09-19). Writing the second as the first
    /// would not be sharing a predicate, it would be answering a question nobody
    /// asked.
    ///
    /// IT IS DERIVED RATHER THAN COMPETING, which is what L261 is actually after:
    /// there is still one place a new reason to be unreal is added, and anything
    /// added to `isDisposableLaunch` is inherited here without a second edit. A
    /// fourth independent predicate spelling out the test conditions again is the
    /// thing that would disagree.
    ///
    /// `isDebugBuild` is injected so both answers can be exercised from one build,
    /// which is the only way either is ever seen (L535).
    nonisolated static func mayReachLiveGoogle(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = StoreLocation.isDebugBuild
    ) -> Bool {
        !isDisposableLaunch(environment: environment) && !isDebugBuild
    }
}
